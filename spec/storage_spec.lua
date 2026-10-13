package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

local files = {}

package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
end
package.preload["datastorage"] = function()
    return {
        getFullDataDir = function() return "/tmp/koreader" end,
        getDataDir = function() return "/tmp/koreader" end,
    }
end
package.preload["ffi/util"] = function()
    return {
        dirname = function() return "/tmp" end,
        joinPath = function(left, right) return left .. "/" .. right end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, attribute)
            if path == "/tmp/KOOBONE" and attribute == "mode" then return "directory" end
            local file = files[path]
            if file and attribute == "mode" then return "file" end
            if file and attribute == "size" then return file.size end
            return nil, "file does not exist"
        end,
        mkdir = function() return true end,
        symlinkattributes=function(path,attribute)
            if files[path] and attribute=="mode" then return "file" end
            if path=="/tmp/KOOBONE" and attribute=="mode" then return "directory" end
        end,
    }
end

G_reader_settings = {
    readSetting = function() return "/tmp" end,
}

local Storage = require("koobone.storage")
local download = { directory = "/tmp/KOOBONE", records = {} }
local flush_count = 0
local settings = {
    download = function() return download end,
    flush = function() flush_count = flush_count + 1 end,
}
local storage = Storage:new(settings)
local item = { vol_name = "Test book", file_type = "epub" }
local final_path = "/tmp/KOOBONE/Test book.epub"
local part_path = final_path .. ".part"

local original_remove = os.remove
os.remove = function(path)
    if not files[path] then return nil, "file does not exist" end
    files[path] = nil
    return true
end

-- A missing .part file returns nil plus an lfs error string on KOReader.
-- This must be treated as zero bytes, not passed to tonumber as its base.
assert(storage:partSize(item) == 0)

files[part_path] = { size = 12345 }
assert(storage:partSize(item) == 12345)

-- Download records report the actual filesystem state, not stale byte counts.
files[final_path] = { size = 20000 }
files["/tmp/KOOBONE/Unrelated.epub"] = { size = 777 }
storage:record(item, "complete", { bytes = 99999 })
local key = storage:itemKey(item)
local row = { key = key, value = download.records[key] }
local info = storage:recordInfo(row)
assert(info.state == "complete")
assert(info.exists == true)
assert(info.size == 20000)
assert(info.part_exists == true)

-- Deleting a downloaded item removes only its exact EPUB, matching .part,
-- and persisted record, and reports the real number of released bytes.
local ok, removed = storage:deleteItem(item)
assert(ok == true)
assert(removed == 32345)
assert(files[final_path] == nil)
assert(files[part_path] == nil)
assert(files["/tmp/KOOBONE/Unrelated.epub"].size == 777)
assert(download.records[key] == nil)

-- If a user deletes the EPUB through a computer or file manager, the stale
-- completed record is exposed as missing and can be cleaned without deleting
-- any other file.
storage:record(item, "complete", { bytes = 20000 })
row = { key = key, value = download.records[key] }
info = storage:recordInfo(row)
assert(info.state == "missing")
local summary = storage:maintenanceSummary()
assert(summary.missing_records == 1)
assert(summary.partial_files == 0)
assert(storage:cleanupMissingRecords() == 1)
assert(download.records[key] == nil)

-- Failed partial downloads are counted by their actual size and bulk cleanup
-- removes the .part plus its now-empty history record.
storage:record(item, "failed", {
    bytes = 4096,
    part_path = part_path,
    error = "timeout",
})
files[part_path] = { size = 4096 }
summary = storage:maintenanceSummary()
assert(summary.missing_records == 0)
assert(summary.partial_files == 1)
assert(summary.partial_bytes == 4096)
local cleanup = storage:cleanupPartialFiles()
assert(cleanup.files == 1)
assert(cleanup.bytes == 4096)
assert(#cleanup.errors == 0)
assert(files[part_path] == nil)
assert(download.records[key] == nil)
assert(flush_count >= 4)
files[final_path]={size=20000}
storage:record(item,"complete")
storage.preprocess={isLocked=function() return true end}
assert(storage:deleteItem(item)==nil and files[final_path],"processing must lock deletion of the reading file")
local cleaned=false
storage.preprocess={isLocked=function() return false end,cleanup=function(_,path)
    assert(path==final_path);cleaned=true;return true,500 end}
local deleted,bytes=storage:deleteItem(item)
assert(deleted and cleaned and bytes==20500,"confirmed deletion must also clean and count preprocessing artifacts")
files[final_path]={size=20000};files[part_path]={size=123}
storage:record(item,"complete",{part_path=part_path})
assert(type(storage.deleteIndexedLocal)=="function","indexed-only local deletion is missing")
local plan=assert(storage:localDeleteInfo(item))
files[final_path].size=20001
assert(not storage:deleteIndexedLocal(plan) and files[final_path],"changed files must not be deleted from stale previews")
plan=assert(storage:localDeleteInfo(item))
storage.is_in_use=function(path) return path==final_path end
assert(not storage:deleteIndexedLocal(plan) and files[final_path],"open reader must block local deletion")
storage.is_in_use=function() return false end
assert(storage:deleteIndexedLocal(plan) and files[part_path] and download.records[key],"batch deletion must preserve partial files and their index")
files[final_path]={size=44}
plan=assert(storage:localDeleteInfo(item))
storage.preprocess.cleanup=function() return nil,"backup permission denied" end
local failed,err,partial=storage:deleteIndexedLocal(plan)
assert(not failed and partial and partial.files==1 and partial.bytes==44 and partial.lower_bound,
    "a backup cleanup failure must still report already removed reading-file bytes")
files[final_path]={size=45}
plan=assert(storage:localDeleteInfo(item))
storage.preprocess.cleanup=function() error("cleanup exception") end
local caught
caught,failed,err,partial=pcall(storage.deleteIndexedLocal,storage,plan)
assert(caught and not failed and partial and partial.files==1 and partial.bytes==45,
    "cleanup exceptions must preserve actual removed-file metrics")
files[final_path]={size=46}
plan=assert(storage:localDeleteInfo(item))
storage.preprocess.cleanup=function() return true,0 end
local old_flush=storage.settings.flush
storage.settings.flush=function() error("flush exception") end
caught,failed,err,partial=pcall(storage.deleteIndexedLocal,storage,plan)
assert(caught and not failed and partial and partial.files==1 and partial.bytes==46,
    "persistence exceptions must preserve actual removed-file metrics")
storage.settings.flush=old_flush
files["/outside.epub"]={size=99}
download.records.bad={path="/outside.epub"}
assert(not storage:deleteRecordFiles("bad") and files["/outside.epub"],"all deletion entrypoints must reject outside-root records")

files[final_path]={size=47}
local guard=require("koobone.runtime_guard");guard.block()
assert(not storage:deleteItem(item) and files[final_path],"old deletion confirmations must preserve files after a code switch")
local prior_flushes=flush_count
assert(not storage:record(item,"complete") and flush_count==prior_flushes,"code replacement must block stale local record writes")
os.remove = original_remove

print("storage spec: OK")
