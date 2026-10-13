require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi");require("ffi/posix_h")
ffi.cdef[[int chmod(const char *, unsigned int); int setuid(unsigned int); unsigned int geteuid(void);]]
local lfs=require("libs/libkoreader-lfs")
local directory="/tmp/koocomic-file-fault-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
local source,output=directory.."/original.epub",directory.."/output.part"
assert(files:write(source,"original sentinel"));assert(files:write(output,"validated output sentinel"))
assert(files:mkdir(source..".sdr"));assert(files:write(source..".sdr/metadata.lua","sidecar sentinel"))
local original=assert(files:hash(source))
assert(ffi.C.chmod(directory,365)==0) -- 0555: read/search only, including for a dropped-privilege child.
local pid=ffi.C.fork();assert(pid>=0)
if pid==0 then
    if ffi.C.geteuid()==0 and ffi.C.setuid(65534)~=0 then ffi.C._exit(2) end
    local writer=files:exclusiveWriter(directory.."/denied.part")
    if writer then writer:close() end
    local renamed=files:rename(output,source,true)
    ffi.C._exit(not writer and not renamed and 0 or 1)
end
local status=ffi.new("int[1]");assert(ffi.C.waitpid(pid,status,0)==pid)
assert(status[0]==0,"actual EACCES must prevent creation and source replacement")
assert(ffi.C.chmod(directory,448)==0)
assert(files:hash(source)==original and files:read(source..".sdr/metadata.lua")=="sidecar sentinel")
local service=require("koobone.preprocess_service"):new{directory=directory.."/processing",
    native_library=root.."/native/preprocess/build/moire-host.so",space=function() return 0 end,is_in_use=function() return false end,
    storage={downloadDir=function() return directory end,isSafeLocalPath=function(_,path) return files:isSafe(path) end,
        resolveLocalPath=function() return source end,itemKey=function() return "generated" end}}
assert(service.available and not service:submit({}) and #service.requests==0 and files:hash(source)==original,
    "zero-space preflight must preserve source and avoid scheduling a codec")
assert(not service.worker:start({id="space-drop",source_path=source,source_fingerprint=original,profile={discard_original=true}},{}),
    "worker execution must recheck space even after an earlier confirmation")
local called,enough=pcall(service.worker.hasSpace,service.worker,directory.."/deleted-after-preview.epub")
assert(called and not enough,"a file deleted after preview must return a safe failure instead of throwing")
local function descriptors()
    local count=0;for name in lfs.dir("/proc/self/fd") do if name~="." and name~=".." then count=count+1 end end;return count
end
local before=descriptors()
for _=1,100 do assert(files:read(source));assert(files:hash(source));assert(files:sync(source)) end
assert(descriptors()==before,"repeated file failure/read/hash/sync paths must release descriptors")
local util=require("ffi/util");local sync=util.fsyncDirectory
util.fsyncDirectory=function() return nil,"injected directory sync failure" end
local saved=files:writeJSON(directory.."/checkpoint.json",{state="prepared"})
util.fsyncDirectory=sync
assert(not saved and files:readJSON(directory.."/checkpoint.json").state=="prepared",
    "applied nondurable metadata must remain recoverable but must not authorize further destructive work")
print("KOReader actual permission/zero-space/file-resource faults: OK")
