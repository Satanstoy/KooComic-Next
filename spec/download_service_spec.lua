package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Service=pcall(require,"koobone.download_service")
assert(loaded,"production download queue service is missing")
local account="one"
local tasks,callbacks,snapshots={ },{ },{ }
local settings={account=function() return {uin=account} end}
local service=Service:new{settings=settings,directory="/private/downloads",storage={isDownloaded=function(_,raw) return raw.file_md5=="exists" end,
        resolveDownloadPath=function(_,raw) return "/books/"..raw.vol_name..".epub" end},api={},
    library={account_id="one",urls_at=os.time(),items={{file_md5="one",file_url="signed"}}},
    space=function() return 1024*1024*128 end,schedule=function(_,callback) tasks[#tasks+1]=callback end,
    worker_factory=function() return {asynchronous=true,start=function(_,_,events)
        callbacks[#callbacks+1]=events;return {cancel=function() return true end}
    end} end,
    store_factory=function(id) return {load=function() return snapshots[id] end,
        save=function(_,value) snapshots[id]=value;return true end} end}
local items={{file_md5="one",vol_name="Original",file_size=12},{file_md5="two",vol_name="Unknown"},
    {file_md5="exists",vol_name="Already here"}}
local preview=assert(service:preview(items))
assert(preview.files==2 and preview.bytes==12 and preview.unknown==1 and preview.downloaded==1)
service.options.space=function() return service.reserve+15 end
assert(not service:preview({items[1]}),"known final bytes plus staging peak must be included in preview")
service.options.space=function() return 1024*1024*128 end
local counts=assert(service:enqueue(items,"one"));assert(counts.added==2)
local summary=service:summary(service.batch)
assert(summary.downloaded==1 and summary.skipped==1,"batch summaries must retain already-downloaded and other skipped classifications")
local restarted=Service:new{settings=settings,storage=service.storage,api={},library={},directory="/private",
    space=service.options.space,schedule=service.schedule,worker_factory=service.options.worker_factory,
    store_factory=service.options.store_factory}
assert(restarted:ensure())
local restored_summary=restarted:summary(restarted.batch)
assert(restarted.batch and restored_summary.pending==2 and restored_summary.downloaded==1,
    "restart must retain batch membership and skipped counts, without counting unrelated history")
assert(service:resume())
table.remove(tasks,1)()
assert(service:isActive() and #callbacks==1)
callbacks[1].stage("downloading");callbacks[1].stage("validating")
callbacks[1].done(true,{validated=true,committed=true,bytes=12,output_fingerprint=string.rep("a",64)})
assert(service:pause())
table.remove(tasks,1)()
assert(#callbacks==1,"pause must preserve pending jobs")
assert(service:resume());table.remove(tasks,1)()
account="two"
assert(not service:enqueue(items,"one"),"late confirmation must not enqueue against another account")
callbacks[2].done(false,{error_code="cancelled"})
assert(service:ensure() and service.queue.account_id=="two" and #service.queue.jobs==0)
service.queue.checkpoint=function() return false end
assert(not service:pause(),"pause checkpoint failures must not be reported as success")
local snapshot=snapshots.one
snapshot.jobs[1].state="validating";snapshot.jobs[1].output_fingerprint=nil
account="one"
local recovered=Service:new{settings=settings,storage=service.storage,api={},library={},directory="/private",
    space=function() return 1024*1024*128 end,schedule=function(_,callback) tasks[#tasks+1]=callback end,
    files={readJSON=function() return {job_id=snapshot.jobs[1].id,account_id="one",state="prepared",
        final_path="/books/Original.epub",output_fingerprint=string.rep("a",64),bytes=12} end,
        isSafe=function() return true end,hashAsync=function(_,_,_,_,done) done(string.rep("a",64)) end},
    worker_factory=function() return {asynchronous=true,start=function() end,paths=function() return {claim="claim"} end} end,
    store_factory=service.options.store_factory}
assert(recovered:ensure())
while #tasks>0 do table.remove(tasks,1)() end
assert(recovered.queue.jobs[1].state=="completed" and recovered.queue.jobs[1].bytes==12,
    "restart must reconcile a committed file when queue completion was not saved")
local added=assert(recovered:enqueue({{file_md5="foreign",vol_name="Wrong account",_catalog_account_id="two"},
    {file_md5="new",vol_name="New"}},"one"))
assert(added.added==1 and added.invalid==1 and #recovered.queue.jobs==3,"invalid preview rows must not be enqueued anyway")
assert(recovered:enqueue({items[1]},"one").added==1 and recovered.queue.jobs[1].state=="pending",
    "an externally deleted completed file must be downloadable again")
print("download service spec: OK")
