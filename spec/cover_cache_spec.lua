package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp/koreader" end }
end
package.preload["ffi/util"] = function()
    return { joinPath = function(left, right) return left .. "/" .. right end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, attribute)
            if attribute == "mode" and path:match("koobone%-covers$") then return "directory" end
            if attribute == "size" then return nil, "file does not exist" end
            return nil
        end,
        mkdir = function() return true end,
    }
end

local CoverCache = require("koobone.cover_cache")
local cache = CoverCache:new{
    BASE = "https://bookof.hk",
    download = function() return nil, "not used" end,
}

assert(cache:url{ cover_small = "/covers/a.jpg" } == "https://bookof.hk/covers/a.jpg")
assert(cache:url{ cover_url = "//img.example.test/a.png" } == "https://img.example.test/a.png")
assert(cache:url{ cover = "http://bookof.hk/a.webp" } == "https://bookof.hk/a.webp")
assert(cache:url{} == nil)

local first = cache:path{ file_md5 = "stable-id", cover_url = "/covers/a.jpg" }
local second = cache:path{ file_md5 = "stable-id", cover_url = "/changed/a.jpg" }
assert(first == second)
assert(first:match("%.jpg$") ~= nil)
assert(cache:path{file_md5="stable-id"}==first,"offline identity must resolve cached covers without persisting a remote URL")
assert(cache:localPath{ file_md5 = "missing", cover_url = "/covers/a.jpg" } == nil)

print("cover cache spec: OK")
local work,done
local async_cache=CoverCache:new({BASE="https://bookof.hk"},{runner={start=function(_,task,complete)
    work,done=task,complete;return {cancel=function() return true end}
end}})
local fetched=false
async_cache.fetch=function() fetched=true;return "/cache/cover.jpg" end
async_cache.localPath=function() return fetched and "/cache/cover.jpg" end
assert(type(async_cache.fetchAsync)=="function","cover HTTP must run outside the UI thread")
local delivered
local handle=assert(async_cache:fetchAsync({file_md5="async"},function(path) delivered=path end))
assert(not fetched and not delivered)
assert(not async_cache:fetchAsync({file_md5="other"},function() end),"cover prefetch must bound itself to one child")
done(work());assert(delivered=="/cache/cover.jpg" and async_cache.active==nil)
assert(handle.cancel())
