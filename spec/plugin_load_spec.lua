package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

local function class()
    local object = {}
    function object:extend(fields)
        fields = fields or {}
        setmetatable(fields, { __index = self })
        return fields
    end
    function object:new(fields)
        fields = fields or {}
        setmetatable(fields, { __index = self })
        return fields
    end
    return object
end

local Widget = class()
local scheduled, shown = {}, {}
local defer_network, waiting = false, {}
local noop_widget_modules = {
    "ui/widget/buttondialog",
    "ui/widget/checkbutton",
    "ui/widget/confirmbox",
    "ui/widget/infomessage",
    "ui/widget/menu",
    "ui/widget/multiinputdialog",
    "ui/widget/buttontable",
    "ui/widget/container/centercontainer",
    "ui/widget/container/framecontainer",
    "ui/widget/container/inputcontainer",
    "ui/widget/progresswidget",
    "ui/widget/textboxwidget",
    "ui/widget/textwidget",
    "ui/widget/widget",
    "ui/widget/iconwidget",
    "ui/widget/imagewidget",
    "ui/widget/horizontalgroup",
    "ui/widget/horizontalspan",
    "ui/widget/overlapgroup",
    "ui/widget/verticalgroup",
    "ui/widget/verticalspan",
}
for _, name in ipairs(noop_widget_modules) do
    package.preload[name] = function() return Widget end
end
package.preload["ui/widget/container/widgetcontainer"] = function() return Widget end
package.preload["ui/gesturerange"] = function() return Widget end

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end,
        getDataDir = function() return "/tmp" end,
        getFullDataDir = function() return "/tmp/koreader" end,
    }
end
package.preload["ui/network/manager"] = function()
    return {
        runWhenOnline = function(_, callback)
            if defer_network then waiting[#waiting + 1] = callback else callback() end
        end,
        isConnected = function() return false end,
    }
end
package.preload["ui/uimanager"] = function()
    return {
        scheduleIn = function(_, _, callback) scheduled[#scheduled + 1] = callback end,
        show = function(_, widget) shown[#shown + 1] = widget end,
        close = function() end,
        setDirty = function() end,
        forceRePaint = function() end,
    }
end
package.preload["apps/reader/readerui"] = function()
    return { showReader = function() end }
end
package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
end
package.preload["socket.http"] = function()
    return { request = function() return nil, 500, {}, "test" end }
end
package.preload["ssl.https"] = function()
    return { request = function() return nil, 500, {}, "test" end }
end
package.preload["socketutil"] = function()
    return {
        FILE_BLOCK_TIMEOUT = 15,
        set_timeout = function() end,
        reset_timeout = function() end,
        table_sink = function(target)
            return function(chunk)
                if chunk then target[#target + 1] = chunk end
                return 1
            end
        end,
    }
end
package.preload["ltn12"] = function()
    return { source = { string = function() return function() end end } }
end
package.preload["json"] = function()
    return { decode = function() return {} end }
end
package.preload["ffi/util"] = function()
    return {
        dirname = function() return "/tmp" end,
        joinPath = function(left, right) return left .. "/" .. right end,
        purgeDir = function() return true end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function() return nil end,
        mkdir = function() return true end,
    }
end
package.preload["ffi/archiver"] = function()
    return { Reader = { new = function() return {} end } }
end
package.preload["ffi/sha2"] = function()
    return { sha256 = function() return function() return "" end end }
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_BLACK = 0, COLOR_WHITE = 1 }
end
package.preload["device"] = function()
    return {
        screen = {
            getSize = function() return { w = 600, h = 800 } end,
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            scaleBySize = function(_, value) return value end,
        },
    }
end
package.preload["ui/font"] = function()
    return { getFace = function() return {} end }
end
package.preload["ui/geometry"] = function()
    return { new = function(_, value) return value end }
end
package.preload["ui/size"] = function()
    return {
        padding = { small = 2, large = 8 },
        margin = { tiny = 1 },
        border = { window = 1 },
        radius = { window = 2 },
    }
end
package.preload["version"] = function()
    return { getShortVersion = function() return "test" end }
end
package.preload["luasettings"] = function()
    local handle = {
        readSetting = function() return nil end,
        saveSetting = function() end,
        flush = function() end,
    }
    return { open = function() return handle end }
end
package.preload["koobone.settings_store"]=function() return {new=function() return {
    load=function() return nil end,save=function() return true end,
} end} end

G_reader_settings = {
    readSetting = function() return "/tmp" end,
}

local Plugin = dofile("koocomic.koplugin/main.lua")
assert(Plugin.version == "0.4.1")
local instance = Plugin:new{
    ui = { menu = { registerToMainMenu = function() end } },
}
instance:init()
assert(instance.download_service and instance.downloader.service==instance.download_service,
    "production main must bind the isolated queue instead of the legacy synchronous downloader")
assert(instance.settings ~= nil)
assert(instance.downloader ~= nil)
assert(instance.updater ~= nil)

local menu = {}
instance:addToMainMenu(menu)
local probe_action
local preprocess_action
for _, action in ipairs(menu.koocomic.sub_item_table) do
    if action.text == "书库能力探测（只读）" then probe_action = action end
    if action.text == "图像优化 / 去彩纹管理" then preprocess_action = action end
end
assert(preprocess_action and instance.preprocess, "independent preprocessing is not connected to the actual plugin")
assert(probe_action, "the read-only catalog probe menu is not implemented")
local limits = {}
instance.auth.restore = function() return true end
instance.api.library = function(_, limit)
    limits[#limits + 1] = limit
    return { data = {} }
end
probe_action.callback()
scheduled[#scheduled]()
assert(#limits == 3 and limits[1] == 28 and limits[3] == 100)
assert(shown[#shown].text:find("尚未确认", 1, true))
instance.auth.restore = function() return nil, "private auth error" end
probe_action.callback()
scheduled[#scheduled]()
assert(#limits == 3, "probe must not request a private catalog after failed authentication")
assert(not shown[#shown].text:find("private", 1, true))
defer_network = true
local before = #scheduled
probe_action.callback()
probe_action.callback()
assert(#waiting == 2)
waiting[1]()
waiting[2]()
assert(#scheduled == before + 1, "deferred online callbacks must not schedule duplicate probes")
instance.auth.restore = function() error("private auth exception") end
scheduled[#scheduled]()
assert(instance.catalog_probe_running == false, "failed probes must release the running guard")
assert(not shown[#shown].text:find("private", 1, true))

local cached={{vol_name="Offline original",file_md5="offline"}}
local cache_shown=false
instance.settings:account().uin=42
instance.settings:account().vlibsid="fixture-session"
instance.library.loadCache=function() return cached end
instance.bookshelf.show=function(_,books) assert(books==cached);cache_shown=true end
instance.bookshelf.refresh=function() error("offline opening must not start a network sync") end
instance.auth.restore=function() error("offline cache must not require live authentication") end
instance:openBookshelf()
assert(cache_shown,"the production entry must show cache before asking for a connection")
local account_options
require("koobone.ui.account").show=function(options) account_options=options end
instance.library.items=cached
instance:showAccount()
account_options.on_logout()
assert(#instance.library.items==0,"logout must clear remote in-memory catalog and pending requests")

print("plugin load spec: OK")
