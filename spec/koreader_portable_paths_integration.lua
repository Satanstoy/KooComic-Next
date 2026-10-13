local ffi=require("ffi")
ffi.cdef[[int unsetenv(const char *name);]]
for _,name in ipairs({"KO_HOME","APPIMAGE","FLATPAK","KO_MULTIUSER","UBUNTU_APPLICATION_ISOLATION"}) do assert(ffi.C.unsetenv(name)==0) end
require("setupkoenv")
require("ffi/posix_h")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local lfs=require("libs/libkoreader-lfs")
local runtime=lfs.currentdir()
local directory="/tmp/koocomic-portable-"..tonumber(ffi.C.getpid())
assert(lfs.mkdir(directory))
local names={};for name in lfs.dir(runtime) do names[#names+1]=name end
for _,name in ipairs(names) do
    if name~="." and name~=".." and name~="settings" and name~="cache" and name~="history" and name~="docsettings" and name~="hashdocsettings" then
        assert(lfs.link(runtime.."/"..name,directory.."/"..name,true))
    end
end
assert(lfs.chdir(directory))
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false}
local DataStorage=require("datastorage")
assert(DataStorage:getSettingsDir()=="./settings","fixture must exercise actual unset-KO_HOME defaults")
local Device=require("device");require("document/canvascontext"):init(Device)
local plugin=dofile(root.."/koocomic.koplugin/main.lua")
local instance=plugin:new{ui={menu={registerToMainMenu=function() end}}}
assert(instance.settings.path==directory.."/settings/koocomic.lua" and lfs.attributes(instance.settings.path,"mode")=="file")
assert(instance.preprocess.directory==directory.."/settings/koocomic-preprocess")
assert(instance.download_service.directory==directory.."/settings/koocomic-downloads")
assert(instance.cover_cache.directory==directory.."/cache/koobone-covers")
assert(instance.updater:recoverUpdate())
instance.download_service:pause();instance.preprocess:pause()
Device:exit()
print("KOReader actual portable relative-path startup: OK")
