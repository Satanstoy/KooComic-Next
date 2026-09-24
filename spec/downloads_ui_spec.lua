package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

local shown = {}
local Widget = {}
function Widget:new(options) return options or {} end

package.preload["ui/widget/buttondialog"] = function() return Widget end
package.preload["ui/widget/confirmbox"] = function() return Widget end
package.preload["ui/widget/infomessage"] = function() return Widget end
package.preload["ui/widget/menu"] = function() return Widget end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) shown[#shown + 1] = widget end,
        close = function() end,
    }
end
package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
end

local DownloadsUI = require("koobone.ui.downloads")

local records = {
    {
        key = "missing",
        value = { title = "Missing book", state = "complete" },
        info = {
            key = "missing",
            value = { title = "Missing book", state = "complete" },
            title = "Missing book",
            state = "missing",
            path = "/books/Missing book.epub",
            exists = false,
            size = 0,
            part_exists = false,
            part_size = 0,
        },
    },
    {
        key = "complete",
        value = { title = "Complete book", state = "complete" },
        info = {
            key = "complete",
            value = { title = "Complete book", state = "complete" },
            title = "Complete book",
            state = "complete",
            path = "/books/Complete book.epub",
            exists = true,
            size = 1024,
            part_exists = false,
            part_size = 0,
        },
    },
}
local storage = {
    records = function() return records end,
    recordInfo = function(_, row) return row.info end,
    maintenanceSummary = function()
        return { missing_records = 1, partial_files = 0, partial_bytes = 0 }
    end,
}
local downloader = {
    isActive = function() return false end,
    notifyChanged = function() end,
    open = function() end,
}

local menu = DownloadsUI.show(storage, downloader)
assert(menu ~= nil)
assert(menu.subtitle == "2 条记录")
assert(menu.item_table[1].text == "清理下载记录与临时文件")
assert(menu.item_table[2].mandatory == "文件已删除")
assert(menu.item_table[3].mandatory == "已完成　1.0 KB")

menu.item_table[2].callback()
local missing_dialog = shown[#shown]
assert(missing_dialog.buttons[1][1].text == "移除失效记录")

menu.item_table[3].callback()
local complete_dialog = shown[#shown]
assert(complete_dialog.buttons[1][1].text == "打开阅读")
assert(complete_dialog.buttons[2][1].text == "删除本地漫画")

print("downloads UI spec: OK")
