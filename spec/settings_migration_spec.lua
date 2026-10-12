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

local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
local fail_save=false
package.preload["luasettings"]=function() return {open=function(_,path)
    files[path]=files[path] or {}
    return {readSetting=function(_,key) return files[path][key] end,
        saveSetting=function(_,key,value) files[path][key]=value end,flush=function() end}
end} end
package.preload["koobone.settings_store"] = function()
    return {
        new = function()
            return {
                load=function(_,path) return copy(files[path]) end,
                save=function(_,path,payload,source)
                    if fail_save then return nil,"injected write failure" end
                    if source then files[path..".pre-v4"]=copy(files[source]) end
                    files[path]=copy(payload);return true
                end,
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
assert(settings:ui().series_style == "divider","old users must get the original divider style")
assert(settings.data.schema_version == 4,"settings must migrate to schema v4")
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
existing:ui().series_style="ribbon"
existing:flush()
assert(Settings:new("/settings/existing.lua"):ui().series_style=="ribbon","series style must survive restart")
existing:ui().series_style="corrupt-style"
existing:flush()
assert(Settings:new("/settings/existing.lua"):ui().series_style=="divider","unknown styles must not reach a missing renderer")

print("settings migration spec: OK")
assert(files["/settings/koocomic.lua.pre-v4"].data.schema_version==2,"migration must retain old settings metadata")
assert(settings:update().product_id=="koocomic-next" and settings.data.preprocess.strength==0.8)
files["/settings/future.lua"]={data={schema_version=5,account={email="future@example.test"}}}
assert(not pcall(Settings.new,Settings,"/settings/future.lua"),"unknown future schemas must reject downgrade writes")
assert(files["/settings/future.lua"].data.schema_version==5)
files["/settings/bad.lua"]={data={schema_version=3,download="corrupt"}}
assert(not pcall(Settings.new,Settings,"/settings/bad.lua"),"malformed sections must not silently become defaults")
files["/settings/fail.lua"]={data={schema_version=3,download={directory="/old/books",records={one={state="complete"}}}}}
fail_save=true
assert(not pcall(Settings.new,Settings,"/settings/fail.lua"))
assert(files["/settings/fail.lua"].data.schema_version==3 and files["/settings/fail.lua"].data.download.records.one)
fail_save=false
files["/settings/v1.lua"]={settings={schema_version=1,email="old@example.test",download={directory="/legacy/books",records={old={state="complete"}}}}}
local v1=Settings:new("/settings/v1.lua")
assert(v1:account().email=="old@example.test" and v1:download().records.old and
    files["/settings/v1.lua.pre-v4"],"flat v1 settings must preserve downloads and receive a metadata backup")
files["/settings/false.lua"]={data={schema_version=false}}
assert(not pcall(Settings.new,Settings,"/settings/false.lua") and files["/settings/false.lua"].data.schema_version==false,
    "invalid false schema marker must not be treated as a missing schema")
files["/settings/badlegacy.lua"]={settings="corrupt"}
assert(not pcall(Settings.new,Settings,"/settings/badlegacy.lua") and files["/settings/badlegacy.lua"].settings=="corrupt")
files["/settings/badold.lua"]={data="corrupt"}
assert(not pcall(Settings.new,Settings,"/settings/untouched.lua","/settings/badold.lua") and
    files["/settings/untouched.lua"]==nil,"invalid legacy data cannot create a replacement with defaults")
