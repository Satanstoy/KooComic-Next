-- Run from the official Linux KOReader runtime with this checkout as arg[1].
require("setupkoenv")
local root=assert(arg[1])
package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local available, Backend=pcall(require,"koobone.preprocess_koreader")
assert(available,"KOReader image/ZIP preprocessing backend is missing")
local files_available, Files=pcall(require,"koobone.preprocess_files")
assert(files_available,"durable preprocessing filesystem backend is missing")
local worker_available, Worker=pcall(require,"koobone.preprocess_worker")
assert(worker_available,"isolated preprocessing process is missing")
local service_available, Service=pcall(require,"koobone.preprocess_service")
assert(service_available,"production preprocessing queue service is missing")
local ffi=require("ffi")
local Png=require("ffi/png")
local Archive=require("ffi/archiver")
local Sha=require("ffi/sha2")
local directory=assert(arg[2]).."/run-"..tonumber(ffi.C.getpid())
assert(require("libs/libkoreader-lfs").mkdir(directory))
local files=Files:new{roots={directory}}
local data=ffi.new("unsigned char[?]",64*64*4)
for y=0,63 do for x=0,63 do
    local offset=(y*64+x)*4
    local value=math.floor(128+60*math.cos(2*math.pi*20*(x+y)/64))
    data[offset],data[offset+1],data[offset+2],data[offset+3]=value,value,value,255
end end
assert(Png.encodeToFile(directory.."/page.png",data,64,64,4))
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local page=read(directory.."/page.png")
local Jpeg=require("ffi/jpeg")
assert(Jpeg.encodeToFile(directory.."/page.jpg",data,64,64,4,100,256))
local jpeg=read(directory.."/page.jpg")
local source=directory.."/source.epub"
local output=directory.."/output.epub"
os.remove(output)
local writer=Archive.Writer:new();assert(writer:open(source,"zip"))
assert(writer:setZipCompression("store"))
assert(writer:addFileFromMemory("mimetype","application/epub+zip"))
assert(writer:setZipCompression("deflate"))
assert(writer:addFileFromMemory("META-INF/container.xml",'<container><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'))
local opf='<package><manifest><item id="page" href="page.png" media-type="image/png"/><item id="jpeg" href="page.jpg" media-type="image/jpeg"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>'
assert(writer:addFileFromMemory("OPS/book.opf",opf))
assert(writer:addFileFromMemory("OPS/chapter.xhtml",'<html xmlns="http://www.w3.org/1999/xhtml"><body><img src="page.png"/></body></html>'))
assert(writer:addFileFromMemory("OPS/page.png",page))
assert(writer:addFileFromMemory("OPS/page.jpg",jpeg));writer:close()
local fingerprint=Sha.sha256(read(source))
local backend=Backend:new{native_library=root.."/native/preprocess/build/moire-host.so",workspace=directory,memory_budget=256*1024*1024}
local result=assert(backend:process(source,output,{profile={strength=1}}))
assert(result.validated and result.processed_pages==2)
assert(Sha.sha256(read(source))==fingerprint,"source EPUB must remain byte-identical")
local reader=Archive.Reader:new();assert(reader:open(output));for _ in reader:iterate() do end
assert(reader:extractToMemory("OPS/book.opf")==opf)
local optimized=assert(reader:extractToMemory("OPS/page.png"))
assert(optimized~=page,"real image bytes must be processed")
assert(reader:extractToMemory("OPS/page.jpg")~=jpeg,"JPEG resources must also be processed")
local f=assert(io.open(directory.."/result.png","wb"));assert(f:write(optimized));f:close()
local ok,image=Png.decodeFromFile(directory.."/result.png",4);assert(ok and image.width==64 and image.height==64)
local low,high=255,0
for index=0,64*64-1 do local value=image.data[index*4];low=math.min(low,value);high=math.max(high,value) end
ffi.C.free(image.data)
assert(high-low<36,"actual EPUB image must suppress the synthetic diagonal pattern")
reader:close()
local odd=ffi.new("unsigned char[?]",63*65*4)
ffi.fill(odd,63*65*4,120)
assert(Png.encodeToFile(directory.."/odd.png",odd,63,65,4))
local odd_result=backend:_image(read(directory.."/odd.png"),"image/png",{strength=0.8})
local out=assert(io.open(directory.."/odd-result.png","wb"));out:write(odd_result);out:close()
local odd_ok,odd_image=Png.decodeFromFile(directory.."/odd-result.png",4)
assert(odd_ok and odd_image.width==63 and odd_image.height==65,"padding must not alter EPUB page dimensions")
for index=0,63*65*4-1 do assert(math.abs(odd_image.data[index]-120)<=1) end
ffi.C.free(odd_image.data)
local scaled_result=backend:_image(page,"image/png",{strength=0.5,scale_mode="fit",target_width=32,target_height=24})
assert(files:write(directory.."/scaled.png",scaled_result))
local scaled_ok,scaled_image=Png.decodeFromFile(directory.."/scaled.png",4)
assert(scaled_ok and scaled_image.width==24 and scaled_image.height==24,
    "target profile must resample before filtering and encode the fitted dimensions")
ffi.C.free(scaled_image.data)
assert(files:hash(source)==fingerprint)
assert(files:writeJSON(directory.."/snapshot.json",{schema_version=1,stage="pending"}))
assert(files:readJSON(directory.."/snapshot.json").stage=="pending")
local scheduled,finished,worker_result={},false,nil
local worker=Worker:new{files=files,directory=directory,native_library=root.."/native/preprocess/build/moire-host.so",
    is_in_use=function() return false end,
    schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
local lfs=require("libs/libkoreader-lfs")
local temporary=source..".koocomic-preprocess.part"
if lfs.symlinkattributes(temporary,"mode")=="link" then os.remove(temporary) end
assert(lfs.link(source,temporary,true))
local unsafe=worker:start({id="symlink-rejection",source_path=source,source_fingerprint=fingerprint,profile={strength=1}},
    {stage=function() end,progress=function() end,done=function() end})
assert(not unsafe,"unsafe temporary output must be rejected before opening the EPUB writer")
assert(files:hash(source)==fingerprint)
assert(os.remove(temporary))
local handle=assert(worker:start({id="integration",source_path=source,source_fingerprint=fingerprint,profile={strength=1}},
    {stage=function() end,progress=function() end,done=function(ok,result) finished=ok;worker_result=result end}))
local bounded=false
for _=1,100 do
    local f=io.open("/proc/"..handle.pid.."/limits","rb")
    if f then local limits=f:read("*a");f:close();bounded=limits:match("Max address space%s+%d")~=nil end
    if bounded then break end
    ffi.C.usleep(10000)
end
assert(bounded,"the isolated worker needs an operating-system allocation limit")
for _=1,200 do
    if finished then break end
    local callbacks=scheduled;scheduled={}
    for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(finished and worker_result.validated,"isolated worker must finish a real file transaction")
assert(files:hash(source)~=fingerprint and files:hash(worker_result.backup_path)==fingerprint)
local optimized_fingerprint=files:hash(source)
finished=false
assert(worker:start({id="restore-integration",source_path=source,source_fingerprint=fingerprint,
    profile={restore=true,output_fingerprint=optimized_fingerprint}},
    {stage=function() end,progress=function() end,done=function(ok) finished=ok end}))
for _=1,200 do
    if finished then break end
    local callbacks=scheduled;scheduled={}
    for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(finished and files:hash(source)==fingerprint,"real original restoration must be byte-identical")
local storage={downloadDir=function() return directory end,isSafeLocalPath=function(_,path) return files:isSafe(path) end,
    resolveLocalPath=function() return source end,itemKey=function() return "service-book" end}
local service=Service:new{storage=storage,retain_original=true,directory=directory.."/service-"..tonumber(ffi.C.getpid()),native_library=root.."/native/preprocess/build/moire-host.so",
    is_in_use=function() return false end,schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
assert(service.available,service.reason)
assert(service:submit({}) and #service:jobs()==1 and not service:isActive())
assert(service:resume())
for _=1,300 do
    if service.queue.jobs[1] and service.queue.jobs[1].state=="completed" then break end
    local callbacks=scheduled;scheduled={}
    for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(service.queue.jobs[1] and service.queue.jobs[1].state=="completed","production service must process a downloaded file")
assert(files:hash(source)~=fingerprint)
assert(service:restore({}))
assert(service:resume())
for _=1,300 do
    if service.queue.jobs[2] and service.queue.jobs[2].state=="completed" then break end
    local callbacks=scheduled;scheduled={}
    for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(service.queue.jobs[2].state=="completed" and files:hash(source)==fingerprint)
assert(service:submit({}) and service:resume())
for _=1,300 do
    local last=service.queue.jobs[#service.queue.jobs]
    if last and last.state=="completed" and not last.profile.restore and #service.requests==0 then break end
    local callbacks=scheduled;scheduled={}
    for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(files:hash(source)~=fingerprint,"restored files must be eligible for processing again")
assert(service:restore({}),"a second recovery cycle must not be rejected as a duplicate")
assert(service:resume())
for _=1,300 do
    if service.queue.jobs[#service.queue.jobs].profile.restore and service.queue.jobs[#service.queue.jobs].state=="completed" then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(files:hash(source)==fingerprint)
assert(service:submit({}) and service:resume())
for _=1,300 do
    local last=service.queue.jobs[#service.queue.jobs]
    if last and last.state=="completed" and not last.profile.restore and #service.requests==0 then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
service:pause()
local damaged=assert(service.files:readJSON(service.state_path))
local last=damaged.queue.jobs[#damaged.queue.jobs]
last.state,last.output_fingerprint="validating",nil
assert(service.files:writeJSON(service.state_path,damaged))
local recovered=Service:new{storage=storage,retain_original=true,directory=service.directory,native_library=root.."/native/preprocess/build/moire-host.so",
    is_in_use=function() return false end,schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
assert(recovered.available,recovered.reason)
for _=1,200 do
    if not recovered.reconciling then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(recovered:record(source),"restart must recover a committed transaction even when the queue snapshot missed completion")
assert(recovered.queue.paused,"recovery must not restart waiting jobs automatically")
assert(recovered:restore({}) and recovered:resume())
for _=1,300 do
    if recovered.queue.jobs[#recovered.queue.jobs].profile.restore and recovered.queue.jobs[#recovered.queue.jobs].state=="completed" then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(files:hash(source)==fingerprint)
assert(recovered:submit({}) and recovered:resume())
for _=1,100 do
    if recovered.queue.active then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
local cancelled_job=assert(recovered.queue.active).job
assert(recovered:cancel(cancelled_job.id))
for _=1,100 do
    if not recovered.queue.active then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(cancelled_job.state=="cancelled" and files:hash(source)==fingerprint)
local interrupted_paths=recovered.worker:paths(cancelled_job)
assert(recovered.files:write(interrupted_paths.temporary,"owned interrupted output"))
assert(recovered.files:write(interrupted_paths.workspace.."/page.codec","owned interrupted codec"))
recovered:reconcile()
for _=1,200 do
    if not recovered.reconciling then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(not recovered.files:exists(interrupted_paths.temporary) and not recovered.files:exists(interrupted_paths.workspace.."/page.codec"))
assert(recovered:retry(cancelled_job.id) and recovered:resume())
for _=1,300 do
    if cancelled_job.state=="completed" then break end
    local callbacks=scheduled;scheduled={};for _, callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(cancelled_job.state=="completed" and files:hash(source)~=fingerprint)
recovered:pause()
local dead_source=directory.."/dead-worker.epub"
assert(files:copy(worker_result.backup_path,dead_source))
local deferred={}
local dead_worker=Worker:new{files=files,directory=directory.."/dead-worker",native_library=root.."/native/preprocess/build/moire-host.so",
    is_in_use=function() return false end,
    schedule=function(delay,callback) deferred[#deferred+1]={delay=delay,callback=callback} end}
local dead_job={id="dead-worker",source_path=dead_source,source_fingerprint=fingerprint,profile={strength=1}}
local dead_paths=dead_worker:paths(dead_job)
local dead_done=false
local dead_handle=assert(dead_worker:start(dead_job,{stage=function() end,progress=function() end,
    done=function(ok) assert(not ok);dead_done=true end}))
for _=1,200 do
    local state=files:readJSON(dead_paths.status)
    if state and state.state=="committing" then break end
    ffi.C.usleep(10000)
end
assert(files:readJSON(dead_paths.status).state=="committing")
table.remove(deferred,1).callback()
require("ffi/util").terminateSubProcess(dead_handle.pid)
ffi.C.usleep(50000)
local poll_index
for index,entry in ipairs(deferred) do if entry.delay==0.1 then poll_index=index end end
assert(poll_index)
table.remove(deferred,poll_index).callback()
assert(dead_done,"dead child must release the task before deferred hashes run")
for _=1,100 do
    if #deferred==0 then break end
    table.remove(deferred,1).callback()
end
assert(files:hash(dead_source)==fingerprint,"late hashes must not commit after the worker exits")
assert(not files:exists(dead_paths.permission),"late hashes must not authorize a retry worker")
local direct_source=directory.."/direct.epub"
assert(files:copy(worker_result.backup_path,direct_source))
local direct_storage={downloadDir=function() return directory end,isSafeLocalPath=function(_,path) return files:isSafe(path) end,
    resolveLocalPath=function() return direct_source end,itemKey=function() return "direct-book" end}
local function directService()
    return Service:new{storage=direct_storage,directory=directory.."/direct-service",
        native_library=root.."/native/preprocess/build/moire-host.so",is_in_use=function() return false end,
        schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
end
local direct=directService()
assert(direct.available and direct:submit({}) and direct:resume())
for _=1,300 do
    if direct.queue.jobs[1] and direct.queue.jobs[1].state=="completed" then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
direct:pause()
local direct_job=assert(direct.queue.jobs[1])
assert(direct_job.state=="completed" and direct_job.profile.discard_original==true)
assert(files:hash(direct_source)~=fingerprint and not direct.files:exists(direct.worker:paths(direct_job).backup),
    "default service must replace the source without creating an original backup")
assert(not direct:restore({}),"direct replacement must not advertise a recoverable original")
local direct_snapshot=assert(direct.files:readJSON(direct.state_path))
direct_snapshot.queue.jobs[1].state="validating";direct_snapshot.queue.jobs[1].output_fingerprint=nil
assert(direct.files:writeJSON(direct.state_path,direct_snapshot))
direct=directService();assert(direct.available)
for _=1,200 do
    if not direct.reconciling then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
assert(direct.queue.jobs[1].state=="completed" and direct:record(direct_source),
    "direct replacement must recover a committed output without a backup")
local profiled_source=directory.."/profiled.epub"
assert(files:copy(worker_result.backup_path,profiled_source))
local controls={strength=0.4,scale_mode="fit",target_width=32,target_height=24}
local profiled=Service:new{storage={downloadDir=function() return directory end,
    isSafeLocalPath=function(_,path) return files:isSafe(path) end,resolveLocalPath=function() return profiled_source end,
    itemKey=function() return "profiled-book" end},directory=directory.."/profiled-service",
    native_library=root.."/native/preprocess/build/moire-host.so",is_in_use=function() return false end,
    profile_provider=function() return controls end,schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
assert(profiled.available and profiled:submit({}))
controls.strength,controls.scale_mode=0.9,"original"
assert(profiled.requests[1].profile.strength==0.4 and profiled:resume())
for _=1,300 do
    if profiled.queue.jobs[1] and profiled.queue.jobs[1].state=="completed" then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
profiled:pause()
assert(profiled.queue.jobs[1].state=="completed" and profiled.queue.jobs[1].profile.scale_mode=="fit",
    "queued processing must use frozen parameters, not controls changed after enqueue")
local scaled_reader=Archive.Reader:new();assert(scaled_reader:open(profiled_source));for _ in scaled_reader:iterate() do end
local frozen_page=assert(scaled_reader:extractToMemory("OPS/page.png"));scaled_reader:close()
assert(files:write(directory.."/frozen.png",frozen_page))
local frozen_ok,frozen_image=Png.decodeFromFile(directory.."/frozen.png",4)
assert(frozen_ok and frozen_image.width==24 and frozen_image.height==24);ffi.C.free(frozen_image.data)
local invalid_directory=directory.."/invalid-profile";assert(files:mkdir(invalid_directory))
assert(files:writeJSON(invalid_directory.."/tasks.json",{schema_version=1,requests={{id=1,book_id="invalid",
    source_path=profiled_source,state="pending",profile=false}},queue={schema_version=1,paused=true,jobs={}}}))
local before_invalid=files:hash(invalid_directory.."/tasks.json")
local invalid_service=Service:new{storage=profiled.storage,directory=invalid_directory,
    native_library=root.."/native/preprocess/build/moire-host.so",is_in_use=function() return false end,
    schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
assert(not invalid_service.available and files:hash(invalid_directory.."/tasks.json")==before_invalid,
    "invalid false request profile must disable recovery without rewriting the snapshot")
local batch_paths,batch_items={},{}
for index=1,20 do
    local id="batch-"..index
    batch_paths[id]=directory.."/"..id..".epub"
    assert(files:copy(worker_result.backup_path,batch_paths[id]))
    batch_items[#batch_items+1]={file_md5=id,vol_name="Original batch "..index}
end
batch_paths.optimized=direct_source
batch_paths.bad=directory.."/bad-batch.epub";assert(files:write(batch_paths.bad,"<html>invalid EPUB</html>"))
batch_paths.occupied=directory.."/occupied-batch.epub";assert(files:copy(worker_result.backup_path,batch_paths.occupied))
direct_storage.resolveLocalPath=function(_,item) return batch_paths[item.file_md5] end
direct_storage.itemKey=function(_,item) return item.file_md5 end
direct_storage.fileSize=function(_,path) return lfs.attributes(path,"size") end
direct.is_in_use=function(path) return path==batch_paths.occupied end
direct.space=function() return 128*1024*1024 end
batch_items[#batch_items+1]={file_md5="optimized"}
batch_items[#batch_items+1]={file_md5="bad"}
batch_items[#batch_items+1]=batch_items[1]
batch_items[#batch_items+1]={file_md5="occupied"}
batch_items[#batch_items+1]={file_md5="missing"}
local batch_summary,batch_notifications=nil,0
direct.on_batch=function(value) batch_summary=value;batch_notifications=batch_notifications+1 end
local added=assert(direct:submitBatch(batch_items))
assert(added.added==22 and added.duplicate==1 and added.occupied==1 and added.invalid==1)
assert(direct:resume())
for _=1,3000 do
    if batch_summary then break end
    local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
    ffi.C.usleep(10000)
end
direct:pause()
assert(batch_summary and batch_summary.completed==20 and batch_summary.optimized==1 and batch_summary.failed==1 and
    batch_summary.skipped==3 and batch_notifications==1,"actual mixed preprocessing batch must continue after failure and summarize once")
for index=1,20 do assert(files:hash(batch_paths["batch-"..index])~=fingerprint) end
local batch_snapshot=assert(direct.files:readJSON(direct.state_path))
batch_snapshot.requests={}
while #batch_snapshot.batch.members>20 do table.remove(batch_snapshot.batch.members) end
batch_snapshot.batch.finished=false
assert(direct.files:writeJSON(direct.state_path,batch_snapshot))
local batch_recovered=directService()
assert(batch_recovered.available,batch_recovered.reason)
assert(batch_recovered.next_id>20,"restart must reserve IDs of transferred requests retained in batch metadata")
local function rejected_snapshot(value)
    assert(files:writeJSON(invalid_directory.."/tasks.json",value))
    local before=files:hash(invalid_directory.."/tasks.json")
    local invalid=Service:new{storage=profiled.storage,directory=invalid_directory,
        native_library=root.."/native/preprocess/build/moire-host.so",is_in_use=function() return false end,
        schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
    assert(not invalid.available and files:hash(invalid_directory.."/tasks.json")==before,"malformed batch/request snapshot must be preserved")
end
rejected_snapshot{schema_version=1,requests={},queue={schema_version=1,paused=true,jobs={}},batch=false}
rejected_snapshot{schema_version=1,requests={{id=1,book_id="one",source_path=profiled_source,state="pending"},
    {id=1,book_id="two",source_path=profiled_source,state="pending"}},queue={schema_version=1,paused=true,jobs={}}}
local Storage=require("koobone.storage")
local records={}
local real_storage=Storage:new{download=function() return {directory=directory,records=records} end,flush=function() end}
local item={file_md5="processed-book",vol_name="Processed book"}
records[real_storage:itemKey(item)]={path=source,title=item.vol_name,state="complete"}
real_storage.is_in_use=function() return false end
real_storage.preprocess=recovered
local callbacks,result={},nil
local manager=require("koobone.local_manager"):new{storage=real_storage,
    schedule=function(_,callback) callbacks[#callbacks+1]=callback end}
local preview=manager:preview({item})
assert(preview.files==1)
local backup=recovered.worker:paths(cancelled_job).backup
assert(files:exists(backup),"processed-book deletion must exercise a real retained original")
assert(manager:execute(preview,function(value) result=value end))
while #callbacks>0 do table.remove(callbacks,1)() end
assert(result.success==1 and result.failed==0 and result.files_removed==1,
    "processed EPUB deletion must tolerate absent worker temporary files and finish cleanup")
assert(not files:exists(source) and not files:exists(backup) and not records[real_storage:itemKey(item)])
print("KOReader real EPUB integration: OK")
