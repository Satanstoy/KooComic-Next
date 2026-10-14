package.path="./koocomic.koplugin/?.lua;"..package.path
local ok,Selection=pcall(require,"koobone.selection")
assert(ok,"stable cross-page selection is missing")
local selection=Selection:new("42")
local a={vol_id=1,file_md5="a",vol_name="Original"}
local b={vol_id=2,file_md5="b"}
selection:begin(a);selection:toggle(b)
assert(selection.active and selection:count()==2 and selection:contains(a))
local updated={vol_id=1,file_md5="a",vol_name="Changed metadata"}
local resolved=selection:resolve({b,updated})
assert(resolved[2]==updated and selection:count()==2,"selection must follow IDs, not old item pointers or row indexes")
selection:toggle(updated)
assert(not selection:contains(a) and selection:count()==1)
selection:reconcile({updated})
assert(selection:count()==0 and selection.active,"removed records must be pruned without moving the page")
selection:begin(updated);selection:setAccount("99")
assert(selection:count()==0 and not selection.active,"account changes must clear selection")
selection:begin(updated);selection:cancel()
assert(not selection.active and selection:count()==0)
print("selection spec: OK")
