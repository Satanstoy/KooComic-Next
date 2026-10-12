-- SPDX-License-Identifier: AGPL-3.0-only
-- Extracted from Bookshelf SpineWidget at 2c8bfd8; see UPSTREAM.md.
local ffi = require("ffi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local ColorRGB32_t = ffi.typeof("ColorRGB32")
local function _paintColorSafeBorder(bb, x, y, w, h, border_size, color, radius, anti_alias)
    if not color or not border_size or border_size <= 0 then return end
    local is_rgb32 = ffi.istype(ColorRGB32_t, color)
    local suppress_invert = is_rgb32 and Device:isAndroid() and bb:getInverse() == 1
    if suppress_invert then bb:setInverse(0) end
    if is_rgb32 then
        bb:paintBorderRGB32(x, y, w, h, border_size, color, radius, anti_alias)
    else
        bb:paintBorder(x, y, w, h, border_size, color, radius, anti_alias)
    end
    if suppress_invert then bb:setInverse(1) end
end

local CornerKeep = {}
CornerKeep.__index = CornerKeep

-- take(bb, x, y, w, h, r) -> keep | nil (nothing to keep, or a target that
-- cannot be read from). x, y, w, h is the card's rect on bb, r its radius.
function CornerKeep.take(bb, x, y, w, h, r)
    if not (bb and bb.blitFrom and bb.getType) then return nil end
    if not (r and w and h) or r <= 0 or w < r or h < r then return nil end
    local ok, squares = pcall(function()
        local typ = bb:getType()
        local at  = { { x, y }, { x + w - r, y }, { x, y + h - r }, { x + w - r, y + h - r } }
        local sq  = {}
        for i = 1, 4 do
            local s = Blitbuffer.new(r, r, typ)
            s:blitFrom(bb, 0, 0, at[i][1], at[i][2], r, r)
            sq[i] = { bb = s, x = at[i][1], y = at[i][2] }
        end
        return sq
    end)
    if not ok or type(squares) ~= "table" then return nil end
    return setmetatable({ squares = squares, r = r }, CornerKeep)
end

-- putRow(bb, cx, cy, cw) -> true when one kept square held the row and it was
-- painted back; false lets the caller fall back to its old guess.
function CornerKeep:putRow(bb, cx, cy, cw)
    if not cw or cw <= 0 then return false end
    local r = self.r
    for i = 1, 4 do
        local s = self.squares[i]
        if s and cx >= s.x and cx + cw <= s.x + r and cy >= s.y and cy < s.y + r then
            local ok = pcall(bb.blitFrom, bb, s.bb, cx, cy, cx - s.x, cy - s.y, cw, 1)
            return ok and true or false
        end
    end
    return false
end

function CornerKeep:free()
    for i = 1, 4 do
        local s = self.squares[i]
        if s and s.bb and s.bb.free then pcall(s.bb.free, s.bb) end
    end
    self.squares = {}
end

local RoundedCornerCard = Widget:extend{
    inner        = nil,                       -- widget to paint inside (image)
    width        = nil,
    height       = nil,
    radius       = 0,
    border_size  = 0,
    border_color = nil,                       -- defaults to COLOR_BLACK
    bg_color     = nil,                       -- page bg (default COLOR_WHITE)
    fade_by      = nil,                        -- 0..1 white-blend over the inner
                                               -- cover (on-hold de-emphasis); nil = none
    -- Shadow restoration: when the card sits over a drop-shadow, mask pixels
    -- in the card's corner overflow that fall inside the shadow's rounded
    -- shape need to be painted shadow-grey (not bg) so the shadow stays
    -- visible at the rounded corners. Set these to the enclosing shadow's
    -- offset (relative to this card's top-left) and color/radius.
    shadow_color    = nil,
    shadow_offset_x = 0,
    shadow_offset_y = 0,
    shadow_radius   = 0,
}

function RoundedCornerCard:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function RoundedCornerCard:getSize() return self.dimen end

function RoundedCornerCard:free(...)
    if self.inner and self.inner.free then self.inner:free(...) end
end

-- Returns true if the card-local pixel (px, py) falls inside the enclosing
-- shadow's painted area (i.e., the shadow color was drawn there before the
-- card overpainted it). Used so the corner mask restores shadow grey
-- instead of stamping bg-white over visible shadow.
function RoundedCornerCard:_pixelInShadow(px, py)
    if not self.shadow_color then return false end
    local sox, soy = self.shadow_offset_x, self.shadow_offset_y
    local sw, sh   = self.width, self.height           -- shadow same size as card
    if px < sox or py < soy
       or px >= sox + sw or py >= soy + sh then
        return false
    end
    local sr = self.shadow_radius or 0
    if sr <= 0 then return true end
    local sx, sy   = px - sox, py - soy
    local cx, cy
    if sx < sr and sy < sr then
        cx, cy = sr, sr                                -- shadow TL corner area
    elseif sx >= sw - sr and sy < sr then
        cx, cy = sw - sr, sr                           -- shadow TR
    elseif sx < sr and sy >= sh - sr then
        cx, cy = sr, sh - sr                           -- shadow BL
    elseif sx >= sw - sr and sy >= sh - sr then
        cx, cy = sw - sr, sh - sr                      -- shadow BR
    end
    if not cx then return true end                     -- straight-edge area
    local ddx, ddy = sx - cx, sy - cy
    return ddx * ddx + ddy * ddy <= sr * sr
end

function RoundedCornerCard:paintTo(bb, x, y)
    -- Record the painted screen position so transient framebuffer effects
    -- (the opening-book squeeze in bookshelf_widget) can target the exact
    -- cover card rather than reconstructing layout geometry.
    self.dimen.x, self.dimen.y = x, y
    -- What is behind the corners, before the cover paints over it (see
    -- CornerKeep). An explicit bg_color -- the selection ring behind a
    -- selected cover -- is meant to show at the corner, so it still wins.
    local keep = nil
    if type(self.bg_color) == "nil" and self.radius and self.radius > 0 then
        keep = CornerKeep.take(bb, x, y, self.width, self.height, self.radius)
    end
    if self.inner then
        self.inner:paintTo(bb, x + self.border_size, y + self.border_size)
    end
    -- On-hold fade: blend the page colour over the cover image so the book
    -- reads as shelved. Applied over the inner area only (inside the border),
    -- BEFORE the corner mask + border so the rounded shape and frame stay
    -- crisp on top of the wash.
    if self.fade_by and self.fade_by > 0 then
        local b  = self.border_size
        local iw = self.width  - 2 * b
        local ih = self.height - 2 * b
        if iw > 0 and ih > 0 then
            bb:lightenRect(x + b, y + b, iw, ih, self.fade_by)
        end
    end
    if self.radius and self.radius > 0 then
        local r       = self.radius
        local w, h    = self.width, self.height
        -- WHAT IS BEHIND THE CORNER, which for a long time could only be the
        -- page and so could only be white. Over a ground it is not: the four
        -- masked corners came out as white teeth on a dark shelf, and over a
        -- picture they punched holes in it (maintainer, on device).
        --
        -- `fill` tries the real thing first -- Wallpaper.restore puts the
        -- picture's own pixels back, and answers false when there is no image
        -- or the target is not the screen -- and otherwise paints a colour:
        -- the caller's bg_color if it set one (the selection ring matches its
        -- own backdrop), else the flat ground, else page white.
        --
        -- One call per corner ROW, not per pixel: the mask already emits a
        -- single strip per row, so this is ~4r calls per card and not 4r².
        local bg = self.bg_color
        if type(bg) == "nil" then bg = Blitbuffer.COLOR_WHITE end
        -- type(), never `== nil` or `or`, on anything that may hold a
        -- Blitbuffer colour: they are ffi cdata, and `a or b` on one is not
        -- the guard it looks like. paintRect indexes the colour it is handed,
        -- so a nil reaching it takes the whole shelf down mid-paint -- which
        -- is exactly what it did.
        local function fill(cx, cy, cw, colour)
            if not cw or cw <= 0 then return end
            local restorable = (type(colour) == "nil")
            -- The pixels that were there, when they were kept.
            if keep and restorable and keep:putRow(bb, cx, cy, cw) then return end
            local c = colour
            if type(c) == "nil" then c = bg end
            if type(c) == "nil" then c = Blitbuffer.COLOR_WHITE end
            bb:paintRect(cx, cy, cw, 1, c)
        end
        local r_sq    = r * r
        -- Resolve the shadow grey LIVE here, not from self.shadow_color
        -- (captured at build time). ShadowRect:paintTo also calls _shadowGray()
        -- live, so the enclosing shadow repaints with the current day/night
        -- grey on every paint. The corner mask captured its colour once at
        -- build, so after a day<->night switch (which repaints the card
        -- without rebuilding it) the masked BR corner kept the OLD grey while
        -- the surrounding shadow had the new one -- the mismatched corner
        -- artifact in night mode (issue #93). self.shadow_color stays as the
        -- "is this card shadowed?" flag + geometry gate; only the painted
        -- value is now live.
        local shadow_paint = self.shadow_color
        -- For each row dy in [0, r), the arc test is monotonic in dx — there's
        -- exactly one transition from "outside arc" (paint) to "inside arc"
        -- (skip). We binary-search-equivalent it with a forward scan and emit
        -- a single paintRect strip per corner-row instead of r per-pixel
        -- setPixel calls. Cost drops from 4·r² FFI calls to ~4·r.
        --
        -- TL/TR/BL corners are guaranteed to lie outside the enclosing
        -- shadow (their pixels have either px < shadow_offset_x or
        -- py < shadow_offset_y), so they paint pure bg. BR can intersect
        -- the shadow's painted area; it falls back to per-pixel.
        for dy = 0, r - 1 do
            -- Top half (dy small): arc center is at (r, r). cutoff_top is the
            -- smallest dx such that (dx-r)² + (dy-r)² ≤ r² — i.e. inside arc.
            -- Pixels [0, cutoff_top) are outside.
            local cutoff_top = 0
            local dy_top_sq = (dy - r) * (dy - r)
            while cutoff_top < r and (cutoff_top - r) * (cutoff_top - r) + dy_top_sq > r_sq do
                cutoff_top = cutoff_top + 1
            end
            if cutoff_top > 0 then
                fill(x, y + dy, cutoff_top)                  -- TL
                fill(x + w - cutoff_top, y + dy, cutoff_top)  -- TR
            end
            -- Bottom half (dy near h): arc center same, but our local dy
            -- iterator runs 0..r-1 while the actual row is h-r+dy. The arc
            -- test for BL at row (h-r+dy) is (dx-r)² + dy² > r².
            local cutoff_bot = 0
            local dy_bot_sq = dy * dy
            while cutoff_bot < r and (cutoff_bot - r) * (cutoff_bot - r) + dy_bot_sq > r_sq do
                cutoff_bot = cutoff_bot + 1
            end
            if cutoff_bot > 0 then
                fill(x, y + h - r + dy, cutoff_bot)          -- BL
                -- BR may overlap the enclosing shadow, so it isn't a flat
                -- bg strip. #217: bb:setPixel always applies its own
                -- night-mode invert, whereas bb:paintRect (on Android) stays
                -- on the fast path that skips per-pixel inversion and relies
                -- on a single invert of the whole frame at blit time -- a
                -- per-pixel setPixel loop here double-inverts on Android,
                -- landing back on the raw, un-inverted color. Run-length
                -- encode the shadow/bg boundary instead and paint each run
                -- with paintRect so this corner gets the same single-invert
                -- treatment as the other three.
                if self.shadow_color then
                    local py = h - r + dy
                    local run_start, run_in_shadow
                    for dx = 0, cutoff_bot - 1 do
                        local px = w - cutoff_bot + dx
                        local in_shadow = self:_pixelInShadow(px, py)
                        if run_start == nil then
                            run_start, run_in_shadow = dx, in_shadow
                        elseif in_shadow ~= run_in_shadow then
                            fill(x + w - cutoff_bot + run_start, y + py,
                                 dx - run_start,
                                 run_in_shadow and shadow_paint or nil)
                            run_start, run_in_shadow = dx, in_shadow
                        end
                    end
                    if run_start then
                        fill(x + w - cutoff_bot + run_start, y + py,
                             cutoff_bot - run_start,
                             run_in_shadow and shadow_paint or nil)
                    end
                else
                    fill(x + w - cutoff_bot, y + h - r + dy, cutoff_bot)   -- BR
                end
            end
        end
    end
    if keep then keep:free() end
    if self.border_size and self.border_size > 0 then
        -- Honour the user's "Border color" setting when the SpineWidget
        -- doesn't set border_color explicitly. resolvedColors().border
        -- defaults to black + adapts to night mode + color panels per
        -- the day/night color split.
        local border_color = self.border_color
        border_color = border_color or Blitbuffer.COLOR_BLACK
        _paintColorSafeBorder(bb, x, y, self.width, self.height,
                              self.border_size, border_color, self.radius, true)
    end
end

local ShadowRect = Widget:extend{width=nil,height=nil,radius=0,color=nil}
function ShadowRect:init()
    self.dimen = Geom:new{w=self.width,h=self.height}
end
function ShadowRect:paintTo(bb,x,y)
    bb:paintRoundedRectRGB32(x,y,self.width,self.height,self.color,self.radius)
end

return {RoundedCornerCard=RoundedCornerCard,ShadowRect=ShadowRect}
