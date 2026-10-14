-- SPDX-License-Identifier: AGPL-3.0-only
local directory=assert(debug.getinfo(1,"S").source:match("^@(.+)/main%.lua$"))
local function fallback(recovered)
    local UI=require("ui/uimanager")
    local Info=require("ui/widget/infomessage")
    local Widget=require("ui/widget/container/widgetcontainer")
    local plugin=Widget:extend{name="koocomic",is_doc_only=false,restart_required=true}
    local message=recovered and "更新启动失败，已恢复旧插件和设置，请重启 KOReader。" or
        "更新恢复未完成，备份已保留。请重启 KOReader；恢复前暂停漫画操作。"
    function plugin:init()
        UI:show(Info:new{text=message})
        if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    end
    function plugin:addToMainMenu(menu)
        menu.koocomic={text="koo漫画：需要重启",callback=function() UI:restartKOReader() end}
    end
    return plugin
end
local options={
    plugin_dir=directory,
    settings_path=require("datastorage"):getSettingsDir().."/koocomic.lua",
    loader=function() return require("koobone.plugin") end,
    fallback=fallback,
}
local loaded,Bootstrap=pcall(require,"koobone.update_bootstrap")
if loaded and type(Bootstrap)=="table" and type(Bootstrap.load)=="function" then
    local ok,result=pcall(Bootstrap.load,options)
    if ok and type(result)=="table" then return result end
end

-- This last-resort entry cannot depend on any new-version recovery module.
local ok,recovered=pcall(function()
    local lfs=require("libs/libkoreader-lfs")
    local function absolute(path)
        if path:sub(1,1)~="/" then path=lfs.currentdir().."/"..path end
        local parts={}
        for part in path:gmatch("[^/]+") do
            assert(part~="..")
            if part~="." then parts[#parts+1]=part end
        end
        return "/"..table.concat(parts,"/")
    end
    local function read(path,limit)
        local prefix=""
        for part in path:gmatch("[^/]+") do
            prefix=prefix.."/"..part
            local stat=lfs.symlinkattributes(prefix)
            assert(not stat or (stat.mode~="link" and (stat.mode~="file" or (stat.nlink or 1)==1)))
        end
        local stat=assert(lfs.symlinkattributes(path));assert(stat.mode=="file" and stat.size<=limit)
        local handle=assert(io.open(path,"rb"));local bytes=handle:read(limit+1);handle:close()
        assert(bytes and #bytes==stat.size);return bytes
    end
    local live=absolute(directory)
    local record=require("json").decode(read(live..".next-update.json",128*1024))
    assert(record.schema_version==1 and record.product_id=="koocomic-next" and type(record.recovery_hashes)=="table")
    assert(record.phase=="installed" or record.phase=="prepared" or record.phase=="rolling_back")
    local old
    for _,path in ipairs({live..".next-backup",live..".next-stage",live}) do
        local stat=lfs.symlinkattributes(path)
        if stat and stat.mode=="directory" and tostring(stat.dev)..":"..tostring(stat.ino)==record.old_identity then old=path;break end
    end
    assert(old)
    local cache={}
    local allowed={update_transaction=true,update_files=true,preprocess_files=true,settings_store=true}
    local function isolated(name)
        local suffix=name:match("^koobone%.([a-z_]+)$")
        if not suffix or not allowed[suffix] then return require(name) end
        if cache[name] then return cache[name] end
        local source=read(old.."/koobone/"..suffix..".lua",1024*1024)
        local digest=require("ffi/sha2").sha256();digest(source)
        assert(digest()==record.recovery_hashes[suffix])
        local chunk=assert(loadstring(source,"@verified-entry-recovery/"..suffix))
        setfenv(chunk,setmetatable({require=isolated},{__index=_G}))
        cache[name]=assert(chunk());return cache[name]
    end
    local settings_path=absolute(options.settings_path)
    local settings={path=settings_path,persistence=isolated("koobone.settings_store"):new{path=settings_path}}
    local backend=isolated("koobone.update_files"):new{plugin_dir=live,settings=settings}
    return isolated("koobone.update_transaction"):new{backend=backend,paths=backend.paths}:rollback()
end)
pcall(function() require("koobone.runtime_guard").block() end)
return fallback(ok and recovered==true)
