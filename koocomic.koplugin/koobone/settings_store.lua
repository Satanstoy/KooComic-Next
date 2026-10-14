-- SPDX-License-Identifier: AGPL-3.0-only
local Store={}
Store.__index=Store
local function parent(path) return assert(path:match("^(/.*)/[^/]+$"),"absolute settings path required") end

function Store:new(options)
    local roots={parent(assert(options.path))}
    if options.legacy_path then roots[#roots+1]=parent(options.legacy_path) end
    return setmetatable({files=options.files or require("koobone.preprocess_files"):new{roots=roots},
        serialize=options.serialize or function(value) return "return "..require("dump")(value,nil,true).."\n" end,
        rename=options.rename or os.rename,
        sync_directory=options.sync_directory or require("ffi/util").fsyncDirectory,
        pid=options.pid or tonumber(require("ffi").C.getpid()),sequence=0,budget=4*1024*1024},self)
end

function Store:load(path)
    if not self.files:exists(path) then return nil end
    local data,err=self.files:read(path,self.budget)
    if not data then return nil,err or "settings read failed" end
    local chunk=loadstring(data,"@settings")
    if not chunk then return nil,"settings parse failed" end
    setfenv(chunk,{})
    local ok,payload=pcall(chunk)
    if not ok or type(payload)~="table" then return nil,"invalid settings payload" end
    return payload
end

function Store:save(path,payload,source)
    if not self.files:isSafe(path) then return nil,"unsafe settings path" end
    local encoded,data=pcall(self.serialize,payload)
    if not encoded or type(data)~="string" or #data>self.budget then return nil,"settings serialization failed" end
    local chunk=loadstring(data);if not chunk then return nil,"settings serialization invalid" end
    setfenv(chunk,{})
    local valid,parsed=pcall(chunk)
    if not valid or type(parsed)~="table" then return nil,"settings serialization invalid" end
    if not self.files:mkdir(parent(path)) then return nil,"settings directory unavailable" end
    local temporary
    for _=1,256 do
        self.sequence=self.sequence+1
        local candidate=path..".next-"..self.pid.."-"..self.sequence..".tmp"
        if not self.files:exists(candidate) and not self.files:exists(candidate..".backup") then temporary=candidate;break end
    end
    if not temporary then return nil,"settings temporary namespace busy; unknown files preserved" end
    if source then
        local backup=path..".pre-v4"
        local digest=self.files:hash(source)
        if not digest then return nil,"settings backup source unreadable" end
        if self.files:exists(backup) then
            if self.files:hash(backup)~=digest then return nil,"existing settings backup differs; preserved" end
        else
            local staging=temporary..".backup"
            local owned
            local copied=self.files:copyExclusive(source,staging,self.files:identity(source),self.budget,function(_,identity)
                owned=identity;return true
            end)
            local function cleanup()
                if owned and self.files:identity(staging)==owned then self.files:remove(staging) end
            end
            if copied~=digest or not self.files:sync(staging) then cleanup();return nil,"settings metadata backup failed" end
            if not self.files:renameNoReplace(staging,backup) then cleanup();return nil,"settings metadata backup commit failed" end
        end
    end
    local writer=self.files:exclusiveWriter(temporary)
    if not writer then return nil,"settings temporary creation failed" end
    local written=writer:write(data)
    local closed=writer:close()
    if not written or not closed then self.files:remove(temporary);return nil,"settings temporary write failed" end
    if not self.files:sync(temporary) then self.files:remove(temporary);return nil,"settings temporary sync failed" end
    if not self.files:isSafe(path) or not self.files:isSafe(temporary) then return nil,"unsafe settings commit" end
    local applied=self.rename(temporary,path)
    if not applied then self.files:remove(temporary);return nil,"settings atomic replace failed" end
    if not self.sync_directory(path) then return true,"settings applied; directory durability unconfirmed" end
    return true
end

return Store
