package.path="./koocomic.koplugin/?.lua;"..package.path
local ok,Manager=pcall(require,"koobone.local_manager")
assert(ok,"batch local-file manager is missing")
local calls,scheduled={},{}
local records={a={key="a",path="/books/a.epub",identity="a1",size=10,title="A"},
    b={key="b",path="/books/b.epub",identity="b1",size=20,title="B"}}
local storage={localDeleteInfo=function(_,item) return records[item.file_md5],"not indexed" end,
    deleteIndexedLocal=function(_,entry)
        calls[#calls+1]=entry.key
        if entry.key=="a" then return nil,"permission denied" end
        return true,entry.size
    end}
local manager=Manager:new{storage=storage,downloader={isActive=function() return false end},
    schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
local preview=manager:preview({{file_md5="a"},{file_md5="b"},{file_md5="b"},{file_md5="missing"}})
assert(preview.files==2 and preview.bytes==30 and preview.skipped==1,"preview must count real deduplicated files")
local summary
assert(manager:execute(preview,function(result) summary=result end))
assert(#calls==0,"batch deletes must yield before the first file")
while #scheduled>0 do table.remove(scheduled,1)() end
assert(summary.failed==1 and summary.success==1 and summary.bytes==20 and summary.files_removed==1)
assert(#calls==2 and #summary.errors==1,"one failure must not stop remaining local deletes")
local busy=Manager:new{storage=storage,downloader={isActive=function() return true end}}
assert(not busy:execute(preview,function() error("busy callback") end),"active transfer must reject deletion")
calls={};summary=nil
assert(manager:execute(preview,function(value) summary=value end,function() return false end))
table.remove(scheduled,1)()
assert(summary and summary.failed==2 and #scheduled==0 and #calls==0,"account loss must abort remaining work and release promptly")
local Coordinator=require("koobone.resource_coordinator")
local coordinator=Coordinator:new()
local broken=Manager:new{storage=storage,coordinator=coordinator,schedule=function() error("scheduler stopped") end}
assert(not broken:execute(preview,function() end) and coordinator:owner()==nil,"schedule failures must not leak the resource permit")
print("local manager spec: OK")
