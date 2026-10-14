-- SPDX-License-Identifier: AGPL-3.0-only
local Status={}
Status.__index=Status
local function fingerprint(value)
    return type(value)=="string" and #value==64 and value:match("^%x+$")~=nil
end
function Status:new(options)
    return setmetatable({storage=assert(options.storage),files=assert(options.files),schedule=assert(options.schedule),
        coordinator=options.coordinator,may_start=options.may_start or function() return true end,
        on_changed=options.on_changed,unschedule=options.unschedule,cache=options.cache or {},queue={},pending={}},self)
end
function Status:check(path,expected)
    if self.closed then return "checking" end
    local identity=self.storage:fileIdentity(path)
    if not identity then return "missing" end
    if not fingerprint(expected) then return "check_failed" end
    local cached=self.cache[path]
    if cached and cached.identity==identity and cached.expected==expected then return cached.state end
    local pending=self.pending[path]
    if not pending or pending.identity~=identity or pending.expected~=expected then
        if pending then pending.cancelled=true end
        local entry={path=path,identity=identity,expected=expected}
        self.pending[path]=entry;self.queue[#self.queue+1]=entry
    end
    self:_start()
    return "checking"
end
function Status:_start()
    if self.closed or self.active or not self.may_start() then return end
    while #self.queue>0 do
        local entry=self.queue[1]
        if entry.cancelled or self.pending[entry.path]~=entry then table.remove(self.queue,1)
        else
            local token
            if self.coordinator then
                token=self.coordinator:acquire("preprocess_status")
                if not token then
                    if not self.retry then
                        self.retry=function() self.retry=nil;self:_start() end
                        self.schedule(0.2,self.retry)
                    end
                    return
                end
            end
            table.remove(self.queue,1)
            local flight={entry=entry,token=token}
            self.active=flight
            local function guard()
                return not self.closed and not entry.cancelled and self.may_start() and
                    self.storage:fileIdentity(entry.path)==entry.identity
            end
            local function done(hash)
                if self.active~=flight then return end
                self.active=nil
                if token then self.coordinator:release(token) end
                if self.pending[entry.path]==entry then self.pending[entry.path]=nil end
                if guard() then
                    self.cache[entry.path]={identity=entry.identity,expected=entry.expected,
                        state=fingerprint(hash) and (hash==entry.expected and "optimized" or "unprocessed") or "check_failed"}
                end
                if not self.closed then
                    self.schedule(0,function()
                        if self.closed then return end
                        if self.on_changed then self.on_changed() end
                        self:_start()
                    end)
                end
            end
            local called=pcall(self.files.hashAsync,self.files,entry.path,self.schedule,guard,done)
            if not called then done(nil) end
            return
        end
    end
end
function Status:close()
    self.closed=true;self.queue={};self.pending={}
    if self.retry and self.unschedule then self.unschedule(self.retry) end
    self.retry=nil
end
return Status
