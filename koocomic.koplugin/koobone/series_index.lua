-- SPDX-License-Identifier: AGPL-3.0-only
local CatalogEntry = require("koobone.catalog_entry")
local SeriesIndex = {}

local function normalized(value)
    return tostring(value or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
end

local function naturalLess(left, right)
    local a, b = tostring(left):lower(), tostring(right):lower()
    local i, j = 1, 1
    while i <= #a and j <= #b do
        local x, y = a:match("^%d+", i), b:match("^%d+", j)
        if x and y then
            local nx, ny = x:gsub("^0+", ""), y:gsub("^0+", "")
            if #nx ~= #ny then return #nx < #ny end
            if nx ~= ny then return nx < ny end
            i, j = i + #x, j + #y
        else
            x, y = a:sub(i, i), b:sub(j, j)
            if x ~= y then return x < y end
            i, j = i + 1, j + 1
        end
    end
    if #a - i ~= #b - j then return #a - i < #b - j end
    return tostring(left) < tostring(right)
end

local function volumeLess(left, right)
    local a, b = left.versions[1], right.versions[1]
    local an, bn = tonumber(a.volume_label), tonumber(b.volume_label)
    if an and bn and an ~= bn then return an < bn end
    if (an ~= nil) ~= (bn ~= nil) then return an ~= nil end
    local at, bt = a.volume_label or a.title, b.volume_label or b.title
    if at ~= bt then return naturalLess(at, bt) end
    return left.id < right.id
end

function SeriesIndex.group(entries)
    local groups, by_key, ungrouped, volume_maps = {}, {}, {}, {}
    for _, entry in ipairs(entries) do
        local title = normalized(entry.series_title)
        local author = normalized(entry.author)
        if title == "" or (author == "" and not entry.series_id) then
            ungrouped[#ungrouped + 1] = entry
        else
            local key = entry.series_id and CatalogEntry.key(entry.account_id, "series", entry.series_id) or
                CatalogEntry.key(entry.account_id, title:lower(), author:lower())
            local group = by_key[key]
            if not group then
                group = { key = key, title = title, volumes = {}, volume_count = 0 }
                by_key[key] = group
                volume_maps[key] = {}
                groups[#groups + 1] = group
            end
            local volume = volume_maps[key][entry.volume_id]
            if not volume then
                volume = { id = entry.volume_id, versions = {} }
                group.volumes[#group.volumes + 1] = volume
                group.volume_count = group.volume_count + 1
                volume_maps[key][entry.volume_id] = volume
            end
            volume.versions[#volume.versions + 1] = entry
        end
    end
    for _, group in ipairs(groups) do
        for _, volume in ipairs(group.volumes) do
            table.sort(volume.versions, function(a, b) return a.id < b.id end)
        end
        table.sort(group.volumes, volumeLess)
    end
    table.sort(groups, function(a, b)
        if a.title ~= b.title then return naturalLess(a.title, b.title) end
        return a.key < b.key
    end)
    table.sort(ungrouped, function(a, b)
        if a.title ~= b.title then return naturalLess(a.title, b.title) end
        return a.id < b.id
    end)
    return groups, ungrouped
end

return SeriesIndex
