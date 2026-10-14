-- SPDX-License-Identifier: AGPL-3.0-only
local ffi=require("ffi")
local Util=require("ffi/util")
local JSON=require("json")
ffi.cdef[[int prctl(int, unsigned long, unsigned long, unsigned long, unsigned long);]]
local Task={}
Task.__index=Task
function Task:new(options)
    options=options or {}
    return setmetatable({schedule=options.schedule or function(delay,callback)
        require("ui/uimanager"):scheduleIn(delay,callback)
    end,max_bytes=options.max_bytes or 32*1024*1024,timeout=options.timeout or 180},self)
end
function Task:start(work,complete)
    local parent=ffi.C.getpid()
    io.stdout:flush()
    local pid,fd=Util.runInSubProcess(function(_,write_fd)
        assert(ffi.C.prctl(1,9,0,0,0)==0 and ffi.C.getppid()==parent,"parent changed")
        local ok,value,err=pcall(work)
        local encoded=JSON.encode({ok=ok and value~=nil,result=ok and value or nil,
            error=not ok and "书库工作进程异常" or err})
        if #encoded>self.max_bytes then encoded=JSON.encode({ok=false,error="书库超过进程通信资源预算"}) end
        local offset=0
        while offset<#encoded do
            local wrote=tonumber(ffi.C.write(write_fd,ffi.cast("const char*",encoded)+offset,#encoded-offset))
            assert(wrote and wrote>0,"pipe write failed")
            offset=offset+wrote
        end
    end,true,false)
    if not pid then return nil,fd end
    local finished,cancelled,failure=false,false,nil
    local chunks,size={},0
    local started=Util.gettime()
    local handle={pid=pid}
    function handle.cancel()
        if finished then return false end
        cancelled=true
        -- Cancellation can precede the child's setpgid; target its PID, not only the process group.
        if not Util.isSubProcessDone(pid) then ffi.C.kill(pid,9) end
        return true
    end
    local function finish(value,err)
        finished=true;ffi.C.close(fd);complete(value,err)
    end
    local function poll()
        if finished then return end
        if Util.gettime()-started>self.timeout and not cancelled then failure="书库同步超时";handle.cancel() end
        local available=Util.getNonBlockingReadSize(fd)
        if available==nil then failure="不支持非阻塞进程通信";handle.cancel() end
        if available and available>0 then
            local length=math.min(available,65536)
            local buffer=ffi.new("char[?]",length)
            local read=tonumber(ffi.C.read(fd,buffer,length))
            if read and read>0 then
                size=size+read
                if size>self.max_bytes then failure="书库超过进程通信资源预算";handle.cancel()
                else chunks[#chunks+1]=ffi.string(buffer,read) end
            elseif not cancelled then failure="进程通信读取失败";handle.cancel() end
        end
        if Util.isSubProcessDone(pid) then
            -- A exited child may leave more than one read budget in the pipe.
            local remaining=Util.getNonBlockingReadSize(fd)
            if not cancelled and remaining and remaining>0 then self.schedule(0.01,poll);return end
            if cancelled then finish(nil,failure or "同步已取消");return end
            local ok,message=pcall(JSON.decode,table.concat(chunks))
            if not ok or type(message)~="table" or not message.ok then
                finish(nil,type(message)=="table" and message.error or "书库进程未返回有效结果")
            else finish(message.result) end
            return
        end
        self.schedule(0.01,poll)
    end
    self.schedule(0.01,poll)
    return handle
end
return Task
