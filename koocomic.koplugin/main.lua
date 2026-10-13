-- koo漫画 for KOReader
-- SPDX-License-Identifier: AGPL-3.0-only
--
-- The plugin only accesses the library of the account that signs in. Network
-- logs must never contain passwords, session cookies, or signed download URLs.

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local AccountUI = require("koobone.ui.account")
local Api = require("koobone.api")
local Auth = require("koobone.auth")
local Bookshelf = require("koobone.ui.bookshelf")
local CatalogProbe = require("koobone.catalog_probe")
local CatalogStore = require("koobone.catalog_store")
local CoverCache = require("koobone.cover_cache")
local Downloader = require("koobone.downloader")
local DownloadService = require("koobone.download_service")
local DownloadsUI = require("koobone.ui.downloads")
local Library = require("koobone.library")
local LoginDialog = require("koobone.ui.login_dialog")
local PluginVersion = require("koobone.plugin_version")
local PreprocessService = require("koobone.preprocess_service")
local PreprocessUI = require("koobone.ui.preprocess")
local Settings = require("koobone.settings")
local SettingsUI = require("koobone.ui.settings")
local Storage = require("koobone.storage")
local Updater = require("koobone.updater")
local UpdaterUI = require("koobone.ui.updater")
local RuntimeGuard=require("koobone.runtime_guard")

local KooComic = WidgetContainer:extend{
    name = "koocomic",
    is_doc_only = false,
    version = PluginVersion.version,
    settings_file = DataStorage:getSettingsDir() .. "/koocomic.lua",
    legacy_settings_file = DataStorage:getSettingsDir() .. "/koobone.lua",
}

function KooComic:init()
    math.randomseed(os.time())
    self.settings = Settings:new(self.settings_file, self.legacy_settings_file)
    self.api = Api:new(self.settings)
    self.auth = Auth:new(self.settings, self.api)
    self.storage = Storage:new(self.settings)
    self.cover_cache = CoverCache:new(self.api)
    self.library = Library:new(self.api, self.storage,{store=CatalogStore:new{
        directory=DataStorage:getSettingsDir().."/koocomic-catalog"},account=function() return self.settings:account().uin end})
    self.preprocess = PreprocessService:get{storage=self.storage,
        profile_provider=function() return self.settings.data.preprocess end,
        on_batch=function(result)
            UIManager:show(InfoMessage:new{text=string.format("去彩纹完成 %d，已优化跳过 %d，失败 %d，取消 %d，其他跳过 %d。",
                result.completed,result.optimized,result.failed,result.cancelled,result.skipped)})
        end,
        directory=DataStorage:getSettingsDir().."/koocomic-preprocess"}
    self.storage.preprocess = self.preprocess
    self.download_service=DownloadService:new{settings=self.settings,api=self.api,library=self.library,storage=self.storage,
        coordinator=self.preprocess.coordinator,directory=DataStorage:getSettingsDir().."/koocomic-downloads",
        on_changed=function()
            if self.bookshelf and self.bookshelf.menu and #self.library.items>0 then self.bookshelf:show(self.library.items) end
        end,
        on_batch=function(result)
            UIManager:show(InfoMessage:new{text=string.format("下载完成 %d，失败 %d，取消 %d，跳过 %d。\n已保存 %s，需核对 %d 项。",
                result.completed,result.failed,result.cancelled,result.skipped,require("koobone.util").friendlySize(result.bytes),result.warnings)})
        end}
    self.downloader = Downloader:new{
        api = self.api,
        library = self.library,
        storage = self.storage,
        preprocess = self.preprocess,
        coordinator = self.preprocess.coordinator,
        service = self.download_service,
        run_when_online=function(callback) self:ensureOnline(callback) end,
        on_changed = function()
            if self.bookshelf and self.bookshelf.menu and #self.library.items > 0 then
                self.bookshelf:show(self.library.items)
            end
        end,
    }
    self.updater = Updater:new{
        settings = self.settings,
        api = self.api,
        current_version = self.version,
        manifest_url = PluginVersion.manifest_url,
        release_prefix = PluginVersion.release_prefix,
        workloads={downloader=self.downloader,preprocess=self.preprocess},
    }
    self.updater_ui = UpdaterUI:new{
        updater = self.updater,
        downloader = self.downloader,
        preprocess=self.preprocess,
        on_changed=function(kind)
            if kind~="installed" and kind~="rollback" then return end
            self.download_service:pause();self.preprocess:pause()
            require("koobone.ui.download_queue").closeAccountViews()
            for index=#UIManager._window_stack,1,-1 do
                local widget=UIManager._window_stack[index].widget
                if widget.name=="koocomic_grid_shelf" or widget.name=="koocomic_info_panel" or widget.name=="koocomic_preprocess_queue" then
                    UIManager:close(widget)
                end
            end
        end,
    }
    self.bookshelf = Bookshelf:new{
        library = self.library,
        storage = self.storage,
        downloader = self.downloader,
        settings = self.settings,
        cover_cache = self.cover_cache,
        preprocess = self.preprocess,
        on_preprocess = function() self:showPreprocess() end,
        on_downloads = function() self:showDownloads() end,
        on_account = function() self:showAccount() end,
        on_settings = function() self:showSettings() end,
    }

    self.ui.menu:registerToMainMenu(self)
    self:scheduleAutomaticUpdateCheck()
    -- Only reaching the end of initialization confirms a just-installed copy
    -- can load and register successfully. The rollback backup survives until
    -- this point.
    local _,update_error=self.updater:confirmInstalledUpdate()
    if update_error then UIManager:show(InfoMessage:new{text="插件更新恢复状态：\n"..tostring(update_error)}) end
end

function KooComic:addToMainMenu(menu_items)
    menu_items.koocomic = {
        text = "koo漫画",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    local nick = self.settings:account().nick
                    return nick and nick ~= "" and ("我的书架（" .. nick .. "）") or "我的书架"
                end,
                callback = function() self:openBookshelf() end,
            },
            {
                text = "下载管理",
                callback = function() self:showDownloads() end,
            },
            {
                text = "图像优化 / 去彩纹管理",
                callback = function() self:showPreprocess() end,
            },
            {
                text = "账号与登录",
                callback = function() self:showAccount() end,
            },
            {
                text = "版本与设置",
                callback = function() self:showSettings() end,
            },
            {
                text = "书库能力探测（只读）",
                callback = function() self:probeCatalogCapabilities() end,
            },
            {
                text = "关于 koo漫画",
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "koo漫画 for KOReader\nv" .. self.version ..
                            "\n\n连接用户自己的 KOOBONE 漫画书库、下载 EPUB 并在 KOReader 中阅读。" ..
                            "\n\n这是独立开发的非官方插件，与 KOOBONE、Bookof.hk 及其开发者不存在隶属、赞助或官方合作关系。" ..
                            "\n\n许可证：AGPL-3.0-only",
                    })
                end,
            },
        },
    }
end

function KooComic:showPreprocess()
    if self:requireRestart() then return end
    return PreprocessUI.show(self.storage,self.preprocess,{settings=self.settings,library=self.library,cover_cache=self.cover_cache})
end

function KooComic:ensureOnline(callback)
    if self:requireRestart() then return end
    NetworkMgr:runWhenOnline(callback)
end

function KooComic:requireRestart()
    if not self.updater.restart_required and not RuntimeGuard.blocked then return false end
    UIManager:show(InfoMessage:new{text="插件代码已切换，请先重启 KOReader。"})
    return true
end

function KooComic:probeCatalogCapabilities()
    if self.downloader:isActive() or self.catalog_probe_running then
        UIManager:show(InfoMessage:new{ text = "请等待当前下载或探测结束。" })
        return
    end
    self:ensureOnline(function()
        if self.downloader:isActive() or self.catalog_probe_running then return end
        self.catalog_probe_running = true
        UIManager:show(InfoMessage:new{ text = "正在验证登录并探测书库……", timeout = 1 })
        UIManager:scheduleIn(0.15, function()
            local succeeded, result = pcall(function()
                if self.downloader:isActive() then return "请等待当前下载结束。" end
                local authenticated = self.auth:restore()
                if not authenticated then return "登录验证未成功，请先登录后再进行书库探测。" end
                return CatalogProbe.format(CatalogProbe:new(self.api):run())
            end)
            self.catalog_probe_running = false
            UIManager:show(InfoMessage:new{
                text = succeeded and result or "书库探测失败，未修改已有目录或下载记录。",
            })
        end)
    end)
end

function KooComic:showLogin()
    self:ensureOnline(function()
        LoginDialog.show{
            auth = self.auth,
            settings = self.settings,
            on_success = function() self.bookshelf:refresh() end,
        }
    end)
end

function KooComic:openBookshelf()
    if self:requireRestart() then return end
    if self.auth:hasSession() then
        local cached=self.library:loadCache()
        if cached then
            self.bookshelf:show(cached)
            if not NetworkMgr:isConnected() then return end
        end
    else
        self.library:clear()
    end
    self:ensureOnline(function()
        UIManager:show(InfoMessage:new{ text = "正在验证登录状态……", timeout = 1 })
        UIManager:scheduleIn(0.15, function()
            local ok, err, needs_login = self.auth:restore()
            if ok then
                self.bookshelf:refresh()
            elseif needs_login then
                self:showLogin()
            else
                UIManager:show(InfoMessage:new{
                    text = "暂时无法验证登录状态，已保留当前会话：\n" .. tostring(err),
                })
            end
        end)
    end)
end

-- Conventional entry point used by SimpleUI/ZenUI style launchers.
function KooComic:launch()
    return self:openBookshelf()
end

function KooComic:showAccount()
    if self:requireRestart() then return end
    AccountUI.show{
        settings = self.settings,
        auth = self.auth,
        on_login = function() self:showLogin() end,
        on_logout = function()
            require("koobone.ui.download_queue").closeAccountViews()
            self.download_service:stop()
            self.library:clear()
            self.bookshelf.cover_generation=self.bookshelf.cover_generation+1
            self.bookshelf.navigation:setAccount("local")
            self.bookshelf.selection:setAccount("local")
            if self.bookshelf and self.bookshelf.menu then
                UIManager:close(self.bookshelf.menu)
                self.bookshelf.menu = nil
            end
        end,
        on_settings = function() self:showSettings() end,
    }
end

function KooComic:showDownloads()
    if self:requireRestart() then return end
    DownloadsUI.show(self.storage, self.downloader)
end

function KooComic:showSettings()
    SettingsUI.show{
        settings = self.settings,
        updater = self.updater,
        updater_ui = self.updater_ui,
        storage = self.storage,
        version = self.version,
        on_ui_changed = function()
            if self.bookshelf and self.bookshelf.menu then self.bookshelf:show(self.library.items) end
        end,
    }
end

function KooComic:scheduleAutomaticUpdateCheck()
    UIManager:scheduleIn(5, function()
        if self.updater:shouldAutoCheck() and NetworkMgr:isConnected() then
            self.updater_ui:check(false)
        end
    end)
end

return KooComic
