-- SPDX-License-Identifier: AGPL-3.0-only
local Guard=require("koobone.runtime_guard")
local Queue=require("koobone.download_queue")
local Entry=require("koobone.catalog_entry")
local Worker=require("koobone.download_worker")
local Service={}
Service.__index=Service

function Service:new(options)
    local self=setmetatable({settings=assert(options.settings),storage=assert(options.storage),api=assert(options.api),
        library=assert(options.library),directory=assert(options.directory),options=options,running=false,
        coordinator=options.coordinator or require("koobone.resource_coordinator"):new(),
        reserve=options.reserve or 16*1024*1024,files=options.files},Service)
    self.schedule=options.schedule or function(delay,callback) require("ui/uimanager"):scheduleIn(delay,callback) end
    return self
end

function Service:account()
    return tostring(self.settings:account().uin or "")
end

function Service:freeSpace()
    if self.options.space then return self.options.space() end
    return require("util").diskUsage(self.storage:downloadDir()).available
end

function Service:_nativeWorker()
    local Files=require("koobone.preprocess_files")
    local Epub=require("koobone.preprocess_epub")
    local Archive=require("ffi/archiver")
    local files=Files:new{roots={self.directory,self.storage:downloadDir()}}
    local validator=Epub:new{validation_only=true,reader=function() return Archive.Reader:new() end}
    local transport=require("koobone.download_transport"):new{files=files,api=self.api,schedule=self.schedule,
        resolve=function(dto)
            if self:account()~=dto.account_id then return nil,"account_changed" end
            for _,item in ipairs(self.library.items) do
                local entry=Entry.normalize(dto.account_id,item)
                if entry and entry.id==dto.id then return item end
            end
            return nil,"catalog_missing"
        end,
        validate=function(path) return validator:validate(path) end}
    local worker=Worker:new{files=files,storage=self.storage,transport=transport,directory=self.directory.."/jobs",
        account=function() return self:account() end,schedule=self.schedule,is_in_use=self.options.is_in_use}
    local start=worker.start
    worker.start=function(instance,job,events)
        local free=self:freeSpace()
        if type(free)~="number" or free<self.reserve or (job.entry.remote_size and free<job.entry.remote_size*2+self.reserve) then
            return nil,"no_space"
        end
        transport.max_bytes=math.min(16*1024*1024*1024,math.floor((free-self.reserve)/2))
        return start(instance,job,events)
    end
    self.files=files
    return worker
end

function Service:ensure()
    local account=self:account()
    if account=="" then return nil,"尚未登录" end
    if self.queue and self.queue.account_id==account then return self.queue end
    if self.reconciling then return nil,"正在核对旧账号任务，请稍后重试" end
    if self.queue and self.queue.active then
        self:stop();return nil,"正在等待旧账号下载退出"
    end
    local ok,queue,store,worker=pcall(function()
        local backend=self.options.worker_factory and self.options.worker_factory(account) or self:_nativeWorker()
        local persistence=self.options.store_factory and self.options.store_factory(account) or
            require("koobone.download_queue_store"):new{directory=self.directory.."/queues",account_id=account,files=self.files}
        local q=Queue:new{account_id=account,worker=backend,coordinator=self.coordinator,
            is_downloaded=function(raw) return self.storage:isDownloaded(raw) end,
            checkpoint=function(snapshot) return persistence:save(snapshot) end}
        local snapshot,err=persistence:load()
        if err then error("下载队列快照无法读取") end
        if snapshot and not q:restore(snapshot) then error("下载队列快照无效，未覆盖") end
        return q,persistence,backend
    end)
    if not ok then return nil,"下载队列初始化失败；已保留原记录" end
    self.queue,self.store,self.worker=queue,store,worker
    self.batch=queue.batch and queue.batch.ids
    self.batch_stats=queue.batch and queue.batch.stats
    self.running,self.refreshing=false,false
    if self.files and worker.paths then self:reconcile() end
    return queue
end

function Service:reconcile()
    if self.reconciling or not self.queue or self.queue.active or not self.files or not self.worker.paths then return false end
    self.reconciling=true
    local queue,worker=self.queue,self.worker
    local function begin()
        if queue.account_id~=self:account() then self.reconciling=false;return end
        local token=self.coordinator:acquire("download_reconcile")
        if not token then self.schedule(0.2,begin);return end
        local index=0
        local function advance()
            index=index+1
            local job=queue.jobs[index]
            if not job then
                queue:_save();self.coordinator:release(token);self.reconciling=false
                if self.running then self:_pump() end
                return
            end
            local claim=self.files:readJSON(worker:paths(job).claim)
            local raw=Worker.raw(job.entry)
            if not claim or claim.job_id~=job.id or claim.account_id~=queue.account_id or
                    (claim.state~="prepared" and claim.state~="committed") or
                    type(claim.output_fingerprint)~="string" or #claim.output_fingerprint~=64 or
                    not claim.output_fingerprint:match("^%x+$") or type(claim.bytes)~="number" or
                    claim.bytes<=0 or claim.bytes>=math.huge or claim.bytes~=math.floor(claim.bytes) or
                    (job.entry.remote_size and job.entry.remote_size~=claim.bytes) or
                    not self.files:isSafe(claim.final_path) or self.storage:resolveDownloadPath(raw)~=claim.final_path then
                self.schedule(0,advance);return
            end
            self.files:hashAsync(claim.final_path,self.schedule,function() return queue.account_id==self:account() end,function(hash)
                if hash==claim.output_fingerprint then
                    job.state,job.bytes,job.total,job.output_fingerprint,job.error_code="completed",claim.bytes,claim.bytes,hash,nil
                    if self.storage.record then pcall(self.storage.record,self.storage,raw,"complete",{path=claim.final_path,bytes=claim.bytes,total=claim.bytes}) end
                end
                self.schedule(0,advance)
            end)
        end
        advance()
    end
    self.schedule(0,begin)
    return true
end

function Service:preview(items)
    local queue,err=self:ensure();if not queue then return nil,err end
    if type(items)~="table" then return nil,"选择无效" end
    local count=0;for key in pairs(items) do
        if type(key)~="number" or key<1 or key~=math.floor(key) then return nil,"选择无效" end
        count=count+1
    end
    if count~=#items then return nil,"选择无效" end
    local preview={files=0,bytes=0,unknown=0,downloaded=0,duplicate=0,invalid=0,account_id=self:account(),items={}}
    local largest=0
    local seen={};for _,job in ipairs(queue.jobs) do if job.state~="completed" then seen[job.id]=true end end
    for _,raw in ipairs(items) do
        local entry=Entry.normalize(preview.account_id,raw)
        if not entry or entry.file_type:lower()~="epub" or (raw._catalog_account_id and raw._catalog_account_id~=preview.account_id) then preview.invalid=preview.invalid+1
        elseif self.storage:isDownloaded(raw) then preview.downloaded=preview.downloaded+1
        elseif seen[entry.id] then preview.duplicate=preview.duplicate+1
        else
            local path=self.storage:resolveDownloadPath(raw)
            if not path then preview.invalid=preview.invalid+1
            else
                preview.files=preview.files+1;seen[entry.id]=true
                preview.items[#preview.items+1]=raw
                if entry.remote_size and entry.remote_size>0 and entry.remote_size<math.huge and entry.remote_size==math.floor(entry.remote_size) then
                    preview.bytes=preview.bytes+entry.remote_size
                    largest=math.max(largest,entry.remote_size)
                else preview.unknown=preview.unknown+1 end
            end
        end
    end
    local ok,free=pcall(self.freeSpace,self)
    preview.temporary_bytes=largest
    if not ok or type(free)~="number" or free<self.reserve or free<preview.bytes+largest+self.reserve then return nil,"可用空间不足或无法确认" end
    preview.free=free
    return preview
end

function Service:enqueue(items,account)
    if not Guard.ensure() then return nil,Guard.reason end
    if account~=self:account() then return nil,"账号已变化，请重新确认" end
    local preview,err=self:preview(items);if not preview then return nil,err end
    local counts,add_error=self.queue:add(preview.items,{reopen_completed=true,
        batch_stats={downloaded=preview.downloaded,duplicate=preview.duplicate,invalid=preview.invalid}})
    if not counts then return nil,add_error end
    self.batch=self.queue.batch and self.queue.batch.ids
    self.batch_stats=self.queue.batch and self.queue.batch.stats
    return counts
end

function Service:isActive()
    return self.reconciling==true or (self.queue and self.queue.active~=nil) or false
end

function Service:summary(ids)
    local result={completed=0,failed=0,cancelled=0,pending=0,bytes=0,total=0,warnings=0,
        downloaded=0,duplicate=0,invalid=0,skipped=0}
    if ids==self.batch and self.batch_stats then
        for _,field in ipairs({"downloaded","duplicate","invalid"}) do result[field]=self.batch_stats[field];result.skipped=result.skipped+result[field] end
    end
    for _,job in ipairs(self.queue and self.queue.jobs or {}) do
        if not ids or ids[job.id] then
            result.total=result.total+1
            if job.warning then result.warnings=result.warnings+1 end
            if job.state=="completed" then result.completed=result.completed+1;result.bytes=result.bytes+job.bytes
            elseif job.state=="failed" or job.state=="interrupted" then result.failed=result.failed+1
            elseif job.state=="cancelled" then result.cancelled=result.cancelled+1
            else result.pending=result.pending+1 end
        end
    end
    return result
end

function Service:_pump()
    if self.pumping then return end
    self.pumping=true
    local function step()
        self.pumping=false
        if not self.queue then return end
        if self.queue.account_id~=self:account() then self:stop();return end
        if self.reconciling then self:_pump();return end
        if self.queue.active then
            self:_pump();return
        end
        if not self.running or self.queue.paused then return end
        for _,job in ipairs(self.queue.jobs) do
            if job.state=="failed" and job.error_code=="network" and job.attempts-(job.retry_base or 0)<=2 then
                self.queue:retry(job.id,false,true)
            end
        end
        if not self.options.worker_factory then
            local age=self.library.urls_at and os.time()-self.library.urls_at
            if self.library.account_id~=self:account() or not age or age<0 or age>=60 then
                if not self.library.sync and not self.refreshing then
                    self.refreshing=true
                    local handle=self.library:refreshAsync(function(items)
                        self.refreshing=false
                        if not items then self:pause() else self:_pump() end
                    end)
                    if not handle then self.refreshing=false;self:pause() end
                end
                self:_pump();return
            end
        end
        local started=self.queue:tick()
        if started or self.queue.active then self:_pump();return end
        if self.coordinator:owner() then self:_pump();return end
        local summary=self:summary(self.batch)
        if summary.pending==0 then
            self.running=false
            if self.batch and next(self.batch) and self.options.on_batch then pcall(self.options.on_batch,summary) end
            local previous=self.queue.batch
            self.queue.batch=nil
            if self.queue:_save() then self.batch,self.batch_stats=nil,nil
            else self.queue.batch=previous end
        else self:_pump() end
        if self.options.on_changed then pcall(self.options.on_changed) end
    end
    self.schedule(0.2,step)
end

function Service:resume()
    if not Guard.ensure() then return nil,Guard.reason end
    local queue,err=self:ensure();if not queue then return nil,err end
    if not queue:resume() then return nil,"队列状态保存失败" end
    self.running=true;self:_pump();return true
end

function Service:pause()
    self.running=false
    if self.queue then return self.queue:pause() end
    return true
end

function Service:stop()
    self:pause()
    if self.queue and self.queue.active then return self.queue:cancel(self.queue.active.job.id) end
    return true
end

function Service:cancel(id)
    if not self.queue then return nil,"没有队列" end
    local ok,err=self.queue:cancel(id)
    if ok and self.running then self:_pump() end
    return ok,err
end

function Service:retry(id)
    if not Guard.ensure() then return nil,Guard.reason end
    local queue,err=self:ensure();if not queue then return nil,err end
    local ok,retry_error=queue:retry(id,false,false,true)
    if ok then
        self.batch,self.batch_stats=queue.batch.ids,queue.batch.stats
        return self:resume()
    end
    return nil,retry_error
end

return Service
