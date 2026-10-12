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
local service=Service:new{storage=storage,directory=directory.."/service-"..tonumber(ffi.C.getpid()),native_library=root.."/native/preprocess/build/moire-host.so",
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
local recovered=Service:new{storage=storage,directory=service.directory,native_library=root.."/native/preprocess/build/moire-host.so",
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
print("KOReader real EPUB integration: OK")
