package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Transport=pcall(require,"koobone.download_transport")
assert(loaded,"independent download transport is missing")
local work,complete,downloaded,validated,synced=nil,nil,false,false,false
local runner={start=function(_,task,done) work,complete=task,done;return {cancel=function() return true end} end}
local files={isSafe=function() return true end,exists=function() return false end,
    sync=function() synced=true;return true end,hash=function() return string.rep("a",64) end,
    prefix=function() return "PK\003\004" end,
    exclusiveWriter=function() return {write=function() return true end,close=function() return true end} end}
local transport=Transport:new{runner=runner,files=files,max_bytes=100,
    resolve=function() return {file_url="https://private.invalid/signed"} end,
    api={download=function(_,url,path,options)
        assert(url=="https://private.invalid/signed" and path=="/books/book.epub.part" and options.max_bytes==100)
        downloaded=true;return true,{},12
    end},validate=function() validated=true;return true end}
local result
assert(transport:start({entry={remote_size=12}},"/books/book.epub.part",function(value) result=value end))
assert(not downloaded and not result,"start must only schedule isolated IO")
local value=assert(work());complete(value)
assert(downloaded and validated and synced and result.validated and not result.committed and result.bytes==12)
assert(result.file_url==nil,"transport result must not leak a signed URL")
transport.validate=function() return nil end
assert(transport:start({entry={}},"/books/book.epub.part",function() end))
local failed=assert(work());assert(failed.error_code=="invalid_epub")
transport.resolve=function() return nil end
assert(transport:start({entry={}},"/books/book.epub.part",function() end))
assert(work().error_code=="network")
assert(not transport:start({entry={}},"/books/unsafe.txt",function() end),"only explicit .part paths may be written")
transport.resolve=function() return {file_url="https://private.invalid/signed"} end
transport.validate=function() return true end
files.prefix=function() return "TAR!" end
assert(transport:start({entry={}},"/books/book.epub.part",function() end))
assert(work().error_code=="invalid_epub","non-ZIP archives must not pass EPUB transport validation")
files.exclusiveWriter=function() return nil,"created by an external writer" end
downloaded=false
assert(transport:start({entry={}},"/books/book.epub.part",function() end))
assert(work().error_code=="path_conflict" and not downloaded,"exclusive creation races must not invoke the unsafe download writer")
print("download transport spec: OK")
