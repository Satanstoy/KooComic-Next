-- Native-resolution regression guard for the settings popup: the dialog must
-- fit the real screen with a bottom margin on any device geometry/DPI, instead
-- of painting past the visible area.
-- usage: luajit koreader_settings_screen_integration.lua <repo-root> <width> <height> <dpi>
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local width,height=assert(tonumber(arg[2])),assert(tonumber(arg[3]))
local dpi=tonumber(arg[4]) or 160
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device")
if dpi~=160 then
    Device.screen.display_dpi=dpi
    Device.screen.scaleBySize=function(_,value) return math.ceil(value*dpi/160) end
end
require("document/canvascontext"):init(Device)
local BB=require("ffi/blitbuffer")
local UI=require("ui/uimanager")
local ui={portrait_columns=3,portrait_rows=2,landscape_columns=4,landscape_rows=2,text_size="large",series_style="divider"}
local settings={update=function() return {auto_check_enabled=true} end,ui=function() return ui end,flush=function() end}
local dialog=require("koobone.ui.settings").show{settings=settings,
    updater={koreaderVersion=function() return "v2026.07.1" end,canRollback=function() return true end},
    updater_ui={},storage={downloadDir=function() return "/tmp" end},version="0.4.1"}
assert(type(dialog.buttons)=="table" and #dialog.buttons>6,"the settings screen must keep its full button list")
local canvas=BB.new(width,height,BB.TYPE_BBRGB32);canvas:fill(BB.COLOR_WHITE)
dialog:paintTo(canvas,0,0)
local box=dialog.movable and dialog.movable.dimen
assert(box,"the settings dialog must expose its movable frame")
assert(box.x>=-1 and box.y>=-1 and box.x+box.w<=width+1 and box.y+box.h<=height+1,
    string.format("settings dialog must fit %dx%d@%d: x=%s y=%s w=%s h=%s",width,height,dpi,box.x,box.y,box.w,box.h))
assert(box.y+box.h<=height*0.95,
    string.format("the lowest settings control must leave a reachable margin on %dx%d@%d (bottom=%s of %s)",
        width,height,dpi,tostring(box.y+box.h),tostring(height)))
canvas:free()
Device:exit()
print("KOReader settings screen fit: OK "..width.."x"..height.."@"..dpi)
