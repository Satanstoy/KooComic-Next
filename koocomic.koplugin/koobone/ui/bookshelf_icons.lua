-- SPDX-License-Identifier: AGPL-3.0-only
-- Bookshelf's symbols-face approach, using KOReader's bundled Nerd Font.
local Font=require("ui/font")
local TextWidget=require("ui/widget/textwidget")
local BB=require("ffi/blitbuffer")
local Icons={}
local glyphs={back="\239\129\160",search="\239\128\130",menu="\239\131\137",
    first="\239\132\128",previous="\239\132\132",next="\239\132\133",last="\239\132\129",
    downloads="\239\128\153"}
local names={back="返回",search="搜索",menu="菜单",first="首页",previous="上一页",next="下一页",last="末页",downloads="下载管理"}
function Icons.build(kind,size,disabled)
    return TextWidget:new{text=assert(glyphs[kind]),face=Font:getFace("symbols",math.min(24,size or 20)),
        fgcolor=disabled and BB.COLOR_GRAY or BB.COLOR_BLACK,bold=false}
end
function Icons.name(kind) return names[kind] end
return Icons
