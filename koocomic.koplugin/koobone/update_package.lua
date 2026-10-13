-- SPDX-License-Identifier: AGPL-3.0-only
local Package={}
Package.__index=Package
function Package:new(options)
    return setmetatable({reader=assert(options.reader),files=assert(options.files),
        max_bytes=options.max_bytes or 64*1024*1024,max_file_bytes=options.max_file_bytes or 16*1024*1024,
        max_entries=options.max_entries or 10000},self)
end
local function safePath(path,mode)
    if type(path)~="string" or path=="" or path:find("[%c\\]") or path:find("//",1,true) then return end
    if mode=="directory" then path=path:gsub("/$","") end
    if path~="koocomic.koplugin" and path:sub(1,18)~="koocomic.koplugin/" then return end
    if path=="koocomic.koplugin" and mode~="directory" then return end
    for part in path:gmatch("[^/]+") do if part=="." or part==".." then return end end
    local name=path:match("([^/]+)$"):lower()
    if name=="koobone.lua" or name=="koocomic.lua" or name:match("%.epub$") or name:match("%.part$") or
            name:match("%.log$") or name:match("%.original$") then return end
    return path
end
function Package:extract(archive,stage)
    local reader,files=self.reader,self.files
    if not files:isSafe(stage) or not reader:open(archive) then reader:close();return nil,"无法打开安全更新包" end
    local count,bytes,seen=0,0,{}
    local function unpack()
        for entry in reader:iterate() do
            local path=safePath(entry.path,entry.mode)
            local size=tonumber(entry.size)
            count=count+1
            if not path or seen[path] or (entry.mode~="file" and entry.mode~="directory") or entry.hardlink or entry.symlink or
                    not size or size~=size or size<0 or size~=math.floor(size) or size>self.max_file_bytes or
                    count>self.max_entries or bytes+size>self.max_bytes or (entry.mode=="directory" and size~=0) then
                return nil,"更新包包含不安全条目或超出解压预算"
            end
            seen[path]=true;bytes=bytes+size
            local target=stage.."/"..path
            if not files:isSafe(target) then return nil,"更新包目标路径不安全" end
            if entry.mode=="directory" then
                if not files:mkdir(target) then return nil,"无法创建更新目录" end
            else
                local data=reader:extractToMemory(entry.path)
                if type(data)~="string" or #data~=size or reader.err or (reader.verifyEnd and not reader:verifyEnd()) then
                    return nil,"更新资源损坏或截断"
                end
                if not files:mkdir(target:match("^(.*)/[^/]+$")) then return nil,"无法创建更新目录" end
                local writer=files:exclusiveWriter(target)
                if not writer then return nil,"更新资源已存在或不能创建" end
                local wrote,written=pcall(writer.write,writer,data)
                local closed,close_ok=pcall(writer.close,writer)
                if not wrote or not written or not closed or not close_ok or not files:sync(target) then
                    return nil,"更新资源写入或同步失败"
                end
            end
        end
        if reader.err or count==0 then return nil,"更新包为空或读取失败" end
        return true
    end
    local called,ok,err=pcall(unpack)
    reader:close()
    if not called then return nil,"无法安全解压更新包" end
    return ok,err
end
return Package
