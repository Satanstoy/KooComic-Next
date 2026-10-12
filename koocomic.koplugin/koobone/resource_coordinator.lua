-- SPDX-License-Identifier: AGPL-3.0-only
local Coordinator = {}
Coordinator.__index = Coordinator

function Coordinator:new()
    return setmetatable({}, self)
end

function Coordinator:acquire(owner)
    assert(type(owner) == "string" and owner ~= "", "resource owner required")
    if self.active then return nil, "busy" end
    local token = { owner = owner }
    self.active = token
    return token
end

function Coordinator:release(token)
    if not token or token ~= self.active then return false end
    self.active = nil
    return true
end

function Coordinator:owner()
    return self.active and self.active.owner
end

return Coordinator
