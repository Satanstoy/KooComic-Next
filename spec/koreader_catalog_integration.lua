-- Run from official KOReader lib/koreader with checkout path as arg[1].
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local loaded,Task=pcall(require,"koobone.async_task")
assert(loaded,"catalog requests need an isolated asynchronous subprocess backend")
local scheduled,done,result={},false,nil
local runner=Task:new{schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
local parent=tonumber(ffi.C.getpid())
assert(runner:start(function()
    ffi.C.usleep(80000)
    return {pid=tonumber(ffi.C.getpid()),data=string.rep("x",200000)}
end,function(value,err) assert(not err,err);result=value;done=true end))
assert(not done,"a request must not complete synchronously on the UI thread")
for _=1,300 do
    if done then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(5000)
end
assert(done and result.pid~=parent and #result.data==200000,"large pipe results must be drained without deadlocking the worker")
local completed=false
local handle=assert(runner:start(function() ffi.C.usleep(2000000);return {} end,function(value,err)
    assert(not value and err);completed=true
end))
assert(handle.cancel())
for _=1,100 do
    if completed then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(5000)
end
assert(completed,"cancelled catalog subprocess must be acknowledged and reaped")
local Store=require("koobone.catalog_store")
local Library=require("koobone.library")
local lfs=require("libs/libkoreader-lfs")
local directory="/tmp/koocomic-catalog-"..parent
assert(lfs.mkdir(directory))
local account="42"
local count=5000
local source={}
for index=1,count do source[index]={vol_id=index,file_md5="id"..index,vol_name="Original "..index,
    file_url="https://example.test/signed/"..index,vol_series="Series",count_page=100} end
local store=Store:new{directory=directory}
local library=Library:new({library=function(_,limit)
    assert(tonumber(ffi.C.getpid())~=parent,"real catalog IO must execute in the child")
    local data={};for index=1,math.min(limit,count) do data[index]=source[index] end
    return {data=data,total=count}
end},{itemKey=function(_,item) return item.file_md5 end},
    {account=function() return account end,store=store,runner=runner})
done=false
assert(library:refreshAsync(function(items,err) assert(items and #items==count,err);done=true end))
for _=1,300 do
    if done then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(5000)
end
assert(done and store:load("42").entries[count].title=="Original "..count)
local snapshot_file=assert(io.open(directory.."/42.json","rb"))
local persisted=snapshot_file:read("*a");snapshot_file:close()
assert(not persisted:find("signed/",1,true),"signed URLs must never reach persistent cache")
library:clear()
assert(library:loadCache() and #library.items==count and library.items[1].file_url==nil)
account="99";assert(not library:loadCache() and #library.items==0)
local victim=directory.."/victim"
local file=assert(io.open(victim,"wb"));file:write("unchanged");file:close()
assert(lfs.link(victim,directory.."/42.json.tmp",true))
assert(not store:commit("42",store:load("42").entries,{coverage="complete",verified=true}),
    "cache writes must refuse symlink temporary files")
assert(lfs.link(victim,directory.."/42.json.tmp",false))
assert(not store:commit("42",store:load("42").entries,{coverage="complete",verified=true}),
    "cache writes must refuse hardlink temporary aliases")
local original=assert(io.open(victim,"rb"));assert(original:read("*a")=="unchanged");original:close()
print("KOReader catalog subprocess integration: OK")
