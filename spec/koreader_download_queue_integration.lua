-- Run from the official KOReader lib/koreader directory.
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
require("ffi/util")
local lfs=require("libs/libkoreader-lfs")
local Queue=require("koobone.download_queue")
local Store=require("koobone.download_queue_store")
local Coordinator=require("koobone.resource_coordinator")
local directory="/tmp/koocomic-download-queue-"..tonumber(ffi.C.getpid())
local store=Store:new{directory=directory,account_id="fixture-account"}
local events
local worker={asynchronous=true,start=function(_,_,callbacks)
    events=callbacks;return {cancel=function() return true end}
end}
local coordinator=Coordinator:new()
local function queue()
    return Queue:new{account_id="fixture-account",coordinator=coordinator,worker=worker,
        checkpoint=function(snapshot) return store:save(snapshot) end}
end
local first=queue()
assert(first:add({{vol_id="one",file_md5="version-one",vol_name="Original generated title",
    file_url="https://private.invalid/?signature=secret",cookie="do-not-save"}}).added==1)
assert(first:resume() and first:tick())
events.stage("downloading");events.progress(10,nil)
local persisted=assert(store:load())
assert(persisted.jobs[1].state=="downloading")
local file=assert(io.open(store.path,"rb"));local data=file:read("*a");file:close()
assert(not data:find("signature",1,true) and not data:find("cookie",1,true) and not data:find("file_url",1,true))
assert(first:cancel(first.jobs[1].id));events.done(false,{error_code="cancelled"})
local restarted=queue()
assert(restarted:restore(persisted) and restarted.paused and restarted.jobs[1].state=="interrupted")
assert(restarted.jobs[1].entry.title=="Original generated title")
assert(restarted:retry(restarted.jobs[1].id) and restarted:resume() and restarted:tick())
events.stage("downloading");events.stage("validating")
events.done(true,{validated=true,committed=true,bytes=50,output_fingerprint=string.rep("a",64)})
assert(store:load().jobs[1].state=="completed")
local recovered=queue();assert(recovered:restore(assert(store:load())) and recovered.jobs[1].state=="completed")
local small=Store:new{directory=directory,account_id="fixture-account",budget=20}
assert(not small:save(recovered:snapshot()),"oversized save must not replace the existing readable queue")
assert(store:load().jobs[1].state=="completed")
local other=Store:new{directory=directory,account_id="other-account"}
assert(other.path~=store.path and not other:load())
assert(lfs.link(store.path,other.path,true))
assert(not other:load() and not other:save{account_id="other-account"},"queue snapshots must reject symbolic aliases")
local hard=Store:new{directory=directory,account_id="hard-account"}
assert(lfs.link(store.path,hard.path,false))
assert(not store:load() and not hard:load(),"hardlinked queue snapshots must not be trusted")
print("KOReader download queue persistence integration: OK (no network worker tested)")
