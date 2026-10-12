package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Worker=pcall(require,"koobone.download_worker")
assert(loaded,"parent-guarded download commit worker is missing")
local callbacks,completed,committed={ },nil,false
local account="test-account"
local entry={account_id=account,title="Original",source={file_md5="version"},remote_size=12}
local claims={}
local fs={isSafe=function() return true end,exists=function() return false end,
    mkdir=function() return true end,identity=function() return "inode" end,
    writeJSON=function(_,path,value) claims[path]=value;return true end,
    readJSON=function(_,path) return claims[path] end,
    hashAsync=function(_,_,_,guard,done) done((not guard or guard()) and string.rep("a",64) or nil) end,
    renameNoReplace=function() committed=true;return true end,remove=function() return true end}
local transport={start=function(_,_,path,done,hooks)
    assert(path=="/books/Original.epub.part");callbacks[#callbacks+1]=function(result)
        result.staged_path=hooks.stage_path;result.stage_identity="inode";done(result)
    end
    assert(hooks.on_created(path,"inode"))
    assert(hooks.on_staged(hooks.stage_path,"inode"))
    return {cancel=function() return true end}
end}
local worker=Worker:new{files=fs,transport=transport,directory="/private/jobs",hash=function() return "job-hash" end,
    account=function() return account end,storage={resolveDownloadPath=function() return "/books/Original.epub" end,
        record=function() return {} end},schedule=function() end,is_in_use=function() return false end}
local job={id="job",entry=entry}
local handle=assert(worker:start(job,{stage=function() end,progress=function() end,done=function(ok,result) completed={ok,result} end}))
assert(not committed and not completed)
callbacks[1]({validated=true,bytes=12,part_path="/books/Original.epub.part",output_fingerprint=string.rep("a",64)})
assert(committed and completed[1] and completed[2].committed,"only parent validation may mark a download committed")
committed,completed=false,nil
assert(worker:start(job,{stage=function() end,progress=function() end,done=function(ok,result) completed={ok,result} end}))
account="other"
callbacks[2]({validated=true,bytes=12,part_path="/books/Original.epub.part",output_fingerprint=string.rep("a",64)})
assert(not committed and not completed[1] and completed[2].error_code=="account_changed")
account="test-account"
for _,boundary in ipairs({"sync","journal","record"}) do
    completed=nil
    local original_write,original_record=fs.writeJSON,worker.storage.record
    fs.renameNoReplace=function() committed=true;return true,boundary=="sync" and "directory sync failed" or nil end
    fs.writeJSON=function(_,path,value)
        if boundary=="journal" and value.state=="committed" then return nil end
        claims[path]=value;return true
    end
    worker.storage.record=function() if boundary=="record" then error("record failure") end;return {} end
    assert(worker:start(job,{stage=function() end,progress=function() end,done=function(ok,result) completed={ok,result} end}))
    callbacks[#callbacks]({validated=true,bytes=12,part_path="/books/Original.epub.part",output_fingerprint=string.rep("a",64)})
    assert(completed[1] and completed[2].committed and completed[2].warning,"applied commit must not be hidden by "..boundary.." failure")
    fs.writeJSON,worker.storage.record=original_write,original_record
end
print("download worker spec: OK")
