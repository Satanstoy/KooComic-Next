-- SPDX-License-Identifier: AGPL-3.0-only
local CatalogEntry = require("koobone.catalog_entry")
local CatalogProbe = {}
CatalogProbe.__index = CatalogProbe

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key, item in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or type(item) ~= "table" then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function errorType(err)
    if type(err) == "string" and (err:match("HTTP 401%f[%D]") or err:match("HTTP 403%f[%D]")) then
        return "authentication"
    end
    return "request"
end

function CatalogProbe:new(api)
    return setmetatable({ api = assert(api, "api required") }, self)
end

function CatalogProbe:run()
    local report = { verified = false, coverage = "unknown", limit_growth = false, order_drift = false, samples = {} }
    local baseline, baseline_count = {}, 0
    for index, limit in ipairs({ 28, 50, 100 }) do
        local called, response, err = pcall(self.api.library, self.api, limit)
        local sample = { limit = limit }
        report.samples[#report.samples + 1] = sample
        if not called or not response then
            sample.error_type = errorType(called and err or response)
            break
        end
        if type(response) ~= "table" or not isArray(response.data) then
            sample.error_type = "protocol"
            break
        end
        sample.count, sample.unique_count, sample.added, sample.unidentified = #response.data, 0, 0, 0
        local seen = {}
        for _, item in ipairs(response.data) do
            local entry = CatalogEntry.normalize("probe", item)
            local id = entry and entry.id
            if not id then
                sample.unidentified = sample.unidentified + 1
            elseif not seen[id] then
                seen[id] = true
                sample.unique_count = sample.unique_count + 1
                if not baseline[id] then sample.added = sample.added + 1 end
            end
        end
        if index == 1 then baseline = seen; baseline_count = sample.unique_count; sample.added = 0 end
        if index > 1 then
            local overlap = sample.unique_count - sample.added
            if overlap < baseline_count then report.order_drift = true end
            if overlap == baseline_count and sample.unique_count > baseline_count and sample.unidentified == 0 then
                report.limit_growth = true
            end
        end
    end
    return report
end

function CatalogProbe.format(report)
    local lines = { "只读书库探测", "" }
    local errors = { authentication = "认证失败", protocol = "响应格式异常", request = "请求失败" }
    for _, sample in ipairs(report.samples) do
        if sample.error_type then
            lines[#lines + 1] = string.format("limit=%d：%s", sample.limit,
                errors[sample.error_type] or "探测失败")
        else
            lines[#lines + 1] = string.format("limit=%d：%d 条，%d 个不同标识，新增 %d 条，缺少标识 %d 条",
                sample.limit, sample.count, sample.unique_count, sample.added, sample.unidentified)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "此探测仅检查 limit 行为，尚未确认分页或完整书库枚举能力。"
    return table.concat(lines, "\n")
end

return CatalogProbe
