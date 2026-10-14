package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Store=pcall(require,"koobone.settings_store")
assert(loaded,"atomic settings metadata store is missing")
local contents={["/settings/old.lua"]="return {data={schema_version=3}}"}
local fail_write,fail_rename,fail_sync,fail_copy=false,false,false,false
local fs={exists=function(_,path) return contents[path]~=nil end,
    isSafe=function() return true end,read=function(_,path) return contents[path] end,
    mkdir=function() return true end,identity=function(_,path) return path end,
    sync=function() return not fail_sync end,
    hash=function(_,path) return contents[path] end,
    copyExclusive=function(_,from,to,_,_,created)
        if contents[to] then return nil end
        contents[to]=fail_copy and "partial" or contents[from]
        if created then created(to,to) end
        return not fail_copy and contents[to] or nil
    end,
    renameNoReplace=function(_,from,to)
        if contents[to] then return nil end
        contents[to]=contents[from];contents[from]=nil;return true
    end,
    exclusiveWriter=function(_,path)
        if contents[path] then return nil end
        contents[path]=""
        return {write=function(_,data) if fail_write then return nil end;contents[path]=data;return true end,
            close=function() return true end}
    end,
    remove=function(_,path) contents[path]=nil;return true end}
local store=Store:new{path="/settings/new.lua",legacy_path="/settings/old.lua",files=fs,
    serialize=function(value) return "return {data={schema_version="..value.data.schema_version.."}}" end,
    rename=function(from,to) if fail_rename then return nil end;contents[to]=contents[from];contents[from]=nil;return true end,
    sync_directory=function() return true end,pid=1}
assert(store:load("/settings/old.lua").data.schema_version==3)
assert(store:save("/settings/new.lua",{data={schema_version=4}},"/settings/old.lua"))
assert(contents["/settings/new.lua.pre-v4"]==contents["/settings/old.lua"] and store:load("/settings/new.lua").data.schema_version==4)
local prior=contents["/settings/new.lua"]
fail_write=true;assert(not store:save("/settings/new.lua",{data={schema_version=9}}));assert(contents["/settings/new.lua"]==prior)
fail_write=false;fail_rename=true
assert(not store:save("/settings/new.lua",{data={schema_version=9}}));assert(contents["/settings/new.lua"]==prior)
fail_rename=false;fail_sync=true
assert(not store:save("/settings/new.lua",{data={schema_version=9}}) and contents["/settings/new.lua"]==prior,
    "temporary settings must be file-synced before replacing the original")
contents["/settings/bad.lua"]="not a Lua table"
local data,err=store:load("/settings/bad.lua");assert(not data and err and contents["/settings/bad.lua"])
contents["/settings/code.lua"]="return os.remove('/private/file')"
data,err=store:load("/settings/code.lua");assert(not data and err,"settings parsing cannot execute global APIs")
fail_sync=false;fail_copy=true
assert(not store:save("/settings/retry.lua",{data={schema_version=4}},"/settings/old.lua"))
assert(not contents["/settings/retry.lua.pre-v4"],"failed backup must not reserve a corrupt permanent backup name")
fail_copy=false
assert(store:save("/settings/retry.lua",{data={schema_version=4}},"/settings/old.lua"),
    "migration must be retryable after a failed backup write")
contents["/settings/orphan.lua.next-1-1.tmp"]="preserve unknown orphan"
contents["/settings/orphan.lua.next-1-2.tmp.backup"]="preserve unknown backup"
store.sequence=0
assert(store:save("/settings/orphan.lua",{data={schema_version=4}}) and
    contents["/settings/orphan.lua.next-1-1.tmp"]=="preserve unknown orphan" and
    contents["/settings/orphan.lua.next-1-2.tmp.backup"]=="preserve unknown backup",
    "reused PID must skip unknown orphan names without deleting them")
print("settings store spec: OK")
