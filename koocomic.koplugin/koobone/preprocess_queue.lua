-- SPDX-License-Identifier: AGPL-3.0-only
local Identity = require("koobone.preprocess_identity")
local Queue = {}
Queue.__index = Queue
local warnings={durability_unconfirmed=true,worker_result_missing=true}

local function counter(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function Queue:new(options)
    assert(options.worker and options.worker.asynchronous == true, "asynchronous worker required")
    return setmetatable({
        coordinator = assert(options.coordinator, "coordinator required"),
        worker = options.worker, checkpoint = assert(options.checkpoint, "checkpoint required"),
        jobs = {}, paused = true,
    }, self)
end

function Queue:snapshot()
    return { schema_version = 1, jobs = copy(self.jobs), paused = self.paused }
end

function Queue:_save()
    local called, ok = pcall(self.checkpoint, self:snapshot())
    if not called or not ok then self.paused = true; return nil, "checkpoint failed" end
    return true
end

function Queue:add(source)
    local id, err = Identity.key(source)
    if not id then return nil, err end
    if type(source.source_path) ~= "string" or source.source_path == "" then return nil, "source path required" end
    for _, job in ipairs(self.jobs) do if job.id == id then return nil, "duplicate" end end
    local job = { id = id, state = "pending", processed_pages = 0 }
    for _, field in ipairs({ "book_id", "source_path", "source_fingerprint", "algorithm_version", "profile" }) do
        job[field] = copy(source[field])
    end
    self.jobs[#self.jobs + 1] = job
    if not self:_save() then table.remove(self.jobs); return nil, "checkpoint failed" end
    return job
end

function Queue:resume()
    self.paused = false
    return self:_save()
end

function Queue:pause()
    self.paused = true
    return self:_save()
end

function Queue:tick()
    if self.paused or self.active then return nil, "paused or busy" end
    local job
    for _, candidate in ipairs(self.jobs) do if candidate.state == "pending" then job = candidate; break end end
    if not job then return nil, "idle" end
    local token = self.coordinator:acquire("preprocess")
    if not token then return nil, "resource busy" end
    local active = { job = job, token = token }
    self.active = active
    job.state = "preparing"
    if not self:_save() then
        job.state = "pending"; self.active = nil; self.coordinator:release(token)
        return nil, "checkpoint failed"
    end
    local function done(ok, result)
        if self.active ~= active then return end
        local committed = type(result)=="table" and result.committed==true
        ok = ok and (job.state == "validating" or committed) and type(result) == "table" and
            result.validated == true and type(result.output_fingerprint) == "string" and result.output_fingerprint ~= ""
        job.state = ok and committed and "completed" or (active.cancel_requested and "cancelled" or (ok and "completed" or "failed"))
        if not ok and not active.cancel_requested then job.error = "worker failed" end
        if ok and type(result) == "table" and type(result.output_fingerprint) == "string" then
            job.output_fingerprint = result.output_fingerprint
            job.warning_code=warnings[result.warning_code] and result.warning_code or nil
        end
        self.active = nil
        self.coordinator:release(token)
        self:_save()
    end
    local called, handle = pcall(self.worker.start, self.worker, copy(job), {
        stage = function(state)
            if self.active ~= active or active.cancel_requested then return end
            if (job.state == "preparing" and state == "processing") or
                    (job.state == "processing" and state == "validating") then
                job.state = state
                self:_save()
            end
        end,
        progress = function(current, total)
            if self.active ~= active or active.cancel_requested then return end
            if counter(current) and counter(total) and total >= current then
                job.processed_pages, job.total_pages = current, total
                self:_save()
            end
        end,
        done = done,
    })
    if not called or not handle then done(false); return nil, "worker start failed" end
    active.handle = handle
    return true
end

function Queue:retry(id, output_invalidated)
    for index, job in ipairs(self.jobs) do
        if job.id == id and (job.state == "failed" or job.state == "cancelled" or
                (job.state == "completed" and output_invalidated == true)) then
            job.state, job.error, job.output_fingerprint,job.warning_code = "pending", nil, nil,nil
            job.processed_pages, job.total_pages = 0, nil
            table.remove(self.jobs,index)
            self.jobs[#self.jobs+1]=job
            return self:_save()
        end
    end
    return nil, "job cannot be retried"
end

function Queue:restore(snapshot)
    if self.active or type(snapshot) ~= "table" or snapshot.schema_version ~= 1 or type(snapshot.jobs) ~= "table" then
        return nil, "invalid snapshot"
    end
    local states = { pending = true, preparing = true, processing = true, validating = true,
        completed = true, failed = true, cancelled = true }
    local jobs, seen, count = {}, {}, 0
    for index in pairs(snapshot.jobs) do
        if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil, "invalid jobs" end
        count = count + 1
    end
    if count ~= #snapshot.jobs then return nil, "sparse jobs" end
    for _, value in ipairs(snapshot.jobs) do
        if type(value) ~= "table" or type(value.id) ~= "string" or not states[value.state] or
                not Identity.key(value) or Identity.key(value) ~= value.id or seen[value.id] or
                type(value.source_path) ~= "string" or value.source_path == "" or
                not counter(value.processed_pages) or
                (value.total_pages ~= nil and (not counter(value.total_pages) or value.total_pages < value.processed_pages)) or
                (value.error ~= nil and type(value.error) ~= "string") or
                (value.warning_code~=nil and not warnings[value.warning_code]) or
                (value.output_fingerprint ~= nil and type(value.output_fingerprint) ~= "string") or
                (value.state == "completed" and (type(value.output_fingerprint) ~= "string" or value.output_fingerprint == "")) then
            return nil, "invalid job"
        end
        seen[value.id] = true
        local job = {}
        for _, field in ipairs({ "id", "state", "book_id", "source_path", "source_fingerprint", "algorithm_version",
                "profile", "processed_pages", "total_pages", "error", "output_fingerprint","warning_code" }) do
            job[field] = copy(value[field])
        end
        if job.state == "preparing" or job.state == "processing" or job.state == "validating" then
            job.state, job.error = "failed", "interrupted"
        end
        jobs[#jobs + 1] = job
    end
    self.jobs, self.paused = jobs, true
    return self:_save()
end

function Queue:cancel(id)
    for _, job in ipairs(self.jobs) do
        if job.id == id then
            if self.active and self.active.job == job then
                self.active.cancel_requested = true
                if self.active.handle and self.active.handle.cancel then pcall(self.active.handle.cancel, self.active.handle) end
                return true
            end
            if job.state ~= "pending" then return nil, "not pending" end
            job.state = "cancelled"
            return self:_save()
        end
    end
    return nil, "unknown job"
end

return Queue
