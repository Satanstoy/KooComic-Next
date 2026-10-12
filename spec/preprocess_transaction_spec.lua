package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, Transaction = pcall(require, "koobone.preprocess_transaction")
assert(available, "safe preprocessing file transactions are not implemented")
local files = { ["/books/book.epub"] = "original", ["/books/book.optimizing"] = "optimized" }
local fail_copy, fail_rename, opened, valid, logs = false, false, false, true, {}
local fs = {
    fingerprint = function(path) return files[path] end,
    copy = function(source, target)
        if fail_copy then return nil end
        files[target] = files[source]; return true
    end,
    rename = function(source, target)
        if fail_rename then return nil end
        files[target], files[source] = files[source], nil; return true
    end,
    size = function() return 10 end,
    free_space = function() return 1000 end,
}
local transaction = Transaction:new{
    fs = fs, is_safe = function(path) return path:match("^/books/") ~= nil or path:match("^/internal/") ~= nil end,
    is_in_use = function() return opened end,
    validate = function() return valid end,
    journal = function(record) logs[#logs + 1] = record; return true end,
}
local request = { source_path = "/books/book.epub", temporary_path = "/books/book.optimizing",
    backup_path = "/internal/original.backup", source_fingerprint = "original",
    output_fingerprint = "optimized" }
fail_copy = true
assert(transaction:commit(request) == nil)
assert(files[request.source_path] == "original", "failed backup must never replace the reading file")
assert(#logs>0 and logs[#logs].state=="backing_up", "backup ownership must be journaled before copying bytes")
fail_copy, valid = false, false
assert(transaction:commit(request) == nil)
assert(files[request.source_path] == "original", "failed EPUB validation must preserve the original")
valid, opened = true, true
assert(transaction:commit(request) == nil)
opened = false
files[request.source_path] = "changed"
assert(transaction:commit(request) == nil, "changed sources must not be overwritten")
files[request.source_path] = "original"
fail_rename = true
assert(transaction:commit(request) == nil)
assert(files[request.source_path] == "original")
fail_rename = false
assert(transaction:commit(request))
assert(files[request.source_path] == "optimized" and files[request.backup_path] == "original")
assert(logs[#logs].state == "committed")
assert(transaction:restore(request))
assert(files[request.source_path] == "original", "restoration must preserve the original content")
assert(transaction:restore(request), "restoration must be idempotent")
files[request.temporary_path] = "optimized"
local original_journal = transaction.journal
transaction.journal = function(record)
    if record.state == "prepared" then files[request.temporary_path] = "corrupted" end
    return true
end
assert(transaction:commit(request) == nil, "changed temporary output must not replace the original")
assert(files[request.source_path] == "original")
files[request.source_path] = "optimized"
transaction.journal = function(record)
    if record.state == "restoring" then files[request.temporary_path] = "corrupted" end
    return true
end
assert(transaction:restore(request) == nil, "changed restore temporary file must not replace the reading file")
assert(files[request.source_path] == "optimized")
transaction.journal = original_journal
files[request.source_path],files[request.temporary_path],files[request.backup_path]="original","optimized",nil
request.discard_original=true
fail_copy=true
assert(transaction:commit(request),"direct replacement must not require an original-copy backup")
assert(files[request.source_path]=="optimized" and not files[request.backup_path],
    "successful direct replacement must leave no original backup")
assert(logs[#logs].discard_original==true,"recovery journal must record direct-replacement policy")
for _,boundary in ipairs({"validation","reading","rename","prepared_journal"}) do
    files[request.source_path],files[request.temporary_path]="original","optimized"
    valid=boundary~="validation";opened=boundary=="reading";fail_rename=boundary=="rename"
    transaction.journal=function(record) return not (boundary=="prepared_journal" and record.state=="prepared") end
    assert(not transaction:commit(request) and files[request.source_path]=="original" and not files[request.backup_path],
        "direct replacement must preserve original on "..boundary.." failure")
end
valid,opened,fail_rename=true,false,false
transaction.journal=function(record) return record.state~="committed" end
assert(not transaction:commit(request) and files[request.source_path]=="optimized" and not files[request.backup_path],
    "a post-rename journal failure must retain the validated readable output for recovery")
print("preprocess transaction spec: OK")
