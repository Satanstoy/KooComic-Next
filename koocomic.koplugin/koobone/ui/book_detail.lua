local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local InfoPanel = require("koobone.ui.info_panel")
local Util = require("koobone.util")

local BookDetail = {}

function BookDetail.show(options)
    local item = assert(options.item, "item required")
    local storage = assert(options.storage, "storage required")
    local downloader = assert(options.downloader, "downloader required")
    local downloaded = storage:isDownloaded(item)
    local partial = storage:partSize(item)
    local title = item.vol_name or item.vol_series or "未命名漫画"
    local author = item.vol_author or "未知作者"
    local progress = tostring(item.last_readpage or 0) .. " / " .. tostring(item.count_page or "?")
    local local_state = downloaded and "已下载" or
        (partial > 0 and ("有临时文件 " .. Util.friendlySize(partial)) or "未下载")
    local description = table.concat({
        "文件：" .. Util.friendlySize(item.file_size),
        "KOOBONE 进度：" .. progress,
        "本地状态：" .. local_state,
    }, "\n")

    local dialog
    local action_text = downloaded and "打开阅读" or (partial > 0 and "重新下载" or "下载")
    local buttons = {
        {
            {
                text = "关闭",
                callback = function() dialog:close() end,
            },
            {
                text = action_text,
                callback = function()
                    dialog:close()
                    if downloaded then
                        local path = storage:resolveLocalPath(item)
                        if path then
                            downloader:open(path)
                        else
                            UIManager:show(InfoMessage:new{ text = "本地文件已丢失或路径不可用，请刷新书库。" })
                        end
                    else
                        downloader:download(item)
                    end
                end,
            },
        },
    }
    local function changed()
        if options.on_changed then
            options.on_changed()
        elseif downloader.notifyChanged then
            downloader:notifyChanged()
        end
    end
    if downloaded then
        if options.preprocess then
            local service=options.preprocess
            local path=storage:resolveLocalPath(item)
            local function perform()
                if not service.available then UIManager:show(InfoMessage:new{text=tostring(service.reason)});return end
                UIManager:show(ConfirmBox:new{
                    text="处理这本漫画的彩纹？成功后直接覆盖原 EPUB，不保留原版备份，不能撤销。".."\n\n"..title,
                    ok_text="开始处理",
                    ok_callback=function()
                        local ok,err
                        ok,err=service:submit(item)
                        if ok then ok,err=service:resume() end
                        if not ok then UIManager:show(InfoMessage:new{text=tostring(err or "处理不可用")})
                        else dialog:close();changed() end
                    end,
                })
            end
            buttons[#buttons+1]={{text="去彩纹处理",enabled=service.available and not service:isLocked(path),
                callback=perform}}
        end
        buttons[#buttons + 1] = {
            {
                text = "删除本地漫画",
                callback = function()
                    if downloader:isActive() then
                        UIManager:show(InfoMessage:new{ text = "请等待当前下载任务结束后再删除。" })
                        return
                    end
                    local path = storage:resolveLocalPath(item)
                    if not path then
                        UIManager:show(InfoMessage:new{ text = "本地文件已丢失或路径不可用，请刷新书库。" })
                        return
                    end
                    local size = storage:fileSize(path)
                    UIManager:show(ConfirmBox:new{
                        text = table.concat({
                            "确定删除 Kindle 上的本地漫画吗？",
                            "",
                            title,
                            Util.friendlySize(size),
                            path,
                            options.preprocess and "同时清理这本漫画的内部原版备份（如有）。" or "",
                            "",
                            "不会删除 KOOBONE 云端书库中的漫画或阅读记录。",
                        }, "\n"),
                        cancel_text = "取消",
                        ok_text = "删除本地漫画",
                        ok_callback = function()
                            local ok, result = storage:deleteItem(item)
                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = "删除失败：\n" .. tostring(result),
                                })
                                return
                            end
                            dialog:close()
                            changed()
                            UIManager:show(InfoMessage:new{
                                text = "已删除本地漫画，释放 " .. Util.friendlySize(result) .. "。",
                            })
                        end,
                    })
                end,
            },
        }
    elseif partial > 0 then
        buttons[#buttons + 1] = {
            {
                text = "删除临时文件",
                callback = function()
                    if downloader:isActive() then
                        UIManager:show(InfoMessage:new{ text = "请等待当前下载任务结束后再清理。" })
                        return
                    end
                    UIManager:show(ConfirmBox:new{
                        text = "确定删除这本漫画的未完成临时文件吗？\n\n" ..
                            title .. "\n" .. Util.friendlySize(partial),
                        cancel_text = "取消",
                        ok_text = "删除临时文件",
                        ok_callback = function()
                            local ok, result = storage:deletePartialItem(item)
                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = "清理失败：\n" .. tostring(result),
                                })
                                return
                            end
                            dialog:close()
                            changed()
                            UIManager:show(InfoMessage:new{
                                text = "已删除临时文件，释放 " .. Util.friendlySize(result) .. "。",
                            })
                        end,
                    })
                end,
            },
        }
    end
    dialog = InfoPanel:new{
        title = title,
        subtitle = author,
        body = description,
        text_size = (options.settings and options.settings:ui().text_size) or "large",
        buttons = buttons,
    }
    UIManager:show(dialog)
    return dialog
end

return BookDetail
