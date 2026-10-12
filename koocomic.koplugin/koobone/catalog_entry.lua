-- SPDX-License-Identifier: AGPL-3.0-only
local CatalogEntry = {}

local function text(value)
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    value = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

function CatalogEntry.key(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local value = tostring(select(i, ...) or "")
        parts[i] = #value .. ":" .. value
    end
    return table.concat(parts, "|")
end

function CatalogEntry.normalize(account_id, item, options)
    account_id = text(account_id)
    if not account_id or type(item) ~= "table" then return nil, "invalid catalog entry" end
    local vol_id, hash = text(item.vol_id), text(item.file_md5)
    if not vol_id and not hash then return nil, "entry has no source identity" end
    local id = CatalogEntry.key(account_id, "entry", vol_id, hash)
    local volume_id = id
    if options and options.volume_id_verified == true and vol_id then
        volume_id = CatalogEntry.key(account_id, "volume", vol_id)
    end
    return {
        id = id,
        volume_id = volume_id,
        account_id = account_id,
        title = type(item.vol_name) == "string" and item.vol_name or text(item.vol_series) or "",
        source = { vol_id = vol_id, file_md5 = hash },
        author = item.vol_author,
        series_title = item.vol_series,
        series_id = options and options.series_id_verified == true and text(item.vol_series_id) or nil,
        volume_label = item.vol_index,
        remote_size = tonumber(item.file_size),
        file_type = type(item.file_type)=="string" and item.file_type or "epub",
        remote_pages = tonumber(item.count_page),
        remote_page = tonumber(item.last_readpage),
    }
end

return CatalogEntry
