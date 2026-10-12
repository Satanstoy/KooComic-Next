-- SPDX-License-Identifier: AGPL-3.0-only
local lfs=require("libs/libkoreader-lfs")
local Util=require("ffi/util")
local Sha=require("ffi/sha2")
local Json=require("json")
local Files={}
Files.__index=Files

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

function Files:read(path,limit)
    if not self:isSafe(path) or lfs.attributes(path,"mode")~="file" then return nil,"unsafe file" end
    local size=tonumber(lfs.attributes(path,"size"))
    if not size or size>(limit or 2*1024*1024) then return nil,"file too large" end
    local file,err=io.open(path,"rb")
    if not file then return nil,err end
    local data=file:read("*a");file:close()
    return data
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
