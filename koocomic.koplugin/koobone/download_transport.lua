-- SPDX-License-Identifier: AGPL-3.0-only
local Transport={}
Transport.__index=Transport

function Transport:new(options)
    return setmetatable({runner=options.runner or require("koobone.async_task"):new{schedule=options.schedule,timeout=1800,max_bytes=4096},
        files=assert(options.files),api=assert(options.api),resolve=assert(options.resolve),validate=assert(options.validate),
        max_bytes=options.max_bytes or 16*1024*1024*1024},self)
end

function Transport:start(job,path,done)
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
        local ok,err,bytes=self.api:download(fresh.file_url,path,{total=job.entry.remote_size,max_bytes=maximum,handle=output})
        if not ok then
            local message=tostring(err)
            return {error_code=message:match("HTTP 401") and "unauthorized" or
                message:match("HTTP 403") and "forbidden" or "network"}
        end
        if type(bytes)~="number" or bytes<=0 or bytes>maximum or bytes~=math.floor(bytes) or
                (job.entry.remote_size and bytes~=job.entry.remote_size) then return {error_code="invalid_epub"} end
        if not self.files:isSafe(path) or self.files:prefix(path,4)~="PK\003\004" or not self.validate(path) then
            return {error_code="invalid_epub"}
        end
        if not self.files:sync(path) then return {error_code="path_conflict"} end
        local fingerprint=self.files:hash(path)
        if type(fingerprint)~="string" or #fingerprint~=64 or not fingerprint:match("^%x+$") then
            return {error_code="invalid_epub"}
        end
        return {validated=true,committed=false,bytes=bytes,part_path=path,output_fingerprint=fingerprint}
    end,function(value)
        done(type(value)=="table" and value or {error_code="worker_failed"})
    end)
end

return Transport
