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
print("KOReader native download queue lifecycle: OK")
Device:exit()
