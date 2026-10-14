-- SPDX-License-Identifier: AGPL-3.0-only
local Entry=require("koobone.catalog_entry")
local Selection={}
Selection.__index=Selection
function Selection:new(account)
    return setmetatable({account=tostring(account or "local"),ids={},active=false},self)
end
function Selection:key(item)
    local entry=Entry.normalize(self.account,item)
    return entry and entry.id
end
function Selection:cancel() self.ids={};self.active=false end
function Selection:setAccount(account)
    account=tostring(account or "local")
    if account~=self.account then self:cancel();self.account=account end
end
function Selection:begin(item)
    self.active=true
    if item then local id=self:key(item);if id then self.ids[id]=true end end
end
function Selection:toggle(item)
    local id=self:key(item)
    if not id then return false end
    self.active=true;self.ids[id]=not self.ids[id] or nil
    return true
end
function Selection:contains(item) return self.ids[self:key(item)]==true end
function Selection:count()
    local count=0;for _ in pairs(self.ids) do count=count+1 end;return count
end
function Selection:resolve(items)
    local result={};for _,item in ipairs(items) do if self:contains(item) then result[#result+1]=item end end
    return result
end
function Selection:reconcile(items)
    local valid={};for _,item in ipairs(items) do local id=self:key(item);if id then valid[id]=true end end
    for id in pairs(self.ids) do if not valid[id] then self.ids[id]=nil end end
end
return Selection
