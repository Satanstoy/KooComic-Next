-- SPDX-License-Identifier: AGPL-3.0-only
local Transport={}
Transport.__index=Transport

function Transport:new(options)
    return setmetatable({runner=options.runner or require("koobone.async_task"):new{schedule=options.schedule,timeout=1800,max_bytes=4096},
        files=assert(options.files),api=assert(options.api),resolve=assert(options.resolve),validate=assert(options.validate),
        max_bytes=options.max_bytes or 16*1024*1024*1024},self)
end

function Transport:start(job,path,done,hooks)
    hooks=hooks or {}
    if type(job)~="table" or type(job.entry)~="table" or type(path)~="string" or not path:match("%.epub%.part$") or
            not self.files:isSafe(path) or self.files:exists(path) then return nil,"unsafe or existing partial file" end
    local maximum=self.max_bytes
    if type(maximum)~="number" or maximum<=0 or maximum>=math.huge or maximum~=math.floor(maximum) then
        return nil,"invalid transfer budget"
    end
    if job.entry.remote_size and (type(job.entry.remote_size)~="number" or job.entry.remote_size<=0 or
            job.entry.remote_size>maximum or job.entry.remote_size~=math.floor(job.entry.remote_size)) then return nil,"invalid expected size" end
    return self.runner:start(function()
        local fresh=self.resolve(job.entry)
        if type(fresh)~="table" or type(fresh.file_url)~="string" or fresh.file_url=="" then return {error_code="network"} end
        if not self.files:isSafe(path) or self.files:exists(path) then return {error_code="path_conflict"} end
        local output=self.files:exclusiveWriter(path)
        if not output then return {error_code="path_conflict"} end
        local source_identity=output.identity and output:identity()
        if hooks.on_created then
            if not source_identity or not hooks.on_created(path,source_identity) then output:close();return {error_code="path_conflict"} end
        end
        if hooks.on_stage then hooks.on_stage("downloading") end
        local stream=hooks.stage_path and require("ffi/sha2").sha256() or nil
        local ok,err,bytes,stream_hash=self.api:download(fresh.file_url,path,{total=job.entry.remote_size,max_bytes=maximum,handle=output,
            on_progress=hooks.on_progress,update_hash=stream})
        if not ok then
            local message=tostring(err)
            return {error_code=message:match("HTTP 401") and "unauthorized" or
                message:match("HTTP 403") and "forbidden" or "network"}
        end
        if type(bytes)~="number" or bytes<=0 or bytes>maximum or bytes~=math.floor(bytes) or
                (job.entry.remote_size and bytes~=job.entry.remote_size) then return {error_code="invalid_epub"} end
        if hooks.on_stage then hooks.on_stage("validating") end
        local validated_path,stage_identity=path,nil
        if hooks.stage_path then
            local copied,count,identity=self.files:copyExclusive(path,hooks.stage_path,source_identity,maximum,hooks.on_staged)
            if not copied or copied~=stream_hash or count~=bytes then return {error_code="path_conflict"} end
            validated_path,stage_identity=hooks.stage_path,identity
        end
        if not self.files:isSafe(validated_path) or self.files:prefix(validated_path,4)~="PK\003\004" or not self.validate(validated_path) then
            return {error_code="invalid_epub"}
        end
        if not self.files:sync(validated_path) then return {error_code="path_conflict"} end
        local fingerprint=self.files:hash(validated_path)
        if type(fingerprint)~="string" or #fingerprint~=64 or not fingerprint:match("^%x+$") then
            return {error_code="invalid_epub"}
        end
        if stream_hash and fingerprint~=stream_hash then return {error_code="path_conflict"} end
        return {validated=true,committed=false,bytes=bytes,part_path=path,output_fingerprint=fingerprint,
            staged_path=hooks.stage_path,stage_identity=stage_identity}
    end,function(value)
        done(type(value)=="table" and value or {error_code="worker_failed"})
    end)
end

return Transport
