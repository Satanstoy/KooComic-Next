package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Transaction=pcall(require,"koobone.update_transaction")
assert(loaded,"updates need a persisted transaction with recoverable code and settings")
local function fixture()
    local paths={live="old",stage="new"};local journal,settings="old settings", "old settings"
    local fail={}
    local backend={exists=function(_,path) return paths[path]~=nil end,
        identity=function(_,path) return paths[path] end,
        exchange=function(_,left,right)
            if fail.exchange or not paths[left] or not paths[right] then return nil,"exchange failed" end
            paths[left],paths[right]=paths[right],paths[left];return true end,
        move=function(_,source,target)
            if fail[source..">"..target] or not paths[source] or paths[target] then return nil,"move failed" end
            paths[target],paths[source]=paths[source],nil;return true end,
        save=function(_,value) if fail.save then return nil end;journal={};for key,item in pairs(value) do journal[key]=item end;return true end,
        load=function() return type(journal)=="table" and journal or nil end,
        backupSettings=function(_,created)
            if fail.backup then return nil end;paths.config=settings
            if created and not created("config",paths.config) then paths.config=nil;return nil end
            return true end,
        restoreSettings=function() if fail.restore then return nil end;settings=paths.config;return true end,
        remove=function(_,path) paths[path]=nil;return true end,
        clear=function() journal=nil;return true end,
        validate=function(_,path,version) return paths[path]==(version=="0.4.1" and "old" or "new") end}
    return Transaction:new{backend=backend,paths={live="live",stage="stage",backup="backup",failed="failed",config="config"}},
        paths,fail,function() return journal end,function(value) settings=value end
end
local tx,paths,fail,journal,settings=fixture()
assert(tx:install("0.4.1","0.5.0",function() settings("new settings");return true end))
assert(paths.live=="new" and paths.backup=="old" and journal().phase=="installed")
assert(tx:confirm("0.5.0") and paths.backup=="old","confirmed code backup must remain available for explicit rollback")
assert(tx:rollback() and paths.live=="old" and journal().phase=="rolled_back")
tx,paths,fail=fixture();fail["stage>backup"]=true
assert(not tx:install("0.4.1","0.5.0",function() return true end) and paths.live=="old")
tx,paths,fail=fixture()
assert(not tx:install("0.4.1","0.5.0",function() error("settings persistence failed") end) and paths.live=="old")
tx,paths,fail=fixture();fail.save=true
assert(not tx:install("0.4.1","0.5.0",function() return true end) and paths.live=="old" and paths.stage=="new")
assert(paths.config==nil,"journal failure must not create an unowned settings backup")
tx,paths,fail=fixture();paths.backup="unknown"
assert(not tx:install("0.4.1","0.5.0",function() return true end) and paths.backup=="unknown","unknown backups must never be purged")
for _,point in ipairs({"before_exchange","after_exchange","after_backup","after_settings"}) do
    tx,paths,fail,journal,settings=fixture()
    local b=tx.backend
    assert(b:backupSettings())
    assert(b:save{schema_version=1,product_id="koocomic-next",phase="prepared",old_version="0.4.1",new_version="0.5.0",
        old_identity="old",new_identity="new",config_identity="old settings"})
    if point~="before_exchange" then assert(b:exchange("live","stage")) end
    if point=="after_backup" or point=="after_settings" then assert(b:move("stage","backup")) end
    if point=="after_settings" then settings("new settings") end
    local reopened=Transaction:new{backend=b,paths=tx.paths}
    assert(reopened:recover("0.5.0") and paths.live=="old" and journal().phase=="rolled_back",point)
end
tx,paths,fail,journal=fixture()
assert(tx:install("0.4.1","0.5.0",function() return true end))
assert(Transaction:new{backend=tx.backend,paths=tx.paths}:recover("0.5.0") and journal().phase=="confirmed")
paths.backup="external"
assert(not tx:rollback() and paths.live=="new","rollback must not consume a replaced backup")
tx,paths,fail,journal=fixture()
assert(tx:install("0.4.1","0.5.0",function() return true end));assert(tx:confirm("0.5.0"))
assert(type(tx.prepareNew)=="function","subsequent updates need safe retirement of owned backup artifacts")
assert(tx:prepareNew() and paths.live=="new" and not paths.backup and not paths.config)
tx,paths,fail,journal=fixture()
assert(tx:install("0.4.1","0.5.0",function() return true end));assert(tx:confirm("0.5.0"))
local remove=tx.backend.remove
tx.backend.remove=function(self,path,expected)
    if path=="backup" then paths.config="external settings" end
    if expected and paths[path]~=expected then return nil end
    return remove(self,path)
end
assert(not tx:prepareNew() and paths.config=="external settings",
    "cleanup must bind each deletion to the prior verified journal identity")
print("update transaction spec: OK")
