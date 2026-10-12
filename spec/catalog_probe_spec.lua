package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, CatalogProbe = pcall(require, "koobone.catalog_probe")
assert(available, "bounded read-only catalog probing is not implemented")

local requests = {}
local api = { library = function(_, limit)
    requests[#requests + 1] = limit
    local data = {}
    for i = 1, limit do
        data[i] = { vol_id = tostring(i), file_md5 = "hash" .. i,
            vol_name = "Private title", file_url = "secret-signed-url", cookie = "private-cookie" }
    end
    return { data = data, total = 100 }
end }
local probe = CatalogProbe:new(api)
local report = probe:run()
assert(#requests == 3 and requests[1] == 28 and requests[2] == 50 and requests[3] == 100)
assert(report.limit_growth == true)
assert(report.samples[1].count == 28 and report.samples[3].count == 100)
assert(report.samples[3].added == 72)
assert(report.verified == false and report.coverage == "unknown",
    "larger limits alone must not prove full enumeration")
local function noPrivateFields(value)
    for key, field in pairs(value) do
        assert(key ~= "vol_name" and key ~= "file_url" and key ~= "cookie" and key ~= "ids")
        if type(field) == "table" then noPrivateFields(field) end
        if type(field) == "string" then assert(not field:find("secret") and not field:find("Private")) end
    end
end
noPrivateFields(report)
requests = {}
api.library = function(_, limit)
    requests[#requests + 1] = limit
    local data = {}
    for i = 1, 28 do data[i] = { vol_id = tostring(i), file_md5 = "same" } end
    return { data = data }
end
report = probe:run()
assert(report.limit_growth == false and report.samples[3].count == 28)
api.library = function(_, limit)
    local data = {}
    for i = 1, 28 do data[i] = { vol_id = tostring(i + limit), file_md5 = "same" } end
    return { data = data }
end
report = probe:run()
assert(report.limit_growth == false and report.order_drift == true,
    "different ids caused by order drift must not be interpreted as a larger limit")
api.library = function() return nil, "HTTP 401 private-cookie secret-url" end
local ran, result = pcall(function() return probe:run() end)
assert(ran and result.samples[1].error_type == "authentication",
    "request failures must produce sanitized evidence, not throw")
assert(#result.samples == 1, "auth errors must stop probing")
noPrivateFields(result)
api.library = function() return { data = { [1] = { vol_id = "a" }, [3] = { vol_id = "b" } } } end
report = probe:run()
assert(report.samples[1].error_type == "protocol", "sparse responses must not look complete")
api.library = function() return { data = { { vol_name = "Unknown" }, { vol_name = "Unknown" } } } end
report = probe:run()
assert(report.samples[1].unidentified == 2 and report.samples[1].unique_count == 0,
    "missing ids must not be fabricated from titles")
api.library = function() return { data = {} } end
report = probe:run()
assert(report.coverage == "unknown" and report.verified == false,
    "an empty limit response alone must not prove completeness")
assert(type(CatalogProbe.format) == "function", "a private-data-free probe summary is missing")
local summary = CatalogProbe.format(report)
assert(summary:find("28", 1, true) and summary:find("100", 1, true))
assert(not summary:find("Private", 1, true) and not summary:find("secret", 1, true))
print("catalog probe spec: OK")
