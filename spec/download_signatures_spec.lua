package.path="./koocomic.koplugin/?.lua;"..package.path
local Service=require("koobone.download_service")
local Library=require("koobone.library")
local Worker=require("koobone.download_worker")
local account,requests="one",0
local tasks,used={},{}
local storage={itemKey=function(_,raw) return raw.file_md5 end,isDownloaded=function() return false end,
    resolveDownloadPath=function(_,raw) return "/books/"..raw.vol_name..".epub" end}
local api={library=function(_,limit)
    requests=requests+1
    local data={}
    for index=1,math.min(limit,31) do data[index]={file_md5="id-"..index,vol_name="Original "..index,file_size=12,
        file_url="https://example.test/generation-"..requests.."/"..index} end
    return {total=31,data=data}
end}
local function schedule(_,callback) tasks[#tasks+1]=callback end
local library=Library:new(api,storage,{account=function() return account end,runner={start=function(_,task,done)
    schedule(0,function() done(task()) end);return {cancel=function() return true end}
end}})
library.account_id="one";library.urls_at=os.time()-61
local originals={}
for index=1,20 do originals[index]={file_md5="id-"..index,vol_name="Original "..index,file_size=12,file_url="expired URL must not be used"} end
library.items=originals
local result
local service=Service:new{settings={account=function() return {uin=account} end},storage=storage,api=api,library=library,
    directory="/private/downloads",space=function() return 128*1024*1024 end,schedule=schedule,
    store_factory=function() return {load=function() end,save=function(_,snapshot)
        for _,job in ipairs(snapshot.jobs) do assert(job.entry.file_url==nil) end;return true end} end,
    on_batch=function(value) result=value end}
function service:_nativeWorker()
    return {asynchronous=true,start=function(_,job,events)
        schedule(0,function()
            local fresh=assert(library:freshItem(Worker.raw(job.entry)))
            used[#used+1]=fresh.file_url
            events.stage("downloading");events.stage("validating")
            events.done(true,{validated=true,committed=true,bytes=12,output_fingerprint=string.rep("a",64)})
            if #used==10 then library.urls_at=os.time()-61 end
        end)
        return {cancel=function() return true end}
    end}
end
assert(service:enqueue(originals,account).added==20 and service:resume())
for _=1,300 do if result then break end;assert(#tasks>0);table.remove(tasks,1)() end
assert(result and result.completed==20 and requests==4,"20 volumes with one expiry must reuse two full-catalog fetches, not fetch per volume")
assert(used[1]:find("generation-2",1,true) and used[11]:find("generation-4",1,true))
account="two"
assert(not library:freshItem({_catalog_account_id="one",file_md5="id-1"}) and requests==4,
    "changed-account stale entries must not fetch or resolve another account's signatures")
print("download signature expiry/index/request-count spec: OK")
