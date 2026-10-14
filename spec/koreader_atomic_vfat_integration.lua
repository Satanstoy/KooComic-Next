-- Runs the atomic commit paths on a real (loop-mounted) FAT-family filesystem,
-- so "desktop ext4 all green, device fat all red" regressions surface in CI.
-- It runs twice: once with the native renameat2 syscall and once with an
-- injected EINVAL shim that forces the vfat degrade path.
-- usage: luajit koreader_atomic_vfat_integration.lua <repo-root> <mount-dir>
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local mount=assert(arg[2],"a mounted filesystem directory is required")
local ffi=require("ffi")
local Files=require("koobone.preprocess_files")
local Store=require("koobone.settings_store")
local EINVAL=22

local function exercise(files,directory,label)
    assert(files:mkdir(directory))

    -- Download final commit (the "all downloads fail at the last stage" defect).
    assert(files:write(directory.."/verified.epub.part","verified"))
    local committed,warning=files:renameNoReplace(directory.."/verified.epub.part",directory.."/final.epub")
    assert(committed,"download commit must succeed on FAT ("..label..")")
    assert(files:read(directory.."/final.epub")=="verified" and not files:exists(directory.."/verified.epub.part"))
    assert(files:write(directory.."/occupied","keep"));assert(files:write(directory.."/again","new"))
    assert(not files:renameNoReplace(directory.."/again",directory.."/occupied"),
        "an existing download must never be overwritten ("..label..")")
    assert(files:read(directory.."/occupied")=="keep")

    -- Settings migration backup (the "plugin disappears after upgrade" defect).
    local store=Store:new{path=directory.."/koocomic.lua",legacy_path=directory.."/koobone.lua",files=files,pid=1}
    assert(files:write(directory.."/koobone.lua","return {data={schema_version=3,account={email='x'}}}\n"))
    assert(store:save(directory.."/koocomic.lua",{data={schema_version=4,account={email="x"}}},directory.."/koobone.lua"),
        "settings migration must commit its metadata backup on FAT ("..label..")")
    assert(store:load(directory.."/koocomic.lua").data.schema_version==4)
    assert(files:exists(directory.."/koocomic.lua.pre-v4"),"the pre-v4 settings backup must exist ("..label..")")

    -- Update directory exchange (the "in-app update cannot finish" defect).
    assert(files:mkdir(directory.."/live"));assert(files:write(directory.."/live/main.lua","old"))
    assert(files:mkdir(directory.."/stage"));assert(files:write(directory.."/stage/main.lua","new"))
    assert(files:exchangeDirectories(directory.."/live",directory.."/stage"),"plugin directory exchange must work ("..label..")")
    assert(files:read(directory.."/live/main.lua")=="new" and files:read(directory.."/stage/main.lua")=="old")
    assert(files:moveDirectoryNoReplace(directory.."/stage",directory.."/stage.next-backup"),"update backup relocation must work ("..label..")")

    -- statx is optional: a missing high-resolution stamp is a documented degrade.
    local stamp=files:stamp(directory.."/final.epub")
    assert(stamp==nil or type(stamp)=="string","statx must return either a stamp or the documented unavailability")

    return warning
end

local base=mount.."/koocomic-atomic-vfat-"..tonumber(ffi.C.getpid())
local native=Files:new{roots={base.."-native"}}
local native_warning=exercise(native,base.."-native","native renameat2")

local forced=Files:new{roots={base.."-forced"},rename_at2=function() return nil,EINVAL end}
local forced_warning=exercise(forced,base.."-forced","forced vfat degrade")
assert(type(forced_warning)=="string" and forced_warning:find("degraded",1,true),
    "the forced FAT pass must actually take the documented degrade path")

print("KOReader vfat atomic filesystem integration: OK (native="..tostring(native_warning or "atomic")..
    ", forced="..tostring(forced_warning)..")")
