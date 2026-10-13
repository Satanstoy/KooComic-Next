package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Guard=pcall(require,"koobone.runtime_guard")
assert(loaded,"code replacement must block stale service callbacks, not just close their parent grid")
assert(Guard.ensure())
local Service=require("koobone.preprocess_service")
local service=Service:new{storage={},directory="/not-created"}
service.available=true
service.storage={resolveLocalPath=function() return "/books/original.epub" end,isSafeLocalPath=function() return true end,
    itemKey=function() return "original" end,fileSize=function() return 10 end}
service.space=function() return 128*1024*1024 end
service.is_in_use=function() return false end
local writes=0
service.files={writeJSON=function() writes=writes+1;return true end}
service.queue={jobs={},snapshot=function() return {} end}
local old_confirmation=function() return service:submitBatch({{file_md5="original"}}) end
local Settings=require("koobone.settings")
local settings=Settings:new("/settings/fixture.lua",nil,{persistence={load=function() return nil end,
    save=function() writes=writes+1;return true end}})
writes=0
Guard.block()
assert(not settings:flush() and writes==0,"stale settings controls must not overwrite restored configuration")
assert(not old_confirmation() and writes==0 and #service.requests==0,
    "a retained preprocessing confirmation must not enqueue or persist anything after code replacement")
assert(not service:resume() and not service.running)
assert(not service:submit({file_md5="original"}) and writes==0)
local Download=require("koobone.download_service")
local download=Download:new{settings={account=function() return {uin="one"} end},storage={},api={},library={},directory="/not-created"}
assert(not download:enqueue({{file_md5="one"}},"one") and not download:resume(),"stale download callbacks must also be blocked")
print("runtime code-switch guard spec: OK")
