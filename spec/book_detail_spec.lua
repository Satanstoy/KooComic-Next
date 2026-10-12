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
storage.resolveLocalPath=function() return "/books/Original title.epub" end
local submitted=0
dialog=BookDetail.show{item={vol_name="New title"},storage=storage,downloader=downloader,
    preprocess={available=true,submit=function() submitted=submitted+1;return true end,
        resume=function() return true end,record=function() return nil end,isLocked=function() return false end}}
local optimize
for _, row in ipairs(dialog.buttons) do for _, button in ipairs(row) do
    if button.text=="去彩纹处理" then optimize=button end
end end
assert(optimize,"downloaded comics need a real preprocessing action in details")
optimize.callback()
assert(submitted==0,"processing must wait for user confirmation")
assert(shown[#shown].text:find("不保留原版备份",1,true),"processing confirmation must disclose irreversible replacement")
shown[#shown].ok_callback()
assert(submitted==1)
dialog=BookDetail.show{item={vol_name="Optimized"},storage=storage,downloader=downloader,
    preprocess={available=true,record=function() return {} end,isLocked=function() return false end}}
for _,row in ipairs(dialog.buttons) do for _,button in ipairs(row) do
    assert(button.text~="恢复原版","no-backup UI must not offer original restoration")
end end
print("book detail spec: OK")
