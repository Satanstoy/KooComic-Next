-- Simulates a filesystem that rejects renameat2 flags (vfat/exfat userstore)
-- by injecting a renameat2 shim that returns EINVAL, while everything else
-- uses the real KOReader runtime and the real local filesystem.
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local Files=require("koobone.preprocess_files")
local directory="/tmp/koocomic-atomic-fallback-"..tonumber(ffi.C.getpid())
local EINVAL=22
local function fallbackFiles()
    -- Every renameat2 call reports an unsupported flag, exactly like vfat.
    return Files:new{roots={directory},rename_at2=function() return nil,EINVAL end}
end

local real=Files:new{roots={directory}};assert(real:mkdir(directory))

-- Baseline: the native atomic primitive still works on a capable filesystem.
assert(real:write(directory.."/native-source","payload"))
local committed,commit_warning=real:renameNoReplace(directory.."/native-source",directory.."/native-target")
assert(committed and not commit_warning,"capable filesystems must keep the atomic no-replace commit")
assert(real:read(directory.."/native-target")=="payload")

-- Fallback: downloads, settings backups and update staging must still commit.
local files=fallbackFiles()
assert(files:write(directory.."/staged","verified download"))
local fallback_committed,warning=files:renameNoReplace(directory.."/staged",directory.."/final.epub")
assert(fallback_committed,"no-replace commit must degrade instead of failing on a vfat userstore")
assert(type(warning)=="string" and warning:find("degraded",1,true),
    "a degraded commit must report a durability warning, not pretend to be atomic")
assert(files:read(directory.."/final.epub")=="verified download" and not files:exists(directory.."/staged"))

-- Conflict safety must survive the fallback: an existing destination is never overwritten.
assert(files:write(directory.."/replacement","replacement"))
assert(files:write(directory.."/occupied","keep existing"))
assert(not files:renameNoReplace(directory.."/replacement",directory.."/occupied"),
    "the degraded commit must still refuse an existing destination")
assert(files:read(directory.."/occupied")=="keep existing" and files:exists(directory.."/replacement"))

-- Directory move (update backup relocation) must degrade too.
assert(files:mkdir(directory.."/live"));assert(files:write(directory.."/live/main.lua","return {}"))
local moved=files:moveDirectoryNoReplace(directory.."/live",directory.."/live.next-backup")
assert(moved and not files:exists(directory.."/live") and files:read(directory.."/live.next-backup/main.lua")=="return {}")
assert(files:mkdir(directory.."/second"));assert(files:write(directory.."/second/main.lua","second"))
assert(not files:moveDirectoryNoReplace(directory.."/second",directory.."/live.next-backup"),
    "directory move must still refuse an existing destination")
assert(files:read(directory.."/second/main.lua")=="second")

-- Directory exchange (in-app update) must degrade to a consistent swap.
assert(files:mkdir(directory.."/stage"));assert(files:write(directory.."/stage/main.lua","new"))
assert(files:mkdir(directory.."/current"));assert(files:write(directory.."/current/main.lua","old"))
assert(files:exchangeDirectories(directory.."/current",directory.."/stage"),
    "directory exchange must degrade for in-app updates")
assert(files:read(directory.."/current/main.lua")=="new" and files:read(directory.."/stage/main.lua")=="old",
    "the degraded exchange must swap both directories without losing either side")
assert(not files:exists(directory.."/stage.kooc-exchange"),"the exchange temporary must not survive")

print("KOReader atomic renameat2 fallback (vfat userstore): OK")
