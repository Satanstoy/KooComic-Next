-- SPDX-License-Identifier: AGPL-3.0-only
local Transaction = {}
Transaction.__index = Transaction

function Transaction:new(options)
    for _, field in ipairs({ "fs", "is_safe", "is_in_use", "validate", "journal" }) do
        assert(options[field], field .. " required")
    end
    return setmetatable(options, self)
end

function Transaction:_check(request)
    if type(request) ~= "table" then return nil, "invalid transaction" end
    local seen = {}
    for _, field in ipairs({ "source_path", "temporary_path", "backup_path" }) do
        local path = request[field]
        if type(path) ~= "string" or seen[path] or not self.is_safe(path, field) then return nil, "unsafe paths" end
        seen[path] = true
    end
    if self.is_in_use(request.source_path) then return nil, "file in use" end
    if type(request.source_fingerprint) ~= "string" or request.source_fingerprint == "" then
        return nil, "source fingerprint required"
    end
    return true
end

function Transaction:_journal(request, state)
    return self.journal{ state = state, source_path = request.source_path, backup_path = request.backup_path,
        temporary_path = request.temporary_path, source_fingerprint = request.source_fingerprint,
        output_fingerprint = request.output_fingerprint,discard_original=request.discard_original==true }
end

function Transaction:commit(request)
    local ok, err = self:_check(request)
    if not ok then return nil, err end
    local fs = self.fs
    if fs.fingerprint(request.source_path) ~= request.source_fingerprint then return nil, "source changed" end
    if type(request.output_fingerprint) ~= "string" or request.output_fingerprint == "" or
            fs.fingerprint(request.temporary_path) ~= request.output_fingerprint or
            not self.validate(request.temporary_path) then return nil, "output validation failed" end
    if not request.discard_original then
        local size, free = fs.size(request.source_path), fs.free_space(request.source_path)
        if type(size) ~= "number" or type(free) ~= "number" or free < size then return nil, "insufficient space" end
        local backup = fs.fingerprint(request.backup_path)
        if backup and backup ~= request.source_fingerprint then return nil, "backup conflict" end
        if not backup then
            if not self:_journal(request,"backing_up") then return nil,"journal failed" end
            if not fs.copy(request.source_path,request.backup_path) then return nil,"backup failed" end
        end
        if fs.fingerprint(request.backup_path) ~= request.source_fingerprint then return nil, "backup validation failed" end
    end
    if not self:_journal(request, "prepared") then return nil, "journal failed" end
    if not self:_check(request) or fs.fingerprint(request.source_path) ~= request.source_fingerprint or
            fs.fingerprint(request.temporary_path) ~= request.output_fingerprint then
        return nil, "source or output changed or in use"
    end
    if not fs.rename(request.temporary_path, request.source_path) then return nil, "commit failed" end
    if not self:_journal(request, "committed") then return nil, "commit needs recovery" end
    return true
end

function Transaction:restore(request)
    local ok, err = self:_check(request)
    if not ok then return nil, err end
    local fs = self.fs
    if fs.fingerprint(request.backup_path) ~= request.source_fingerprint then return nil, "invalid backup" end
    local current = fs.fingerprint(request.source_path)
    if current == request.source_fingerprint then return true end
    if current ~= request.output_fingerprint then return nil, "reading file changed" end
    if not fs.copy(request.backup_path, request.temporary_path) or
            fs.fingerprint(request.temporary_path) ~= request.source_fingerprint or
            not self.validate(request.temporary_path) then return nil, "restore validation failed" end
    if not self:_journal(request, "restoring") then return nil, "journal failed" end
    if not self:_check(request) or fs.fingerprint(request.source_path) ~= current or
            fs.fingerprint(request.temporary_path) ~= request.source_fingerprint then
        return nil, "reading or restore file changed or in use"
    end
    if not fs.rename(request.temporary_path, request.source_path) then return nil, "restore failed" end
    if not self:_journal(request, "restored") then return nil, "restore needs recovery" end
    return true
end

return Transaction
