package.path="./koocomic.koplugin/?.lua;"..package.path
local available,Store=pcall(require,"koobone.download_queue_store")
assert(available,"atomic account download queue store is missing")
local files={}
local content
local fail=false
local fs={mkdir=function() return true end,exists=function(_,path) return files[path]~=nil end,
    read=function(_,path) return files[path] end,write=function(_,path,data) files[path]=data;return true end,
    rename=function(_,from,to) if fail then return nil end;files[to],files[from]=files[from],nil;return true end}
local codec={encode=function(value) content=value;return string.rep("x",value.size or 10) end,
    decode=function() return content end}
local store=Store:new{directory="/private/queue",account_id="one",files=fs,codec=codec,hash=function(value) return "hash-"..value end,budget=100}
assert(store:load()==nil)
assert(store:save{account_id="one",size=10} and store:load().account_id=="one")
local previous=files[store.path]
fail=true
assert(not store:save{account_id="one",size=20} and files[store.path]==previous,"failed rename must keep old queue snapshot")
fail=false
assert(not store:save{account_id="one",size=101} and files[store.path]==previous,"writer must obey reader budget")
assert(not store:save{account_id="other"},"wrong-account snapshots must not overwrite this store")
local other=Store:new{directory="/private/queue",account_id="two",files=fs,codec=codec,hash=function(value) return "hash-"..value end}
assert(other.path~=store.path)
fs.rename=function(_,from,to) files[to],files[from]=files[from],nil;return true,"durability unconfirmed" end
assert(not store:save{account_id="one",size=30},"an applied but nondurable queue checkpoint must not authorize a worker")
print("download queue store spec: OK")
