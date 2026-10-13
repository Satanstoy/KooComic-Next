require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
ffi.cdef[[int symlink(const char *target, const char *linkpath);]]
local Archiver=require("ffi/archiver")
local directory="/tmp/koocomic-update-package-"..tonumber(ffi.C.getpid())
local Files=require("koobone.preprocess_files")
local files=Files:new{roots={directory}};assert(files:mkdir(directory))
local function zip(name,entries)
    local path=directory.."/"..name..".zip"
    local writer=Archiver.Writer:new();assert(writer:open(path,"zip"));assert(writer:setZipCompression("store"))
    for _,entry in ipairs(entries) do assert(writer:addFileFromMemory(entry[1],entry[2])) end
    writer:close();return path
end
local Updater=require("koobone.updater")
local updater=Updater:new{settings={},api={},current_version="0.4.1"}
local good=zip("good",{{"koocomic.koplugin/main.lua","return {}"},{"koocomic.koplugin/_meta.lua","return {product_id='koocomic-next'}"}})
local stage=directory.."/good";assert(files:mkdir(stage))
assert(updater:_extractPackage(good,stage));assert(files:read(stage.."/koocomic.koplugin/main.lua")=="return {}")
assert(not updater:_extractPackage(good,stage),"a second extraction must not overwrite existing resources")
for index,path in ipairs({"koocomic.koplugin/../outside.lua","koocomic.koplugin/book.epub","koocomic.koplugin//alias.lua"}) do
    local archive=zip("bad-"..index,{{path,"private fixture"}})
    local target=directory.."/bad-"..index;assert(files:mkdir(target))
    assert(not updater:_extractPackage(archive,target),"unsafe real ZIP path accepted")
end
assert(files:write(directory.."/source","link fixture"))
assert(ffi.C.symlink(directory.."/source",directory.."/link")==0)
local writer=Archiver.Writer:new();local linked=directory.."/linked.zip"
assert(writer:open(linked,"zip"));writer:addPath("koocomic.koplugin/link",directory.."/link",false)
assert(not writer.err);writer:close()
local reader=Archiver.Reader:new();assert(reader:open(linked));assert(reader:next().mode=="link");reader:close()
local target=directory.."/linked";assert(files:mkdir(target))
assert(not updater:_extractPackage(linked,target),"real ZIP symbolic links must be rejected")
local corrupt=assert(files:read(good))
local at=assert(corrupt:find("return {}",1,true))
corrupt=corrupt:sub(1,at-1).."X"..corrupt:sub(at+1)
assert(files:write(directory.."/crc.zip",corrupt));target=directory.."/crc";assert(files:mkdir(target))
assert(not updater:_extractPackage(directory.."/crc.zip",target),"real libarchive CRC failure must abort package extraction")
if arg[2] then
    local release_stage=directory.."/release";assert(files:mkdir(release_stage))
    assert(updater:_extractPackage(arg[2],release_stage),"current packaged release must satisfy strict extraction")
    assert(files:read(release_stage.."/koocomic.koplugin/main.lua"))
end
print("KOReader bounded update package integration: OK")
