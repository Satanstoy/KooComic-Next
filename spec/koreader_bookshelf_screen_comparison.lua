-- Five actual screens, with upstream hero collapsed, using the same generated EPUB covers.
require("setupkoenv")
local root,reference,directory=assert(arg[1]),assert(arg[2]),assert(arg[3])
local width,height=tonumber(arg[4]) or 600,tonumber(arg[5]) or 800
local role=arg[6] or "final"
package.path=root.."/koocomic.koplugin/?.lua;"..reference.."/?.lua;plugins/coverbrowser.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local BB=require("ffi/blitbuffer")
local UI=require("ui/uimanager")
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
local books_dir=directory.."/books";assert(files:mkdir(books_dir));G_reader_settings:saveSetting("home_dir",books_dir)
local cover_path=directory.."/same-cover.png"
local cover=BB.new(120,180,BB.TYPE_BBRGB32);cover:fill(BB.COLOR_WHITE)
cover:paintRectRGB32(8,8,104,72,BB.colorFromString("#38836c"));cover:paintRectRGB32(8,88,104,84,BB.colorFromString("#c2446a"))
assert(cover:writeToFile(cover_path,"png"));cover:free()
local handle=assert(io.open(cover_path,"rb"));local png=handle:read("*a");handle:close()
local BIM=require("bookinfomanager")
local items={}
for index=1,8 do
    local title="Same Original Volume "..index
    local path=books_dir.."/"..title..".epub"
    if not files:exists(path) then
        local writer=require("ffi/archiver").Writer:new();assert(writer:open(path,"zip"))
        for _,entry in ipairs({{"mimetype","application/epub+zip"},
            {"META-INF/container.xml",'<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'},
            {"content.opf",'<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>'..title..'</dc:title><dc:creator>Fixture</dc:creator><dc:identifier id="id">generated-'..index..'</dc:identifier><dc:language>en</dc:language><meta name="cover" content="cover"/><meta name="calibre:series" content="Same Original Series"/><meta name="calibre:series_index" content="'..index..'"/></metadata><manifest><item id="cover" href="cover.png" media-type="image/png"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>'},
            {"cover.png",png},{"chapter.xhtml",'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>'..title..'</title></head><body><img src="cover.png"/></body></html>'}}) do
            assert(writer:addFileFromMemory(entry[1],entry[2]))
        end
        writer:close()
    end
    BIM:extractBookInfo(path,{max_cover_w=240,max_cover_h=360})
    items[index]={file_md5=tostring(index),vol_name=title,vol_series="Same Original Series",_koobone_cover_path=cover_path}
end
local Settings=require("lib/bookshelf_settings_store")
require("lib/bookshelf_fonts").setUIFontFace(nil)
Settings.save("home_expanded",true);Settings.save("active_chip","series")
Settings.save("font_scale",100);Settings.save("stack_label_font_scale",100)
Settings.save("bookshelf_columns",height>=width and 3 or 4)
local Tabs=require("lib/bookshelf_tab_model")
local tabs=Tabs.load()
for _,tab in ipairs(tabs) do tab.view_mode="covers";if tab.id=="series" then tab.group_display="divider" end end
Tabs.save(tabs)
local Repo=require("lib/bookshelf_book_repository");Repo.invalidateAllCache()
local groups=Repo.getSeriesGroups(50,0)
assert(#groups==1 and groups[1].series_name=="Same Original Series","actual upstream metadata must resolve the same series")
local upstream=require("lib/bookshelf_widget"):new{}
UI:show(upstream)
local Grid=require("koobone.ui.bookshelf_grid")
local storage={isDownloaded=function() return true end,partSize=function() return 0 end}
local function paint(widget,name)
    local canvas=BB.new(width,height,BB.TYPE_BBRGB32);canvas:fill(BB.COLOR_WHITE);widget:paintTo(canvas,0,0)
    local ink,green,pink=0,0,0
    for y=0,height-1,12 do for x=0,width-1,12 do
        local pixel=canvas:getPixel(x,y)
        if pixel:getColor8().a<240 then ink=ink+1 end
        local rgb=pixel:getColorRGB32()
        if rgb.r==56 and rgb.g==131 and rgb.b==108 then green=green+1 end
        if rgb.r==194 and rgb.g==68 and rgb.b==106 then pink=pink+1 end
    end end
    assert(ink>30,"comparison screen must render actual content")
    assert(green>10 and (name:match("%-series$") or pink>10),
        "same generated cover must appear (folder may intentionally cover its lower half): "..name.." "..green.."/"..pink)
    assert(canvas:writeToFile(directory.."/"..width.."x"..height.."-"..name..".png","png"));canvas:free()
end
for _,state in ipairs({"series","inside-series","volumes","search","selected"}) do
    upstream:_drillBackTo(0)
    upstream:_selectChip((state=="series" or state=="inside-series") and "series" or "all")
    if state=="inside-series" then upstream:_drillInto{kind="series",label="Same Original Series",payload=groups[1]} end
    if state=="search" then upstream:_searchAndDrill("Volume 1") end
    if state=="selected" then
        upstream._selection:enterMode();upstream._selection:add(books_dir.."/Same Original Volume 1.epub");upstream:_rebuild()
    end
    paint(upstream,"target-"..state)
    local shown=state=="series" and {{vol_name="Same Original Series",_koobone_cover_path=cover_path,_series={books=items,volume_count=8,downloaded_count=8}}} or
        state=="search" and {items[1]} or items
    local shelf=Grid.show{books=shown,mode=state=="series" and "series" or "volumes",storage=storage,
        ui={text_size="normal",series_style="divider"},path_label=state=="inside-series" and "Same Original Series" or
            state=="search" and "搜索：Volume 1 · 1 项" or nil,selection_active=state=="selected",selected_count=1,
        is_selected=function(item) return state=="selected" and item.file_md5=="1" end}
    paint(shelf,role.."-"..state);shelf:_close()
    if upstream._selection:isActive() then upstream._selection:exitMode();upstream:_rebuild() end
end
UI:close(upstream);Device:exit()
print("Actual Bookshelf / "..role.." five-state screens: OK "..width.."x"..height.." "..directory)
