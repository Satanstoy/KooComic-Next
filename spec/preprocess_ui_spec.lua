package.path="./koocomic.koplugin/?.lua;"..package.path
local shown={}
local Widget={new=function(_,options) return options end}
for _,module in ipairs({"menu","buttondialog","confirmbox","infomessage"}) do
    package.preload["ui/widget/"..module]=function() return Widget end
end
package.preload["ui/uimanager"]=function() return {show=function(_,widget) shown[#shown+1]=widget end,
    close=function() end,scheduleIn=function() end} end
local storage={records=function() return {{key="book"}} end,
    recordInfo=function() return {exists=true,path="/books/book.epub",title="Book"} end}
local service={available=true,record=function() return {} end,jobs=function() return {} end}
local menu=require("koobone.ui.preprocess").show(storage,service)
menu.item_table[2].callback()
shown[#shown].item_table[1].callback()
local dialog=shown[#shown]
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do
    assert(button.text~="恢复原版","no-backup management must not offer restoration")
end end
dialog.buttons[1][1].callback()
assert(shown[#shown].text:find("不保留原版备份",1,true),"management confirmation must disclose replacement")
print("preprocess UI spec: OK")
