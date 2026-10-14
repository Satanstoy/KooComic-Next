package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, Queue = pcall(require, "koobone.preprocess_queue")
assert(available, "independent preprocessing queue is not implemented")
local Coordinator = require("koobone.resource_coordinator")
local callbacks, started, saved = {}, {}, nil
local coordinator = Coordinator:new()
local queue = Queue:new{
    coordinator = coordinator,
    worker = { asynchronous = true, start = function(_, job, events)
        assert(type(events.stage) == "function", "processing stage transitions are missing")
        events.stage("processing")
        started[#started + 1] = job.book_id
        callbacks[#callbacks + 1] = events
        return { cancel = function() return true end }
    end },
    checkpoint = function(snapshot) saved = snapshot; return true end,
}
local function source(id)
    return { book_id = id, source_path = "/books/" .. id .. ".epub", source_fingerprint = "hash-" .. id,
        algorithm_version = "fft-1", profile = { strength = 0.8 } }
end
local first = assert(queue:add(source("one")))
assert(queue:add(source("one")) == nil, "duplicate pending tasks must be skipped")
local second = assert(queue:add(source("two")))
assert(#started == 0, "adding tasks must never start processing automatically")
local downloading = assert(coordinator:acquire("download"))
queue:resume()
assert(queue:tick() == nil and #started == 0, "download contention must postpone processing")
coordinator:release(downloading)
assert(queue:tick())
assert(first.state == "processing" and started[1] == "one")
callbacks[1].progress(2, 10)
assert(first.processed_pages == 2 and first.total_pages == 10)
callbacks[1].progress(3.5, math.huge)
assert(first.processed_pages == 2 and first.total_pages == 10, "invalid counters must be ignored")
callbacks[1].stage("validating")
callbacks[1].done(true, { validated = true, output_fingerprint = "optimized-one" })
assert(first.state == "completed" and second.state == "pending")
assert(coordinator:owner() == nil)
assert(queue:tick())
assert(queue:cancel(second.id))
assert(coordinator:owner() == "preprocess", "cancellation must wait for worker acknowledgement")
callbacks[2].done(true, {})
assert(second.state == "cancelled" and coordinator:owner() == nil)
callbacks[1].done(false, "late callback")
assert(first.state == "completed", "late callbacks must not change completed jobs")
assert(queue:retry(first.id)==nil, "valid completed results must not be retried blindly")
assert(saved.schema_version == 1 and saved.jobs[1].state == "completed")
assert(saved.jobs[1].handle == nil and saved.jobs[1].token == nil)
local third = assert(queue:add(source("three")))
assert(queue:tick())
callbacks[3].done(true, {})
assert(third.state == "failed", "unvalidated worker success must not complete a task")
assert(type(queue.retry) == "function" and queue:retry(third.id))
assert(third.state == "pending")
assert(type(queue.restore) == "function", "persistent queue recovery is missing")
local snapshot = queue:snapshot()
snapshot.jobs[3].state = "processing"
local recovered = Queue:new{ coordinator = coordinator, worker = queue.worker,
    checkpoint = function() return true end }
assert(recovered:restore(snapshot))
assert(recovered.paused == true and recovered.jobs[3].state == "failed")
assert(recovered.jobs[3].error == "interrupted")
snapshot.jobs[3].id = "forged"
assert(recovered:restore(snapshot) == nil, "restoration must verify source/profile identities")
local ran, restored = pcall(function() return recovered:restore{ schema_version = 1, jobs = {{state = "pending"}} } end)
assert(ran and restored == nil, "incomplete jobs must be rejected without throwing")
for _, mutation in ipairs({
    function(job) job.source_path = nil end,
    function(job) job.processed_pages = math.huge end,
    function(job) job.total_pages = -1 end,
    function(job) job.error = {} end,
    function(job) job.output_fingerprint = nil end,
}) do
    local invalid = queue:snapshot()
    mutation(invalid.jobs[1])
    assert(recovered:restore(invalid) == nil, "malformed persisted fields must be rejected")
end
local checkpoint_ok, failure_starts = false, 0
local failure_queue = Queue:new{
    coordinator = coordinator,
    worker = { asynchronous = true, start = function() failure_starts = failure_starts + 1; error("start failed") end },
    checkpoint = function() return checkpoint_ok end,
}
assert(failure_queue:add(source("failure")) == nil and #failure_queue.jobs == 0)
checkpoint_ok = true
local failure_job = assert(failure_queue:add(source("failure")))
assert(failure_queue:resume())
checkpoint_ok = false
assert(failure_queue:tick() == nil and failure_starts == 0 and coordinator:owner() == nil)
assert(failure_job.state == "pending" and failure_queue.paused)
checkpoint_ok = true
assert(failure_queue:resume())
assert(failure_queue:tick() == nil and failure_job.state == "failed" and coordinator:owner() == nil)
assert(queue:retry(first.id,true), "verified invalidated output must allow a completed task to be queued again")
assert(queue.jobs[#queue.jobs]==first and first.state=="pending")
assert(queue:cancel(third.id))
assert(queue:tick())
assert(first.state=="processing")
assert(queue:cancel(first.id))
callbacks[4].done(true,{validated=true,committed=true,output_fingerprint="committed-before-poll",warning_code="durability_unconfirmed"})
assert(first.state=="completed", "late cancellation must not hide an already committed file transaction")
assert(first.warning_code=="durability_unconfirmed" and queue:snapshot().jobs[#queue.jobs].warning_code=="durability_unconfirmed",
    "applied-output warnings must survive queue persistence")
print("preprocess queue spec: OK")
