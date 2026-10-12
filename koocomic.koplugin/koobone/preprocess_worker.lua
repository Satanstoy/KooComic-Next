-- SPDX-License-Identifier: AGPL-3.0-only
local Util=require("ffi/util")
local Sha=require("ffi/sha2")
local Transaction=require("koobone.preprocess_transaction")
local ffi=require("ffi")
ffi.cdef[[int prctl(int, unsigned long, unsigned long, unsigned long, unsigned long);]]
ffi.cdef[[struct rlimit { unsigned long rlim_cur; unsigned long rlim_max; };
int setrlimit(int, const struct rlimit *); int getpagesize(void);]]
local Worker={asynchronous=true}
Worker.__index=Worker

function Worker:new(options)
    return setmetatable({files=assert(options.files),directory=assert(options.directory),
        native_library=assert(options.native_library),memory_budget=options.memory_budget or 384*1024*1024,
        is_in_use=assert(options.is_in_use),schedule=options.schedule or function(delay,callback)
            require("ui/uimanager"):scheduleIn(delay,callback)
        end},self)
end

function Worker:paths(job)
    local key=Sha.sha256(job.id)
    local workspace=self.directory.."/jobs/"..key
    return {workspace=workspace,status=workspace.."/status.json",cancel=workspace.."/cancel.json",
        reading=workspace.."/reading.json",journal=workspace.."/journal.json",permission=workspace.."/permission.json",claim=workspace.."/claim.json",
        temporary=job.source_path..".koocomic-preprocess.part",
        backup=self.directory.."/originals/"..Sha.sha256(job.source_path).."-"..job.source_fingerprint..".original"}
end

function Worker:start(job,events)
    if not self.files:isSafe(job.source_path) or self.is_in_use(job.source_path) then return nil,"file in use or unsafe" end
    if type(job.source_fingerprint)~="string" or not job.source_fingerprint:match("^%x+$") or #job.source_fingerprint~=64 then
        return nil,"SHA-256 source identity required"
    end
    local paths=self:paths(job)
    if not self.files:isSafe(paths.temporary) or not self.files:isSafe(paths.backup) or self.files:exists(paths.temporary) then
        return nil,"unsafe or existing temporary EPUB"
    end
    if not self.files:mkdir(paths.workspace) or not self.files:mkdir(self.directory.."/originals") then
        return nil,"worker directory unavailable"
    end
    if not self.files:isSafe(paths.workspace.."/page.codec") or self.files:exists(paths.workspace.."/page.codec") then
        return nil,"unsafe or existing codec temporary file"
    end
    self.files:remove(paths.cancel);self.files:remove(paths.status);self.files:remove(paths.permission)
    if not self.files:writeJSON(paths.reading,{occupied=false}) then return nil,"reading lock unavailable" end
    if not self.files:writeJSON(paths.claim,{source_path=job.source_path,temporary_path=paths.temporary,
            source_fingerprint=job.source_fingerprint}) then return nil,"temporary ownership unavailable" end
    events.stage("processing")
    local parent_pid=ffi.C.getpid()
    io.stdout:flush()
    local pid,spawn_error=Util.runInSubProcess(function()
        assert(ffi.C.prctl(1,9,0,0,0)==0 and ffi.C.getppid()==parent_pid,"parent process changed")
        local function cancelled() return self.files:readJSON(paths.cancel)~=nil end
        local function occupied()
            local reading=self.files:readJSON(paths.reading)
            return cancelled() or not reading or reading.occupied~=false
        end
        local owned_output=false
        local ok,result=pcall(function()
            local memory_file=assert(io.open("/proc/self/statm","rb"),"worker memory accounting unavailable")
            local pages=tonumber(memory_file:read("*a"):match("^(%d+)"));memory_file:close()
            local ceiling=assert(pages)*ffi.C.getpagesize()+self.memory_budget
            if ffi.sizeof("unsigned long")==4 then ceiling=math.min(ceiling,0xe0000000) end
            local limit=ffi.new("struct rlimit[1]")
            limit[0].rlim_cur,limit[0].rlim_max=ceiling,ceiling
            assert(ffi.C.setrlimit(9,limit)==0,"worker allocation limit unavailable")
            assert(not occupied(),"file in use or cancelled")
            local Backend=require("koobone.preprocess_koreader")
            local backend=Backend:new{native_library=self.native_library,workspace=paths.workspace,
                memory_budget=self.memory_budget,files=self.files}
            local request={source_path=job.source_path,temporary_path=paths.temporary,backup_path=paths.backup,
                source_fingerprint=job.source_fingerprint}
            local validated_fingerprint
            local transaction_fs=self.files:transactionFS()
            transaction_fs.rename=function(source,target)
                assert(source==paths.temporary and target==job.source_path,"unexpected commit paths")
                assert(self.files:sync(source),"output sync failed")
                assert(self.files:writeJSON(paths.status,{state="committing",output_fingerprint=validated_fingerprint}),
                    "cannot request commit")
                while true do
                    local permission=self.files:readJSON(paths.permission)
                    if permission then return permission.applied==true end
                    if cancelled() or ffi.C.getppid()~=parent_pid then return nil end
                    ffi.C.usleep(10000)
                end
            end
            local transaction=Transaction:new{fs=transaction_fs,
                is_safe=function(path) return self.files:isSafe(path) end,is_in_use=occupied,
                validate=function(path) return self.files:hash(path)==validated_fingerprint end,
                journal=function(record) return self.files:writeJSON(paths.journal,record) end}
            if job.profile.restore then
                request.output_fingerprint=assert(job.profile.output_fingerprint)
                validated_fingerprint=job.source_fingerprint
                owned_output=true
                assert(transaction:restore(request))
            else
                assert(self.files:hash(job.source_path)==job.source_fingerprint,"source changed")
                local processed,err=backend:process(job.source_path,paths.temporary,{profile=job.profile,
                    cancelled=cancelled,
                    created=function() owned_output=true end,
                    progress=function(current,total)
                        assert(self.files:writeJSON(paths.status,{state="processing",current=current,total=total}))
                    end,
                    validating=function() assert(self.files:writeJSON(paths.status,{state="validating"})) end})
                assert(processed,err)
                validated_fingerprint=assert(self.files:hash(paths.temporary),"output fingerprint failed")
                request.output_fingerprint=validated_fingerprint
                assert(transaction:commit(request))
            end
            return {validated=true,committed=true,output_fingerprint=validated_fingerprint,backup_path=paths.backup}
        end)
        if not ok and owned_output then self.files:remove(paths.temporary) end
        self.files:writeJSON(paths.status,{state=ok and "completed" or "failed",result=ok and result or nil,
            error=not ok and tostring(result) or nil})
    end,false,false)
    if not pid then return nil,spawn_error end
    local acknowledged=false
    local cancellation=false
    local committing=false
    local commit_applied=false
    local handle={pid=pid,cancel=function()
        if commit_applied then return false,"already committed" end
        cancellation=true
        self.files:writeJSON(paths.cancel,{cancelled=true})
        Util.terminateSubProcess(pid)
        return true
    end}
    local function guard()
        return not acknowledged and not cancellation and not self.is_in_use(job.source_path)
    end
    local function commit(state)
        committing=true
        local expected_source=job.profile.restore and job.profile.output_fingerprint or job.source_fingerprint
        self.files:hashAsync(paths.temporary,self.schedule,guard,function(output_hash)
            if acknowledged then return end
            if output_hash~=state.output_fingerprint then self.files:writeJSON(paths.permission,{applied=false});return end
            self.files:hashAsync(job.source_path,self.schedule,guard,function(source_hash)
                if acknowledged then return end
                local applied=false
                if source_hash==expected_source and guard() then
                    applied=self.files:rename(paths.temporary,job.source_path,true)==true
                end
                commit_applied=applied
                local saved=self.files:writeJSON(paths.permission,{applied=applied})
                if not saved then
                    Util.terminateSubProcess(pid)
                    acknowledged=true
                    events.done(applied,applied and {validated=true,committed=true,
                        output_fingerprint=state.output_fingerprint,backup_path=paths.backup} or nil)
                end
            end)
        end)
    end
    local function poll()
        if acknowledged then return end
        local guarded=self.files:writeJSON(paths.reading,{occupied=self.is_in_use(job.source_path)==true})
        if not guarded then handle.cancel() end
        local state=self.files:readJSON(paths.status)
        if state and state.current then events.progress(state.current,state.total) end
        if state and state.state=="validating" then events.stage("validating") end
        if state and state.state=="committing" and not committing then
            events.stage("validating")
            commit(state)
        end
        if Util.isSubProcessDone(pid) then
            acknowledged=true
            if state and state.state=="completed" then events.stage("validating");events.done(true,state.result)
            else events.done(false,state and state.error or "worker exited without a result") end
            return
        end
        self.schedule(0.1,poll)
    end
    self.schedule(0.1,poll)
    return handle
end

return Worker
