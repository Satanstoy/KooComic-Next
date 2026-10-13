require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
require("ffi/posix_h")
local directory="/tmp/koocomic-update-txn-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
assert(type(files.exchangeDirectories)=="function","plugin updates must exchange directories atomically without a missing-live gap")
local live,stage=directory.."/live",directory.."/stage"
assert(files:mkdir(live));assert(files:mkdir(stage))
assert(files:write(live.."/marker","old"));assert(files:write(stage.."/marker","new"))
assert(files:exchangeDirectories(live,stage))
assert(files:read(live.."/marker")=="new" and files:read(stage.."/marker")=="old")
assert(files:moveDirectoryNoReplace(stage,directory.."/backup"))
assert(not files:moveDirectoryNoReplace(live,directory.."/backup"))
assert(files:read(live.."/marker")=="new" and files:read(directory.."/backup/marker")=="old")
local loaded,Backend=pcall(require,"koobone.update_files")
assert(loaded,"updater needs a native persisted transaction/settings adapter")
local Settings=require("koobone.settings")
local settings=Settings:new(directory.."/settings.lua")
settings.data.ui.series_style="ribbon";assert(settings:flush())
local plugin=directory.."/koocomic.koplugin"
local function code(path,version)
    assert(files:mkdir(path));assert(files:write(path.."/main.lua","return {}"))
    assert(files:mkdir(path.."/koobone"))
    assert(files:write(path.."/koobone/plugin_version.lua",'return {product_id="koocomic-next",version="'..version..'"}'))
end
code(plugin,"0.4.1");code(plugin..".next-stage","0.5.0")
local backend=Backend:new{plugin_dir=plugin,settings=settings}
local tx=require("koobone.update_transaction"):new{backend=backend,paths=backend.paths}
assert(tx:install("0.4.1","0.5.0",function()
    settings.data.ui.series_style="stack";assert(settings:flush());return true end))
assert(backend:validate(plugin,"0.5.0") and settings:ui().series_style=="stack")
local reopened=Backend:new{plugin_dir=plugin,settings=settings}
assert(require("koobone.update_transaction"):new{backend=reopened,paths=reopened.paths}:recover("0.5.0"))
assert(tx:rollback() and backend:validate(plugin,"0.4.1") and Settings:new(settings.path):ui().series_style=="ribbon")
local external=directory.."/external";assert(files:mkdir(external));assert(files:write(external.."/sentinel","preserve"))
assert(require("libs/libkoreader-lfs").link(external,backend.paths.backup.."/escape",true))
assert(not tx:prepareNew() and files:read(external.."/sentinel")=="preserve",
    "owned backup cleanup must refuse nested links without deleting their external target")
assert(os.remove(backend.paths.backup.."/escape"))
assert(require("libs/libkoreader-lfs").link(external.."/sentinel",backend.paths.backup.."/hard",false))
assert(not tx:prepareNew() and require("libs/libkoreader-lfs").attributes(external.."/sentinel","size")==8,
    "hard-linked external files must prevent backup cleanup")
assert(os.remove(backend.paths.backup.."/hard"))
assert(files:read(external.."/sentinel")=="preserve")
assert(tx:prepareNew() and backend:validate(plugin,"0.4.1") and not files:exists(backend.paths.journal),
    "safe retirement must remove owned artifacts and preserve the live plugin")
code(backend.paths.stage,"0.5.0")
local save=settings.persistence.save
local first=true
settings.persistence.save=function(self,...)
    if first then first=false;return nil,"injected settings write failure" end
    return save(self,...)
end
assert(not tx:install("0.4.1","0.5.0",function()
    settings.data.ui.series_style="stack";return settings:flush() end))
settings.persistence.save=save
assert(backend:validate(plugin,"0.4.1") and Settings:new(settings.path):ui().series_style=="ribbon",
    "actual settings write failure must restore old code and original settings")
assert(tx:prepareNew())
code(backend.paths.stage,"0.5.0")
assert(tx:install("0.4.1","0.5.0",function() return true end));assert(tx:confirm("0.5.0"))
local remove=backend.remove
backend.remove=function(self,path,expected)
    local ok,err=remove(self,path,expected)
    if path==self.paths.backup and ok then
        assert(os.rename(self.paths.config,self.paths.config..".preserved"))
        assert(files:write(self.paths.config,"external settings replacement"))
    end
    return ok,err
end
assert(not tx:prepareNew() and files:read(backend.paths.config)=="external settings replacement",
    "native cleanup must preserve a settings artifact replaced after preflight")
print("KOReader atomic plugin directory exchange: OK")
