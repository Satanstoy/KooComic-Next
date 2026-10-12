-- SPDX-License-Identifier: AGPL-3.0-only
local Entry = require("koobone.catalog_entry")
local Identity = {}

local function scalar(value)
    local kind = type(value)
    if kind == "number" and (value ~= value or math.abs(value) == math.huge) then return nil end
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
    return kind .. ":" .. (kind == "number" and string.format("%.17g", value == 0 and 0 or value) or tostring(value))
end

function Identity.key(source)
    if type(source) ~= "table" then return nil, "invalid source" end
    for _, field in ipairs({ "book_id", "source_fingerprint", "algorithm_version" }) do
        if type(source[field]) ~= "string" or source[field] == "" then return nil, "missing " .. field end
    end
    if type(source.profile) ~= "table" then return nil, "profile required" end
    local keys, fields = {}, {}
    for key, value in pairs(source.profile) do
        if type(key) ~= "string" or not scalar(value) then return nil, "invalid profile" end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do fields[#fields + 1] = Entry.key(key, scalar(source.profile[key])) end
    return Entry.key(source.book_id, source.source_fingerprint, source.algorithm_version, table.concat(fields, "|"))
end

return Identity
