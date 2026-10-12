-- SPDX-License-Identifier: AGPL-3.0-only
local Entry=require("koobone.catalog_entry")
local Queue={}
Queue.__index=Queue

local function counter(value)
    return type(value)=="number" and value>=0 and value<math.huge and value==math.floor(value)
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

local function dense(value)
    if type(value)~="table" then return false end
    local count=0
    for key in pairs(value) do
        if not counter(key) or key<1 then return false end
        count=count+1
    end
    return count==#value
end

local states={pending=true,preparing=true,downloading=true,validating=true,completed=true,
    failed=true,cancelled=true,interrupted=true}
local errors={worker_failed=true,cancelled=true,interrupted=true,network=true,unauthorized=true,forbidden=true,
    no_space=true,path_conflict=true,invalid_epub=true,account_changed=true}

local function entry(account,raw)
    local normalized=Entry.normalize(account,raw)
    if not normalized or normalized.file_type:lower()~="epub" then return nil end
    local dto={id=normalized.id,account_id=normalized.account_id,title=normalized.title,
        source=copy(normalized.source),file_type="epub"}
    for _,field in ipairs({"author","series_title","volume_label"}) do
        local value=normalized[field]
        if type(value)=="string" or (type(value)=="number" and value==value and math.abs(value)<math.huge) then dto[field]=value end
    end
    if counter(normalized.remote_size) and normalized.remote_size>0 then dto.remote_size=normalized.remote_size end
    return dto
end

function Queue:new(options)
    assert(options.worker and options.worker.asynchronous==true,"asynchronous download worker required")
    local account=assert(Entry.normalize(options.account_id,{file_md5="queue"}),"account required").account_id
    return setmetatable({account_id=account,worker=options.worker,coordinator=assert(options.coordinator),
        checkpoint=assert(options.checkpoint),is_downloaded=options.is_downloaded or function() return false end,
        jobs={},paused=true},self)
end

function Queue:snapshot()
    return {schema_version=1,account_id=self.account_id,jobs=copy(self.jobs),paused=self.paused}
end

function Queue:_save()
    local called,saved=pcall(self.checkpoint,self:snapshot())
    if not called or not saved then self.paused=true;return nil,"checkpoint failed" end
    return true
end

function Queue:add(items)
    if not dense(items) then return nil,"invalid items" end
    local counts={added=0,duplicate=0,downloaded=0,invalid=0}
    local known={};for _,job in ipairs(self.jobs) do known[job.id]=true end
    local initial=#self.jobs
    for _,raw in ipairs(items) do
        local dto=entry(self.account_id,raw)
        if not dto then counts.invalid=counts.invalid+1
        elseif known[dto.id] then counts.duplicate=counts.duplicate+1
        else
            local called,downloaded=pcall(self.is_downloaded,raw)
            if not called then counts.invalid=counts.invalid+1
            elseif downloaded then counts.downloaded=counts.downloaded+1
            else
                self.jobs[#self.jobs+1]={id=dto.id,entry=dto,state="pending",attempts=0,bytes=0,total=dto.remote_size}
                known[dto.id]=true;counts.added=counts.added+1
            end
        end
    end
    if counts.added>0 and not self:_save() then
        while #self.jobs>initial do table.remove(self.jobs) end
        return nil,"checkpoint failed"
    end
    return counts
end

function Queue:resume()
    self.paused=false
    return self:_save()
end

function Queue:pause()
    self.paused=true
    return self:_save()
end

function Queue:tick()
    if self.paused or self.active then return nil,"paused or busy" end
    local job
    for _,candidate in ipairs(self.jobs) do if candidate.state=="pending" then job=candidate;break end end
    if not job then return nil,"idle" end
    local token=self.coordinator:acquire("download")
    if not token then return nil,"resource busy" end
    local active={job=job,token=token}
    self.active=active
    local attempts=job.attempts
    job.state,job.attempts="preparing",attempts+1
    if not self:_save() then
        job.state,job.attempts="pending",attempts;self.active=nil;self.coordinator:release(token)
        return nil,"checkpoint failed"
    end
    local function done(ok,result)
        if self.active~=active then return end
        local valid=ok and type(result)=="table" and result.validated==true and result.committed==true and
            counter(result.bytes) and result.bytes>0 and type(result.output_fingerprint)=="string" and
            #result.output_fingerprint==64 and result.output_fingerprint:match("^%x+$") and
            (job.entry.remote_size==nil or job.entry.remote_size==result.bytes)
        if valid then
            job.state,job.bytes,job.total,job.output_fingerprint,job.error_code="completed",result.bytes,result.bytes,result.output_fingerprint,nil
        else
            job.state=active.cancel_requested and "cancelled" or "failed"
            job.error_code=active.cancel_requested and "cancelled" or
                (type(result)=="table" and errors[result.error_code] and result.error_code or "worker_failed")
        end
        self.active=nil;self.coordinator:release(token);self:_save()
    end
    local called,handle=pcall(self.worker.start,self.worker,copy(job),{
        stage=function(state)
            if self.active~=active or active.cancel_requested then return end
            if (job.state=="preparing" and state=="downloading") or (job.state=="downloading" and state=="validating") then
                job.state=state;self:_save()
            end
        end,
        progress=function(bytes,total)
            if self.active~=active or active.cancel_requested or job.state~="downloading" then return end
            if counter(bytes) and bytes>=job.bytes and (total==nil or (counter(total) and total>0 and total>=bytes)) then
                job.bytes,job.total=bytes,total
            end
        end,
        done=done,
    })
    if not called or type(handle)~="table" or type(handle.cancel)~="function" then done(false);return nil,"worker start failed" end
    active.handle=handle
    return true
end

function Queue:cancel(id)
    for _,job in ipairs(self.jobs) do
        if job.id==id then
            local active=self.active
            if active and active.job==job then
                active.cancel_requested=true
                local called,ok=pcall(active.handle.cancel,active.handle)
                if not called or not ok then
                    if self.active==active then active.cancel_requested=false end
                    return nil,"cancellation failed"
                end
                return true
            end
            if job.state~="pending" then return nil,"not pending" end
            job.state,job.error_code="cancelled","cancelled"
            if not self:_save() then job.state,job.error_code="pending",nil;return nil,"checkpoint failed" end
            return true
        end
    end
    return nil,"unknown job"
end

function Queue:retry(id)
    for _,job in ipairs(self.jobs) do
        if job.id==id and (job.state=="failed" or job.state=="cancelled" or job.state=="interrupted") then
            local old={state=job.state,error_code=job.error_code,bytes=job.bytes,total=job.total}
            job.state,job.error_code,job.bytes,job.total="pending",nil,0,job.entry.remote_size
            if not self:_save() then
                job.state,job.error_code,job.bytes,job.total=old.state,old.error_code,old.bytes,old.total
                return nil,"checkpoint failed"
            end
            return true
        end
    end
    return nil,"job cannot be retried"
end

function Queue:restore(snapshot)
    if self.active or type(snapshot)~="table" or snapshot.schema_version~=1 or snapshot.account_id~=self.account_id or
            type(snapshot.paused)~="boolean" or not dense(snapshot.jobs) then return nil,"invalid snapshot" end
    local jobs,seen={},{}
    for _,value in ipairs(snapshot.jobs) do
        local dto=type(value)=="table" and value.entry
        if type(dto)~="table" or type(dto.source)~="table" or dto.account_id~=self.account_id or
                type(dto.title)~="string" or dto.file_type~="epub" or
                (dto.remote_size~=nil and (not counter(dto.remote_size) or dto.remote_size==0)) then
            return nil,"invalid entry"
        end
        local normalized=entry(self.account_id,{vol_id=dto.source.vol_id,file_md5=dto.source.file_md5,
            vol_name=dto.title,file_type=dto.file_type,file_size=dto.remote_size,vol_author=dto.author,
            vol_series=dto.series_title,vol_index=dto.volume_label})
        if not normalized or normalized.id~=dto.id or dto.id~=value.id or seen[value.id] or not states[value.state] or
                not counter(value.attempts) or not counter(value.bytes) or
                (value.total~=nil and (not counter(value.total) or value.total==0 or value.total<value.bytes)) or
                (value.error_code~=nil and not errors[value.error_code]) or
                (value.output_fingerprint~=nil and (type(value.output_fingerprint)~="string" or
                    #value.output_fingerprint~=64 or not value.output_fingerprint:match("^%x+$"))) or
                (value.state=="completed" and (not value.output_fingerprint or value.attempts==0 or value.bytes==0 or
                    value.total~=value.bytes or (dto.remote_size~=nil and dto.remote_size~=value.bytes))) then
            return nil,"invalid job"
        end
        local job={id=value.id,entry=normalized,state=value.state,attempts=value.attempts,bytes=value.bytes,
            total=value.total,error_code=value.error_code,output_fingerprint=value.output_fingerprint}
        if job.state=="preparing" or job.state=="downloading" or job.state=="validating" then
            job.state,job.error_code="interrupted","interrupted"
        end
        seen[value.id]=true;jobs[#jobs+1]=job
    end
    local previous=self.jobs
    self.jobs,self.paused=jobs,true
    if not self:_save() then self.jobs=previous;return nil,"checkpoint failed" end
    return true
end

return Queue
