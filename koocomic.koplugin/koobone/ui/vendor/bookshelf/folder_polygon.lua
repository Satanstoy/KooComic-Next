-- SPDX-License-Identifier: AGPL-3.0-only
-- Adapted from AndyHazz/bookshelf.koplugin lib/bookshelf_folder_card.lua,
-- commit 2c8bfd8e53b73b24232e674e12ebc6168963aef5. See UPSTREAM.md.
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local Device = require("device")
local Polygon = Widget:extend{}

function Polygon:init()
    self.dimen = Geom:new{w=self.width,h=self.height}
end

function Polygon:paintTo(bb, x, y)
    local w, h, tw, th = self.width, self.height, self.tab_w, self.tab_h
    local fill, edge, border = self.fill_color, self.edge_color, self.border or 1
    local radius = math.min(self.radius or 0, math.floor((h-th)/2))
    local tab_radius = math.min(self.radius or 0, th, math.floor(tw/2))
    local function fillRect(rx, ry, rw, rh) bb:paintRectRGB32(rx,ry,rw,rh,fill) end
    local function edgeRect(rx, ry, rw, rh) bb:paintRectRGB32(rx,ry,rw,rh,edge) end
    local function rounded(rx, ry, rw, rh, r)
        local suppress = Device.isAndroid and Device:isAndroid() and bb.getInverse and bb:getInverse() == 1
        if suppress then bb:setInverse(0) end
        bb:paintRoundedRectRGB32(rx,ry,rw,rh,fill,r)
        if edge then bb:paintBorderRGB32(rx,ry,rw,rh,border,edge,r,true) end
        if suppress then bb:setInverse(1) end
    end
    if tw > 0 and th > 0 then
        rounded(x,y,tw,th,tab_radius)
        local clear = math.max(tab_radius,border)
        if th > clear then
            fillRect(x,y+th-clear,tw,clear)
            if edge then
                edgeRect(x,y+th-clear,border,clear)
                edgeRect(x+tw-border,y+th-clear,border,clear)
            end
        end
    end
    if h > th then
        rounded(x,y+th,w,h-th,radius)
        fillRect(x,y+th,w,math.max(radius,border))
    end
    if edge then
        edgeRect(x+tw,y+th,w-tw,border)
        edgeRect(x,y+th,border,math.max(radius,border))
        edgeRect(x+w-border,y+th,border,math.max(radius,border))
    end
end

return Polygon
