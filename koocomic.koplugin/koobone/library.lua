local Library = {}
Library.__index = Library
local Entry=require("koobone.catalog_entry")

function Library:new(api, storage, options)
    options=options or {}
    return setmetatable({
        api = assert(api, "api required"),
        storage = assert(storage, "storage required"),
        items = {},
        fetched_at = 0,
        account=options.account or function() return storage.settings and storage.settings:account().uin end,
        store=options.store,now=options.now or os.time,coverage="unknown",runner=options.runner,
    }, self)
end

local function validate(account,response)
    if type(response)~="table" or type(response.data)~="table" then return nil,"书库响应格式无效" end
    local total=tonumber(response.total)
    if not total or total~=total or total<0 or total>100000 or total~=math.floor(total) then
        return nil,"书库 total 缺失、无效或超过资源预算，无法确认完整性"
    end
    local count,seen=0,{}
    for index,item in pairs(response.data) do
        if type(index)~="number" or index<1 or index~=math.floor(index) or type(item)~="table" then
            return nil,"书库记录不是有效数组"
        end
        count=count+1
        local entry=Entry.normalize(account,item)
        if not entry or seen[entry.id] then return nil,"书库存在重复或缺少身份的记录" end
        seen[entry.id]=true
    end
    if count~=#response.data or count>total then return nil,"书库记录数与 total 不符" end
    return {total=total,ids=seen,count=count}
end

function Library:fetch(account)
    local response,err=self.api:library(28)
    if not response then return nil,err end
    local initial,check_err=validate(account,response)
    if not initial then return nil,check_err end
    if initial.count<initial.total then
        response,err=self.api:library(initial.total)
        if not response then return nil,err end
        local full,full_err=validate(account,response)
        if not full then return nil,full_err end
        if full.total~=initial.total or full.count~=full.total then return nil,"服务器未返回完整书库或同步期间目录已变化" end
        for id in pairs(initial.ids) do if not full.ids[id] then return nil,"同步期间书库身份集合已变化，请重试" end end
    end
    return response.data
end

function Library:accept(account,items)
    if tostring(self.account() or "")~=account then return nil,"账号已变化，已丢弃旧同步结果" end
    local valid,err=validate(account,{data=items,total=type(items)=="table" and #items or nil})
    if not valid then return nil,err end
    local entries={}
    for index,item in ipairs(items) do
        entries[index]=assert(Entry.normalize(account,item));entries[index].sort_rank=index
    end
    local timestamp=self.now()
    if self.store then
        local ok,err=self.store:commit(account,entries,{coverage="complete",verified=true,synced_at=timestamp})
        if not ok then return nil,err end
    end
    self.items,self.account_id,self.fetched_at,self.coverage=items,account,timestamp,"complete"
    self.urls_at=timestamp
    for _,item in ipairs(items) do item._catalog_account_id=account end
    return items,{total=#items,coverage="complete"}
end

function Library:loadCache()
    local account=tostring(self.account() or "")
    if self.account_id~=account then self:clear() end
    self.account_id=account
    if account=="" or not self.store then return nil,"没有可用账号缓存" end
    local snapshot,err=self.store:load(account)
    if not snapshot then return nil,err end
    local items={}
    for _,entry in ipairs(snapshot.entries) do
        items[#items+1]={vol_id=entry.source.vol_id,file_md5=entry.source.file_md5,vol_name=entry.title,
            vol_series=entry.series_title,vol_author=entry.author,vol_index=entry.volume_label,file_size=entry.remote_size,
            file_type=entry.file_type or "epub",count_page=entry.remote_pages,last_readpage=entry.remote_page,
            _catalog_account_id=account}
    end
    self.items,self.fetched_at,self.coverage=items,snapshot.meta.synced_at or 0,"complete"
    self.urls_at=nil
    return items
end

function Library:clear()
    if self.sync and self.sync.handle then self.sync.handle.cancel() end
    self.sync=nil
    self.items,self.account_id,self.fetched_at,self.coverage={},nil,0,"unknown"
    self.urls_at=nil
end

function Library:refreshAsync(complete)
    local account=tostring(self.account() or "")
    if account=="" then return nil,"尚未登录" end
    if (self.account_id and self.account_id~=account) or (self.sync and self.sync.account~=account) then self:clear() end
    if self.sync then return nil,"书库正在同步" end
    if not self.runner then
        local ok,runner=pcall(function() return require("koobone.async_task"):new() end)
        if not ok then return nil,"当前 KOReader 不支持独立书库同步进程" end
        self.runner=runner
    end
    local token={account=account}
    self.sync=token
    local handle,err=self.runner:start(function() return self:fetch(account) end,function(items,worker_err)
        if self.sync~=token then return end
        self.sync=nil
        if tostring(self.account() or "")~=account then return end
        if not items then complete(nil,worker_err);return end
        local ok,books,result=pcall(self.accept,self,account,items)
        if not ok then complete(nil,"无法提交完整书库快照") else complete(books,result) end
    end)
    if not handle then self.sync=nil;return nil,err end
    if self.sync==token then token.handle=handle end
    return handle
end

function Library:refresh()
    if self.sync then return nil,"书库正在同步，请等待完成" end
    local account=tostring(self.account() or "")
    if account=="" then return nil,"尚未登录" end
    local items,err=self:fetch(account)
    if not items then return nil,err end
    return self:accept(account,items)
end

function Library:freshItem(item)
    local account=tostring(self.account() or "")
    if item._catalog_account_id and item._catalog_account_id~=account then return nil,"漫画来自其他账号" end
    if self.account_id==account and self.urls_at and self.now()-self.urls_at>=0 and self.now()-self.urls_at<60 then
        local wanted=self.storage:itemKey(item)
        for _,candidate in ipairs(self.items) do
            if self.storage:itemKey(candidate)==wanted and type(candidate.file_url)=="string" and candidate.file_url~="" then return candidate end
        end
    end
    local items, err = self:refresh()
    if not items then return nil, err end
    local wanted = self.storage:itemKey(item)
    for _, candidate in ipairs(items) do
        if self.storage:itemKey(candidate) == wanted then return candidate end
    end
    return nil, "刷新书库后没有找到这本漫画"
end

return Library
