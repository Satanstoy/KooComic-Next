-- SPDX-License-Identifier: AGPL-3.0-only
local Staging={}
Staging.__index=Staging
local roles={work=true,archive=true,stage=true}
function Staging:new(options) return setmetatable({backend=assert(options.backend)},self) end
function Staging:_load()
    local record,err=self.backend:loadLease()
    if not record then return nil,err end
    if type(record)~="table" or record.schema_version~=1 or record.product_id~="koocomic-next" or
            record.state~="working" or type(record.assets)~="table" then return nil,"invalid staging lease" end
    local count,seen=0,{}
    for index,asset in pairs(record.assets) do
        count=count+1
        if type(index)~="number" or index~=math.floor(index) or index<1 or index>3 or type(asset)~="table" or
                not roles[asset.role] or seen[asset.role] or type(asset.identity)~="string" or asset.identity=="" then
            return nil,"invalid staging ownership"
        end
        seen[asset.role]=true
    end
    if count~=#record.assets then return nil,"sparse staging lease" end
    return record
end
function Staging:begin()
    local b=self.backend
    local prior,err=b:loadLease();if prior or err then return nil,"staging recovery required" end
    for role in pairs(roles) do if b:exists(b.paths[role]) then return nil,"unknown staging artifact" end end
    return b:saveLease{schema_version=1,product_id="koocomic-next",state="working",assets={}}
end
function Staging:_claim(role,id)
    local record,err=self:_load();if not record then return nil,err or "missing staging lease" end
    if not roles[role] or type(id)~="string" or id=="" then return nil,"invalid staging claim" end
    local next_record={schema_version=1,product_id="koocomic-next",state="working",assets={}}
    for _,asset in ipairs(record.assets) do
        if asset.role==role then return asset.identity==id or nil,"staging role already claimed" end
        next_record.assets[#next_record.assets+1]={role=asset.role,identity=asset.identity}
    end
    next_record.assets[#next_record.assets+1]={role=role,identity=id}
    return self.backend:saveLease(next_record)
end
function Staging:createWork()
    local b=self.backend
    if not self:_load() then return nil,"missing staging lease" end
    if not b:createDirectory(b.paths.work) then return nil,"cannot reserve update work directory" end
    local id=b:identity(b.paths.work)
    if not self:_claim("work",id) then if id then b:remove(b.paths.work,id) end;return nil,"work ownership save failed" end
    return true
end
function Staging:openArchive()
    local b=self.backend
    if not self:_load() then return nil,"missing staging lease" end
    local writer,err=b.files:exclusiveWriter(b.paths.archive);if not writer then return nil,err end
    local id=writer:identity()
    if not self:_claim("archive",id) then
        writer:close();if id then b:remove(b.paths.archive,id) end;return nil,"archive ownership save failed"
    end
    return writer
end
function Staging:handoff()
    local b=self.backend
    local candidate=b.paths.work.."/koocomic.koplugin"
    local id=b:identity(candidate)
    if b:exists(b.paths.stage) or not id or not self:_claim("stage",id) then return nil,"candidate ownership failed" end
    return b:move(candidate,b.paths.stage)
end
function Staging:cleanup()
    local b=self.backend
    local record,err=self:_load()
    if not record then
        local prior,load_error=b:loadLease()
        if prior or load_error then return nil,err end
        for role in pairs(roles) do if b:exists(b.paths[role]) then return nil,"unknown staging artifact" end end
        return true
    end
    local owned={}
    for _,asset in ipairs(record.assets) do owned[asset.role]=asset.identity end
    for role in pairs(roles) do
        if b:exists(b.paths[role]) and b:identity(b.paths[role])~=owned[role] then return nil,"staging identity changed" end
    end
    for _,role in ipairs({"stage","archive","work"}) do
        if b:exists(b.paths[role]) and not b:remove(b.paths[role],owned[role]) then return nil,"staging cleanup failed" end
    end
    return b:clearLease()
end
return Staging
