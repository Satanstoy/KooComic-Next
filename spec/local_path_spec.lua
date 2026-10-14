package.path = "./koocomic.koplugin/?.lua;" .. package.path
local files = { ["/books/KOOBONE/Old name.epub"] = { mode = "file", size = 123 } }
package.preload["socket"] = function() return {} end
package.preload["datastorage"] = function() return {} end
package.preload["ffi/util"] = function()
    return { joinPath = function(a, b) return a .. "/" .. b end }
end
package.preload["libs/libkoreader-lfs"] = function()
    local function attributes(path, field)
        if path == "/books/KOOBONE" then return "directory" end
        local file = files[path]
        return file and file[field]
    end
    return { attributes = attributes, symlinkattributes = attributes }
end

local Storage = require("koobone.storage")
local download = { directory = "/books/KOOBONE", records = {
    hash = { title = "Old name", path = "/books/KOOBONE/Old name.epub", state = "complete" },
} }
local settings = { download = function() return download end, flush = function() end }
local storage = Storage:new(settings)
local item = { file_md5 = "hash", vol_name = "New cloud title", file_type = "epub" }
assert(type(storage.resolveLocalPath) == "function", "local path resolution is not implemented")
local path, state = storage:resolveLocalPath(item)
assert(path == "/books/KOOBONE/Old name.epub" and state == "downloaded",
    "recorded paths must take precedence over reconstructed names")
assert(storage:isDownloaded(item), "renamed remote books must remain downloaded")

files["/books/KOOBONE/New cloud title.epub"] = { mode = "file", size = 9 }
local other = { file_md5 = "other", vol_name = "Old name", file_type = "epub" }
path, state = storage:resolveLocalPath(other)
assert(path == nil and state == "conflict", "same-name files owned by another record must not be claimed")

local record = download.records.hash
record.path = "/books/KOOBONE/../private.epub"
files[record.path] = { mode = "file" }
path, state = storage:resolveLocalPath(item)
assert(path == nil and state == "invalid_path", "parent traversal must be rejected")
record.path = "/books/KOOBONE-other/escape.epub"
files[record.path] = { mode = "file" }
assert(storage:resolveLocalPath(item) == nil, "prefix matches must not escape the root")
record.path = "/books/KOOBONE/link/book.epub"
files["/books/KOOBONE/link"] = { mode = "link" }
files[record.path] = { mode = "file" }
path, state = storage:resolveLocalPath(item)
assert(path == nil and state == "invalid_path", "symlink directories must be rejected")
record.path = "/books/KOOBONE/Old name.epub"
files[record.path] = nil
path, state = storage:resolveLocalPath(item)
assert(path == nil and state == "missing", "missing record paths must not fall back to unrelated files")
storage:record(item, "preparing")
assert(download.records.hash.path == "/books/KOOBONE/Old name.epub",
    "retrying an existing record must retain its historical path")
assert(type(storage.resolveDownloadPath) == "function", "safe download path resolution is missing")
assert(storage:resolveDownloadPath(item) == "/books/KOOBONE/Old name.epub")
download.records.other = { path = "/books/KOOBONE/New cloud title.epub" }
download.records.hash = nil
path, state = storage:resolveDownloadPath(item)
assert(path == nil and state == "conflict", "downloads must not overwrite another record")
download.records.other = nil
files["/books/KOOBONE/New cloud title.epub.part"] = { mode = "link" }
path, state = storage:resolveDownloadPath(item)
assert(path == nil and state == "invalid_path", "partial symlinks must not be opened for writing")
files["/books/KOOBONE/New cloud title.epub.part"] = nil
download.records.other = { path = "/books/KOOBONE/New cloud title.epub.part" }
path, state = storage:resolveDownloadPath(item)
assert(path == nil and state == "conflict", "partial paths must not overwrite another indexed file")
print("local path spec: OK")
