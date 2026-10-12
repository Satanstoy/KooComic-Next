package.path="./koocomic.koplugin/?.lua;"..package.path
local shown,timers={ },{ }
local Widget={new=function(_,fields) return fields end,onCloseWidget=function() end}
for _,module in ipairs({"menu","buttondialog","confirmbox","infomessage"}) do
    package.preload["ui/widget/"..module]=function() return Widget end
end
package.preload["socket"]=function() return {gettime=os.time} end
package.preload["ui/uimanager"]=function() return {show=function(_,widget) shown[#shown+1]=widget end,
    close=function() end,scheduleIn=function(_,_,callback) timers[#timers+1]=callback end,setDirty=function() end} end
local loaded,View=pcall(require,"koobone.ui.download_queue")
assert(loaded,"production queue management view is missing")
local cancelled,retried,paused,history=nil,nil,false,false
local queue={jobs={{id="pending",state="pending",entry={title="Waiting",source={file_md5="p"}},bytes=0},
    {id="failed",state="failed",entry={title="Failed",source={file_md5="f"}},bytes=8,error_code="network"}}}
local service={running=true,ensure=function() return queue end,account=function() return "one" end,
    summary=function() return {completed=0,failed=1,pending=1,total=2} end,
    pause=function() paused=true;return true end,resume=function() return true end,
    cancel=function(_,id) cancelled=id;return true end,retry=function(_,id) retried=id;return true end,
    storage={resolveLocalPath=function() return nil end}}
local menu=View.show(service,{on_history=function() history=true end})
assert(menu and menu.title=="下载队列")
local function row(title) for _,item in ipairs(menu.item_table) do if item.text==title then return item end end end
assert(row("暂停队列") and row("Waiting") and row("下载历史"))
-- KOReader invokes close_callback on ordinary selections without closing Menu.
if menu.close_callback then menu.close_callback() end
assert(not menu._queue_closed,"selecting a menu entry must not stop refresh or unregister the visible menu")
row("暂停队列").callback();assert(paused)
row("Waiting").callback();shown[#shown].buttons[1][1].callback();assert(cancelled=="pending")
row("Failed").callback()
local retry
for _,buttons in ipairs(shown[#shown].buttons) do for _,button in ipairs(buttons) do if button.text=="重试" then retry=button end end end
assert(retry);retry.callback();assert(retried=="failed")
row("下载历史").callback();assert(history)
cancelled=nil
row("取消等待任务").callback()
queue.jobs[1].state="downloading"
shown[#shown].ok_callback()
assert(not cancelled,"waiting-only confirmation must not cancel a job that started meanwhile")
row("Waiting").callback();shown[#shown].buttons[1][1].callback()
assert(not cancelled and shown[#shown].ok_callback,"running transfers need explicit confirmation")
shown[#shown].ok_callback();assert(cancelled=="pending")
View.closeAccountViews()
assert(menu._queue_closed,"logout must immediately close account-scoped queue views")
print("download queue UI spec: OK")
