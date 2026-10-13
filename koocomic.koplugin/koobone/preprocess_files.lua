-- SPDX-License-Identifier: AGPL-3.0-only
local lfs=require("libs/libkoreader-lfs")
local Util=require("ffi/util")
local Sha=require("ffi/sha2")
local Json=require("json")
local Files={}
Files.__index=Files

local function openParent(path)
    local ffi=require("ffi")
    if ffi.os~="Linux" then return nil,"anchored output unavailable" end
    ffi.cdef[[int openat(int, const char *, int, ...); long syscall(long, ...);]]
    local C=ffi.C
    local directory_flag=ffi.arch=="arm" and 16384 or 65536
    local nofollow=ffi.arch=="arm" and 32768 or 131072
    local flags=C.O_RDONLY+C.O_CLOEXEC+directory_flag+nofollow
    local parent=C.open("/",flags)
    if parent<0 then return nil,"cannot anchor directory" end
    local parts={};for component in path:gmatch("[^/]+") do parts[#parts+1]=component end
    if #parts==0 then C.close(parent);return nil,"invalid file name" end
    for index=1,#parts-1 do
        local next_fd=C.openat(parent,parts[index],flags)
        C.close(parent)
        if next_fd<0 then return nil,"unsafe output ancestor" end
        parent=next_fd
    end
    return parent,parts[#parts],nofollow,ffi
end

function Files:new(options)
    return setmetatable({roots=assert(options.roots)},self)
end

function Files:isSafe(path)
    if type(path)~="string" or path:sub(1,1)~="/" or path:find("[%c]") or path:find("//",1,true) then return false end
    local allowed=false
    for _, root in ipairs(self.roots) do
        root=root:gsub("/+$","")
        if path==root or path:sub(1,#root+1)==root.."/" then allowed=true end
    end
    if not allowed then return false end
    local prefix=""
    for part in path:gmatch("[^/]+") do
        if part=="." or part==".." then return false end
        prefix=prefix.."/"..part
        if lfs.symlinkattributes(prefix,"mode")=="link" then return false end
    end
    if lfs.attributes(path,"mode")=="file" and (tonumber(lfs.attributes(path,"nlink")) or 1)>1 then return false end
    return true
end

function Files:mkdir(path)
    if not self:isSafe(path) then return nil,"unsafe directory" end
    return require("util").makePath(path)
end

function Files:mkdirExclusive(path)
    if not self:isSafe(path) then return nil,"unsafe directory reservation" end
    local parent,name,_,ffi=openParent(path)
    if not parent then return nil,name end
    ffi.cdef[[int mkdirat(int, const char *, unsigned int);]]
    local status=ffi.C.mkdirat(parent,name,ffi.cast("unsigned int",448))
    local synced=status==0 and ffi.C.fsync(parent)==0
    ffi.C.close(parent)
    if status~=0 then return nil,"directory exists or cannot be reserved" end
    return true,not synced and "directory sync failed" or nil
end

function Files:read(path,limit)
    if not self:isSafe(path) or lfs.attributes(path,"mode")~="file" then return nil,"unsafe file" end
    local size=tonumber(lfs.attributes(path,"size"))
    if not size or size>(limit or 2*1024*1024) then return nil,"file too large" end
    local file,err=io.open(path,"rb")
    if not file then return nil,err end
    local data=file:read("*a");file:close()
    return data
end

function Files:prefix(path,length)
    if type(length)~="number" or length<1 or length>4096 or length~=math.floor(length) or
            not self:isSafe(path) or lfs.attributes(path,"mode")~="file" then return nil,"unsafe prefix read" end
    local file,err=io.open(path,"rb")
    if not file then return nil,err end
    local data,read_error=file:read(length);file:close()
    return data,read_error
end

function Files:exclusiveWriter(path)
    if not self:isSafe(path) then return nil,"unsafe exclusive output" end
    local parent,name,nofollow,ffi=openParent(path)
    if not parent then return nil,name end
    local C=ffi.C
    local largefile=ffi.arch=="arm" and 131072 or 0
    local fd=C.openat(parent,name,C.O_WRONLY+C.O_CREAT+C.O_CLOEXEC+128+nofollow+largefile,ffi.cast("int",384))
    C.close(parent)
    if fd<0 then return nil,"output exists or cannot be created" end
    local owner=ffi.gc(ffi.new("int[1]",fd),function(value) if value[0]>=0 then C.close(value[0]) end end)
    return {
        identity=function()
            if owner[0]<0 then return nil end
            local stat=lfs.attributes("/proc/self/fd/"..tonumber(owner[0]))
            return stat and tostring(stat.dev)..":"..tostring(stat.ino) or nil
        end,
        write=function(_,data)
            if owner[0]<0 then return nil,"output is closed" end
            local offset=0
            while offset<#data do
                local count=tonumber(C.write(owner[0],ffi.cast("const char*",data)+offset,#data-offset))
                if count and count>0 then offset=offset+count
                elseif ffi.errno()~=C.EINTR then return nil,"exclusive output write failed" end
            end
            return true
        end,
        close=function()
            if owner[0]<0 then return nil,"output is closed" end
            local current=owner[0];owner[0]=-1
            if C.close(current)~=0 then return nil,"exclusive output close failed" end
            return true
        end,
    }
end

function Files:identity(path)
    if not self:isSafe(path) then return nil end
    local stat=lfs.attributes(path)
    if not stat or stat.mode~="file" or (stat.nlink or 1)~=1 then return nil end
    return tostring(stat.dev)..":"..tostring(stat.ino)
end


local function renameDirectories(self,source,target,exchange)
    if not self:isSafe(source) or not self:isSafe(target) or lfs.symlinkattributes(source,"mode")~="directory" or
            (exchange and lfs.symlinkattributes(target,"mode")~="directory") then return nil,"unsafe update directories" end
    local parent,name,_,ffi=openParent(source)
    if not parent then return nil,name end
    local target_parent,target_name=openParent(target)
    if not target_parent then ffi.C.close(parent);return nil,target_name end
    local number=({x64=316,arm=382,arm64=276})[ffi.arch]
    if not number then ffi.C.close(parent);ffi.C.close(target_parent);return nil,"atomic directory exchange unavailable" end
    local status=ffi.C.syscall(ffi.cast("long",number),ffi.cast("int",parent),ffi.cast("const char*",name),
        ffi.cast("int",target_parent),ffi.cast("const char*",target_name),ffi.cast("unsigned int",exchange and 2 or 1))
    local synced=status==0 and ffi.C.fsync(parent)==0 and ffi.C.fsync(target_parent)==0
    ffi.C.close(parent);ffi.C.close(target_parent)
    if status~=0 then return nil,"atomic directory operation unavailable or destination conflict" end
    return true,not synced and "directory sync failed" or nil
end
function Files:exchangeDirectories(source,target) return renameDirectories(self,source,target,true) end
function Files:moveDirectoryNoReplace(source,target) return renameDirectories(self,source,target,false) end

function Files:removeDirectorySecure(path,expected)
    if not self:isSafe(path) then return nil,"unsafe directory cleanup" end
    local parent,name,nofollow,ffi=openParent(path)
    if not parent then return nil,name end
    ffi.cdef[[int unlinkat(int, const char *, int);]]
    local C=ffi.C
    local flags=C.O_RDONLY+C.O_CLOEXEC+nofollow+(ffi.arch=="arm" and 16384 or 65536)
    local root=C.openat(parent,name,flags)
    if root<0 then C.close(parent);return nil,"cannot anchor cleanup directory" end
    local stat=lfs.attributes("/proc/self/fd/"..tonumber(root))
    local root_id=stat and tostring(stat.dev)..":"..tostring(stat.ino)
    if root_id~=expected then C.close(root);C.close(parent);return nil,"cleanup ownership changed" end
    local entries=0
    local function walk(fd,depth,remove)
        if depth>64 then return nil,"cleanup depth budget" end
        local prefix="/proc/self/fd/"..tonumber(fd)
        local iterator,object=lfs.dir(prefix)
        local function visit()
            for child in iterator,object do
                if child~="." and child~=".." then
                    entries=entries+1;if entries>10000 then return nil,"cleanup entry budget" end
                    local value=lfs.symlinkattributes(prefix.."/"..child)
                    if not value or (value.mode~="file" and value.mode~="directory") or
                            (value.mode=="file" and (value.nlink or 1)~=1) then return nil,"unsafe cleanup descendant" end
                    if value.mode=="directory" then
                        local next_fd=C.openat(fd,child,flags)
                        if next_fd<0 then return nil,"cleanup directory changed" end
                        local called,ok,err=pcall(walk,next_fd,depth+1,remove)
                        C.close(next_fd)
                        if not called or not ok then return nil,err or "cleanup traversal failed" end
                    end
                    if remove and C.unlinkat(fd,child,value.mode=="directory" and 512 or 0)~=0 then
                        return nil,"cleanup unlink failed"
                    end
                end
            end
            return true
        end
        local called,ok,err=pcall(visit)
        pcall(function() object:close() end)
        if not called then return nil,"cleanup traversal failed" end
        return ok,err
    end
    local ok,err=walk(root,0,false)
    if ok then entries=0;ok,err=walk(root,0,true) end
    C.close(root)
    if ok then
        local current=lfs.symlinkattributes(path)
        if not current or tostring(current.dev)..":"..tostring(current.ino)~=expected or C.unlinkat(parent,name,512)~=0 then
            ok,err=nil,"cleanup root changed"
        elseif C.fsync(parent)~=0 then ok,err=nil,"cleanup directory sync failed" end
    end
    C.close(parent)
    return ok,err
end
function Files:copyExclusive(source,target,expected,max_bytes,on_created)
    if not self:isSafe(source) or not self:isSafe(target) then return nil,"unsafe capture" end
    local parent,name,nofollow,ffi=openParent(source)
    if not parent then return nil,name end
    local C=ffi.C
    local source_fd=C.openat(parent,name,C.O_RDONLY+C.O_CLOEXEC+nofollow+(ffi.arch=="arm" and 131072 or 0))
    C.close(parent)
    if source_fd<0 then return nil,"cannot capture source" end
    local stat=lfs.attributes("/proc/self/fd/"..tonumber(source_fd))
    if not stat or stat.mode~="file" or (stat.nlink or 1)~=1 or tostring(stat.dev)..":"..tostring(stat.ino)~=expected then
        C.close(source_fd);return nil,"source identity changed"
    end
    local output,err=self:exclusiveWriter(target)
    if not output then C.close(source_fd);return nil,err end
    local output_identity=output:identity()
    local owned=true
    if on_created then local called,result=pcall(on_created,target,output_identity);owned=called and result end
    if not owned then
        C.close(source_fd);output:close()
        if self:identity(target)==output_identity then self:remove(target) end
        return nil,"capture ownership could not be saved"
    end
    local update=Sha.sha256()
    local buffer,bytes=ffi.new("unsigned char[65536]"),0
    local valid=true
    while true do
        local count=tonumber(C.read(source_fd,buffer,65536))
        if count==0 then break end
        if count<0 then
            if ffi.errno()~=C.EINTR then valid=false;break end
        else
            bytes=bytes+count
            if bytes>max_bytes then valid=false;break end
            local chunk=ffi.string(buffer,count);update(chunk)
            if not output:write(chunk) then valid=false;break end
        end
    end
    C.close(source_fd)
    local identity=output:identity()
    local closed=output:close()
    if not valid or not closed or bytes~=stat.size or not self:sync(target) then return nil,"capture failed" end
    return update(),bytes,identity
end

function Files:renameNoReplace(source,target)
    local directory=source:match("^(.*)/[^/]+$")
    if not self:identity(source) or not self:isSafe(target) then
        return nil,"unsafe commit paths"
    end
    local parent,name,_,ffi=openParent(source)
    if not parent then return nil,name end
    local target_parent,target_name=openParent(target)
    if not target_parent then ffi.C.close(parent);return nil,target_name end
    local number=({x64=316,arm=382,arm64=276})[ffi.arch]
    if not number then ffi.C.close(parent);ffi.C.close(target_parent);return nil,"atomic commit unavailable" end
    local status=ffi.C.syscall(ffi.cast("long",number),ffi.cast("int",parent),ffi.cast("const char*",name),
        ffi.cast("int",target_parent),ffi.cast("const char*",target_name),ffi.cast("unsigned int",1))
    local synced=status==0 and ffi.C.fsync(target_parent)==0 and ffi.C.fsync(parent)==0
    ffi.C.close(parent)
    ffi.C.close(target_parent)
    if status~=0 then return nil,"destination exists or commit unavailable" end
    if not synced then return true,"directory sync failed" end
    return true
end

function Files:write(path,data)
    if not self:isSafe(path) then return nil,"unsafe output" end
    local file,err=io.open(path,"wb")
    if not file then return nil,err end
    local ok,werr=file:write(data)
    local synced,serr=Util.fsyncOpenedFile(file,true)
    local closed,cerr=file:close()
    if not ok or not synced or not closed then return nil,werr or serr or cerr end
    return true
end

function Files:rename(source,target,already_synced)
    if not self:isSafe(source) or not self:isSafe(target) then return nil,"unsafe rename" end
    if not already_synced then
        local synced,sync_error=self:sync(source)
        if not synced then return nil,sync_error end
    end
    local ok,err=os.rename(source,target)
    if not ok then return nil,err end
    return Util.fsyncDirectory(target)
end

function Files:exists(path) return lfs.symlinkattributes(path,"mode")~=nil end

function Files:sync(path)
    if not self:isSafe(path) or lfs.attributes(path,"mode")~="file" then return nil,"unsafe sync" end
    local file,err=io.open(path,"rb")
    if not file then return nil,err end
    local ok,sync_error=Util.fsyncOpenedFile(file,true)
    file:close()
    return ok,sync_error
end

function Files:hashAsync(path,schedule,guard,callback)
    if not self:isSafe(path) then callback(nil,"unsafe hash path");return end
    local file,err=io.open(path,"rb")
    if not file then callback(nil,err);return end
    local update=Sha.sha256()
    local initial=lfs.attributes(path)
    local bytes=0
    local function step()
        if not self:isSafe(path) or (guard and not guard()) then file:close();callback(nil,"file in use or cancelled");return end
        local chunk,read_error=file:read(65536)
        if chunk then bytes=bytes+#chunk;update(chunk);schedule(0.01,step)
        else
            file:close()
            local current=lfs.attributes(path)
            if read_error or not current or not initial or bytes~=initial.size or current.ino~=initial.ino or current.size~=initial.size or
                    current.modification~=initial.modification or current.change~=initial.change then
                callback(nil,"file changed")
            else callback(update()) end
        end
    end
    schedule(0,step)
end

function Files:remove(path)
    if not self:isSafe(path) then return nil,"unsafe removal" end
    if lfs.attributes(path,"mode")==nil then return true end
    if lfs.attributes(path,"mode")~="file" then return nil,"not a file" end
    return os.remove(path)
end

function Files:writeJSON(path,value)
    local encoded,data=pcall(Json.encode,value)
    if not encoded then return nil,"JSON encoding failed" end
    local ok,err=self:write(path..".tmp",data)
    if not ok then return nil,err end
    return self:rename(path..".tmp",path)
end

function Files:readJSON(path)
    local data,err=self:read(path)
    if not data then return nil,err end
    local ok,result=pcall(Json.decode,data)
    if not ok or type(result)~="table" then return nil,"invalid JSON" end
    return result
end

function Files:hash(path)
    if not self:isSafe(path) or lfs.attributes(path,"mode")~="file" then return nil end
    local file=io.open(path,"rb")
    if not file then return nil end
    local update=Sha.sha256()
    local size,bytes=tonumber(lfs.attributes(path,"size")),0
    while true do
        local chunk,err=file:read(65536)
        if not chunk then if err then file:close();return nil end;break end
        bytes=bytes+#chunk;update(chunk)
    end
    file:close()
    if bytes~=size then return nil end
    return update()
end

function Files:copy(source,target)
    if not self:isSafe(source) or not self:isSafe(target) then return nil,"unsafe copy" end
    local input,err=io.open(source,"rb")
    if not input then return nil,err end
    local output,oerr=io.open(target,"wb")
    if not output then input:close();return nil,oerr end
    local ok=true
    local size,bytes=tonumber(lfs.attributes(source,"size")),0
    while true do
        local chunk,read_error=input:read(65536)
        if not chunk then if read_error then ok=false end;break end
        bytes=bytes+#chunk
        if not output:write(chunk) then ok=false;break end
    end
    input:close()
    local synced=Util.fsyncOpenedFile(output,true)
    local closed=output:close()
    if not ok or not synced or not closed or bytes~=size then return nil,"copy failed" end
    return Util.fsyncDirectory(target)
end

function Files:transactionFS()
    return {fingerprint=function(path) return self:hash(path) end,
        copy=function(source,target) return self:copy(source,target) end,
        rename=function(source,target) return self:rename(source,target) end,
        size=function(path) return tonumber(lfs.attributes(path,"size")) end,
        free_space=function(path) return require("util").diskUsage(Util.dirname(path)).available end}
end

return Files
