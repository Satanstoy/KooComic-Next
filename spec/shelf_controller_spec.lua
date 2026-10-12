package.path = "./koocomic.koplugin/?.lua;" .. package.path
local function widget() return {new=function(_, fields) return fields end} end
for _, name in ipairs({"buttondialog","infomessage","menu","multiinputdialog","confirmbox"}) do
    package.preload["ui/widget/"..name] = widget
end
package.preload["socket"] = function() return {gettime=os.time} end
local shown,callbacks=nil,{}
package.preload["ui/uimanager"] = function() return {show=function(_,widget) shown=widget end,close=function() end,
    scheduleIn=function(_,delay,callback) callbacks[#callbacks+1]=callback end} end
package.preload["koobone.ui.book_detail"] = function() return {show=function() end} end
local current
package.preload["koobone.ui.bookshelf_grid"] = function()
    return {show=function(options)
        current = options
        return {update=function(_, changed) current=changed end, closed=false}
    end}
end
local Bookshelf = require("koobone.ui.bookshelf")
local shelf = Bookshelf:new{library={items={}},storage={isDownloaded=function() return false end},downloader={},
    settings={account=function() return {uin="42"} end, ui=function() return {} end}}
local books = {
    {vol_id=1,file_md5="a",vol_name="Original 1",vol_series="Series",vol_author="Author"},
    {vol_id=2,file_md5="b",vol_name="Original 2",vol_series="Series",vol_author="Author"},
}
shelf:show(books)
assert(current.mode == "series" and #current.books == 1, "production controller still shows a flat shelf")
assert(type(current.on_menu) == "function" and type(current.on_view) == "function")
current.on_select(current.books[1])
assert(#current.books == 2 and current.path_label == "Series")
assert(current.on_back())
assert(#current.books == 1 and current.path_label == "")
current.on_view("volumes")
assert(#current.books == 2 and current.mode == "volumes")
assert(books[1].vol_name == "Original 1")
current.on_view("series")
local recent = {
    {vol_id=3,file_md5="c",vol_name="Z",vol_series="Z",vol_author="Author"},
    {vol_id=4,file_md5="d",vol_name="A",vol_series="A",vol_author="Author"},
}
shelf:show(recent)
assert(current.books[1]._series.title=="Z")
shelf:showSort()
shown.buttons[2][1].callback()
assert(current.books[1]._series.title=="A", "actual title-sort command must update the root series view")
local ui={series_style="collage"}
shelf.settings.ui=function() return ui end
local fetched={}
shelf.cover_cache={url=function() return "fixture" end,fetch=function() error("HTTP on UI thread") end,
    fetchAsync=function(_,item,done) fetched[#fetched+1]=item;done("cached");return {cancel=function() return true end} end}
shelf.grid_view.refreshCovers=function() end
local members={}
for index=1,9 do members[index]={file_md5=tostring(index)} end
shelf:_prefetchCovers({{_series={books=members}}})
for _=1,20 do if #callbacks==0 then break end;table.remove(callbacks,1)() end
assert(#fetched==4 and fetched[1]==members[1] and fetched[4]==members[4],"collage must fetch four visible members, not an unbounded series")
ui.series_style="text";fetched={}
shelf:_prefetchCovers({{_series={books=members}}})
assert(#callbacks==0,"text style must not schedule artwork downloads")
shelf.cover_cache=nil
shelf:show(books)
current.on_view("volumes")
assert(type(current.on_hold)=="function","holding a volume must enter actual multi-selection")
current.on_hold(books[1])
assert(current.selection_active and current.selected_count==1 and current.is_selected(books[1]))
current.on_select(books[2])
assert(current.selected_count==2)
current.on_back()
assert(not current.selection_active,"Back should cancel selection before leaving the view")
current.on_view("series")
current.on_hold(current.books[1])
assert(shown.title=="Series" and not current.selection_active,"holding a series must show actions, not select every volume")
local deleted=0
shelf.local_manager={preview=function(_,items) assert(#items==2);return {
    files=2,bytes=30,skipped=0,entries={{title="A"},{title="B"}}} end,
    execute=function(_,preview,done,guard)
        assert(guard());deleted=preview.files
        done({success=2,failed=0,files_removed=2,bytes=30,errors={}});return true
    end}
shown.buttons[2][1].callback()
assert(shown.ok_callback and deleted==0,"series delete must preview and require explicit confirmation")
shown.ok_callback()
assert(deleted==2 and shown.text:find("删除 2 个阅读文件",1,true),"actual series action must execute and show a result")
local queued
shelf.downloader.enqueue=function(_,items) queued=items end
current.on_view("series");current.on_hold(current.books[1])
local download_action
for _,row in ipairs(shown.buttons) do for _,button in ipairs(row) do
    if button.text=="下载系列未下载卷" then download_action=button end
end end
assert(download_action,"series actions must expose real batch enqueue")
download_action.callback();assert(#queued==2)
current.on_view("volumes");current.on_hold(books[1]);current.on_select(books[2])
assert(type(current.on_selection_download)=="function")
current.on_selection_download();assert(#queued==2 and queued[1].file_md5=="a")
print("shelf controller spec: OK")
