package.path="./koocomic.koplugin/?.lua;"..package.path
local Service=require("koobone.preprocess_service")
local service=Service:new{storage={},directory="/not-created"}
assert(type(service.submitBatch)=="function","real processing service lacks batch enqueue")
service.available=true
service.storage={resolveLocalPath=function(_,item) return item.file_md5 and "/books/"..item.file_md5..".epub" end,
    isSafeLocalPath=function() return true end,itemKey=function(_,item) return item.file_md5 end,
    fileSize=function() return 10 end}
service.is_in_use=function(path) return path=="/books/occupied.epub" end
service.space=function() return 128*1024*1024 end
service.queue={jobs={},snapshot=function(self) return {jobs=self.jobs} end}
local snapshot,fail_save
service.files={writeJSON=function(_,_,value) if fail_save then return nil end;snapshot=value;return true end}
local items={{file_md5="one",vol_name="Original"},{file_md5="one"},{file_md5="two"},{file_md5="occupied"},{vol_name="Invalid"}}
local preview=assert(service:previewBatch(items))
assert(preview.files==2 and preview.bytes==20 and preview.duplicate==1 and preview.occupied==1 and preview.invalid==1)
local counts=assert(service:submitBatch(items))
assert(counts.added==2 and #service.requests==2 and #snapshot.batch.members==2)
assert(snapshot.requests[1].profile.discard_original and service:batchSummary().pending==2)
fail_save=true
assert(not service:submitBatch({{file_md5="three"}}) and #service.requests==2 and #service.batch.members==2,
    "batch checkpoint failure must roll back requests and batch membership together")
service.requests[1].state="skipped";service.requests[2].state="failed"
local result=service:batchSummary()
assert(result.optimized==1 and result.failed==1 and result.skipped==3 and result.pending==0)
fail_save=false
local tasks={}
service.schedule=function(_,callback) tasks[#tasks+1]=callback end
service.queue.resume=function(self) self.paused=false;return true end
service.queue.tick=function() return nil,"idle" end
assert(service:resume());table.remove(tasks,1)()
assert(not service.running and #tasks==0,"finished processing queues must stop polling instead of waking an idle device at 5 Hz")
print("preprocess batch spec: OK")
