package.path = "./koocomic.koplugin/?.lua;" .. package.path
local shown, scheduled, recorded, transfers = {}, {}, 0, 0
local Widget = {}
function Widget:new(options) return options end
package.preload["socket"] = function() return { gettime = function() return 1 end } end
package.preload["ui/widget/confirmbox"] = function() return Widget end
package.preload["ui/widget/infomessage"] = function() return Widget end
local reader_called=false
package.preload["apps/reader/readerui"] = function() return {showReader=function() reader_called=true end} end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, w) shown[#shown + 1] = w end,
        scheduleIn = function(_, _, callback) scheduled[#scheduled + 1] = callback end,
    }
end
package.preload["koobone.ui.download_dialog"] = function()
    return { new = function()
        return { show = function() end, close = function() end, setStage = function() end,
            setProgress = function() end }
    end }
end
local Downloader = require("koobone.downloader")
local downloaded = true
local storage = {
    itemPath = function() return "/books/New name.epub" end,
    resolveLocalPath = function() if downloaded then return "/books/Old name.epub" end end,
    isDownloaded = function() return downloaded end,
    resolveDownloadPath = function() return nil, "conflict" end,
    record = function() recorded = recorded + 1 end,
}
local downloader = Downloader:new{ storage = storage, library = {}, api = {
    download = function() transfers = transfers + 1 end,
} }
local opened
downloader.open = function(_, path) opened = path end
downloader:download{ vol_name = "New name" }
shown[#shown].ok_callback()
assert(opened == "/books/Old name.epub", "existing-file shortcut must use the recorded path")
downloaded = false
downloader:download{ vol_name = "New name" }
assert(#scheduled == 0 and recorded == 0 and transfers == 0,
    "conflicting paths must be rejected before scheduling or changing records")
local guarded=Downloader:new{storage=storage,library={},api={},preprocess={isLocked=function() return true end}}
assert(guarded:open("/books/Old name.epub")==nil,"reading a file locked by preprocessing must be refused")
assert(not reader_called,"a processing lock must prevent opening the real reader")
assert(shown[#shown].text:find("处理",1,true),"blocked reading needs an explicit message")
storage.resolveDownloadPath=function() return "/books/New name.epub" end
local blocked=Downloader:new{storage=storage,library={},api={},coordinator={acquire=function() return nil end}}
blocked:download{vol_name="New name"}
assert(#scheduled==0 and recorded==0,"preprocessing resource contention must not change download state")
local enqueued,resumed=0,false
local batch=Downloader:new{storage=storage,library={},api={},service={
    isActive=function() return true end,
    preview=function() return {files=2,bytes=100,temporary_bytes=50,unknown=1,downloaded=1,duplicate=0,invalid=0,free=1000,account_id="one"} end,
    enqueue=function(_,items,account) assert(#items==2 and account=="one");enqueued=2;return {added=2} end,
    resume=function() resumed=true;return true end,account=function() return "one" end}}
assert(type(batch.enqueue)=="function","production facade lacks confirmed batch enqueue")
assert(batch:isActive())
batch:enqueue({{file_md5="a"},{file_md5="b"}})
assert(enqueued==0 and shown[#shown].ok_callback and shown[#shown].text:find("未知大小",1,true))
assert(not shown[#shown].text:find("暂存最多",1,true),"unknown sizes cannot promise a maximum staging size")
shown[#shown].ok_callback()
assert(enqueued==2 and resumed and transfers==0,"new downloads must use the isolated queue service, not legacy synchronous IO")
require("koobone.runtime_guard").block()
reader_called=false
assert(not Downloader.open(downloader,"/books/old.epub") and not reader_called,"old reader callbacks must not open files after a code switch")
print("downloader path spec: OK")
