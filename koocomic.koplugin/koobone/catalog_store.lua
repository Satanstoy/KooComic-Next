-- SPDX-License-Identifier: AGPL-3.0-only
local CatalogStore = {}
CatalogStore.__index = CatalogStore
local CatalogEntry = require("koobone.catalog_entry")

local function nativeFilesystem()
    local lfs = require("libs/libkoreader-lfs")
    local has_util,ffiUtil=pcall(require,"ffi/util")
    local function safe(path)
        if path:sub(1,1)~="/" or path:find("[%z\1-\31]") then return false end
        local current=""
        for part in path:gmatch("[^/]+") do
            if part=="." or part==".." then return false end
            current=current.."/"..part
            if lfs.symlinkattributes and lfs.symlinkattributes(current,"mode")=="link" then return false end
            if lfs.attributes(current,"mode")=="file" and (lfs.attributes(current,"nlink") or 1)>1 then return false end
        end
        return true
    end
    return {
        mkdir = function(path)
            if not safe(path) then return nil,"unsafe cache path" end
            if lfs.attributes(path, "mode") == "directory" then return true end
            return require("util").makePath(path)
        end,
        read = function(path)
            if not safe(path) then return nil,"unsafe snapshot" end
            local handle, err = io.open(path, "rb")
            if not handle then return nil, err end
            local content, read_err = handle:read(32*1024*1024+1)
            handle:close()
            if content and #content>32*1024*1024 then return nil,"snapshot exceeds resource budget" end
            return content, read_err
        end,
        write = function(path, content)
            if not safe(path) then return nil,"unsafe snapshot temporary path" end
            local handle, err = io.open(path, "wb")
            if not handle then return nil, err end
            local wrote, write_err = handle:write(content)
            local flushed, flush_err = handle:flush()
            if wrote and flushed and has_util and ffiUtil.fsyncOpenedFile then
                flushed,flush_err=ffiUtil.fsyncOpenedFile(handle)
            end
            local closed, close_err = handle:close()
            if not wrote or not flushed or not closed then return nil, write_err or flush_err or close_err end
            return true
        end,
        rename = function(source,target)
            if not safe(source) or not safe(target) then return nil,"unsafe snapshot commit path" end
            local ok,err=os.rename(source,target)
            if ok and has_util and ffiUtil.fsyncDirectory then pcall(ffiUtil.fsyncDirectory,target:match("^(.*)/[^/]+$")) end
            return ok,err
        end,
        remove = os.remove,
    }
end

local function accountKey(value)
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    local key = tostring(value)
    if key == "" or key:find("[^%w_-]") then return nil end
    return key
end

local function copyScalars(source, fields)
    local result = {}
    if type(source) ~= "table" then return result end
    for _, field in ipairs(fields) do
        local value = source[field]
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            result[field] = value
        end
    end
    return result
end

local function snapshot(account_id, entries, meta)
    if type(entries) ~= "table" or type(meta) ~= "table" or
            meta.coverage ~= "complete" or meta.verified ~= true then
        return nil, "unverified or incomplete snapshot"
    end
    local safe, seen = {}, {}
    local count = 0
    for index in pairs(entries) do
        if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
            return nil, "entries must be an array"
        end
        count = count + 1
    end
    if count ~= #entries then return nil, "entries must be a dense array" end
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or entry.account_id ~= account_id or
                type(entry.id) ~= "string" or entry.id == "" or seen[entry.id] or
                type(entry.title) ~= "string" or type(entry.volume_id) ~= "string" or
                type(entry.source) ~= "table" then
            return nil, "invalid or duplicate entry"
        end
        local source = entry.source
        local normalized = CatalogEntry.normalize(account_id, source)
        if not normalized or normalized.id ~= entry.id or
                (entry.volume_id ~= entry.id and
                entry.volume_id ~= CatalogEntry.key(account_id, "volume", source.vol_id)) then
            return nil, "invalid entry identity"
        end
        seen[entry.id] = true
        safe[index] = copyScalars(entry, {
            "id", "account_id", "volume_id", "title", "author", "series_title", "series_id",
            "volume_label", "remote_size", "sort_rank",
            "file_type", "remote_pages", "remote_page",
        })
        safe[index].source = copyScalars(entry.source, { "vol_id", "file_md5" })
    end
    return {
        schema_version = 1, account_id = account_id, entries = safe,
        meta = copyScalars(meta, { "coverage", "verified", "synced_at" }),
    }
end

function CatalogStore:new(options)
    assert(type(options.directory) == "string" and options.directory ~= "", "cache directory required")
    return setmetatable({
        directory = options.directory:gsub("/+$", ""),
        fs = options.fs or nativeFilesystem(),
        codec = options.codec or require("json"),
    }, self)
end

function CatalogStore:commit(account_id, entries, meta)
    account_id = accountKey(account_id)
    if not account_id then return nil, "invalid account" end
    local data, err = snapshot(account_id, entries, meta)
    if not data then return nil, err end
    local made, ready = pcall(self.fs.mkdir, self.directory)
    if not made or not ready then return nil, "cache directory unavailable" end
    local path = self.directory .. "/" .. account_id .. ".json"
    local encoded, content = pcall(self.codec.encode, data)
    if not encoded or type(content) ~= "string" then return nil, "snapshot encode failed" end
    if #content>32*1024*1024 then return nil,"snapshot exceeds resource budget" end
    local called, ok
    called, ok, err = pcall(self.fs.write, path .. ".tmp", content)
    if called and ok then called, ok, err = pcall(self.fs.rename, path .. ".tmp", path) end
    if not called or not ok then
        pcall(self.fs.remove, path .. ".tmp")
        return nil, type(err) == "string" and err or "snapshot commit failed"
    end
    return true
end

function CatalogStore:load(account_id)
    account_id = accountKey(account_id)
    if not account_id then return nil, "invalid account" end
    local read, content = pcall(self.fs.read, self.directory .. "/" .. account_id .. ".json")
    if not read or not content then return nil, "missing snapshot" end
    local decoded, data = pcall(self.codec.decode, content)
    if not decoded or type(data) ~= "table" or data.schema_version ~= 1 or data.account_id ~= account_id then
        return nil, "invalid snapshot"
    end
    return snapshot(account_id, data.entries, data.meta)
end

return CatalogStore
