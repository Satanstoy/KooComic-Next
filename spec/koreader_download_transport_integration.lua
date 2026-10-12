-- Real HTTP transfer in an isolated child; generated input, no user session.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{}
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local Util=require("ffi/util")
local socket=require("socket")
local lfs=require("libs/libkoreader-lfs")
local Archive=require("ffi/archiver")
local Epub=require("koobone.preprocess_epub")
local Files=require("koobone.preprocess_files")
local Transport=require("koobone.download_transport")
local parent=tonumber(ffi.C.getpid())
local directory="/tmp/koocomic-http-"..parent
local files=Files:new{roots={directory}};assert(files:mkdir(directory))
assert(type(files.exclusiveWriter)=="function","native downloads need exclusive no-follow output creation")
local race_path=directory.."/race.epub.part"
assert(files:write(race_path,"keep existing"))
assert(not files:exclusiveWriter(race_path))
assert(files:read(race_path)=="keep existing")
local link_path=directory.."/link.epub.part"
assert(lfs.link(race_path,link_path,true))
assert(not files:exclusiveWriter(link_path) and files:read(race_path)=="keep existing")
assert(type(files.renameNoReplace)=="function","validated downloads require atomic no-replace commit")
local replacement=directory.."/replacement.epub"
assert(files:write(replacement,"replacement"))
assert(not files:renameNoReplace(replacement,race_path) and files:read(race_path)=="keep existing")
local committed,commit_error=files:renameNoReplace(replacement,directory.."/committed.epub")
assert(committed and not commit_error and not files:exists(replacement))
assert(type(files.copyExclusive)=="function","validation staging needs a new inode immune to old partial-file writers")
local duplicate=directory.."/private-copy.epub.part"
local copy_digest=assert(files:copyExclusive(race_path,duplicate,files:identity(race_path),1024))
assert(copy_digest==files:hash(duplicate) and files:identity(duplicate)~=files:identity(race_path))
assert(not files:copyExclusive(race_path,duplicate,files:identity(race_path),1024))
local interrupted=directory.."/interrupted-copy.epub.part"
local claimed
assert(not files:copyExclusive(race_path,interrupted,files:identity(race_path),1,function(_,identity) claimed=identity;return true end))
assert(claimed and files:identity(interrupted)==claimed,"a failed copy must retain ownership recorded before writing bytes")
local caught,copied=pcall(files.copyExclusive,files,race_path,directory.."/throw-copy.epub.part",files:identity(race_path),1024,
    function() error("ownership write failed") end)
assert(caught and not copied,"ownership callback errors must close descriptors and return failure")
local source=directory.."/source.epub"
local writer=Archive.Writer:new();assert(writer:open(source,"zip"));assert(writer:setZipCompression("store"))
assert(writer:addFileFromMemory("mimetype","application/epub+zip"))
assert(writer:addFileFromMemory("META-INF/container.xml",'<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>'))
assert(writer:addFileFromMemory("book.opf",'<package><manifest><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>'))
assert(writer:addFileFromMemory("chapter.xhtml","<html><body>Generated test</body></html>"));writer:close()
assert(files:write(directory.."/bad.html","<html>Not an EPUB</html>"))
local listener=assert(socket.bind("127.0.0.1",0));local _,port=listener:getsockname();listener:close()
local server=assert(Util.runInSubProcess(function()
    os.execute("python3 -m http.server "..port.." --bind 127.0.0.1 --directory "..directory.." >/dev/null 2>&1")
end,false,false))
local function tests()
    local ready=false
    for _=1,200 do
        local connection=socket.connect("127.0.0.1",port)
        if connection then connection:close();ready=true;break end
        ffi.C.usleep(10000)
    end
    assert(ready,"local fixture server must start")
    local scheduled,finished,result={ },false,nil
    local validator=Epub:new{validation_only=true,reader=function() return Archive.Reader:new() end}
    local base="http://127.0.0.1:"..port
    local transport=Transport:new{files=files,api=require("koobone.api"):new{account=function() return {} end},
        schedule=function(_,callback) scheduled[#scheduled+1]=callback end,
        resolve=function() assert(tonumber(ffi.C.getpid())~=parent);return {file_url=base.."/source.epub"} end,
        validate=function(path) return validator:validate(path) end}
    local path=directory.."/download.epub.part"
    local job={entry={remote_size=lfs.attributes(source,"size")}}
    local function pump()
        for _=1,400 do
            if finished then break end
            local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
            ffi.C.usleep(5000)
        end
        assert(finished,"worker must be acknowledged")
    end
    assert(transport:start(job,path,function(value) result=value;finished=true end))
    assert(not finished,"UI thread must return without waiting for transfer acknowledgement")
    pump()
    assert(result.validated and result.committed==false and files:hash(path)==files:hash(source))
    assert(not files:exists(directory.."/download.epub"),"transport must not bypass parent commit")
    transport.resolve=function() return {file_url=base.."/bad.html"} end
    finished=false
    assert(transport:start({entry={}},directory.."/bad.epub.part",function(value) result=value;finished=true end));pump()
    assert(result.error_code=="invalid_epub" and not result.validated)
    transport.resolve=function() ffi.C.usleep(2000000);return {file_url=base.."/source.epub"} end
    finished=false
    local handle=assert(transport:start({entry={}},directory.."/cancel.epub.part",function(value) result=value;finished=true end))
    assert(handle.cancel());pump()
    assert(result.error_code=="worker_failed" and not files:exists(directory.."/cancel.epub.part"))
    local Storage=require("koobone.storage")
    local records={}
    local storage=Storage:new{download=function() return {directory=directory.."/downloads",records=records} end,
        flush=function() end}
    assert(files:mkdir(directory.."/downloads"))
    local account="fixture-account"
    transport.resolve=function() return {file_url=base.."/source.epub"} end
    local worker=require("koobone.download_worker"):new{files=files,storage=storage,transport=transport,
        directory=directory.."/jobs",account=function() return account end,is_in_use=function() return false end,
        schedule=function(_,callback) scheduled[#scheduled+1]=callback end}
    local queue=require("koobone.download_queue"):new{account_id=account,
        worker=worker,coordinator=require("koobone.resource_coordinator"):new(),checkpoint=function() return true end}
    local batch={}
    for index=1,20 do batch[index]={file_md5="generated-"..index,vol_name="Generated "..index,file_size=job.entry.remote_size} end
    assert(queue:add(batch).added==20 and queue:resume())
    for _=1,4000 do
        if not queue.active then queue:tick() end
        local all=true;for _,entry in ipairs(queue.jobs) do if entry.state~="completed" then all=false end end
        if all then break end
        local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
        ffi.C.usleep(5000)
    end
    for index,entry in ipairs(queue.jobs) do
        assert(entry.state=="completed",entry.error_code)
        assert(files:hash(storage:itemPath(batch[index]))==files:hash(source))
    end
    local rename=files.renameNoReplace
    files.renameNoReplace=function(self,from,to)
        assert(self:write(to,"foreign file created during commit"))
        return rename(self,from,to)
    end
    assert(queue:add({{file_md5="conflict",vol_name="Conflict",file_size=job.entry.remote_size}}).added==1)
    for _=1,400 do
        if not queue.active then queue:tick() end
        if queue.jobs[21].state=="failed" then break end
        local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
        ffi.C.usleep(5000)
    end
    assert(queue.jobs[21].state=="failed" and files:read(directory.."/downloads/Conflict.epub")=="foreign file created during commit")
    files.renameNoReplace=rename
    files.renameNoReplace=function(self,from,to)
        if to==directory.."/downloads/Source race.epub" then assert(self:write(to..".part","late source change")) end
        return rename(self,from,to)
    end
    assert(queue:add({{file_md5="source-race",vol_name="Source race",file_size=job.entry.remote_size}}).added==1)
    for _=1,400 do
        if not queue.active then queue:tick() end
        if queue.jobs[22].state=="completed" or queue.jobs[22].state=="failed" then break end
        local callbacks=scheduled;scheduled={};for _,callback in ipairs(callbacks) do callback() end
        ffi.C.usleep(5000)
    end
    assert(queue.jobs[22].state=="completed" and files:hash(directory.."/downloads/Source race.epub")==files:hash(source),
        "changing the public partial at commit time must not publish unvalidated bytes")
    files.renameNoReplace=rename
end
local ok,err=pcall(tests)
Util.terminateSubProcess(server)
for _=1,100 do if Util.isSubProcessDone(server) then break end;ffi.C.usleep(5000) end
assert(ok,err)
print("KOReader real HTTP download integration: OK (20 serial commits and external-file race)")
