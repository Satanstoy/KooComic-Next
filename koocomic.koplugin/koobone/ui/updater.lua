local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DownloadDialog = require("koobone.ui.download_dialog")
local Util = require("koobone.util")
local Guard=require("koobone.runtime_guard")

local UpdaterUI = {}
UpdaterUI.__index = UpdaterUI

function UpdaterUI:new(options)
    return setmetatable({
        updater = assert(options.updater, "updater required"),
        downloader = assert(options.downloader, "downloader required"),
        on_changed = options.on_changed,
        preprocess=options.preprocess,
    }, self)
end

function UpdaterUI:_busy()
    return Guard.busy{downloader=self.downloader,preprocess=self.preprocess}
end

function UpdaterUI:rollback()
    if self:_busy() then UIManager:show(InfoMessage:new{text="下载或去彩纹任务正在运行，请完成后再回退插件。"});return end
    if not self.updater:canRollback() then UIManager:show(InfoMessage:new{text="没有可验证的插件备份。"});return end
    UIManager:show(ConfirmBox:new{text="回退上一版插件及更新前的设置？更新后的设置修改将丢失。漫画文件和去彩纹结果不会回退。",
        ok_text="回退插件",ok_callback=function()
            if self:_busy() then UIManager:show(InfoMessage:new{text="任务正在运行，未回退插件。"});return end
            local ok,err=self.updater:rollbackUpdate()
            if not ok then UIManager:show(InfoMessage:new{text="回退失败，备份已保留：\n"..tostring(err)});return end
            if self.on_changed then self.on_changed("rollback") end
            UIManager:show(ConfirmBox:new{text="旧插件和设置已恢复，必须重启 KOReader。",ok_text="立即重启",
                ok_callback=function() UIManager:restartKOReader() end})
        end})
end

function UpdaterUI:_releaseText(release)
    local rows = {
        "koo漫画 v" .. tostring(release.version) .. " 已发布",
        "当前版本：v" .. tostring(self.updater.current_version),
        "安装包：" .. Util.friendlySize(release.size),
    }
    if release.summary and release.summary ~= "" then rows[#rows + 1] = "\n" .. release.summary end
    if release.notes and release.notes ~= "" then rows[#rows + 1] = "\n" .. release.notes end
    return table.concat(rows, "\n")
end

function UpdaterUI:install(release)
    if self:_busy() then
        UIManager:show(InfoMessage:new{ text = "下载或去彩纹任务正在运行，请完成后再更新插件。" })
        return
    end
    local dialog = DownloadDialog:new{
        title = "更新 koo漫画到 v" .. tostring(release.version),
        hide_cancel = true,
    }
    dialog:show()
    UIManager:scheduleIn(0.15, function()
        if self:_busy() then dialog:close();UIManager:show(InfoMessage:new{text="任务正在运行，未更新插件。"});return end
        local ok, err = self.updater:install(release, function(state)
            dialog:setProgress{
                stage = state.stage,
                current = state.percent,
                total = 100,
            }
        end)
        dialog:close()
        if not ok then
            UIManager:show(InfoMessage:new{ text = "更新失败：\n" .. tostring(err) })
            return
        end
        if self.on_changed then self.on_changed("installed") end
        UIManager:show(ConfirmBox:new{
            text = "koo漫画 v" .. tostring(release.version) ..
                " 已安装。必须重启 KOReader 才能启用新版本。"..(err and "\n注意："..tostring(err) or ""),
            cancel_text = "稍后重启",
            ok_text = "立即重启",
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

function UpdaterUI:showAvailable(release, automatic)
    if automatic then self.updater:markPromptShown(release) end
    UIManager:show(ConfirmBox:new{
        text = self:_releaseText(release),
        cancel_text = "稍后更新",
        ok_text = "立即更新",
        cancel_callback = function()
            if automatic then
                self.updater:deferPrompt()
                if self.on_changed then self.on_changed() end
            end
        end,
        ok_callback = function() self:install(release) end,
        flush_events_on_show = true,
    })
end

function UpdaterUI:check(manual)
    if not self.updater:isConfigured() then
        if manual then
            UIManager:show(InfoMessage:new{
                text = "当前版本尚未配置 GitHub 发布地址。创建仓库后即可启用在线更新。",
            })
        end
        return
    end
    if manual then UIManager:show(InfoMessage:new{ text = "正在检查更新……", timeout = 1 }) end
    UIManager:scheduleIn(0.15, function()
        local release, has_update = self.updater:check()
        if not release then
            if manual then UIManager:show(InfoMessage:new{ text = "检查更新失败：\n" .. tostring(has_update) }) end
            return
        end
        if has_update then
            if manual or self.updater:shouldPrompt(release) then
                self:showAvailable(release, not manual)
            end
        elseif manual then
            UIManager:show(InfoMessage:new{
                text = "当前已是最新版本：v" .. tostring(self.updater.current_version),
            })
        end
    end)
end

return UpdaterUI
