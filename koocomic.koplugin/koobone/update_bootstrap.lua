-- SPDX-License-Identifier: AGPL-3.0-only
local Bootstrap={}
function Bootstrap.absolute(path)
    assert(type(path)=="string" and path~="","runtime path required")
    if path:sub(1,1)~="/" then path=require("libs/libkoreader-lfs").currentdir().."/"..path end
    local parts={}
    for part in path:gmatch("[^/]+") do
        assert(part~="..","runtime parent traversal refused")
        if part~="." then parts[#parts+1]=part end
    end
    return "/"..table.concat(parts,"/")
end
-- Recovery imports are isolated from package.loaded and use the installed
-- transaction's fingerprints, not potentially broken new-version modules.
function Bootstrap.prepare(options)
    local lfs=require("libs/libkoreader-lfs")
    local live=Bootstrap.absolute(options.plugin_dir)
    local settings_path=Bootstrap.absolute(options.settings_path)
    local function safe(path)
        if path:find("/%.%./") or path:find("//",1,true) then return false end
        local current=""
        for part in path:gmatch("[^/]+") do
            current=current.."/"..part
            local stat=lfs.symlinkattributes(current)
            if stat and (stat.mode=="link" or (stat.mode=="file" and (stat.nlink or 1)>1)) then return false end
        end
        return true
    end
    local function read(path,budget)
        if not safe(path) then return nil end
        local stat=lfs.symlinkattributes(path)
        if not stat or stat.mode~="file" or stat.size>budget then return nil end
        local handle=io.open(path,"rb");if not handle then return nil end
        local bytes=handle:read(budget+1);handle:close()
        return bytes and #bytes==stat.size and bytes or nil
    end
    local journal=live..".next-update.json"
    if not lfs.symlinkattributes(journal) then return {} end
    local called,context=pcall(function()
        local bytes=assert(read(journal,128*1024))
        local record=require("json").decode(bytes)
        assert(record.schema_version==1 and record.product_id=="koocomic-next")
        local function identity(path)
            if not safe(path) then return nil end
            local stat=lfs.symlinkattributes(path)
            return stat and stat.mode=="directory" and tostring(stat.dev)..":"..tostring(stat.ino) or nil
        end
        local function versionMatches(path,expected)
            local chunk=assert(loadstring(assert(read(path.."/koobone/plugin_version.lua",65536))))
            setfenv(chunk,{})
            local prior,mask,count=debug.gethook()
            debug.sethook(function() error("metadata budget") end,"",10000)
            local ok,value=pcall(chunk)
            debug.sethook(prior,mask,count)
            return ok and type(value)=="table" and value.product_id=="koocomic-next" and value.version==expected
        end
        if record.phase=="confirmed" then
            assert(identity(live)==record.new_identity and versionMatches(live,record.new_version))
            return {}
        end
        local old
        for _,candidate in ipairs({live,live..".next-backup",live..".next-stage"}) do
            if identity(candidate)==record.old_identity then old=candidate;break end
        end
        assert(old)
        local recovery_root,recovery_identity=old,record.old_identity
        local legacy=record.recovery_hashes==nil
        if legacy then
            -- Older installers validated the full release but did not record
            -- old-module hashes. Use that release's isolated recovery modules.
            recovery_root=nil
            for _,candidate in ipairs({live,live..".next-stage",live..".next-backup"}) do
                if identity(candidate)==record.new_identity then recovery_root=candidate;break end
            end
            assert(recovery_root);recovery_identity=record.new_identity
            assert(versionMatches(recovery_root,record.new_version))
        else assert(type(record.recovery_hashes)=="table") end
        local cache={}
        local allowed={update_transaction=true,update_files=true,preprocess_files=true,settings_store=true}
        local function isolated(name)
            local suffix=name:match("^koobone%.([a-z_]+)$")
            if not suffix or not allowed[suffix] then return require(name) end
            if cache[name] then return cache[name] end
            assert(identity(recovery_root)==recovery_identity)
            local source=assert(read(recovery_root.."/koobone/"..suffix..".lua",1024*1024))
            if not legacy then
                local digest=require("ffi/sha2").sha256();digest(source)
                assert(digest()==record.recovery_hashes[suffix])
            end
            local chunk=assert(loadstring(source,"@verified-update-recovery/"..suffix))
            setfenv(chunk,setmetatable({require=isolated},{__index=_G}))
            cache[name]=assert(chunk());return cache[name]
        end
        local Store=isolated("koobone.settings_store")
        local settings={path=settings_path,persistence=Store:new{path=settings_path}}
        local backend=isolated("koobone.update_files"):new{plugin_dir=live,settings=settings}
        local tx=isolated("koobone.update_transaction"):new{backend=backend,paths=backend.paths}
        record=assert(tx:_load())
        local rollback=function() return tx:rollback() end
        if record.phase=="installed" then return {pending=true,rollback=rollback} end
        assert(tx:recover(record.old_version))
        local switched=identity(live)~=record.new_identity and
            (record.phase=="prepared" or record.phase=="rolling_back")
        return {restart=switched,recovered=switched}
    end)
    if not called then return {restart=true,recovered=false} end
    return context
end
function Bootstrap.load(options)
    local context=(options.prepare or Bootstrap.prepare)(options)
    if context.restart then return options.fallback(context.recovered) end
    if not context.pending then return options.loader() end
    local function recover(instance)
        if instance then
            for _,name in ipairs({"download_service","preprocess"}) do
                local service=instance[name]
                if service and service.pause then pcall(service.pause,service) end
            end
        end
        local called,recovered=pcall(context.rollback)
        pcall(function() require("koobone.runtime_guard").block() end)
        return options.fallback(called and recovered==true)
    end
    local called,plugin=pcall(options.loader)
    if not called or type(plugin)~="table" or type(plugin.init)~="function" or type(plugin.new)~="function" then return recover() end
    local init=plugin.init
    plugin.init=function(self,...)
        local ok=pcall(init,self,...)
        if ok then return end
        local replacement=recover(self)
        setmetatable(self,{__index=replacement})
        if replacement.init then replacement.init(self) end
    end
    local new=plugin.new
    plugin.new=function(self,...)
        local ok,instance=pcall(new,self,...)
        if ok and type(instance)=="table" then return instance end
        return recover():new(...)
    end
    return plugin
end
return Bootstrap
