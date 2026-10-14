-- SPDX-License-Identifier: AGPL-3.0-only
local Margins = require("koobone.ui.vendor.bookshelf.grid_margins")
local Layout = {}

function Layout.compute(options)
    local width, height, scale = options.width, options.height, options.scale or 1
    local function px(value) return math.floor(value*scale+0.5) end
    local margin, gap, header_h, footer_h = math.min(px(16), math.floor(width*0.03)), px(12), px(44), px(44)
    local path_h = options.path and px(28) or 0
    local content_w = width-margin*2
    local columns = options.columns or (height >= width and 3 or 4)
    columns = math.max(1, math.min(columns, math.floor((content_w+gap)/(px(120)+gap))))
    local card_w = math.floor((content_w-gap*(columns-1))/columns)
    local card_h = math.floor(card_w/0.7)+px(44)
    local available_h = height-header_h-footer_h-path_h
    local rows = math.max(1, math.floor((available_h-gap)/(card_h+gap)))
    if options.rows then rows = math.min(rows, options.rows) end
    card_h = math.min(card_h, math.max(1, available_h-gap*2))
    local slack = math.max(0, available_h-rows*card_h-gap*(rows+1))
    local gaps = Margins.split{pad=gap, n_rows=rows, extra=slack, spread=true}
    local result = {columns=columns, rows=rows, card_w=card_w, card_h=card_h, slots={},
        header={x=0,y=0,w=width,h=header_h}, footer={x=0,y=height-footer_h,w=width,h=footer_h},
        path={x=margin,y=header_h,w=content_w,h=path_h}, margin=margin}
    for row=0, rows-1 do
        for column=0, columns-1 do
            result.slots[#result.slots+1] = {x=margin+column*(card_w+gap),
                y=header_h+path_h+gaps.top+row*(card_h+gaps.between),w=card_w,h=card_h}
        end
    end
    return result
end

return Layout
