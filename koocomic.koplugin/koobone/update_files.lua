-- SPDX-License-Identifier: AGPL-3.0-only
local Files=require("koobone.preprocess_files")
local Store=require("koobone.settings_store")
local lfs=require("libs/libkoreader-lfs")
local Backend={}
Backend.__index=Backend
local function absolute(path)
    assert(type(path)=="string" and path~="","update path required")
    if path:sub(1,1)~="/" then path=lfs.currentdir().."/"..path:gsub("^%./","") end
    return path
end
function Backend:new(options)
    local live=absolute(options.plugin_dir)
    local settings=assert(options.settings)
    local settings_path=absolute(assert(settings.path))
    local paths={live=live,stage=live..".next-stage",backup=live..".next-backup",failed=live..".next-failed",
        config=live..".next-settings.lua",journal=live..".next-update.json",work=live..".next-work",
        archive=live..".next-package.zip",lease=live..".next-staging.json"}
    local files=options.files or Files:new{roots={assert(live:match("^(.*)/[^/]+$")),assert(settings_path:match("^(.*)/[^/]+$"))}}
    assert(files:isSafe(live) and files:isSafe(settings_path),"unsafe update roots")
    return setmetatable({paths=paths,settings=settings,settings_path=settings_path,files=files},self)
end
function Backend:exists(path) return self.files:exists(path) end
function Backend:identity(path)
    if not self.files:isSafe(path) then return nil end
    local stat=lfs.symlinkattributes(path)
    if not stat or (stat.mode~="directory" and stat.mode~="file") or (stat.mode=="file" and (stat.nlink or 1)>1) then return nil end
    return tostring(stat.dev)..":"..tostring(stat.ino)
end
function Backend:move(source,target) return self.files:moveDirectoryNoReplace(source,target) end
function Backend:exchange(source,target) return self.files:exchangeDirectories(source,target) end
function Backend:save(record) return self.files:writeJSON(self.paths.journal,record) end
function Backend:load()
    if not self.files:exists(self.paths.journal) then return nil end
    return self.files:readJSON(self.paths.journal)
end
function Backend:loadLease()
    if not self.files:exists(self.paths.lease) then return nil end
    return self.files:readJSON(self.paths.lease)
end
function Backend:saveLease(record) return self.files:writeJSON(self.paths.lease,record) end
function Backend:clearLease() return self.files:remove(self.paths.lease) end
function Backend:createDirectory(path) return self.files:mkdirExclusive(path) end
function Backend:backupSettings(created)
    local id=self.files:identity(self.settings_path)
    if not id then return nil,"unsafe settings source" end
    return self.files:copyExclusive(self.settings_path,self.paths.config,id,4*1024*1024,created)
end
function Backend:remove(path,expected)
    if not expected or self:identity(path)~=expected then return nil,"update cleanup identity changed" end
    if not self.files:isSafe(path) then return nil,"unsafe update cleanup" end
    if lfs.symlinkattributes(path,"mode")=="directory" then
        return self.files:removeDirectorySecure(path,expected)
    end
    return self.files:remove(path)
end
function Backend:clear() return self.files:remove(self.paths.journal) end
function Backend:recoveryHashes(path)
    local hashes={}
    for _,name in ipairs({"update_transaction","update_files","preprocess_files","settings_store"}) do
        local source=path.."/koobone/"..name..".lua"
        if self.files:exists(source) then
            hashes[name]=self.files:hash(source)
            if not hashes[name] then return nil end
        end
    end
    return hashes
end
function Backend:restoreSettings()
    local store=Store:new{path=self.paths.config,files=self.files}
    local payload,err=store:load(self.paths.config)
    if not payload or type(payload.data)~="table" then return nil,err or "invalid settings backup" end
    local saved,save_error=self.settings.persistence:save(self.settings_path,payload)
    if not saved then return nil,save_error end
    self.settings.payload,self.settings.data=payload,payload.data
    return true,save_error
end
function Backend:validate(path,version)
    if not self.files:isSafe(path) or lfs.symlinkattributes(path,"mode")~="directory" then return false end
    local count,bytes=0,0
    local function compile(directory,depth)
        if depth>32 then return false end
        local names={}
        for name in lfs.dir(directory) do if name~="." and name~=".." then names[#names+1]=name end end
        for _,name in ipairs(names) do
            count=count+1;if count>10000 then return false end
            local entry=directory.."/"..name
            local stat=lfs.symlinkattributes(entry)
            if not stat or not self.files:isSafe(entry) then return false end
            if stat.mode=="directory" then
                if not compile(entry,depth+1) then return false end
            elseif stat.mode=="file" and (stat.nlink or 1)==1 then
                bytes=bytes+stat.size;if bytes>15*1024*1024 then return false end
                if name:match("%.lua$") then
                    local source=self.files:read(entry,1024*1024)
                    if not source or not loadstring(source) then return false end
                end
            else return false end
        end
        return true
    end
    local compiled,valid=pcall(compile,path,0)
    if not compiled or not valid then return false end
    local metadata=self.files:read(path.."/koobone/plugin_version.lua",65536)
    local main=self.files:read(path.."/main.lua",1024*1024)
    if not metadata or not main or not loadstring(main) then return false end
    local chunk=loadstring(metadata,"@update-version");if not chunk then return false end
    setfenv(chunk,{})
    local prior,mask,count=debug.gethook()
    debug.sethook(function() error("update metadata instruction budget") end,"",10000)
    local called,value=pcall(chunk)
    debug.sethook(prior,mask,count)
    return called and type(value)=="table" and value.product_id=="koocomic-next" and value.version==version
end
return Backend
