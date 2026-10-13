-- SPDX-License-Identifier: AGPL-3.0-only
local Queue=require("koobone.preprocess_queue")
local Coordinator=require("koobone.resource_coordinator")
local Identity=require("koobone.preprocess_identity")
local Profile=require("koobone.preprocess_profile")
local Service={}
Service.__index=Service
local instances={}
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
local function counter(value)
    return type(value)=="number" and value>=0 and value<math.huge and value==math.floor(value)
end
local function dense(value)
    if type(value)~="table" then return false end
    local count=0;for key in pairs(value) do if not counter(key) or key<1 then return false end;count=count+1 end
    return count==#value
end

function Service:get(options)
    local existing=instances[options.directory]
    if existing then
        existing.storage=options.storage
        if options.profile_provider then existing.profile_provider=options.profile_provider end
        if options.on_batch then existing.on_batch=options.on_batch end
        return existing
    end
    local service=self:new(options)
    instances[options.directory]=service
    return service
end

function Service:new(options)
    local self=setmetatable({storage=options.storage,directory=options.directory,requests={},next_id=1,
        profile_provider=options.profile_provider or function() return {} end,
        space=options.space,reserve=64*1024*1024,on_batch=options.on_batch,listeners={},
        available=false,running=false,retain_original=options.retain_original==true,
        coordinator=options.coordinator or Coordinator:new()},Service)
    local loaded,err=pcall(function()
        local ffi=require("ffi")
        local Files=require("koobone.preprocess_files")
        local Worker=require("koobone.preprocess_worker")
        local Sha=require("ffi/sha2")
        local directory=assert(options.directory)
        local native=options.native_library
        if not native then
            local Device=require("device")
            assert(Device.model=="KindleColorSoft" and ffi.arch=="arm","本构建只支持 Colorsoft ARM hard-float")
            local location=debug.getinfo(1,"S").source:sub(2):match("^(.*)/[^/]+$")
            native=location.."/native/moire-kindlehf.so"
        end
        self.files=Files:new{roots={directory,self.storage:downloadDir()}}
        assert(self.files:mkdir(directory),"任务目录不可用")
        self.schedule=options.schedule or function(delay,callback) require("ui/uimanager"):scheduleIn(delay,callback) end
        self.is_in_use=options.is_in_use or function(path)
            local reader=require("apps/reader/readerui").instance
            return reader and reader.document and reader.document.file==path or false
        end
        self.sha=Sha.sha256
        self.state_path=directory.."/tasks.json"
        require("koobone.preprocess_koreader"):new{native_library=native,workspace=directory}
        self.worker=Worker:new{files=self.files,directory=directory,native_library=native,
            is_in_use=self.is_in_use,schedule=self.schedule}
        self.queue=Queue:new{coordinator=self.coordinator,worker=self.worker,checkpoint=function(snapshot)
            return self:_save(snapshot)
        end}
        local snapshot=self.files:readJSON(self.state_path)
        if snapshot then
            assert(snapshot.schema_version==1 and type(snapshot.requests)=="table","任务快照不兼容")
            assert(dense(snapshot.requests),"稀疏请求快照无效")
            local request_ids={}
            for _, request in ipairs(snapshot.requests) do
                assert(type(request)=="table" and type(request.book_id)=="string" and
                    type(request.id)=="number" and request.id>=1 and request.id<math.huge and
                    request.id==math.floor(request.id) and self.storage:isSafeLocalPath(request.source_path),"任务路径或身份无效")
                assert(not request_ids[request.id],"重复请求身份无效")
                request_ids[request.id]=true
                assert(request.state=="pending" or request.state=="preparing" or request.state=="failed" or request.state=="cancelled" or request.state=="skipped",
                    "任务状态无效")
                local restored={id=request.id,book_id=request.book_id,source_path=request.source_path,
                    state=request.state=="preparing" and "failed" or request.state,
                    profile=assert(Profile.normalize(request.profile))}
                restored.profile.discard_original=not self.retain_original
                self.requests[#self.requests+1]=restored
                self.next_id=math.max(self.next_id,request.id+1)
            end
            assert(type(snapshot.queue)=="table" and type(snapshot.queue.jobs)=="table","队列快照无效")
            for _, job in ipairs(snapshot.queue.jobs) do
                assert(type(job)=="table" and self.storage:isSafeLocalPath(job.source_path) and
                    type(job.source_fingerprint)=="string" and #job.source_fingerprint==64 and job.source_fingerprint:match("^%x+$") and
                    (job.algorithm_version=="restore-1" or job.algorithm_version=="kissfft-f2892a2-v1"),"原生任务身份无效")
            end
            if snapshot.batch~=nil then
                local batch=snapshot.batch
                assert(type(batch)=="table" and dense(batch.members) and type(batch.stats)=="table" and type(batch.finished)=="boolean","批次快照无效")
                self.batch={members={},stats={},finished=batch.finished}
                for _,field in ipairs({"duplicate","occupied","invalid"}) do
                    assert(counter(batch.stats[field]),"批次计数无效");self.batch.stats[field]=batch.stats[field]
                end
                local seen={}
                for _,member in ipairs(batch.members) do
                    assert(type(member)=="table" and counter(member.request_id) and member.request_id>=1 and
                        not seen[member.request_id] and self.storage:isSafeLocalPath(member.source_path),"批次成员无效")
                    local valid=false
                    for _,request in ipairs(self.requests) do
                        if request.id==member.request_id and request.source_path==member.source_path then valid=true end
                    end
                    if member.job_id~=nil then
                        assert(type(member.job_id)=="string","批次任务身份无效")
                        local found=false
                        for _,job in ipairs(snapshot.queue.jobs) do
                            if job.id==member.job_id and job.source_path==member.source_path then found=true end
                        end
                        assert(found,"批次任务不存在");valid=true
                    end
                    assert(valid,"批次请求不存在")
                    seen[member.request_id]=true
                    self.next_id=math.max(self.next_id,member.request_id+1)
                    self.batch.members[#self.batch.members+1]={request_id=member.request_id,source_path=member.source_path,job_id=member.job_id}
                end
            end
            assert(self.queue:restore(snapshot.queue))
        elseif require("libs/libkoreader-lfs").attributes(self.state_path,"mode") then
            error("任务快照损坏；原文件未改动")
        end
        self.available=true
        if snapshot then self:reconcile() end
    end)
    if not loaded then self.reason=tostring(err) end
    return self
end

function Service:_save(snapshot)
    local ok,err=self.files:writeJSON(self.state_path,{schema_version=1,requests=self.requests,
        queue=snapshot or self.queue:snapshot(),batch=self.batch})
    if ok then for callback in pairs(self.listeners) do pcall(callback) end end
    return ok,err
end

function Service:subscribe(callback)
    self.listeners[callback]=true
    return function() self.listeners[callback]=nil end
end

function Service:jobs()
    local result={}
    for _, request in ipairs(self.requests) do result[#result+1]=request end
    for _, job in ipairs(self.queue and self.queue.jobs or {}) do result[#result+1]=job end
    return result
end

function Service:isActive() return self.reconciling==true or self.hashing~=nil or (self.queue and self.queue.active~=nil) or false end

function Service:isLocked(path)
    if self.hashing and self.hashing.request.source_path==path then return true end
    if self.queue and self.queue.active then
        local job=self.queue.active.job
        return job.source_path==path or self.worker:paths(job).temporary==path or self.worker:paths(job).backup==path
    end
    return false
end

function Service:cleanup(path)
    if not self.available then return true,0 end
    if self:isLocked(path) then return nil,"文件正在使用" end
    local seen,total={},0
    for _, request in ipairs(self.requests) do
        if request.source_path==path and request.state=="pending" then request.state="cancelled" end
    end
    for _, job in ipairs(self.queue.jobs) do
        if job.source_path==path then
            if job.state=="pending" then job.state="cancelled" end
            local paths=self.worker:paths(job)
            for _, artifact in ipairs({paths.backup,paths.temporary,paths.workspace.."/page.codec",paths.status,
                    paths.reading,paths.cancel,paths.permission,paths.journal,paths.claim}) do
                if not seen[artifact] then
                    seen[artifact]=true
                    local attribute=require("libs/libkoreader-lfs").attributes(artifact,"size")
                    local size=tonumber(attribute) or 0
                    local removed,err=self.files:remove(artifact)
                    if not removed then return nil,err end
                    total=total+size
                end
            end
        end
    end
    if not self:_save() then return nil,"清理状态未能保存" end
    return true,total
end

function Service:record(path)
    for index=#(self.queue and self.queue.jobs or {}),1,-1 do
        local job=self.queue.jobs[index]
        if job.source_path==path and job.state=="completed" then
            if job.profile.restore then return nil end
            return job
        end
    end
end

function Service:profile()
    local called,value=pcall(self.profile_provider)
    if not called then return nil,"处理参数不可用" end
    local profile,err=Profile.normalize(value)
    if not profile then return nil,err end
    profile.discard_original=not self.retain_original
    return profile
end

function Service:previewBatch(items)
    if not self.available then return nil,self.reason end
    if self.reconciling then return nil,"正在核对文件事务" end
    if not dense(items) then return nil,"选择无效" end
    local profile,err=self:profile();if not profile then return nil,err end
    local result={files=0,bytes=0,temporary_bytes=0,duplicate=0,occupied=0,invalid=0,items={},profile=profile}
    local seen={}
    for _,request in ipairs(self.requests) do if request.state=="pending" or request.state=="preparing" then seen[request.source_path]=true end end
    for _,job in ipairs(self.queue.jobs) do
        if job.state=="pending" or job.state=="preparing" or job.state=="processing" or job.state=="validating" then seen[job.source_path]=true end
    end
    for _,item in ipairs(items) do
        local path=type(item)=="table" and self.storage:resolveLocalPath(item)
        if not path or not path:lower():match("%.epub$") or not self.storage:isSafeLocalPath(path) then result.invalid=result.invalid+1
        elseif seen[path] then result.duplicate=result.duplicate+1
        elseif self.is_in_use(path) or self:isLocked(path) then result.occupied=result.occupied+1
        else
            local size=self.storage:fileSize(path)
            if not counter(size) or size==0 then result.invalid=result.invalid+1
            else
                seen[path]=true;result.files=result.files+1;result.bytes=result.bytes+size
                result.temporary_bytes=math.max(result.temporary_bytes,size*2)
                result.items[#result.items+1]={item=item,path=path}
            end
        end
    end
    local called,free=pcall(function()
        if self.space then return self.space() end
        return require("util").diskUsage(self.storage:downloadDir()).available
    end)
    if not called or type(free)~="number" or free~=free or free<result.temporary_bytes+self.reserve then return nil,"临时空间不足或无法确认" end
    result.free=free
    return result
end

function Service:submitBatch(items,expected_profile)
    local preview,err=self:previewBatch(items);if not preview then return nil,err end
    if expected_profile~=nil then
        local function key(profile)
            return Identity.key{book_id="profile",source_fingerprint="controls",algorithm_version="kissfft-f2892a2-v1",profile=profile}
        end
        local expected=key(expected_profile)
        if not expected or expected~=key(preview.profile) then return nil,"处理参数已变化，请重新确认" end
    end
    local counts={added=preview.files,duplicate=preview.duplicate,occupied=preview.occupied,invalid=preview.invalid}
    if preview.files==0 then return counts end
    local initial,next_id,previous=#self.requests,self.next_id,self.batch
    self.batch=copy(self.batch and not self.batch.finished and self.batch or {members={},stats={duplicate=0,occupied=0,invalid=0},finished=false})
    for _,field in ipairs({"duplicate","occupied","invalid"}) do self.batch.stats[field]=self.batch.stats[field]+counts[field] end
    for _,entry in ipairs(preview.items) do
        local request={id=self.next_id,book_id=tostring(self.storage:itemKey(entry.item)),source_path=entry.path,
            state="pending",profile=copy(preview.profile)}
        self.next_id=self.next_id+1;self.requests[#self.requests+1]=request
        self.batch.members[#self.batch.members+1]={request_id=request.id,source_path=request.source_path}
    end
    if not self:_save() then
        while #self.requests>initial do table.remove(self.requests) end
        self.next_id,self.batch=next_id,previous;return nil,"批次保存失败"
    end
    return counts
end

function Service:batchSummary()
    local result={completed=0,optimized=0,failed=0,cancelled=0,pending=0,skipped=0}
    if not self.batch then return result end
    local jobs,requests={},{}
    for _,job in ipairs(self.queue.jobs) do jobs[job.id]=job end
    for _,request in ipairs(self.requests) do requests[request.id]=request end
    for _,field in ipairs({"duplicate","occupied","invalid"}) do result.skipped=result.skipped+self.batch.stats[field] end
    for _,member in ipairs(self.batch.members) do
        local state
        if member.job_id and jobs[member.job_id] then state=jobs[member.job_id].state end
        if not state and requests[member.request_id] then state=requests[member.request_id].state end
        if state=="completed" then result.completed=result.completed+1
        elseif state=="skipped" then result.optimized=result.optimized+1
        elseif state=="failed" or not state then result.failed=result.failed+1
        elseif state=="cancelled" then result.cancelled=result.cancelled+1
        else result.pending=result.pending+1 end
    end
    return result
end

function Service:submit(item)
    if not self.available then return nil,self.reason end
    if self.reconciling then return nil,"正在核对文件事务，请稍后重试" end
    local profile,profile_error=self:profile()
    if not profile then return nil,profile_error end
    local path,err=self.storage:resolveLocalPath(item)
    if not path or not self.storage:isSafeLocalPath(path) then return nil,err or "本地文件不可用" end
    if self.is_in_use(path) or self:isLocked(path) then return nil,"请先关闭正在阅读或处理的漫画" end
    for _, request in ipairs(self.requests) do
        if request.source_path==path and (request.state=="pending" or request.state=="preparing") then return nil,"已排队" end
    end
    local request={id=self.next_id,book_id=tostring(self.storage:itemKey(item)),source_path=path,state="pending",profile=profile}
    self.next_id=self.next_id+1;self.requests[#self.requests+1]=request
    local saved,save_error=self:_save()
    if not saved then table.remove(self.requests);return nil,save_error end
    return true
end

function Service:restore(item)
    if not self.available then return nil,self.reason end
    if self.reconciling then return nil,"正在核对文件事务，请稍后重试" end
    local path=self.storage:resolveLocalPath(item)
    local original=path and self:record(path)
    if not original or original.profile.discard_original or self.is_in_use(path) or self:isLocked(path) then return nil,"原版备份不可用或文件正在使用" end
    local request={book_id=original.book_id,source_path=path,
        source_fingerprint=original.source_fingerprint,algorithm_version="restore-1",
        profile={restore=true,output_fingerprint=original.output_fingerprint}}
    local id=Identity.key(request)
    for _, previous in ipairs(self.queue.jobs) do
        if previous.id==id then return self.queue:retry(id,previous.state=="completed") end
    end
    local queued,err=self.queue:add(request)
    return queued~=nil,err
end

function Service:cancel(id)
    if not self.available then return nil,self.reason end
    if type(id)=="number" then
        for _, request in ipairs(self.requests) do
            if request.id==id and (request.state=="pending" or request.state=="preparing") then
                request.state="cancelled";return self:_save()
            end
        end
        return nil,"任务不可取消"
    end
    return self.queue:cancel(id)
end

function Service:retry(id)
    if not self.available then return nil,self.reason end
    if type(id)=="number" then
        for _, request in ipairs(self.requests) do
            if request.id==id and (request.state=="failed" or request.state=="cancelled") then
                request.state="pending";return self:_save()
            end
        end
        return nil,"任务不可重试"
    end
    return self.queue:retry(id)
end

function Service:_hash(request,token)
    local file=io.open(request.source_path,"rb")
    if not file then self.coordinator:release(token);request.state="failed";self:_save();return end
    request.state="preparing"
    if not self:_save() then file:close();self.coordinator:release(token);request.state="pending";self.running=false;return end
    local update=self.sha()
    local size=tonumber(require("libs/libkoreader-lfs").attributes(request.source_path,"size"))
    local bytes=0
    self.hashing={request=request,token=token}
    local function step()
        local aborted=request.state=="cancelled" or not self.storage:isSafeLocalPath(request.source_path) or self.is_in_use(request.source_path)
        local chunk,read_error
        if not aborted then chunk,read_error=file:read(65536) end
        if chunk then bytes=bytes+#chunk;update(chunk);self.schedule(0.01,step);return end
        file:close();self.hashing=nil;self.coordinator:release(token)
        if aborted then
            request.state=request.state=="cancelled" and "cancelled" or "failed"
        elseif read_error or bytes~=size then
            request.state="failed";request.error="源文件读取不完整"
        else
            local fingerprint=update()
            local record=self:record(request.source_path)
            local job,err
            if record and record.output_fingerprint==fingerprint then
                request.state,request.error="skipped",nil
            else
                local expected_id=Identity.key{book_id=request.book_id,source_fingerprint=fingerprint,
                    algorithm_version="kissfft-f2892a2-v1",profile=request.profile}
                if self.batch then for _,member in ipairs(self.batch.members) do
                    if member.request_id==request.id then member.job_id=expected_id end
                end end
                for _, previous in ipairs(self.queue.jobs) do
                    if previous.book_id==request.book_id and previous.source_path==request.source_path and
                            previous.source_fingerprint==fingerprint and previous.algorithm_version=="kissfft-f2892a2-v1" and
                            Identity.key{book_id=request.book_id,source_fingerprint=fingerprint,
                                algorithm_version="kissfft-f2892a2-v1",profile=request.profile}==previous.id then
                        if previous.state=="pending" then job=previous
                        else
                            local retried,retry_error=self.queue:retry(previous.id,previous.state=="completed")
                            if retried then job=previous else err=retry_error end
                        end
                        break
                    end
                end
                if not job and not err then
                    job,err=self.queue:add{book_id=request.book_id,source_path=request.source_path,
                        source_fingerprint=fingerprint,algorithm_version="kissfft-f2892a2-v1",
                        profile=request.profile}
                end
            end
            if job then
                for index,value in ipairs(self.requests) do if value==request then table.remove(self.requests,index);break end end
            elseif request.state~="skipped" then
                request.state="failed";request.error=err
                if self.batch then for _,member in ipairs(self.batch.members) do
                    if member.request_id==request.id then member.job_id=nil end
                end end
            end
        end
        if not self:_save() then self.queue.paused=true;self.running=false end
    end
    self.schedule(0.01,step)
end

function Service:resume()
    if not self.available then return nil,self.reason end
    if self.reconciling then return nil,"正在核对文件事务，请稍后重试" end
    local ok,err=self.queue:resume()
    if not ok then return nil,err end
    self.running=true
    if self.scheduled then return true end
    local function pump()
        self.scheduled=false
        if not self.running then return end
        if self.queue.paused then self.running=false;return end
        if self.was_active and not self.queue.active then
            local finished=self.was_active
            self.was_active=nil
            if finished.state=="failed" or finished.state=="cancelled" then self:reconcile() end
        end
        if not self:isActive() then
            local started=self.queue:tick()
            if self.queue.active then self.was_active=self.queue.active.job end
            if not started then
                for _, request in ipairs(self.requests) do
                    if request.state=="pending" then
                        local token=self.coordinator:acquire("preprocess")
                        if token then self:_hash(request,token) end
                        break
                    end
                end
            end
        end
        if self.batch and not self.batch.finished and not self:isActive() then
            local summary=self:batchSummary()
            if summary.pending==0 then
                self.batch.finished=true
                if self:_save() then
                    if self.on_batch then pcall(self.on_batch,summary) end
                else self.batch.finished=false;self.running=false;self.queue.paused=true;return end
            end
        end
        if not self:isActive() then
            local waiting=false
            for _,request in ipairs(self.requests) do
                if request.state=="pending" or request.state=="preparing" then waiting=true end
            end
            for _,job in ipairs(self.queue.jobs) do
                if job.state=="pending" or job.state=="preparing" or job.state=="processing" or job.state=="validating" then waiting=true end
            end
            if not waiting then self.running=false;return end
        end
        self.scheduled=true;self.schedule(0.2,pump)
    end
    self.scheduled=true;self.schedule(0,pump)
    return true
end

function Service:reconcile()
    if not self.available or self.reconciling or self.hashing or (self.queue and self.queue.active) then return false end
    self.reconciling=true
    local function begin()
        local token=self.coordinator:acquire("preprocess")
        if not token then self.schedule(0.2,begin);return end
        local index=0
        local function advance()
            index=index+1
            local job=self.queue.jobs[index]
            if not job then
                self.reconciling=false;self.coordinator:release(token)
                if not self:_save() then self.queue.paused=true;self.running=false end
                return
            end
            local paths=self.worker:paths(job)
            local journal=self.files:readJSON(paths.journal)
            local claim=self.files:readJSON(paths.claim)
            local claimed=claim and claim.source_path==job.source_path and claim.temporary_path==paths.temporary and
                claim.source_fingerprint==job.source_fingerprint
            if not journal then
                if claimed then
                    self.files:hashAsync(job.source_path,self.schedule,nil,function(current)
                        if current==job.source_fingerprint then
                            self.files:remove(paths.temporary);self.files:remove(paths.workspace.."/page.codec")
                        end
                        self.schedule(0,advance)
                    end)
                else self.schedule(0,advance) end
                return
            end
            if journal.source_path~=job.source_path or journal.backup_path~=paths.backup or
                    journal.temporary_path~=paths.temporary or journal.source_fingerprint~=job.source_fingerprint or
                    type(journal.output_fingerprint)~="string" or #journal.output_fingerprint~=64 or
                    not journal.output_fingerprint:match("^%x+$") or
                    not ({backing_up=true,prepared=true,committed=true,restoring=true,restored=true})[journal.state] then
                self.schedule(0,advance);return
            end
            local expected=job.profile.restore and job.source_fingerprint or journal.output_fingerprint
            self.files:hashAsync(job.source_path,self.schedule,nil,function(current)
                self.files:hashAsync(paths.backup,self.schedule,nil,function(backup)
                    if current==expected and ((job.profile.discard_original==true and journal.discard_original==true) or
                            backup==job.source_fingerprint) then
                        job.state,job.output_fingerprint,job.error="completed",expected,nil
                    elseif current==job.source_fingerprint and claimed and not job.profile.restore then
                        self.files:remove(paths.temporary);self.files:remove(paths.workspace.."/page.codec")
                        if journal.state=="backing_up" and backup~=job.source_fingerprint then self.files:remove(paths.backup) end
                    end
                    self.schedule(0,advance)
                end)
            end)
        end
        advance()
    end
    self.schedule(0,begin)
    return true
end

function Service:pause()
    self.running=false
    if self.queue then return self.queue:pause() end
    return nil,self.reason
end

return Service
