-- SPDX-License-Identifier: AGPL-3.0-only
local Bookshelf=require("koobone.ui.bookshelf")
local Dialog=require("ui/widget/buttondialog")
local Confirm=require("ui/widget/confirmbox")
local Info=require("ui/widget/infomessage")
local UI=require("ui/uimanager")
local Util=require("koobone.util")
local Status=require("koobone.preprocess_status")
local Manager={}
Manager.__index=Manager
local labels={unprocessed="未处理",optimized="已处理",failed="失败",queued="已排队",processing="处理中",missing="缺失",checking="核对中",check_failed="核对失败"}
function Manager:new(options)
    local self=setmetatable({storage=assert(options.storage),service=assert(options.service),settings=assert(options.settings),
        source_library=options.library,filter="all",options=options},Manager)
    local local_settings={account=function() return {uin="local",nick="本地漫画"} end,ui=function() return self.settings:ui() end}
    local local_storage={isDownloaded=function(_,item) return self:state(item)=="optimized" end,partSize=function() return 0 end}
    local covers=options.cover_cache and {localPath=function(_,item) return options.cover_cache:localPath(item) end,url=function() return nil end}
    self.shelf=Bookshelf:new{settings=local_settings,storage=local_storage,library={items={}},cover_cache=covers,
        downloader={enqueue=function(_,items) self:confirm(items) end},
        on_downloads=function() if options.on_queue then options.on_queue() end end,
        on_book_select=function(item) self:confirm({item}) end,
        decorate_grid=function(grid)
            grid.tabs={{id="series",label="系列"},{id="volumes",label="单卷"},{id="downloaded",label="已处理"}}
            grid.status_for=function(item) return labels[self:state(item)] end
            grid.selection_action_icon="preprocess";grid.selection_delete_enabled=false
            grid.queue_icon="processing_queue";grid.series_count_prefix="✓"
            grid.path_label="去彩纹管理"..(grid.path_label~="" and " / "..grid.path_label or "")
            return grid
        end}
    local visible=self.shelf._visibleBooks
    self.shelf._visibleBooks=function(shelf)
        self:_refreshStates()
        local result={}
        for _,item in ipairs(visible(shelf)) do
            local state=self:state(item)
            if state~="missing" and (self.filter=="all" or state==self.filter) then result[#result+1]=item end
        end
        return result
    end
    self.shelf.showFilter=function() self:showFilter() end
    self.shelf.showMore=function() self:showActions() end
    self.shelf.showSeriesActions=function(_,series) self:confirm(series.books) end
    self.shelf.showSelectionActions=function() self:confirm(self.shelf.selection:resolve(self.shelf.library.items)) end
    self.shelf._items=function(_,books)
        local rows={{text="处理队列",callback=options.on_queue},{text="状态筛选",callback=function() self:showFilter() end}}
        for _,item in ipairs(books) do local value=item
            rows[#rows+1]={text=value.vol_name,mandatory=labels[self:state(value)],callback=function() self:confirm({value}) end}
        end
        return rows
    end
    return self
end

function Manager:state(item)
    local path=self.storage:resolveLocalPath(item)
    if not path then return "missing" end
    if self.service:isLocked(path) then return "processing" end
    local state=self.states and self.states[path] or "unprocessed"
    if state=="optimized" then
        if not self.verifier then
            self.status_cache=self.status_cache or {}
            self.verifier=Status:new{storage=self.storage,files=self.service.files,cache=self.status_cache,
                coordinator=self.service.coordinator,
                schedule=self.options.status_schedule or function(delay,callback) UI:scheduleIn(delay,callback) end,
                unschedule=function(callback) UI:unschedule(callback) end,
                may_start=function() return not self.service.running and not self.service:isActive() end,
                on_changed=function()
                    local view=self.shelf.grid_view
                    if view and not view.closed then self.shelf:_render() end
                end}
        end
        return self.verifier:check(path,self.fingerprints[path])
    end
    return state
end

function Manager:_refreshStates()
    -- Series counters query every local volume, so index the queue once per render.
    self.states,self.fingerprints={},{}
    for _,job in ipairs(self.service:jobs()) do
        local path,state=job.source_path,job.state
        local status=(state=="pending" or state=="preparing") and "queued" or
            (state=="processing" or state=="validating") and "processing" or
            state=="failed" and "failed" or
            (state=="skipped" or (state=="completed" and not (job.profile and job.profile.restore))) and "optimized" or "unprocessed"
        local prior=self.states[path]
        if state=="completed" and not (job.profile and job.profile.restore) then self.fingerprints[path]=job.output_fingerprint end
        if prior~="queued" and prior~="processing" or status=="queued" or status=="processing" then self.states[path]=status end
    end
end

function Manager:show()
    local by_key={}
    for _,item in ipairs(self.source_library and self.source_library.items or {}) do by_key[self.storage:itemKey(item)]=item end
    local books={}
    for _,row in ipairs(self.storage:records()) do
        local info=self.storage:recordInfo(row)
        if info and info.exists then
            local source=by_key[row.key] or {}
            local item={file_md5=row.key,vol_name=info.title,file_type="epub",_process_path=info.path}
            for _,field in ipairs({"vol_id","vol_series","vol_author","vol_index","cover_small","cover_url","cover","thumb_url","thumbnail"}) do
                item[field]=source[field]
            end
            books[#books+1]=item
        end
    end
    self.shelf:show(books)
    self:_watch(self.shelf.grid_view)
    return self.shelf.menu
end

function Manager:_watch(view)
    if not view or (self.watched_view==view and self.watch_active) then return end
    if self.watch and UI.unschedule then UI:unschedule(self.watch) end
    self.watched_view,self.watch_active=view,true
    if not view._processing_close_hook then
        local original=view.onCloseWidget
        view.onCloseWidget=function(widget)
            self.watch_active=false
            if self.watch and UI.unschedule then UI:unschedule(self.watch) end
            self.watch,self.watched_view=nil,nil
            self.shelf.selection:cancel()
            self.shelf.library.items={}
            self.shelf.navigation.books,self.shelf.navigation.series,self.shelf.navigation.parent={},nil,nil
            self.states={}
            if self.verifier then self.verifier:close();self.verifier=nil end
            if self.unsubscribe then self.unsubscribe();self.unsubscribe=nil end
            if original then return original(widget) end
        end
        view._processing_close_hook=true
    end
    if not self.unsubscribe and self.service.subscribe then
        self.unsubscribe=self.service:subscribe(function()
            local current=self.shelf.grid_view
            if current and not current.closed then self:_watch(current) end
        end)
    end
    local prior
    local function watch()
        if view.closed or self.shelf.grid_view~=view then self.watch_active=false;return end
        local fields={tostring(self.service.running)}
        for _,job in ipairs(self.service:jobs()) do fields[#fields+1]=tostring(job.id)..":"..tostring(job.state) end
        local signature=table.concat(fields,"|")
        if signature~=prior then prior=signature;self.shelf:_render() end
        if self.service.running or self.service:isActive() then UI:scheduleIn(1,watch)
        else self.watch_active=false end
    end
    self.watch=watch;UI:scheduleIn(1,watch)
end

function Manager:confirm(items)
    local preview,err=self.service:previewBatch(items)
    if not preview then UI:show(Info:new{text=tostring(err)});return end
    if preview.files==0 then UI:show(Info:new{text=string.format("没有可处理的文件。已排队 %d，占用 %d，无效 %d。",preview.duplicate,preview.occupied,preview.invalid)});return end
    local profile=preview.profile
    local scale=profile.scale_mode=="fit" and string.format("%d × %d px",profile.target_width,profile.target_height) or "原尺寸"
    UI:show(Confirm:new{text=string.format("处理 %d 个本地 EPUB？\n成功后直接覆盖，不保留原版备份，不能撤销。\n%s，强度 %d%%。\n原文件共 %s，额外临时空间估计 %s。\n已优化文件核对后跳过；已排队 %d，占用 %d，无效 %d。",
        preview.files,scale,math.floor(profile.strength*100+0.5),Util.friendlySize(preview.bytes),Util.friendlySize(preview.temporary_bytes),
        preview.duplicate,preview.occupied,preview.invalid),ok_text="开始处理",ok_callback=function()
            local counts,error_message=self.service:submitBatch(items,profile)
            if not counts then UI:show(Info:new{text=tostring(error_message)});return end
            if counts.added>0 then
                local ok,resume_error=self.service:resume()
                if not ok then UI:show(Info:new{text=tostring(resume_error)}) end
            end
            self:show()
        end})
end

function Manager:showFilter()
    local dialog,buttons
    buttons={}
    for _,choice in ipairs({{id="all",text="全部"},{id="unprocessed",text="未处理"},{id="optimized",text="已处理"},
        {id="failed",text="失败"},{id="queued",text="已排队"},{id="processing",text="处理中"}}) do
        local id=choice.id
        buttons[#buttons+1]={{text=choice.text,callback=function() self.filter=id;UI:close(dialog);self:show() end}}
    end
    dialog=Dialog:new{title="处理状态",buttons=buttons};UI:show(dialog)
end

function Manager:showActions()
    local dialog
    local function close() UI:close(dialog) end
    dialog=Dialog:new{title="去彩纹管理",buttons={
        {{text="处理筛选结果",callback=function() close();self:confirm(self:visibleVolumes()) end}},
        {{text="状态筛选",callback=function() close();self:showFilter() end}},
        {{text="去彩纹参数",callback=function() close();require("koobone.ui.preprocess_profile").show(self.settings) end}},
        {{text="处理队列",callback=function() close();if self.options.on_queue then self.options.on_queue() end end}},
        {{text="刷新本地漫画",callback=function() close();self:show() end}},
        {{text="批次结果",callback=function()
            close();local result=self.service:batchSummary()
            UI:show(Info:new{text=string.format("完成 %d，已优化跳过 %d，失败 %d，取消 %d，等待/运行 %d，其他跳过 %d。",
                result.completed,result.optimized,result.failed,result.cancelled,result.pending,result.skipped)})
        end}},
        {{text="关闭",callback=close}},
    }};UI:show(dialog)
end

function Manager:visibleVolumes()
    local visible=self.shelf:_visibleBooks()
    local allowed={};for _,item in ipairs(visible) do allowed[item]=true end
    local result,seen={},{}
    for _,row in ipairs(self.shelf.navigation:items(visible)) do
        for _,item in ipairs(row._series and row._series.books or {row}) do
            if allowed[item] and not seen[item] then seen[item]=true;result[#result+1]=item end
        end
    end
    return result
end
return Manager
