package.path = "./koocomic.koplugin/?.lua;" .. package.path
local shown, opened = {}, nil
local Widget = {}
function Widget:new(options)
    options.close = function() end
    return options
end
package.preload["socket"] = function() return {} end
package.preload["ui/widget/confirmbox"] = function() return Widget end
package.preload["ui/widget/infomessage"] = function() return Widget end
package.preload["koobone.ui.info_panel"] = function() return Widget end
package.preload["ui/uimanager"] = function()
    return { show = function(_, widget) shown[#shown + 1] = widget end }
end
local BookDetail = require("koobone.ui.book_detail")
local storage = {
    isDownloaded = function() return true end,
    resolveLocalPath = function() return "/books/Original title.epub", "downloaded" end,
    itemPath = function() return "/books/New title.epub" end,
    partSize = function() return 0 end,
    fileSize = function() return 100 end,
}
local downloader = {
    open = function(_, path) opened = path end,
    isActive = function() return false end,
}
local dialog = BookDetail.show{
    item = { vol_name = "New title" }, storage = storage, downloader = downloader,
}
dialog.buttons[1][2].callback()
assert(opened == "/books/Original title.epub", "detail must open the recorded file path")
opened = nil
storage.resolveLocalPath = function() return nil, "missing" end
dialog.buttons[1][2].callback()
assert(opened == nil, "a file removed after rendering must not be opened")
print("book detail spec: OK")
