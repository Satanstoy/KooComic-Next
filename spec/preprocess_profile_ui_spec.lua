package.path="./koocomic.koplugin/?.lua;"..package.path
local shown={}
for _,module in ipairs({"menu","spinwidget","infomessage"}) do
    package.preload["ui/widget/"..module]=function() return {new=function(_,fields) return fields end} end
end
package.preload["ui/uimanager"]=function() return {show=function(_,widget) shown[#shown+1]=widget end,close=function() end} end
package.preload["device"]=function() return {screen={getWidth=function() return 758 end,getHeight=function() return 1024 end}} end
local loaded,View=pcall(require,"koobone.ui.preprocess_profile")
assert(loaded,"processing profile needs native parameter controls")
local saves=0
local settings={data={preprocess={strength=0.8,scale_mode="original"}},flush=function() saves=saves+1;return true end}
local menu=View.show(settings)
menu.item_table[1].callback();shown[#shown].item_table[2].callback()
assert(settings.data.preprocess.scale_mode=="fit" and settings.data.preprocess.target_width==758 and saves==1)
menu=shown[#shown];menu.item_table[2].callback()
local spin=shown[#shown];assert(spin.value_min==0 and spin.value_max==100)
spin.callback({value=65});assert(settings.data.preprocess.strength==0.65 and saves==2)
menu=shown[#shown];menu.item_table[3].callback()
shown[#shown].callback({value=600});assert(settings.data.preprocess.target_width==600)
local previous=settings.data.preprocess
settings.flush=function() error("injected failure") end
menu=shown[#shown];menu.item_table[2].callback();shown[#shown].callback({value=20})
assert(settings.data.preprocess==previous,"failed parameter persistence must restore the previous in-memory profile")
print("preprocess profile UI spec: OK")
