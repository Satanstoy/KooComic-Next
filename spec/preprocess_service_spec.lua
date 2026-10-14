package.path="./koocomic.koplugin/?.lua;"..package.path
package.preload["libs/libkoreader-lfs"]=function() return {attributes=function() return nil end} end
local available,Service=pcall(require,"koobone.preprocess_service")
assert(available,"downloaded-file preprocessing service is missing")
assert(type(Service.nativeLibraryPath)=="function","default native library path must match the packaged plugin/native directory")
assert(Service.nativeLibraryPath():match("koocomic%.koplugin/native/moire%-kindlehf%.so$"),
    "default library must not resolve under koobone/native")
assert(Service.nativeLibraryPath({isKobo=function() return true end}):match("koocomic%.koplugin/native/moire%-kobo%.so$"),
    "Kobo colour devices must resolve the kobo filter")
assert(Service.colorCapable({hasColorScreen=function() return true end},{arch="arm"})==true,
    "colour e-ink ARM devices must enable the filter")
assert(Service.colorCapable({hasColorScreen=true},{arch="arm"})==true)
assert(Service.colorCapable({hasColorScreen=function() return false end},{arch="arm"})==false,
    "non-colour screens have no moire to remove")
assert(Service.colorCapable({hasColorScreen=function() return true end},{arch="x64"})==false,
    "only the arm targets have a prebuilt filter")
assert(Service.colorCapable({},{arch="arm"})==false)
local disabled=Service:new{storage={},directory="/not-created-by-test"}
assert(disabled.available==false and type(disabled.reason)=="string")
local missing_native=Service:new{storage={downloadDir=function() return "/tmp" end},
    directory="/not-created-by-test",native_library="/nonexistent/native/moire-kindlehf.so"}
assert(missing_native.available==false and missing_native.reason:find("原生去彩纹组件",1,true),
    "a package without the native filter must explain the missing component, not raise a loader errno: "..tostring(missing_native.reason))
assert(disabled:submit({})==nil and disabled:isActive()==false)
assert(disabled:jobs()[1]==nil and disabled:isLocked("/books/book.epub")==false)
assert(type(disabled.profile)=="function","processing service must freeze validated profile controls at enqueue time")
local profile=assert(disabled:profile())
assert(profile.scale_mode=="original" and profile.strength==0.8 and profile.discard_original)
disabled.profile_provider=function() return {strength=0.6,scale_mode="fit",target_width=600,target_height=800} end
profile=assert(disabled:profile());assert(profile.strength==0.6 and profile.target_width==600)
disabled.profile_provider=function() return {strength=math.huge} end
assert(not disabled:profile())
local shared=Service:get{storage={},directory="/not-created-shared"}
local callback=function() end
assert(Service:get{storage={},directory="/not-created-shared",on_batch=callback}==shared and shared.on_batch==callback,
    "reinitialization must bind batch results to the current plugin instance")
local notifications=0
assert(type(shared.subscribe)=="function","idle views need persisted-state notifications to resume watching")
local unsubscribe=shared:subscribe(function() notifications=notifications+1 end)
shared.files={writeJSON=function() return true end};shared.queue={snapshot=function() return {} end}
assert(shared:_save());assert(notifications==1)
unsubscribe();assert(shared:_save());assert(notifications==1)
shared:subscribe(function() notifications=notifications+1 end)
shared.files.writeJSON=function() return nil,"failed" end
assert(not shared:_save());assert(notifications==1,"failed persistence must not publish a state update")
print("preprocess service spec: OK")
