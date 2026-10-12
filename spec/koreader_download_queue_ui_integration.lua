require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800}}
local Device=require("device")
require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local View=require("koobone.ui.download_queue")
local account="fixture"
local paused=false
local service={running=true,account=function() return account end,
    ensure=function() return {jobs={}} end,
    pause=function() paused=true;return true end,
    summary=function() return {total=0,completed=0,failed=0,pending=0} end}
local menu=View.show(service)
menu:onMenuSelect(menu.item_table[1])
assert(paused and not menu._queue_closed,"native selection must leave visible menu registered and refreshing")
View.closeAccountViews()
assert(menu._queue_closed,"logout must close the selected native menu")
local another=View.show(service)
UI:close(another)
assert(another._queue_closed,"native close event must stop refresh")
local parameters={data={preprocess={strength=0.8,scale_mode="original"}},flush=function() return true end}
local profile_menu=require("koobone.ui.preprocess_profile").show(parameters)
profile_menu:onMenuSelect(profile_menu.item_table[1])
local picker=UI._window_stack[#UI._window_stack].widget
picker:onMenuSelect(picker.item_table[2])
assert(parameters.data.preprocess.scale_mode=="fit" and parameters.data.preprocess.target_width==600)
profile_menu=UI._window_stack[#UI._window_stack].widget
profile_menu:onMenuSelect(profile_menu.item_table[2])
local spin=UI._window_stack[#UI._window_stack].widget
assert(spin.value_min==0 and spin.value_max==100 and spin.value==80)
spin.value=65;spin.callback(spin);UI:close(spin)
assert(parameters.data.preprocess.strength==0.65)
UI:close(UI._window_stack[#UI._window_stack].widget)
print("KOReader native download queue lifecycle: OK")
Device:exit()
