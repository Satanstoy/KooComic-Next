-- SPDX-License-Identifier: AGPL-3.0-only
local Store={}
Store.__index=Store

function Store:new(options)
    local account=assert(options.account_id,"account required")
    assert(type(account)=="string" and account~="","invalid account")
    local directory=assert(options.directory):gsub("/+$","")
    local hash=options.hash or require("ffi/sha2").sha256
    local name=hash(account)
    assert(type(name)=="string" and name:match("^[%w_-]+$"),"invalid account hash")
    local budget=options.budget or 2*1024*1024
    assert(type(budget)=="number" and budget>0 and budget<math.huge and budget==math.floor(budget),"invalid budget")
    return setmetatable({account_id=account,directory=directory,path=directory.."/"..name..".json",budget=budget,
        files=options.files or require("koobone.preprocess_files"):new{roots={directory}},
        codec=options.codec or require("json")},self)
end

function Store:save(snapshot)
    if type(snapshot)~="table" or snapshot.account_id~=self.account_id then return nil,"invalid account snapshot" end
    local encoded,data=pcall(self.codec.encode,snapshot)
    if not encoded or type(data)~="string" then return nil,"snapshot encoding failed" end
    if #data>self.budget then return nil,"snapshot exceeds budget" end
    local created,err=self.files:mkdir(self.directory)
    if not created then return nil,err end
    local written,write_error=self.files:write(self.path..".tmp",data)
    if not written then return nil,write_error end
    local applied,warning=self.files:rename(self.path..".tmp",self.path)
    if applied and warning then return nil,warning end
    return applied,warning
end

function Store:load()
    if not self.files:exists(self.path) then return nil end
    local data,err=self.files:read(self.path,self.budget)
    if not data then return nil,err or "snapshot read failed" end
    if #data>self.budget then return nil,"snapshot exceeds budget" end
    local decoded,value=pcall(self.codec.decode,data)
    if not decoded or type(value)~="table" or value.account_id~=self.account_id then return nil,"invalid snapshot" end
    return value
end

return Store
