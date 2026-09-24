package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

local files = {
    ["/settings/koobone.lua"] = {
        data = {
            schema_version = 2,
            account = {
                email = "reader@example.test",
                password = "local-test-only",
                remember_password = true,
                vlibsid = "session-a",
                kbskey = "session-b",
                nick = "Reader",
            },
            download = { records = { one = { state = "complete" } } },
            update = { auto_check_enabled = true },
        },
    },
    ["/settings/koocomic.lua"] = {},
}

package.preload["luasettings"] = function()
    return {
        open = function(_, path)
            files[path] = files[path] or {}
            return {
                readSetting = function(_, key) return files[path][key] end,
                saveSetting = function(_, key, value) files[path][key] = value end,
                flush = function() end,
            }
        end,
    }
end

local Settings = require("koobone.settings")
local settings = Settings:new("/settings/koocomic.lua", "/settings/koobone.lua")

assert(settings:account().email == "reader@example.test")
assert(settings:account().nick == "Reader")
assert(settings:account().remember_password == true)
assert(settings:account().password == "local-test-only")
assert(settings:ui().portrait_columns == 3)
assert(settings:ui().portrait_rows == 2)
assert(settings:ui().text_size == "large")
assert(settings.data.schema_version == 3)
assert(files["/settings/koobone.lua"].data.account.nick == "Reader")
assert(files["/settings/koocomic.lua"].data.account.nick == "Reader")

-- New installations opt in to the lightweight daily version check, while an
-- existing user's explicit choice to turn it off must remain untouched.
local fresh = Settings:new("/settings/fresh.lua")
assert(fresh:update().auto_check_enabled == true)

files["/settings/existing.lua"] = {
    data = {
        schema_version = 3,
        update = { auto_check_enabled = false },
    },
}
local existing = Settings:new("/settings/existing.lua")
assert(existing:update().auto_check_enabled == false)

print("settings migration spec: OK")
