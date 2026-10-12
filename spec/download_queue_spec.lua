package.path="./koocomic.koplugin/?.lua;"..package.path
local available,Queue=pcall(require,"koobone.download_queue")
assert(available,"persistent independent download queue is missing")
local Coordinator=require("koobone.resource_coordinator")
local callbacks,started,saved={},{},nil
local coordinator=Coordinator:new()
local worker={asynchronous=true,start=function(_,job,events)
    started[#started+1]=job;callbacks[#callbacks+1]=events
    return {cancel=function() return true end}
end}
local function item(id,size)
    return {vol_id=id,file_md5="version-"..id,vol_name="Original title "..id,file_size=size,
        file_url="https://private.invalid/?signature=secret",cookie="do-not-save"}
end
local queue=Queue:new{account_id="test-account",coordinator=coordinator,worker=worker,
    is_downloaded=function(raw) return raw.vol_id=="existing" end,
    checkpoint=function(snapshot) saved=snapshot;return true end}
local counts=assert(queue:add({item("one",100),item("one",100),item("two"),item("existing"),{vol_name="invalid"}}))
assert(counts.added==2 and counts.duplicate==1 and counts.downloaded==1 and counts.invalid==1)
assert(queue.paused and #started==0 and #queue.jobs==2,"enqueue must not implicitly start work")
assert(queue.jobs[1].entry.title=="Original title one" and queue.jobs[2].entry.remote_size==nil)
assert(saved.jobs[1].entry.file_url==nil and saved.jobs[1].entry.cookie==nil and saved.jobs[1].entry.source.file_md5=="version-one")
assert(saved.jobs[1].handle==nil and saved.jobs[1].token==nil)
assert(type(queue.resume)=="function" and type(queue.tick)=="function","download execution state machine is missing")
local token=assert(coordinator:acquire("preprocess"))
assert(queue:resume())
assert(not queue:tick() and #started==0)
coordinator:release(token)
assert(queue:tick() and queue.jobs[1].state=="preparing" and queue.jobs[1].attempts==1)
callbacks[1].stage("downloading");callbacks[1].progress(20,100)
assert(queue.jobs[1].state=="downloading" and queue.jobs[1].bytes==20)
callbacks[1].progress(19,100);callbacks[1].progress(math.huge,math.huge)
assert(queue.jobs[1].bytes==20,"invalid/backwards progress must not corrupt counters")
assert(queue:pause())
callbacks[1].stage("validating")
callbacks[1].done(true,{validated=true,committed=true,bytes=100,output_fingerprint=string.rep("a",64)})
assert(queue.jobs[1].state=="completed" and coordinator:owner()==nil)
assert(not queue:tick() and #started==1,"pause must stop the next item, not the current item")
assert(queue:resume() and queue:tick())
assert(queue:cancel(queue.jobs[2].id) and coordinator:owner()=="download","running cancellation must wait for acknowledgement")
callbacks[2].done(false,{error_code="cancelled"})
assert(queue.jobs[2].state=="cancelled" and coordinator:owner()==nil)
assert(queue:retry(queue.jobs[2].id) and queue:tick())
callbacks[2].done(false,{error_code="late"})
assert(coordinator:owner()=="download" and queue.jobs[2].state=="preparing","late worker must not release a new permit")
callbacks[3].done(true,{})
assert(queue.jobs[2].state=="failed","unvalidated success must not complete downloads")
assert(not queue:retry(queue.jobs[1].id),"completed downloads must not be blindly retried")
assert(type(queue.restore)=="function","download restart reconciliation is missing")
local recovering=Queue:new{account_id="test-account",coordinator=coordinator,worker=worker,checkpoint=function() return true end}
local snapshot=queue:snapshot();snapshot.jobs[2].state="downloading"
assert(recovering:restore(snapshot) and recovering.paused and recovering.jobs[2].state=="interrupted")
assert(recovering.jobs[1].state=="completed" and #started==3)
local invalid=queue:snapshot();invalid.jobs[1].id="forged"
assert(not recovering:restore(invalid) and recovering.jobs[1].id==snapshot.jobs[1].id)
invalid=queue:snapshot();invalid.account_id="other"
assert(not recovering:restore(invalid),"another account queue must not be restored")
for _,mutate in ipairs({
    function(value) value.jobs[1].bytes=math.huge end,
    function(value) value.jobs[1].output_fingerprint=nil end,
    function(value) value.jobs[1].entry.source={} end,
    function(value) value.jobs[1].entry.remote_size=-1 end,
    function(value) value.jobs[1].error_code="https://private.invalid/?Cookie=secret" end,
    function(value) value.jobs[1].state="invented" end,
    function(value) value.jobs[1].bytes=1;value.jobs[1].total=2 end,
    function(value) value.jobs[1].total=nil end,
    function(value) value.jobs[3]=value.jobs[1];value.jobs[2]=nil end,
}) do
    invalid=queue:snapshot();mutate(invalid)
    local caught,ok=pcall(recovering.restore,recovering,invalid)
    assert(caught and not ok,"corrupt persisted fields must be rejected without throwing")
end
local save_ok=false
local failure=Queue:new{account_id="test-account",coordinator=coordinator,worker=worker,
    checkpoint=function() return save_ok end}
assert(not failure:add({item("failure")}) and #failure.jobs==0)
save_ok=true;assert(failure:add({item("failure")}) and failure:resume())
save_ok=false;local start_count=#started
assert(not failure:tick() and failure.jobs[1].state=="pending" and coordinator:owner()==nil and #started==start_count)
save_ok=true;assert(failure:resume() and failure:tick())
assert(failure:cancel(failure.jobs[1].id))
callbacks[#callbacks].done(true,{validated=true,committed=true,bytes=10,output_fingerprint=string.rep("b",64)})
assert(failure.jobs[1].state=="completed","committed file must win over late cancellation")
assert(not queue:add({[2]=item("sparse")}),"sparse input must not silently omit selected jobs")
assert(queue:add({item("unauthorized",12)}).added==1)
assert(queue:tick())
callbacks[#callbacks].done(false,{error_code="unauthorized",error="Cookie=secret"})
assert(queue.jobs[#queue.jobs].error_code=="unauthorized","typed nonretryable failures must survive without secret error text")
assert(queue:retry(queue.jobs[#queue.jobs].id) and queue:tick())
callbacks[#callbacks].done(true,{validated=true,committed=true,bytes=11,output_fingerprint=string.rep("a",64)})
assert(queue.jobs[#queue.jobs].state=="failed","known declared byte size must agree before completion")
assert(queue:add({item("empty")}).added==1 and queue:tick())
callbacks[#callbacks].done(true,{validated=true,committed=true,bytes=0,output_fingerprint=string.rep("a",64)})
assert(queue.jobs[#queue.jobs].state=="failed","empty files must not become completed EPUBs")
local fail_restore=Queue:new{account_id="test-account",coordinator=coordinator,worker=worker,checkpoint=function() return false end}
fail_restore.paused=false
assert(not fail_restore:restore(queue:snapshot()) and #fail_restore.jobs==0 and fail_restore.paused,
    "restore checkpoint failure must preserve old jobs and stop launching workers")
print("download queue spec: OK")
