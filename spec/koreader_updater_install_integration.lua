require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local package_path=assert(arg[2])
if arg[3] then
    local directory=assert(arg[4])
    package.path=directory.."/koocomic.koplugin/?.lua;"..package.path
    local files=require("koobone.preprocess_files"):new{roots={directory,package_path:match("^(.*)/[^/]+$")}}
    local settings=require("koobone.settings"):new(directory.."/settings.lua")
    local bytes=assert(files:read(package_path,15*1024*1024))
    local api={download=function(_,_,_,options) assert(options.handle:write(bytes));assert(options.handle:close());return true end}
    local updater=require("koobone.updater"):new{settings=settings,api=api,
        current_version=arg[3]=="confirm-rollback" and "0.4.1" or "0.4.0",plugin_dir=directory.."/koocomic.koplugin",
        manifest_url="https://example.test/update.json",release_prefix="https://example.test/releases/"}
    if arg[3]=="confirm-rollback" then
        assert(updater:confirmInstalledUpdate() and updater:canRollback())
        assert(updater:rollbackUpdate())
    else
        assert(updater:install{product_id="koocomic-next",version="0.4.1",size=#bytes,sha256=assert(files:hash(package_path)),
            package_url="https://example.test/releases/v0.4.1/package.zip"})
    end
    return
end
local Files=require("koobone.preprocess_files")
local ffi=require("ffi")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local directory="/tmp/koocomic-install-"..tonumber(ffi.C.getpid())
local files=Files:new{roots={directory,package_path:match("^(.*)/[^/]+$")}};assert(files:mkdir(directory))
local settings=require("koobone.settings"):new(directory.."/settings.lua")
settings.data.download.directory=directory.."/books";assert(files:mkdir(settings.data.download.directory))
local comic=settings.data.download.directory.."/Original.epub";assert(files:write(comic,"fixture original bytes"))
local item={file_md5="fixture",vol_name="Original",file_type="epub"}
settings.data.download.records.fixture={path=comic,title="Original",state="complete"}
settings.data.ui.series_style="ribbon";assert(settings:flush())
local storage=require("koobone.storage"):new(settings)
local processing=require("koobone.preprocess_service"):new{storage=storage,directory=directory.."/processing",
    native_library=root.."/native/preprocess/build/moire-host.so",space=function() return 1024*1024*1024 end}
assert(processing.available)
local stale=require("ui/widget/confirmbox"):new{text="Generated stale processing confirmation",ok_callback=function()
    local submitted=processing:submitBatch({item})
    if submitted then processing:resume() end
end}
UI:show(stale)
local plugin=directory.."/koocomic.koplugin";assert(files:mkdir(plugin));assert(files:mkdir(plugin.."/koobone"))
assert(files:write(plugin.."/main.lua","return {}"))
assert(files:write(plugin.."/_meta.lua",'return {version="0.4.0"}'))
assert(files:write(plugin.."/koobone/plugin_version.lua",'return {product_id="koocomic-next",version="0.4.0"}'))
local bytes=assert(files:read(package_path,15*1024*1024))
local calls=0
local api={download=function(_,_,_,options)
    calls=calls+1
    assert(options.handle,"update download must use an already-owned exclusive file")
    assert(options.handle:write(bytes));assert(options.handle:close());return true
end}
local Updater=require("koobone.updater")
local updater=Updater:new{settings=settings,api=api,current_version="0.4.0",plugin_dir=plugin,
    manifest_url="https://example.test/update.json",release_prefix="https://example.test/releases/"}
local release={product_id="koocomic-next",version="0.4.1",size=#bytes,sha256=assert(files:hash(package_path)),
    package_url="https://example.test/releases/v0.4.1/package.zip"}
assert(type(updater.recoverUpdate)=="function","production updater must bind durable recovery and rollback")
assert(updater:install(release))
stale.ok_callback()
assert(#processing.requests==0 and #processing:jobs()==0 and not processing.running and files:read(comic)=="fixture original bytes",
    "native retained confirmation must not start old processing or change the EPUB after installation")
UI:close(stale)
assert(calls==1 and settings:update().pending_version=="0.4.1")
local function cold(mode)
    assert(os.execute(string.format("./luajit %q %q %q %q %q",root.."/spec/koreader_updater_install_integration.lua",root,package_path,mode,directory))==0)
end
cold("confirm-rollback")
local restored=assert(settings.persistence:load(settings.path))
assert(restored.data.ui.series_style=="ribbon" and restored.data.update.pending_version==nil)
assert(files:read(plugin.."/koobone/plugin_version.lua"):find('version="0.4.0"',1,true))
cold("retry")
print("KOReader real full-package upgrade/confirm/rollback/retry: OK")
Device:exit()
