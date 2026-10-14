require("setupkoenv")
local root,reference,order=assert(arg[1]),assert(arg[2]),assert(arg[3])
package.path=root.."/koocomic.koplugin/?.lua;"..reference.."/?.lua;plugins/coverbrowser.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false,start_with="filemanager"}
local Device=require("device");require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local ffi=require("ffi")
local directory="/tmp/koocomic-coexist-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}}
assert(files:mkdir(directory));G_reader_settings:saveSetting("home_dir",directory)
local path=directory.."/Generated Original.epub"
local writer=require("ffi/archiver").Writer:new();assert(writer:open(path,"zip"))
for _,entry in ipairs({{"mimetype","application/epub+zip"},
    {"META-INF/container.xml",'<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'},
    {"content.opf",'<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Generated Original</dc:title><dc:identifier id="id">generated</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>'},
    {"chapter.xhtml",'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Generated</title></head><body><h1>Generated Original</h1><p>Offline interoperability fixture.</p></body></html>'}}) do
    assert(writer:addFileFromMemory(entry[1],entry[2]))
end
writer:close()
local registry={}
local host={menu={registerToMainMenu=function(_,plugin) registry[plugin.name]=plugin end}}
local original_path=package.path
local function start(name)
    local plugin=dofile((name=="bookshelf" and reference or root.."/koocomic.koplugin").."/main.lua")
    return plugin:new{ui=host,path=name=="bookshelf" and reference or root.."/koocomic.koplugin"}
end
if order=="bookshelf-first" then start("bookshelf");start("koocomic") else start("koocomic");start("bookshelf") end
assert(registry.bookshelf and registry.koocomic and package.path==original_path)
local comic=registry.koocomic
comic.settings.data.download.directory=directory
local item={file_md5="generated",vol_name="Generated Original",file_type="epub"}
assert(comic.storage:record(item,"complete"));assert(comic.storage:isDownloaded(item))
local Repo=require("lib/bookshelf_book_repository")
Repo.invalidateWalkCache()
local scanned,total=Repo.getAll(directory,50,0,{{key="title",reverse=false}})
local found=false;for _,book in ipairs(scanned) do if book.filepath==path then found=true end end
assert(found and total==1,"real Bookshelf scanner must see original KooComic file, not a derived duplicate")
local document=assert(require("document/documentregistry"):openDocument(path))
assert(document:loadDocument(),"generated EPUB must load in provider "..tostring(document.provider))
document:render();assert(document:getPageCount()>0);document:close()
local second={file_md5="second",vol_name="Generated Second",file_type="epub"}
local second_path=comic.storage:itemPath(second)
assert(files:copy(path,second_path));assert(comic.storage:record(second,"complete"))
assert(comic.storage:deleteRecordFiles(comic.storage:itemKey(item)))
Repo.invalidateWalkCache();scanned,total=Repo.getAll(directory,50,0,{{key="title",reverse=false}})
assert(total==1 and not comic.storage:isDownloaded(item),"KooComic deletion must disappear from real Bookshelf disk refresh")
local Settings=require("lib/bookshelf_settings_store")
Settings.save("active_chip","all")
registry.bookshelf:show()
local shelf=registry.bookshelf._widget
assert(shelf and shelf._selection and UI:isWidgetShown(shelf),"actual Bookshelf widget must open alongside KooComic")
shelf._selection:enterMode();shelf._selection:add(second_path)
require("lib/bookshelf_bulk_actions").show{selection=shelf._selection,bw=shelf}
local delete
for _,window in ipairs(UI._window_stack) do
    for _,row in ipairs(window.widget.buttons or {}) do
        for _,button in ipairs(row) do if button.text and button.text:find("Delete",1,true) then delete=button end end
    end
end
assert(delete);delete.callback()
local confirmation
for _,window in ipairs(UI._window_stack) do
    if window.widget.ok_callback and (window.widget.text or ""):find("Delete",1,true) then confirmation=window.widget end
end
assert(confirmation.ok_callback);confirmation.ok_callback();UI:close(confirmation)
assert(not comic.storage:isDownloaded(second),"real Bookshelf delete must update KooComic's actual disk status")
Settings.save("koocomic_isolation_fixture",true)
assert(comic.settings.data.koocomic_isolation_fixture==nil)
local menu={};registry.bookshelf:addToMainMenu(menu);registry.koocomic:addToMainMenu(menu)
assert(menu.koocomic and menu.bookshelf_toggle,"menu keys must coexist")
for index=#UI._window_stack,1,-1 do UI:close(UI._window_stack[index].widget) end
if registry.bookshelf.onCloseWidget then registry.bookshelf:onCloseWidget() end
comic.download_service:pause();comic.preprocess:pause()
assert(not comic.download_service:isActive() and not comic.preprocess:isActive())
Device:exit()
print("KOReader actual Bookshelf coexistence/scan/read/delete: OK "..order)
