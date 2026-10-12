package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, CatalogStore = pcall(require, "koobone.catalog_store")
assert(available, "atomic catalog storage is not implemented")
local CatalogEntry = require("koobone.catalog_entry")
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end
local files, encoded, sequence = {}, {}, 0
local fail_write, fail_rename = false, false
local fs = {
    mkdir = function() return true end,
    read = function(path) return files[path] end,
    write = function(path, content)
        files[path] = content
        if fail_write then return nil, "write failed" end
        return true
    end,
    rename = function(old, new)
        if fail_rename then return nil, "rename failed" end
        files[new], files[old] = files[old], nil
        return true
    end,
    remove = function(path) files[path] = nil end,
}
local codec = {
    encode = function(value)
        sequence = sequence + 1
        local token = "snapshot-" .. sequence
        encoded[token] = clone(value)
        return token
    end,
    decode = function(token) return clone(encoded[token]) end,
}
local store = CatalogStore:new{ directory = "/cache", fs = fs, codec = codec }
local entry = assert(CatalogEntry.normalize("42", { vol_id = "1", file_md5 = "a", vol_name = "First" }))
local complete = { coverage = "complete", verified = true, synced_at = 123 }
assert(store:commit("42", { entry }, complete))
local snapshot = assert(store:load("42"))
assert(snapshot.entries[1].title == "First" and snapshot.account_id == "42")
assert(snapshot.meta.coverage == "complete")
entry.title = "Second"
fail_write = true
assert(store:commit("42", { entry }, complete) == nil)
assert(store:load("42").entries[1].title == "First", "write failure must preserve the old snapshot")
fail_write, fail_rename = false, true
assert(store:commit("42", { entry }, complete) == nil)
assert(store:load("42").entries[1].title == "First", "rename failure must preserve the old snapshot")
fail_rename = false
entry.file_url, entry.cookie = "signed-secret", "cookie-secret"
complete.password = "password-secret"
assert(store:commit("42", { entry }, complete))
snapshot = assert(store:load("42"))
assert(snapshot.entries[1].file_url == nil and snapshot.entries[1].cookie == nil,
    "snapshots must whitelist persistent catalog fields")
assert(snapshot.meta.password == nil)
assert(store:load("99") == nil, "accounts must not share snapshots")
assert(store:load("../42") == nil, "account identifiers must not escape the cache directory")
assert(store:commit("../42", { entry }, complete) == nil)
assert(store:commit("99", { entry }, complete) == nil, "cross-account entries must be rejected")
assert(store:commit("42", { entry }, { coverage = "partial" }) == nil,
    "partial sync must not replace a complete snapshot")
assert(store:commit("42", { entry, entry }, complete) == nil, "duplicates must be rejected")
assert(store:commit("42", {{ id = "a", account_id = "42", series_title = "A" }}, complete) == nil,
    "incomplete entries must not produce unusable snapshots")
assert(store:commit("42", { [1] = entry, [3] = entry }, complete) == nil,
    "sparse arrays must not be silently truncated")
assert(store:commit("42", { book = entry }, complete) == nil,
    "objects must not be silently accepted as empty catalogs")
files["/cache/42.json"] = "broken-json"
assert(store:load("42") == nil, "corrupted snapshots must not crash or be accepted")

package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function(path) if path == "/tmp" then return "directory" end end }
end
local native = CatalogStore:new{ directory = "/tmp", codec = codec }
assert(type(native.fs) == "table", "a native filesystem backend is not implemented")
local temporary = os.tmpname()
os.remove(temporary)
local native_account = "native-" .. temporary:match("([^/]+)$")
local native_entry = assert(CatalogEntry.normalize(native_account, { file_md5 = "a", vol_name = "Native" }))
assert(native:commit(native_account, { native_entry }, complete))
assert(native:load(native_account).entries[1].title == "Native", "native IO must round-trip a snapshot")
os.remove("/tmp/" .. native_account .. ".json")
print("catalog store spec: OK")
