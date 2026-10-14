-- SPDX-License-Identifier: AGPL-3.0-only
-- Adapted from pinned Bookshelf stack_display; see UPSTREAM.md.
local Screen=require("device").screen
local Space=require("koobone.ui.vendor.bookshelf.space")
local Font=require("ui/font")
local Geom=require("ui/geometry")
local M={DIVIDER="divider",RIBBON="ribbon",STACK="stack",COLLAGE="collage",TEXT="text",NONE="none",MAX_PILE_BOOKS=4}
M.OPTIONS={
    {value="divider",label="文件夹标签"},{value="ribbon",label="缎带"},
    {value="stack",label="书籍叠放"},{value="collage",label="封面拼贴"},
    {value="text",label="纯文字"},{value="none",label="纯封面"},
}
function M.resolve(value)
    for _,option in ipairs(M.OPTIONS) do if option.value==value then return value end end
    return M.DIVIDER
end
function M.labelFor(value)
    value=M.resolve(value)
    for _,option in ipairs(M.OPTIONS) do if option.value==value then return option.label end end
end
function M.needsExternalLabel(mode)
    return mode==M.STACK or mode==M.COLLAGE or mode==M.NONE
end
function M.pileLayers(book_count)
    if type(book_count)~="number" then return M.MAX_PILE_BOOKS-1 end
    local n=math.floor(book_count)
    if n<1 then return 0 end
    if n>M.MAX_PILE_BOOKS then n=M.MAX_PILE_BOOKS end
    return n-1
end
function M.pileStep() return Screen:scaleBySize(5) end
function M.pileInset(mode,count)
    if mode~=M.STACK then return 0 end
    return M.pileStep()*M.pileLayers(count)
end
function M.ribbonOverhang() return Screen:scaleBySize(4) end
function M.ribbonInset(mode)
    if mode~=M.RIBBON then return 0 end
    return M.ribbonOverhang()*2
end
local RIBBON_MIN_HEIGHT,RIBBON_BOTTOM_GAP=0.18,0.07
local ORDER_BY_COUNT={{1},{1,4},{1,2,3},{1,2,3,4}}
function M.collagePlacement(count)
    if type(count)~="number" or count<1 then return ORDER_BY_COUNT[1] end
    return ORDER_BY_COUNT[math.min(4,math.floor(count))] or ORDER_BY_COUNT[4]
end
local RibbonTextBox

-- One rendered line's height for a face/width, memoised: the clamp below needs
-- it per render and probing costs a full layout pass. Mirrors the same memo in
-- bookshelf_folder_card.
local _line_h_memo = {}
local function _lineHeight(face, bold, width)
    local key = tostring(face) .. "\1" .. tostring(bold) .. "\1" .. tostring(width)
    local h = _line_h_memo[key]
    if h then return h end
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local probe = TextBoxWidget:new{ text = "Mg", face = face, bold = bold,
                                     width = width }
    h = probe:getSize().h
    probe:free()
    _line_h_memo[key] = h
    return h
end

-- ribbonWidget(cover_w, cover_h, label) -> widget, y_offset
--
-- The widget is sized to the FULL band (cover width plus both overhangs) and
-- the caller offsets it by -overhang on x, so the band is centred on the
-- cover and protrudes evenly. y_offset is where the band's top sits relative
-- to the cover's top, so a caller that has already offset the cover downward
-- (true aspect bottom-anchors the card) adds the two together.
--
-- Returns nil for an empty label: a band with nothing in it says nothing and
-- just hides a third of the artwork.
function M.ribbonWidget(cover_w, cover_h, label, options)
    if type(label) ~= "string" or label == "" then return nil end
    if not (cover_w and cover_h and cover_w > 0 and cover_h > 0) then return nil end
    local TextBoxWidget   = require("ui/widget/textboxwidget")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    -- KooComic injects its face; no Bookshelf font wrapper or global settings.
    if not RibbonTextBox then RibbonTextBox = TextBoxWidget:extend{ alpha = true } end

    local text = label
    local over    = M.ribbonOverhang()
    local band_w  = cover_w + over * 2
    local pad     = Space.padding.small
    local avail_w = band_w - pad * 2
    if avail_w <= 0 then return nil end

    -- Same font and the same user scale the cardboard label uses, so the two
    -- modes read as the same family rather than as two different designs.
    local face, bold = options.face or Font:getFace("infofont",15), true
    local fill, fg = options.theme.ribbon_bg, options.theme.ribbon_fg

    -- Text clamped by the SAME rule the cardboard label uses: at most two
    -- lines, ellipsis when it overflows. Derived from the real rendered line
    -- height rather than from a fraction of the cover, so the two modes cut a
    -- long folder name at the same place and a font-scale change moves both.
    local line_h = _lineHeight(face, bold, avail_w)
    local max_h  = 2 * line_h
    local probe = TextBoxWidget:new{
        text = text, face = face, bold = bold, width = avail_w,
    }
    local content_h = probe:getSize().h
    probe:free()
    local fits  = content_h <= max_h
    local txt_h = fits and content_h or max_h
    local txt = RibbonTextBox:new{
        text      = text,
        face      = face,
        bold      = bold,
        width     = avail_w,
        height    = txt_h,
        alignment = "center",
        fgcolor   = fg,
        -- TextBoxWidget FILLS its own background before drawing glyphs, and
        -- that default is white: without this it paints a white rectangle
        -- over the band and then draws white text onto it, which is exactly
        -- as invisible as it sounds.
        bgcolor   = fill,
        height_overflow_show_ellipsis = not fits,
    }

    local band_h = math.max(txt_h + pad * 2,
                            math.floor(cover_h * RIBBON_MIN_HEIGHT))
    local band = FrameContainer:new{
        width          = band_w,
        height         = band_h,
        background     = fill,
        bordersize     = 0,
        padding        = 0,
        margin         = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = band_w, h = band_h },
            txt,
        },
    }

    -- BOTTOM-ANCHORED, and the band grows UPWARD from that line. Anchoring the
    -- TOP instead put every band at the same y and let each grow downward by
    -- however many lines its name needed, so a row of folders had bands ending
    -- at four different heights -- the one thing that makes a row of straps
    -- read as an accident rather than a design. Pinned at the bottom they
    -- share a line and only their thickness varies, which is what a real band
    -- around a bundle does.
    --
    -- Not flush with the bottom edge: a strap has cover showing beneath it.
    -- Measured from the cover's own bottom, above the drop shadow, so the gap
    -- is to the artwork rather than to the shadow's outer edge.
    local shadow = Space.px(4)
    local gap = math.max(Space.px(3),
                         math.floor(cover_h * RIBBON_BOTTOM_GAP))
    local y = cover_h - shadow - gap - band_h
    if y < 0 then y = 0 end
    return band, y
end


return M
