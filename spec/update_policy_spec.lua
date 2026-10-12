package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
end
package.preload["ffi/archiver"] = function()
    return { Reader = { new = function() return {} end } }
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp" end }
end
package.preload["json"] = function()
    return { decode = function() return {} end }
end
package.preload["ffi/util"] = function()
    return { purgeDir = function() return true end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function() return nil end,
        mkdir = function() return true end,
    }
end
package.preload["ffi/sha2"] = function()
    return { sha256 = function() return function() return "" end end }
end
package.preload["version"] = function()
    return { getShortVersion = function() return "test" end }
end

local Util = require("koobone.util")
local Updater = require("koobone.updater")

assert(Util.compareVersions("0.2.0", "0.1.0") == 1)
assert(Util.compareVersions("0.2.0", "0.2.0") == 0)
assert(Util.compareVersions("0.1.0", "0.2.0") == -1)
assert(Util.compareVersions("invalid", "0.2.0") == nil)

local update_state = {
    auto_check_enabled = true,
    last_auto_update_check_at = 0,
    last_update_prompt_date = "",
    update_prompt_later_count = 0,
    auto_update_prompt_disabled = false,
}
local fake_settings = {
    update = function() return update_state end,
    flush = function() end,
}
local updater = Updater:new{
    settings = fake_settings,
    api = {},
    current_version = "0.2.0",
    manifest_url = "https://example.test/update.json",
    release_prefix = "https://example.test/releases/",
    plugin_dir = "/tmp/koocomic.koplugin",
}
local release = { version = "0.3.0" }

assert(updater:shouldPrompt(release) == true)
updater:markPromptShown(release)
assert(updater:shouldPrompt(release) == false)

-- Simulate a new day before each explicit "Later" choice.
for index = 1, 3 do
    update_state.last_update_prompt_date = "2000-01-0" .. tostring(index)
    assert(updater:shouldPrompt(release) == true)
    updater:deferPrompt()
end
assert(update_state.update_prompt_later_count == 3)
assert(update_state.auto_update_prompt_disabled == true)
assert(update_state.auto_check_enabled == false)
assert(updater:shouldPrompt{ version = "9.0.0" } == false)

updater:resetPromptPolicy()
assert(update_state.update_prompt_later_count == 0)
assert(update_state.auto_update_prompt_disabled == false)
assert(update_state.auto_check_enabled == true)

print("update policy spec: OK")
local Next=require("koobone.plugin_version")
assert(Next.release_prefix=="https://github.com/Satanstoy/KooComic-Next/releases/download/" and
    Next.manifest_url=="https://satanstoy.github.io/KooComic-Next/update.json",
    "Next must never fetch or install upstream KooComic releases")
local next_updater=Updater:new{settings=fake_settings,api={},current_version=Next.version,
    manifest_url=Next.manifest_url,release_prefix=Next.release_prefix}
local manifest={version="0.5.0",product_id="koocomic-next",channel="stable",package_type="full",
    package_url=Next.release_prefix.."v0.5.0/package.zip",size=100,sha256=string.rep("a",64)}
assert(next_updater:_validateManifest(manifest))
manifest.product_id="koocomic"
assert(not next_updater:_validateManifest(manifest),"another product cannot masquerade as a Next update")
manifest.product_id=nil
assert(not next_updater:_validateManifest(manifest),"legacy unscoped manifests must be rejected")
manifest.product_id="koocomic-next"
manifest.package_url="https://github.com/jackchensky/KooComic/releases/download/v9.0.0/package.zip"
assert(not next_updater:_validateManifest(manifest))
manifest.package_url=Next.release_prefix.."v0.5.0/package.zip"
manifest.product_id="koocomic"
local caught,installed=pcall(next_updater.install,next_updater,manifest)
assert(caught and not installed,"installation must revalidate product identity even for cached metadata")
assert(not next_updater:_packageUrlAllowed(Next.release_prefix.."../../../../other/releases/download/v0.5.0/package.zip"),
    "release URL allowlist must reject traversal, not merely match a string prefix")
manifest.product_id="koocomic-next";manifest.size=0/0
assert(not next_updater:_validateManifest(manifest),"manifest sizes must be finite integers")
