require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local width,height=tonumber(arg[2]) or 600,tonumber(arg[3]) or 800
local text_size,format,night=arg[4] or "large",arg[5] or "rgb",arg[6]=="night"
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device")
Device.screen.night_mode=night
require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local BB=require("ffi/blitbuffer")
local first={vol_id=10,file_md5=string.rep("a",32),file_type="epub",vol_name="生成漫画 长标题第一卷 VeryLongOriginalComicNameWithoutSpaces Original version",vol_author="Fixture"}
local second={vol_id=10,file_md5=string.rep("b",32),file_type="epub",vol_name="生成漫画 第一卷 Revised version",vol_author="Fixture"}
local chosen
local detail=require("koobone.ui.book_detail").show{item=first,versions={first,second},
    storage={isDownloaded=function() return true end,partSize=function() return 0 end,
        resolveLocalPath=function() return "/books/generated-original.epub" end},
    downloader={},preprocess={available=true,isLocked=function() return false end},
    settings={ui=function() return {text_size=text_size} end},
    on_select_version=function(item) chosen=item end}
assert(detail.frame[1][1]:getSize().h<=detail.frame[1].dimen.h,
    "version controls and text must fit the native detail frame in both orientations")
local canvas=BB.new(width,height,format=="gray" and BB.TYPE_BB8 or BB.TYPE_BBRGB32);canvas:fill(BB.COLOR_WHITE)
detail:paintTo(canvas,0,0)
if night then canvas:invert() end
local output="/tmp/koocomic-file-versions-"..width.."x"..height.."-"..text_size.."-"..format.."-"..tostring(night)..".png"
assert(canvas:writeToFile(output,"png"));canvas:free()
local button
for _,row in ipairs(detail.buttons) do for _,value in ipairs(row) do if value.text=="文件版本 (2)" then button=value end end end
assert(button);button.callback()
local menu=UI._window_stack[#UI._window_stack].widget
assert(menu.title=="文件版本" and #menu.item_table==2)
menu:onMenuSelect(menu.item_table[2]);assert(chosen==second)
assert(#UI._window_stack==0,"native version selection must close both the old detail and chooser")
print("KOReader file-version detail/chooser: OK "..output)
Device:exit()
