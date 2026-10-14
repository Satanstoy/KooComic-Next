package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Status=pcall(require,"koobone.preprocess_status")
assert(loaded,"processing status must verify the current local file asynchronously")
local path="/books/one.epub"
local versions={[path]="inode-1"}
local hashes={[path]=string.rep("a",64)}
local tasks,changes={},0
local busy=false
local coordinator=require("koobone.resource_coordinator"):new()
local options={storage={fileIdentity=function(_,value) return versions[value] end},coordinator=coordinator,
    schedule=function(_,callback) tasks[#tasks+1]=callback end,may_start=function() return not busy end,
    on_changed=function() changes=changes+1 end,
    files={hashAsync=function(_,value,schedule,guard,done)
        schedule(0,function() done(guard() and hashes[value] or nil) end)
    end}}
local status=Status:new(options)
local function pump() for _=1,20 do if #tasks==0 then return end;table.remove(tasks,1)() end;assert(#tasks==0) end
assert(status:check(path,string.rep("a",64))=="checking" and coordinator:owner()=="preprocess_status")
pump();assert(status:check(path,string.rep("a",64))=="optimized" and coordinator:owner()==nil)
versions[path],hashes[path]="inode-2",string.rep("b",64)
assert(status:check(path,string.rep("a",64))=="checking","same-path replacement cannot inherit the old processed status")
pump();assert(status:check(path,string.rep("a",64))=="unprocessed")
versions[path]=nil;assert(status:check(path,string.rep("a",64))=="missing")
versions[path],hashes[path]="inode-3",nil
assert(status:check(path,string.rep("a",64))=="checking")
pump();assert(status:check(path,string.rep("a",64))=="check_failed" and #tasks==0,"read failures must not create an endless verification loop")
versions[path],hashes[path]="inode-4",string.rep("a",64)
busy=true
assert(status:check(path,string.rep("a",64))=="checking" and #tasks==0)
busy=false
assert(status:check(path,string.rep("a",64))=="checking")
local before=changes
status:close();pump()
assert(coordinator:owner()==nil and changes==before,"closing must release a cancelled hash without publishing stale state")
print("preprocess current-file status spec: OK")
