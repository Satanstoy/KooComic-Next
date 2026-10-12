package.path = "./koocomic.koplugin/?.lua;" .. package.path
local function widget() return {new=function(_, fields) return fields end} end
for _, name in ipairs({"buttondialog","infomessage","menu","multiinputdialog"}) do
    package.preload["ui/widget/"..name] = widget
end
package.preload["socket"] = function() return {gettime=os.time} end
local shown
package.preload["ui/uimanager"] = function() return {show=function(_,widget) shown=widget end,close=function() end} end
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
print("shelf controller spec: OK")
