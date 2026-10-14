-- Guards the end-to-end path "change rows/columns -> current shelf re-layouts".
-- Runs on the real KOReader widget stack so the controller/grid wiring is
-- exercised, not just an isolated grid.
require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local Bookshelf=require("koobone.ui.bookshelf")

local ui={portrait_columns=3,portrait_rows=2,landscape_columns=4,landscape_rows=2,text_size="large",series_style="divider"}
local settings={account=function() return {uin="42",nick="Tester"} end,ui=function() return ui end}
local books={}
for index=1,24 do
    books[index]={vol_id=index,file_md5="m"..index,vol_name="Book "..index,vol_series="S"..index,vol_author="A"}
end
local storage={isDownloaded=function() return false end,partSize=function() return 0 end,
    resolveLocalPath=function() return nil end,isSafeLocalPath=function() return false end}
local shelf=Bookshelf:new{library={items=books},storage=storage,downloader={enqueue=function() end},settings=settings}
shelf:show(books)
local first=shelf.grid_view
assert(first and first.perpage==6,"the default portrait 3x2 shelf must show 6 cards, got "..tostring(first and first.perpage))

-- Exactly what SettingsUI's on_ui_changed does after the user cycles the rows.
ui.portrait_columns=2;ui.portrait_rows=1
shelf:show(books)
assert(shelf.grid_view==first,"the live grid must be reused, not rebuilt from scratch")
assert(first.perpage==2,"2 columns x 1 row must reduce the visible count on the current shelf, got "..first.perpage)

ui.portrait_columns=4;ui.portrait_rows=2
shelf:show(books)
assert(first.perpage>=6,"a wider grid must raise the visible count again, got "..first.perpage)
assert(first.pages==math.max(1,math.ceil(#first.options.books/first.perpage)),"the page count must follow the new per-page size")

first:_close()
Device:exit()
print("KOReader shelf rows/columns live update: OK")
