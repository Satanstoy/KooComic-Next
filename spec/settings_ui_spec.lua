package.path="./koocomic.koplugin/?.lua;"..package.path
local function class()
    return {new=function(_,value) return value end}
end
for _,name in ipairs({"ui/widget/buttondialog","ui/widget/confirmbox","ui/widget/infomessage","ui/widget/menu"}) do
    package.preload[name]=function() return class() end
end
local shown={}
package.preload["ui/uimanager"]=function() return {show=function(_,value) shown[#shown+1]=value end,close=function() end} end
package.preload["device"]=function() return {screen={scaleBySize=function(_,n) return n end}} end
package.preload["ui/font"]=function() return {} end
package.preload["ui/geometry"]=function() return {} end
local ui={series_style="divider",text_size="normal",portrait_columns=3,portrait_rows=2,landscape_columns=4,landscape_rows=2}
local flushes,changes=0,0
local options={settings={ui=function() return ui end,update=function() return {} end,flush=function() flushes=flushes+1;return true end},
    updater={koreaderVersion=function() return "test" end},updater_ui={},storage={},version="test",on_ui_changed=function() changes=changes+1 end}
local dialog=require("koobone.ui.settings").show(options)
local choice
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do
    if button.text:find("系列样式",1,true) then choice=button end
end end
assert(choice,"series style must have an explicit settings picker")
choice.callback()
local picker=shown[#shown]
assert(#picker.item_table==6,"all six styles must be individually selectable")
assert(picker.item_table[1].checked==true)
picker.item_table[2].callback()
assert(ui.series_style=="ribbon" and flushes==1 and changes==1)
local profile_button
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do if button.text=="去彩纹参数" then profile_button=button end end end
assert(profile_button,"settings must expose processing scale and strength controls")
local rollback_calls=0
options.updater.canRollback=function() return true end
options.updater_ui.rollback=function() rollback_calls=rollback_calls+1 end
dialog=require("koobone.ui.settings").show(options)
local rollback_button
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do if button.text=="回退插件版本" then rollback_button=button end end end
assert(rollback_button and rollback_button.enabled,"verified backups need a native settings rollback entry")
rollback_button.callback();assert(rollback_calls==1)
-- A failed local settings save must still apply the layout change and notify
-- the shelf, instead of aborting the callback and leaving stale rows/columns.
local good_settings=options.settings
options.settings={ui=function() return ui end,update=function() return {} end,
    flush=function() error("injected settings save failure") end}
local before_changes=changes
dialog=require("koobone.ui.settings").show(options)
local column_button
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do
    if button.text:find("竖屏列数",1,true) then column_button=button end
end end
assert(column_button,"settings must expose the portrait column control")
column_button.callback()
assert(changes==before_changes+1,"a failed save must still notify the shelf to relayout")
local warned=false
for _,widget in ipairs(shown) do
    if widget.text and tostring(widget.text):find("未能保存",1,true) then warned=true end
end
assert(warned,"the user must be told when the layout change could not be persisted")
options.settings=good_settings
print("settings UI spec: OK")
