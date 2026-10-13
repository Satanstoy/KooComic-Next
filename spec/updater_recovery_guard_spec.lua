package.path="./koocomic.koplugin/?.lua;"..package.path
for _,name in ipairs({"ffi/archiver","json","libs/libkoreader-lfs","version","socket"}) do
    package.preload[name]=function() return {} end
end
local Updater=require("koobone.updater")
for _,method in ipairs({"rollbackUpdate","recoverUpdate"}) do
    package.loaded["koobone.runtime_guard"]=nil
    local Guard=require("koobone.runtime_guard")
    -- Reload the updater so each case has a fresh process-equivalent guard.
    package.loaded["koobone.updater"]=nil;Updater=require("koobone.updater")
    local current="new inode"
    local updater=Updater:new{settings={},api={},current_version="0.5.0"}
    updater.backend={paths={live="live"},identity=function() return current end,
        load=function() return {phase="installed"} end,
        validate=function() return current=="new inode" end}
    local switched=function() current="old inode";return nil,"settings restore failed" end
    updater.transaction={rollback=switched,recover=switched}
    updater.staging={cleanup=function() error("must preserve recovery artifacts") end}
    assert(not updater[method](updater))
    assert(updater.restart_required and not Guard.ensure(),
        method.." must block writes when code exchanged even though settings recovery failed")
    local requests=0
    updater.manifest_url="https://example.test/update.json";updater.release_prefix="https://example.test/releases/"
    updater.api.requestOk=function() requests=requests+1;return nil,"network error" end
    updater:check()
    assert(requests==0,"a retained automatic update timer must not contact the network after recovery")
end
print("updater failed recovery guard spec: OK")
