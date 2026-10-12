-- SPDX-License-Identifier: AGPL-3.0-only
local Manager={}
Manager.__index=Manager
function Manager:new(options)
    return setmetatable({storage=assert(options.storage),downloader=options.downloader,
        coordinator=options.coordinator,schedule=options.schedule or function(delay,callback)
            require("ui/uimanager"):scheduleIn(delay,callback)
        end},self)
end
function Manager:preview(items)
    local preview={entries={},files=0,bytes=0,skipped=0,errors={}}
    local seen={}
    for _,item in ipairs(items) do
        local entry,err=self.storage:localDeleteInfo(item)
        if entry then
            if not seen[entry.path] then
                seen[entry.path]=true;preview.entries[#preview.entries+1]=entry
                preview.files=preview.files+1;preview.bytes=preview.bytes+entry.size
            end
        else preview.skipped=preview.skipped+1;preview.errors[#preview.errors+1]=tostring(err) end
    end
    return preview
end
function Manager:execute(preview,done,guard)
    if type(preview)~="table" or type(preview.entries)~="table" then return nil,"删除预览无效" end
    if self.active or (self.downloader and self.downloader:isActive()) then return nil,"下载或删除任务正在运行" end
    local token,err
    if self.coordinator then token,err=self.coordinator:acquire("local_delete");if not token then return nil,"文件资源正在使用" end end
    self.active=true
    local result={success=0,failed=0,files_removed=0,bytes=0,errors={}}
    local index,finished=1,false
    local function finish()
        if finished then return end
        finished=true
        self.active=false
        if token then self.coordinator:release(token) end
        done(result)
    end
    local function step()
        if finished then return end
        local entry=preview.entries[index]
        if not entry then finish();return end
        index=index+1
        local allowed=true
        if guard then local valid,value=pcall(guard);allowed=valid and value==true end
        if not allowed then
            result.failed=result.failed+#preview.entries-index+2
            result.errors[#result.errors+1]={key=entry.key,title=entry.title,error="账号已变化，已取消剩余删除"}
            finish();return
        end
        local called,ok,value,partial=pcall(self.storage.deleteIndexedLocal,self.storage,entry)
        if called and ok then
            result.success=result.success+1;result.files_removed=result.files_removed+(type(partial)=="table" and partial.files or 1)
            result.bytes=result.bytes+(tonumber(value) or 0)
        else
            result.failed=result.failed+1
            result.errors[#result.errors+1]={key=entry.key,title=entry.title,error=called and tostring(value) or "本地删除异常"}
            if type(partial)=="table" then
                result.bytes=result.bytes+(partial.bytes or 0);result.files_removed=result.files_removed+(partial.files or 0)
                result.lower_bound=result.lower_bound or partial.lower_bound
            end
        end
        local scheduled=pcall(self.schedule,0.01,step)
        if not scheduled then
            result.failed=result.failed+math.max(0,#preview.entries-index+1)
            result.errors[#result.errors+1]={key=entry.key,title=entry.title,error="删除调度已中断"}
            finish()
        end
    end
    local scheduled=pcall(self.schedule,0.01,step)
    if not scheduled then
        finished=true
        self.active=false;if token then self.coordinator:release(token) end
        return nil,"无法安排删除任务"
    end
    return true
end
return Manager
