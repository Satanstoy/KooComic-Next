-- Real temporary-file deletion; run from official KOReader lib/koreader.
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local lfs=require("libs/libkoreader-lfs")
local Storage=require("koobone.storage")
local available,Manager=pcall(require,"koobone.local_manager")
assert(available,"production batch deletion backend is missing")
local directory="/tmp/koocomic-local-"..tonumber(ffi.C.getpid())
assert(lfs.mkdir(directory));assert(lfs.mkdir(directory.."/books"))
local records={}
local settings={download=function() return {directory=directory.."/books",records=records} end,flush=function() end}
local storage=Storage:new(settings)
storage.is_in_use=function() return false end
local Archive=require("ffi/archiver")
local function epub(path)
    local writer=Archive.Writer:new();assert(writer:open(path,"zip"));assert(writer:setZipCompression("store"))
    assert(writer:addFileFromMemory("mimetype","application/epub+zip"));writer:close()
end
local a,b,c={file_md5="a",vol_name="A"},{file_md5="b",vol_name="B"},{file_md5="c",vol_name="C"}
local ap,bp,cp=storage:itemPath(a),storage:itemPath(b),storage:itemPath(c)
epub(ap);epub(bp);epub(cp)
storage:record(a,"complete");storage:record(b,"complete");storage:record(c,"complete")
local f=assert(io.open(bp..".part","wb"));f:write("keep partial");f:close()
assert(lfs.mkdir(bp..".sdr"))
local callbacks={}
local manager=Manager:new{storage=storage,schedule=function(_,callback) callbacks[#callbacks+1]=callback end}
local preview=manager:preview({a,b,c})
assert(preview.files==3 and preview.bytes>0)
storage.is_in_use=function(path) return path==ap end
local changed=assert(io.open(cp,"ab"));changed:write("changed after confirmation");changed:close()
local result
assert(manager:execute(preview,function(value) result=value end))
while #callbacks>0 do table.remove(callbacks,1)() end
assert(result.failed==2 and result.success==1 and result.files_removed==1)
assert(lfs.attributes(ap,"mode")=="file" and lfs.attributes(cp,"mode")=="file")
assert(not lfs.attributes(bp,"mode") and lfs.attributes(bp..".part","mode")=="file")
assert(lfs.attributes(bp..".sdr","mode")=="directory" and records.b,"partial files must remain indexed and sidecars untouched")
local outside=directory.."/outside.epub";epub(outside)
records.outside={path=outside,title="Outside"}
assert(not storage:deleteRecordFiles("outside") and lfs.attributes(outside,"mode")=="file")
local link=directory.."/books/link.epub";assert(lfs.link(outside,link,true))
records.link={path=link,title="Link"}
assert(not storage:localDeleteInfo{file_md5="link"})
print("KOReader real batch deletion integration: OK")
