package.path = "./koocomic.koplugin/?.lua;" .. package.path
local shown, scheduled, recorded, transfers = {}, {}, 0, 0
local Widget = {}
function Widget:new(options) return options end
package.preload["socket"] = function() return { gettime = function() return 1 end } end
package.preload["ui/widget/confirmbox"] = function() return Widget end
package.preload["ui/widget/infomessage"] = function() return Widget end
package.preload["apps/reader/readerui"] = function() return {} end
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
print("downloader path spec: OK")
