require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local width,height=tonumber(arg[2]) or 600,tonumber(arg[3]) or 800
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local books={}
for index=1,60 do books[index]={file_md5="generated-"..index,vol_name=index==1 and "Unique needle" or "Original "..index,
    vol_series="Generated Series",vol_author="Generated"} end
local controller=require("koobone.ui.bookshelf"):new{library={items=books},downloader={},
    storage={isDownloaded=function() return false end,partSize=function() return 0 end},
    settings={account=function() return {uin="fixture"} end,ui=function() return {text_size="large"} end}}
local view=controller:show(books)
view.options.on_view("volumes");assert(view:_changePage(5))
local function search(query,clear)
    controller:showSearch()
    local dialog
    for _,window in ipairs(UI._window_stack) do if window.widget.input_fields then dialog=window.widget end end
    assert(dialog,"real search dialog must open")
    if clear then dialog.buttons[1][1].callback()
    else dialog.input_fields[1]:setText(query);dialog.buttons[1][3].callback() end
end
search("Unique needle")
assert(view.page==1 and #view.options.books==1 and view.options.path_label:find("1 项",1,true))
search("",true)
assert(view.page==5 and controller.navigation.page==5 and #view.options.books==60)
view.options.on_view("series");view.options.on_select(view.options.books[1])
assert(controller.navigation.series and view.page==1)
view:onShelfSwipe(nil,{direction="east",pos={x=width/2,y=height/2}})
assert(controller.navigation.series,"content swipe at first page must not also return")
view.options.on_hold(view.options.books[1])
view:onShelfSwipe(nil,{direction="east",pos={x=1,y=height/2}})
assert(controller.navigation.series and not controller.selection.active,"edge back must cancel selection first")
assert(view:_changePage(5));search("Unique needle")
assert(view.options.path_label:find("Generated Series",1,true) and view.options.path_label:find("Unique needle",1,true))
search("",true);assert(view.page==5)
view:onShelfSwipe(nil,{direction="east",pos={x=1,y=height/2}})
assert(not controller.navigation.series and view.page==1,"edge return must restore parent state, not page backward")
search("Unique needle");view.options.on_select(view.options.books[1])
controller:show({{file_md5="foreign",vol_name="Other",vol_series="Other Series"}})
assert(controller.query=="Unique needle" and #view.options.books==0 and view.options.path_label:find("0 项",1,true))
view:_close();assert(#UI._window_stack==0)
Device:exit()
print("KOReader actual search/edge/page/selection navigation: OK "..width.."x"..height)
