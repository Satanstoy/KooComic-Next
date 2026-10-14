-- SPDX-License-Identifier: AGPL-3.0-only
local Menu=require("ui/widget/menu")
local ButtonDialog=require("ui/widget/buttondialog")
local ConfirmBox=require("ui/widget/confirmbox")
local InfoMessage=require("ui/widget/infomessage")
local UIManager=require("ui/uimanager")
local Util=require("koobone.util")
local Worker=require("koobone.download_worker")
local View={}
local views=setmetatable({},{__mode="k"})
local names={pending="等待",preparing="准备中",downloading="下载中",validating="校验中",completed="完成",
    failed="失败",cancelled="已取消",interrupted="中断"}
local errors={network="网络连接失败",unauthorized="登录已过期",forbidden="下载地址被拒绝",catalog_missing="漫画已不在当前书库",no_space="可用空间不足",
    path_conflict="文件变化、占用或保存失败",invalid_epub="EPUB校验失败",account_changed="账号已变化",
    worker_failed="下载进程失败",interrupted="上次运行中断",cancelled="已取消"}

function View.closeAccountViews()
    for widget in pairs(views) do
        widget._queue_closed=true;views[widget]=nil;UIManager:close(widget)
    end
end

function View.show(service,options)
    options=options or {}
    local account=service:account()
    local queue,load_error=service:ensure()
    local menu
    local function valid()
        if service:account()==account then return true end
        View.closeAccountViews();return false
    end
    local function report(ok,err)
        if not ok then UIManager:show(InfoMessage:new{text=tostring(err or "操作失败")}) end
    end
    local function showJob(job)
        if not valid() then return end
        local dialog
        local path=job.state=="completed" and service.storage:resolveLocalPath(Worker.raw(job.entry))
        local buttons={
            {{text="取消任务",enabled=job.state=="pending" or job.state=="preparing" or job.state=="downloading" or job.state=="validating",
                callback=function()
                    if not valid() then return end
                    local function cancel() if valid() then report(service:cancel(job.id)) end end
                    if job.state=="pending" then cancel()
                    else
                        local confirm=ConfirmBox:new{text="取消当前下载？",ok_text="取消下载",ok_callback=cancel}
                        views[confirm]=true;UIManager:show(confirm)
                    end
                    UIManager:close(dialog);views[dialog]=nil
                end}},
            {{text="重试",enabled=job.state=="failed" or job.state=="cancelled" or job.state=="interrupted",
                callback=function() if valid() then report(service:retry(job.id));UIManager:close(dialog);views[dialog]=nil end end}},
        }
        if path and options.on_open then buttons[#buttons+1]={{text="打开阅读",callback=function()
            if not valid() then return end
            local current=service.storage:resolveLocalPath(Worker.raw(job.entry))
            if current then UIManager:close(dialog);views[dialog]=nil;options.on_open(current) end
        end}} end
        buttons[#buttons+1]={{text="关闭",callback=function() UIManager:close(dialog);views[dialog]=nil end}}
        dialog=ButtonDialog:new{title=(job.entry.title~="" and job.entry.title or "未命名漫画").."\n"..
            (names[job.state] or job.state).."\n"..(errors[job.error_code] or "")..
            (job.warning and "\n文件已保存，记录或目录同步需核对。" or ""),buttons=buttons}
        views[dialog]=true;UIManager:show(dialog)
    end
    local function rows()
        if not queue then
            return {{text="下载队列不可用",callback=function() UIManager:show(InfoMessage:new{text=tostring(load_error)}) end},
                {text="下载历史",callback=options.on_history}}
        end
        local result={
            {text=service.running and "暂停队列" or "继续队列",callback=function()
                if not valid() then return end
                if service.running then report(service:pause()) else report(service:resume()) end
            end},
            {text="取消等待任务",callback=function()
                if not valid() then return end
                local ids={};for _,job in ipairs(queue.jobs) do if job.state=="pending" then ids[#ids+1]=job.id end end
                if #ids==0 then return end
                local confirm=ConfirmBox:new{text="取消 "..#ids.." 个等待任务？",ok_text="取消等待任务",ok_callback=function()
                    if valid() then
                        for _,id in ipairs(ids) do
                            for _,job in ipairs(queue.jobs) do
                                if job.id==id and job.state=="pending" then report(service:cancel(id));break end
                            end
                        end
                    end
                end}
                views[confirm]=true;UIManager:show(confirm)
            end},
            {text="下载历史",callback=options.on_history},
        }
        if service.reconcile then result[#result+1]={text="重新核对文件",callback=function() if valid() then service:reconcile() end end} end
        for _,value in ipairs(queue.jobs) do
            local job=value
            result[#result+1]={text=job.entry.title~="" and job.entry.title or "未命名漫画",mandatory=names[job.state] or job.state,
                post_text=Util.friendlySize(job.bytes)..(job.total and " / "..Util.friendlySize(job.total) or " / 未知大小"),
                callback=function() showJob(job) end}
        end
        return result
    end
    local refresh
    menu=Menu:new{title="下载队列",item_table=rows(),is_borderless=true,title_bar_fm_style=true}
    local original_close=menu.onCloseWidget or Menu.onCloseWidget
    menu.onCloseWidget=function(widget)
        widget._queue_closed=true;views[widget]=nil
        if UIManager.unschedule and refresh then UIManager:unschedule(refresh) end
        if original_close then return original_close(widget) end
    end
    views[menu]=true;UIManager:show(menu)
    refresh=function()
        if menu._queue_closed or not valid() then return end
        menu.item_table=rows()
        local summary=service:summary()
        menu.subtitle=string.format("%d 项，完成 %d，失败 %d，等待/运行 %d",summary.total,summary.completed,summary.failed,summary.pending)
        if menu.updateItems then menu:updateItems(nil,true) end
        UIManager:setDirty(menu,"ui")
        UIManager:scheduleIn(0.5,refresh)
    end
    if queue then UIManager:scheduleIn(0.5,refresh) end
    return menu
end

return View
