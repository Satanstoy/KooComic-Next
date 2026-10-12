-- Run from an official Linux KOReader runtime, not the repository root.
-- ./luajit /absolute/checkout/scripts/render_shelf.lua CHECKOUT OUTPUT WIDTH HEIGHT MODE
require("setupkoenv")
local root, output = assert(arg[1]), assert(arg[2])
local width, height = tonumber(arg[3]) or 600, tonumber(arg[4]) or 800
local mode = arg[5] or "series"
package.path = root.."/koocomic.koplugin/?.lua;"..package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):wrap{
    sdl_window={width=width,height=height},dev_no_c_blitter=false,
}
local Device = require("device")
require("document/canvascontext"):init(Device)
local BB = require("ffi/blitbuffer")
local Grid = require("koobone.ui.bookshelf_grid")
local books = {}
for index=1, 8 do
    local item = {vol_name="示例漫画 "..index,vol_id=index,file_md5="sample"..index}
    if mode == "series" then
        item._series = {title=item.vol_name,volume_count=index+2,downloaded_count=index%3}
    end
    books[#books+1] = item
end
local view = Grid.show{books=books,mode=mode,ui={text_size="normal"},
    path_label=mode=="series" and "" or "示例系列",
    storage={isDownloaded=function() return false end,partSize=function() return 0 end}}
local buffer = BB.new(Device.screen:getWidth(),Device.screen:getHeight(),BB.TYPE_BBRGB32)
buffer:fill(BB.COLOR_WHITE)
view:paintTo(buffer,0,0)
local written = buffer:writeToFile(output,"png")
assert(written, "shelf screenshot failed")
print("Rendered actual KOReader shelf: "..output)
buffer:free()
view:_close()
Device:exit()
