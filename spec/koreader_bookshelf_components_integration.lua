-- Run from official KOReader lib/koreader with checkout path as arg[1].
require("setupkoenv")
local root=assert(arg[1])
package.path=root.."/koocomic.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false}
local Device=require("device")
require("document/canvascontext"):init(Device)
local BB=require("ffi/blitbuffer")
local loaded,Cover=pcall(require,"koobone.ui.vendor.bookshelf.cover_card")
assert(loaded,"the rounded cover and shadow must use the upstream rendering kernel")
local Widget=require("ui/widget/widget")
local inner=Widget:extend{}
function inner:paintTo(bb,x,y) bb:paintRect(x,y,98,138,BB.COLOR_BLACK) end
local buffer=BB.new(150,180,BB.TYPE_BBRGB32)
local background=BB.colorFromString("#82b3d2")
buffer:paintRectRGB32(0,0,150,180,background)
local card=Cover.RoundedCornerCard:new{width=100,height=140,radius=8,border_size=1,
    border_color=BB.COLOR_BLACK,inner=inner:new{}}
card:paintTo(buffer,10,10)
local corner=buffer:getPixel(10,10):getColorRGB32()
assert(corner.r==background.r and corner.g==background.g and corner.b==background.b,
    "rounded corners must restore the actual background")
assert(buffer:getPixel(60,60):getColor8().a==0,"cover content must remain intact")
assert(Cover.ShadowRect,"upstream-style hard shadow renderer is required")
local shadow=Cover.ShadowRect:new{width=100,height=140,radius=8,color=BB.COLOR_GRAY}
shadow:paintTo(buffer,14,14)
card:paintTo(buffer,10,10)
assert(buffer:getPixel(112,80):getColor8().a==BB.COLOR_GRAY.a,"shadow must stay visible outside the card")
local Folder=require("koobone.ui.vendor.bookshelf.folder_card")
local Badge=require("koobone.ui.vendor.bookshelf.count_badge")
local theme={folder_bg=BB.colorFromString("#e7c9a9"),folder_fg=BB.COLOR_BLACK,
    border=BB.COLOR_BLACK,badge_bg=BB.COLOR_WHITE,badge_fg=BB.COLOR_BLACK}
local folder,label=Folder.build{width=100,height=140,label="Series",theme=theme,font_size=14}
folder:paintTo(buffer,10,10);label:paintTo(buffer,10,10)
local color=buffer:getPixel(95,135):getColorRGB32()
assert(color.r==231 and color.g==201 and color.b==169,"folder fill must retain its RGB values")
local badge=Badge.render(19,{theme=theme})
badge:paintTo(buffer,70,10)
assert(badge:getSize().w>15 and badge:getSize().h>15)
badge:free();folder:free();label:free();card:free();buffer:free()
for name in pairs(package.loaded) do assert(not name:match("^lib/bookshelf_"),"Bookshelf runtime leaked") end
local Grid=require("koobone.ui.bookshelf_grid")
local members={{vol_name="One"},{vol_name="Two"},{vol_name="Three"},{vol_name="Four"}}
for _,style in ipairs({"divider","ribbon","stack","collage","text","none"}) do
    local shelf=Grid.show{books={{vol_name="Series",_series={books=members,volume_count=4,downloaded_count=1}}},
        mode="series",ui={series_style=style,text_size="normal"},storage={isDownloaded=function() return false end,partSize=function() return 0 end}}
    local canvas=BB.new(600,800,BB.TYPE_BBRGB32)
    canvas:fill(BB.COLOR_WHITE)
    shelf:paintTo(canvas,0,0)
    local ink=0
    for y=80,650,10 do for x=10,590,10 do if canvas:getPixel(x,y):getColor8().a<240 then ink=ink+1 end end end
    assert(ink>10,"style did not render visible content: "..style)
    shelf:_close();canvas:free()
end
Device:exit()
print("KOReader imported Bookshelf component integration: OK")
