package.path="./koocomic.koplugin/?.lua;"..package.path
local Library=require("koobone.library")
local function items(count)
    local result={}
    for index=1,count do result[index]={vol_id=index,file_md5="hash"..index,vol_name="Original "..index,
        vol_series="Series",file_url="https://example.test/signed/"..index} end
    return result
end
local all=items(65)
local calls={}
local account="42"
local api={library=function(_,limit)
    calls[#calls+1]=limit
    local result={};for index=1,math.min(limit,#all) do result[index]=all[index] end
    return {data=result,total=#all}
end}
local saved
local store={commit=function(_,id,entries,meta) saved={account_id=id,entries=entries,meta=meta};return true end,
    load=function(_,id) if saved and saved.account_id==id then return saved end end}
local library=Library:new(api,{itemKey=function(_,item) return item.file_md5 end},
    {account=function() return account end,store=store,now=function() return 123 end})
local loaded=assert(library:refresh())
assert(#loaded==65 and calls[2]==65,"official refresh must enumerate total, not stay fixed at 28")
assert(library.coverage=="complete" and saved.meta.verified==true)
assert(loaded[65].vol_name=="Original 65")
local current=library.items
local before=#calls
assert(library:freshItem(all[65])==all[65] and #calls==before,"fresh signed URLs must use memory index without refetching every book")
api.library=function() return {data={all[1],all[1]},total=2} end
assert(not library:refresh() and library.items==current,"duplicate IDs cannot produce a complete catalog")
api.library=function() return {data={all[1]},total=65} end
assert(not library:refresh() and library.items==current,"server caps must preserve the old complete catalog")
local request=0
api.library=function()
    request=request+1
    if request==1 then return {data={all[1]},total=2} end
    return {data={all[1],all[2]},total=3}
end
assert(not library:refresh() and library.items==current,"changing totals cannot replace a trusted catalog")
request=0
api.library=function()
    request=request+1
    if request==1 then return {data={all[1]},total=2} end
    return {data={all[2],all[3]},total=2}
end
assert(not library:refresh() and library.items==current,"a changing identity set requires a new sync, not merged guesses")
api.library=function() return {data={all[1]}} end
assert(not library:refresh(),"missing total cannot be declared complete")
api.library=function() return {data={},total=0/0} end
assert(not library:refresh(),"invalid total must be rejected")
account="99"
assert(not library:loadCache() and #library.items==0,"account switch must discard previous in-memory catalog")
account="42"
assert(library:loadCache() and #library.items==65)
assert(library.items[1].file_url==nil,"offline reconstruction cannot contain signed URLs")
api.library=function() return {data={},total=0} end
assert(library:refresh() and #library.items==0,"verified empty library is a valid complete snapshot")
local work,callback
library.runner={start=function(_,task,done) work,callback=task,done;return {cancel=function() return true end} end}
api.library=function() return {data={all[1]},total=1} end
local completed=false
assert(library:refreshAsync(function(books) assert(#books==1);completed=true end))
assert(not completed and #library.items==0,"catalog refresh must execute outside the UI caller")
assert(not library:refresh(),"synchronous refresh must not race an outstanding async snapshot")
local value=work();callback(value)
assert(completed and #library.items==1)
assert(library:refreshAsync(function() error("stale account callback must be ignored") end))
value=work();account="99";library:clear();callback(value)
assert(#library.items==0 and saved.account_id=="42","late account results must never commit or repaint")
print("library full catalog spec: OK")
