-- SPDX-License-Identifier: AGPL-3.0-only
local Transaction={}
Transaction.__index=Transaction
local phases={planned=true,backing_config=true,aborted=true,prepared=true,installed=true,confirmed=true,rolling_back=true,rolled_back=true}
local function version(value) return type(value)=="string" and value:match("^%d+%.%d+%.%d+$") end
local function identity(value) return type(value)=="string" and value~="" end
function Transaction:new(options)
    return setmetatable({backend=assert(options.backend),paths=assert(options.paths)},self)
end
function Transaction:_load()
    local record,err=self.backend:load()
    if not record then return nil,err end
    if type(record)~="table" or record.schema_version~=1 or record.product_id~="koocomic-next" or
            not phases[record.phase] or not version(record.old_version) or not version(record.new_version) or
            not identity(record.old_identity) or not identity(record.new_identity) or
            (record.config_identity~=nil and not identity(record.config_identity)) or
            (record.phase~="planned" and record.phase~="backing_config" and record.phase~="aborted" and
                not identity(record.config_identity)) then return nil,"invalid update transaction" end
    return record
end
function Transaction:_save(record,phase)
    record.phase=phase
    return self.backend:save(record)
end
function Transaction:install(old_version,new_version,persist_settings)
    local b,p=self.backend,self.paths
    if not version(old_version) or not version(new_version) or not b:validate(p.live,old_version) or
            not b:validate(p.stage,new_version) then return nil,"invalid update inputs" end
    local prior,load_error=b:load()
    if prior or load_error or b:exists(p.backup) or b:exists(p.failed) or b:exists(p.config) then return nil,"unresolved update backup" end
    local record={schema_version=1,product_id="koocomic-next",old_version=old_version,new_version=new_version,
        old_identity=b:identity(p.live),new_identity=b:identity(p.stage)}
    if b.recoveryHashes then
        record.recovery_hashes=b:recoveryHashes(p.live)
        if not record.recovery_hashes then return nil,"recovery modules unreadable" end
    end
    if not identity(record.old_identity) or not identity(record.new_identity) then return nil,"unsafe update directories" end
    if not self:_save(record,"planned") then return nil,"transaction save failed" end
    if not b:backupSettings(function(_,id)
        record.config_identity=id;return self:_save(record,"backing_config")
    end) then return nil,"settings backup failed; recovery required" end
    record.config_identity=record.config_identity or b:identity(p.config)
    if not identity(record.config_identity) or not self:_save(record,"prepared") then return nil,"transaction save failed" end
    local exchanged,err=b:exchange(p.live,p.stage)
    if not exchanged then return nil,err or "atomic exchange unavailable" end
    if not b:move(p.stage,p.backup) then
        local restored,restore_error=self:rollback()
        return nil,restored and "backup relocation failed; old version restored" or restore_error
    end
    local called,saved=pcall(persist_settings)
    if not called or not saved or not self:_save(record,"installed") then
        local restored,restore_error=self:rollback()
        return nil,restored and "update persistence failed; old version restored" or restore_error
    end
    return true
end
function Transaction:rollback()
    local record,err=self:_load();if not record then return nil,err or "no recoverable update" end
    local b,p=self.backend,self.paths
    if b:identity(p.config)~=record.config_identity then return nil,"settings backup identity changed" end
    local live=b:identity(p.live)
    if live~=record.old_identity and live~=record.new_identity then return nil,"live plugin identity changed" end
    if live==record.new_identity then
        local old=b:identity(p.backup)==record.old_identity and p.backup or
            b:identity(p.stage)==record.old_identity and p.stage or nil
        if not old or not b:validate(old,record.old_version) then return nil,"old plugin backup unavailable" end
        if not self:_save(record,"rolling_back") then return nil,"rollback intent save failed" end
        if not b:exchange(p.live,old) then return nil,"rollback exchange failed; backups preserved" end
    end
    if not b:restoreSettings() then return nil,"old code restored; settings recovery still required" end
    if not self:_save(record,"rolled_back") then return nil,"old code restored; transaction reconciliation required" end
    return true
end
function Transaction:recover(current_version)
    local record,err=self:_load();if not record then return nil,err end
    if record.phase=="planned" or record.phase=="backing_config" then
        if self.backend:identity(self.paths.live)~=record.old_identity then return nil,"unexpected pre-install code" end
        return self:_save(record,"aborted")
    end
    if record.phase=="prepared" or record.phase=="rolling_back" then return self:rollback() end
    if record.phase=="installed" then return self:confirm(current_version) end
    if record.phase=="confirmed" then
        return self.backend:identity(self.paths.live)==record.new_identity and
            self.backend:validate(self.paths.live,record.new_version) or nil,"confirmed update changed"
    end
    return self.backend:identity(self.paths.live)==record.old_identity or nil,"rollback changed"
end
function Transaction:prepareNew()
    local record,err=self:_load()
    if not record then local prior,load_error=self.backend:load();if prior or load_error then return nil,err end;return true end
    if record.phase~="confirmed" and record.phase~="rolled_back" and record.phase~="aborted" then return nil,"update recovery required" end
    local b,p=self.backend,self.paths
    local expected=record.phase=="confirmed" and record.new_identity or record.old_identity
    if b:identity(p.live)~=expected then return nil,"live update identity changed" end
    local owned={}
    for _,path in ipairs({p.backup,p.stage,p.failed}) do
        local id=b:identity(path)
        if b:exists(path) and id~=record.old_identity and id~=record.new_identity then return nil,"unknown update artifact" end
        owned[path]=id
    end
    if b:exists(p.config) and b:identity(p.config)~=record.config_identity then return nil,"unknown settings backup" end
    owned[p.config]=record.config_identity
    for _,path in ipairs({p.backup,p.stage,p.failed,p.config}) do
        if b:exists(path) and (not owned[path] or not b:remove(path,owned[path])) then return nil,"update artifact cleanup failed" end
    end
    return b:clear()
end
function Transaction:confirm(current_version)
    local record,err=self:_load();if not record then return nil,err end
    if current_version~=record.new_version or self.backend:identity(self.paths.live)~=record.new_identity or
            not self.backend:validate(self.paths.live,current_version) then return self:rollback() end
    return self:_save(record,"confirmed")
end
return Transaction
