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
end
local ok,err=pcall(tests)
Util.terminateSubProcess(server)
for _=1,100 do if Util.isSubProcessDone(server) then break end;ffi.C.usleep(5000) end
assert(ok,err)
print("KOReader real HTTP download transport integration: OK (parent commit not connected)")
