package.path="./koocomic.koplugin/?.lua;"..package.path
local shown,timers={},{}
local Widget={new=function(_,options) return options end}
for _,module in ipairs({"menu","buttondialog","confirmbox","infomessage"}) do
    package.preload["ui/widget/"..module]=function() return Widget end
end
package.preload["ui/uimanager"]=function() return {show=function(_,widget) shown[#shown+1]=widget end,
    close=function() end,scheduleIn=function(_,_,callback) timers[#timers+1]=callback end,setDirty=function() end} end
local storage={records=function() return {{key="book"}} end,
    recordInfo=function() return {exists=true,path="/books/book.epub",title="Book"} end}
local service={available=true,record=function() return {} end,jobs=function() return {} end}
local menu=require("koobone.ui.preprocess").show(storage,service)
local refreshed=0
menu.updateItems=function() refreshed=refreshed+1 end
if menu.close_callback then menu.close_callback() end
table.remove(timers,1)()
assert(refreshed==1,"native menu selection must not unregister the still-visible processing queue")
menu.item_table[2].callback()
shown[#shown].item_table[1].callback()
local dialog=shown[#shown]
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do
    assert(button.text~="恢复原版","no-backup management must not offer restoration")
end end
dialog.buttons[1][1].callback()
assert(shown[#shown].text:find("不保留原版备份",1,true),"management confirmation must disclose replacement")
local received
package.preload["koobone.ui.preprocess_manager"]=function() return {new=function(_,options)
    received=options;return {show=function() return "grid" end}
end} end
assert(require("koobone.ui.preprocess").show(storage,service,{settings={},library={items={}}})=="grid" and
    received.service==service and received.on_queue,"production management must default to the shared grid, retaining a separate queue view")
local cancelled=false
service.jobs=function() return {{id="running",source_path="/books/book.epub",state="processing"}} end
service.cancel=function() cancelled=true;return true end
local queue=require("koobone.ui.preprocess").show(storage,service,{queue_only=true})
queue.item_table[4].callback();shown[#shown].buttons[1][1].callback()
assert(not cancelled and shown[#shown].ok_callback,"running processing cancellation must require confirmation")
shown[#shown].ok_callback();assert(cancelled)
print("preprocess UI spec: OK")
