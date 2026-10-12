-- SPDX-License-Identifier: AGPL-3.0-only
local Queue=require("koobone.preprocess_queue")
local Coordinator=require("koobone.resource_coordinator")
local Identity=require("koobone.preprocess_identity")
local Service={}
Service.__index=Service
local instances={}

function Service:get(options)
    local existing=instances[options.directory]
    if existing then existing.storage=options.storage;return existing end
    local service=self:new(options)
    instances[options.directory]=service
    return service
end

function Service:new(options)
    local self=setmetatable({storage=options.storage,directory=options.directory,requests={},next_id=1,
        available=false,running=false,coordinator=options.coordinator or Coordinator:new()},Service)
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
            for _, request in ipairs(snapshot.requests) do
                assert(type(request)=="table" and type(request.book_id)=="string" and
                    type(request.id)=="number" and request.id>=1 and request.id<math.huge and
                    request.id==math.floor(request.id) and self.storage:isSafeLocalPath(request.source_path),"任务路径或身份无效")
                assert(request.state=="pending" or request.state=="preparing" or request.state=="failed" or request.state=="cancelled",
                    "任务状态无效")
                local restored={id=request.id,book_id=request.book_id,source_path=request.source_path,
                    state=request.state=="preparing" and "failed" or request.state}
                self.requests[#self.requests+1]=restored
                self.next_id=math.max(self.next_id,request.id+1)
            end
            assert(type(snapshot.queue)=="table" and type(snapshot.queue.jobs)=="table","队列快照无效")
            for _, job in ipairs(snapshot.queue.jobs) do
                assert(type(job)=="table" and self.storage:isSafeLocalPath(job.source_path) and
                    type(job.source_fingerprint)=="string" and #job.source_fingerprint==64 and job.source_fingerprint:match("^%x+$") and
                    (job.algorithm_version=="restore-1" or job.algorithm_version=="kissfft-f2892a2-v1"),"原生任务身份无效")
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
    return self.files:writeJSON(self.state_path,{schema_version=1,requests=self.requests,
        queue=snapshot or self.queue:snapshot()})
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

function Service:submit(item)
    if not self.available then return nil,self.reason end
    if self.reconciling then return nil,"正在核对文件事务，请稍后重试" end
    local path,err=self.storage:resolveLocalPath(item)
    if not path or not self.storage:isSafeLocalPath(path) then return nil,err or "本地文件不可用" end
    if self.is_in_use(path) or self:isLocked(path) then return nil,"请先关闭正在阅读或处理的漫画" end
    for _, request in ipairs(self.requests) do
        if request.source_path==path and (request.state=="pending" or request.state=="preparing") then return nil,"已排队" end
    end
    local request={id=self.next_id,book_id=tostring(self.storage:itemKey(item)),source_path=path,state="pending"}
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
    if not original or self.is_in_use(path) or self:isLocked(path) then return nil,"原版备份不可用或文件正在使用" end
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
                err="已优化，请先恢复原版后重新处理"
            else
                for _, previous in ipairs(self.queue.jobs) do
                    if previous.book_id==request.book_id and previous.source_path==request.source_path and
                            previous.source_fingerprint==fingerprint and previous.algorithm_version=="kissfft-f2892a2-v1" then
                        local retried,retry_error=self.queue:retry(previous.id,previous.state=="completed")
                        if retried then job=previous else err=retry_error end
                        break
                    end
                end
                if not job and not err then
                    job,err=self.queue:add{book_id=request.book_id,source_path=request.source_path,
                        source_fingerprint=fingerprint,algorithm_version="kissfft-f2892a2-v1",profile={strength=0.8}}
                end
            end
            if job then
                for index,value in ipairs(self.requests) do if value==request then table.remove(self.requests,index);break end end
            else request.state="failed";request.error=err end
        end
        self:_save()
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
                    if current==expected and backup==job.source_fingerprint then
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
