require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local Files=require("koobone.preprocess_files")
local Settings=require("koobone.settings")
local directory="/tmp/koocomic-settings-"..tonumber(ffi.C.getpid())
local files=Files:new{roots={directory}};assert(files:mkdir(directory))
local old=directory.."/koobone.lua"
local old_text='return {data={schema_version=2,account={email="reader@example.test",remember_password=false},download={directory="/original/books",records={one={state="complete",path="/original/books/Original.epub"}}},ui={series_style="ribbon"}}}'
assert(files:write(old,old_text))
local path=directory.."/koocomic.lua"
local settings=Settings:new(path,old)
assert(settings.data.schema_version==4 and settings:download().directory=="/original/books" and settings:ui().series_style=="ribbon")
assert(files:read(path..".pre-v4")==old_text and files:read(old)==old_text)
assert(Settings:new(path):download().records.one.path=="/original/books/Original.epub")
local future=directory.."/future.lua";local text='return {data={schema_version=5}}'
assert(files:write(future,text))
assert(not pcall(Settings.new,Settings,future) and files:read(future)==text)
local broken=directory.."/broken.lua";assert(files:write(broken,"broken settings"))
assert(not pcall(Settings.new,Settings,broken) and files:read(broken)=="broken settings")
local link=directory.."/link.lua"
assert(require("libs/libkoreader-lfs").link(old,link,true))
assert(not pcall(Settings.new,Settings,link) and files:read(old)==old_text)
local failed_path=directory.."/failure.lua"
local prior='return {data={schema_version=3,download={records={one={state="complete"}}}}}'
assert(files:write(failed_path,prior))
local Store=require("koobone.settings_store")
local store=Store:new{path=failed_path,files=files}
local sync=files.sync
files.sync=function(self,target) if target:match("%.tmp$") then return nil end;return sync(self,target) end
assert(not pcall(Settings.new,Settings,failed_path,nil,{persistence=store}) and files:read(failed_path)==prior,
    "actual temporary fsync failure must preserve old settings")
files.sync=sync
assert(Settings:new(failed_path,nil,{persistence=store}).data.schema_version==4)
local retry_path=directory.."/retry.lua";assert(files:write(retry_path,prior))
store=Store:new{path=retry_path,files=files}
local capture=files.copyExclusive
files.copyExclusive=function(self,source,target,identity,_,created) return capture(self,source,target,identity,1,created) end
assert(not pcall(Settings.new,Settings,retry_path,nil,{persistence=store}) and files:read(retry_path)==prior and
    not files:exists(retry_path..".pre-v4"),"interrupted actual metadata copy must not publish a partial backup")
files.copyExclusive=capture
assert(Settings:new(retry_path,nil,{persistence=store}).data.schema_version==4)
print("KOReader actual settings v4 migration and preservation: OK")
