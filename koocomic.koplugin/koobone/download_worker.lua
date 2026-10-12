-- SPDX-License-Identifier: AGPL-3.0-only
local Worker={asynchronous=true}
Worker.__index=Worker

function Worker.raw(entry)
    return {vol_id=entry.source.vol_id,file_md5=entry.source.file_md5,vol_name=entry.title,
        vol_series=entry.series_title,vol_author=entry.author,vol_index=entry.volume_label,
        file_size=entry.remote_size,file_type=entry.file_type,_catalog_account_id=entry.account_id}
end

function Worker:new(options)
    return setmetatable({files=assert(options.files),storage=assert(options.storage),transport=assert(options.transport),
        directory=assert(options.directory),account=assert(options.account),hash=options.hash or require("ffi/sha2").sha256,
        schedule=options.schedule or function(delay,callback) require("ui/uimanager"):scheduleIn(delay,callback) end,
        is_in_use=options.is_in_use or function(path)
            local reader=require("apps/reader/readerui").instance
            return reader and reader.document and reader.document.file==path
        end},self)
end

function Worker:paths(job)
    local directory=self.directory.."/"..self.hash(job.id)
    return {directory=directory,claim=directory.."/claim.json",progress=directory.."/progress.json"}
end

function Worker:start(job,events)
    if tostring(self.account() or "")~=job.entry.account_id then return nil,"account changed" end
    local raw=Worker.raw(job.entry)
    local final=self.storage:resolveDownloadPath(raw)
    if not final or not self.files:isSafe(final) or self.files:exists(final) or self.is_in_use(final) then
        return nil,"path conflict or file in use"
    end
    local part=final..".part"
    local paths=self:paths(job)
    if not self.files:mkdir(paths.directory) then return nil,"private job directory unavailable" end
    local stage_directory=final:match("^(.*)/[^/]+$").."/.koocomic-downloads/"..self.hash(job.id)
    local stage=stage_directory.."/verified.epub.part"
    if not self.files:mkdir(stage_directory) then return nil,"path_conflict" end
    local claim=self.files:readJSON(paths.claim)
    if self.files:exists(stage) then
        if not claim or claim.stage_path~=stage or not claim.stage_identity or self.files:identity(stage)~=claim.stage_identity then
            return nil,"path_conflict"
        end
        if not self.files:remove(stage) then return nil,"path_conflict" end
    end
    if self.files:exists(part) then
        if not claim or claim.job_id~=job.id or claim.account_id~=job.entry.account_id or claim.part_path~=part or
                self.files:identity(part)~=claim.part_identity then return nil,"unowned partial file" end
        if not self.files:remove(part) then return nil,"cannot clear owned partial file" end
    end
    if not self.files:writeJSON(paths.progress,{state="preparing",bytes=0}) then return nil,"progress storage unavailable" end
    local finished,cancelled,child_done,committed=false,false,false,false
    local function finish(ok,result)
        if finished then return end
        finished=true
        events.done(ok,result)
    end
    local function guard()
        return not finished and not cancelled and tostring(self.account() or "")==job.entry.account_id and
            not self.is_in_use(final) and self.files:isSafe(stage) and self.files:isSafe(final)
    end
    local child,err=self.transport:start(job,part,function(result)
        child_done=true
        if finished then return end
        if cancelled then finish(false,{error_code="cancelled"});return end
        if tostring(self.account() or "")~=job.entry.account_id then finish(false,{error_code="account_changed"});return end
        if not result.validated or result.part_path~=part or result.staged_path~=stage then finish(false,result);return end
        events.stage("downloading");events.stage("validating")
        local owner=self.files:readJSON(paths.claim)
        if not owner or owner.job_id~=job.id or owner.account_id~=job.entry.account_id or owner.part_path~=part or
                owner.stage_path~=stage or not owner.stage_identity or self.files:identity(stage)~=owner.stage_identity or
                result.stage_identity~=owner.stage_identity then
            finish(false,{error_code="path_conflict"});return
        end
        self.files:hashAsync(stage,self.schedule,guard,function(fingerprint)
            if finished then return end
            if not guard() or fingerprint~=result.output_fingerprint or self.files:identity(stage)~=owner.stage_identity or
                    self.files:exists(final) or self.storage:resolveDownloadPath(raw)~=final then
                finish(false,{error_code=tostring(self.account() or "")~=job.entry.account_id and "account_changed" or "path_conflict"});return
            end
            owner.state,owner.output_fingerprint,owner.bytes="prepared",fingerprint,result.bytes
            if not self.files:writeJSON(paths.claim,owner) then finish(false,{error_code="path_conflict"});return end
            local applied,commit_error=self.files:renameNoReplace(stage,final)
            committed=applied==true
            if not applied then finish(false,{error_code="path_conflict"});return end
            owner.state="committed"
            local saved=self.files:writeJSON(paths.claim,owner)
            local called,recorded=pcall(self.storage.record,self.storage,raw,"complete",{path=final,bytes=result.bytes,total=result.bytes,queue_id=job.id})
            local warning=commit_error and "durability_warning" or ((not saved or not called or not recorded) and "metadata_warning" or nil)
            local function complete()
                finish(true,{validated=true,committed=true,bytes=result.bytes,output_fingerprint=fingerprint,warning=warning})
            end
            if self.files:identity(part)==owner.part_identity then
                self.files:hashAsync(part,self.schedule,nil,function(original_hash)
                    if original_hash==fingerprint and self.files:identity(part)==owner.part_identity then self.files:remove(part) end
                    complete()
                end)
            else complete() end
        end)
    end,{
        stage_path=stage,
        on_created=function(path,identity)
            return self.files:writeJSON(paths.claim,{job_id=job.id,account_id=job.entry.account_id,final_path=final,
                part_path=path,part_identity=identity,state="created"})
        end,
        on_staged=function(path,identity)
            local owner=self.files:readJSON(paths.claim)
            if not owner then return nil end
            owner.stage_path,owner.stage_identity=path,identity
            return self.files:writeJSON(paths.claim,owner)
        end,
        on_stage=function(state)
            local progress=self.files:readJSON(paths.progress) or {};progress.state=state
            assert(self.files:writeJSON(paths.progress,progress))
        end,
        on_progress=function(bytes,total)
            local now=os.time()
            if now~=self.last_progress_at then
                self.last_progress_at=now
                assert(self.files:writeJSON(paths.progress,{state="downloading",bytes=bytes,total=total>0 and total or nil}))
            end
        end,
    })
    if not child then return nil,err end
    local function poll()
        if finished then return end
        if not cancelled then
            local progress=self.files:readJSON(paths.progress)
            if progress then events.stage(progress.state);events.progress(progress.bytes,progress.total) end
        end
        self.schedule(0.2,poll)
    end
    self.schedule(0.2,poll)
    return {cancel=function()
        if finished or committed then return false end
        cancelled=true
        if child_done then finish(false,{error_code="cancelled"});return true end
        local ok=child.cancel()
        if not ok then cancelled=false end
        return ok
    end}
end

return Worker
