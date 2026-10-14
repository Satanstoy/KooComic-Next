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
        space=options.space,reserve=options.reserve or 64*1024*1024,
        is_in_use=assert(options.is_in_use),schedule=options.schedule or function(delay,callback)
            require("ui/uimanager"):scheduleIn(delay,callback)
        end},self)
end

function Worker:hasSpace(source)
    local fs=self.files:transactionFS()
    local called,size=pcall(fs.size,source)
    if not called or type(size)~="number" or size~=size or size<=0 or size==math.huge then return nil,"source size unavailable" end
    local required=size*2+self.reserve
    for _,path in ipairs({source,self.directory}) do
        local called,free=pcall(self.space or fs.free_space,path)
        if not called or type(free)~="number" or free~=free or free==math.huge or free<required then
            return nil,"temporary space insufficient or unknown"
        end
    end
    return true
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
    local enough,space_error=self:hasSpace(job.source_path)
    if not enough then return nil,space_error end
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
        local output_identity
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
                source_fingerprint=job.source_fingerprint,discard_original=job.profile.discard_original==true}
            local validated_fingerprint
            local transaction_fs=self.files:transactionFS()
            transaction_fs.rename=function(source,target)
                assert(source==paths.temporary and target==job.source_path,"unexpected commit paths")
                if job.profile.restore then output_identity=self.files:identity(source) end
                assert(output_identity and self.files:identity(source)==output_identity,"output ownership changed")
                assert(self.files:sync(source),"output sync failed")
                assert(self.files:writeJSON(paths.status,{state="committing",output_fingerprint=validated_fingerprint,
                    output_identity=output_identity}),
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
                    created=function() owned_output=true;output_identity=self.files:identity(paths.temporary) end,
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
        if not ok and owned_output and self.files:identity(paths.temporary)==output_identity then self.files:remove(paths.temporary) end
        self.files:writeJSON(paths.status,{state=ok and "completed" or "failed",result=ok and result or nil,
            error=not ok and tostring(result) or nil})
    end,false,false)
    if not pid then return nil,spawn_error end
    local acknowledged=false
    local cancellation=false
    local committing=false
    local commit_applied=false
    local committed_result
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
        local output_identity=self.files:identity(paths.temporary)
        local source_identity=self.files:identity(job.source_path)
        self.files:hashAsync(paths.temporary,self.schedule,guard,function(output_hash)
            if acknowledged then return end
            if output_hash~=state.output_fingerprint then self.files:writeJSON(paths.permission,{applied=false});return end
            self.files:hashAsync(job.source_path,self.schedule,guard,function(source_hash)
                if acknowledged then return end
                local source_stamp=self.files:stamp(job.source_path)
                self.files:hashAsync(paths.temporary,self.schedule,guard,function(final_hash)
                    if acknowledged then return end
                    local applied=false
                    if source_hash==expected_source and final_hash==state.output_fingerprint and guard() and
                            source_identity and self.files:identity(job.source_path)==source_identity and
                            source_stamp and self.files:stamp(job.source_path)==source_stamp and
                            output_identity and output_identity==state.output_identity and self.files:identity(paths.temporary)==output_identity then
                        local renamed,warning=self.files:rename(paths.temporary,job.source_path,true)
                        applied=renamed==true
                        if applied then committed_result={validated=true,committed=true,
                            output_fingerprint=state.output_fingerprint,backup_path=paths.backup,
                            warning_code=warning and "durability_unconfirmed" or nil} end
                    end
                    commit_applied=applied
                    local saved=self.files:writeJSON(paths.permission,{applied=applied})
                    if not saved then
                        Util.terminateSubProcess(pid)
                        if committed_result then committed_result.warning_code=committed_result.warning_code or "worker_result_missing" end
                    end
                end,true)
            end,true)
        end,true)
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
            if commit_applied then
                if not state or state.state~="completed" then committed_result.warning_code=committed_result.warning_code or "worker_result_missing" end
                events.stage("validating");events.done(true,committed_result)
            elseif state and state.state=="completed" then events.stage("validating");events.done(true,state.result)
            else events.done(false,state and state.error or "worker exited without a result") end
            return
        end
        self.schedule(0.1,poll)
    end
    self.schedule(0.1,poll)
    return handle
end

return Worker
