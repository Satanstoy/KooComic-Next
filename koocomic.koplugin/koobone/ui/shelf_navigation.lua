-- SPDX-License-Identifier: AGPL-3.0-only
local Entry = require("koobone.catalog_entry")
local SeriesIndex = require("koobone.series_index")
local Navigation = {}
Navigation.__index = Navigation

function Navigation:new(options)
    return setmetatable({account_id=tostring(options.account_id or "local"), storage=options.storage,
        mode="series", page=1, query="", sort_mode="recent", filter_mode="all", memories={}, books={}}, self)
end

function Navigation:setAccount(id)
    id = tostring(id or "local")
    if self.account_id == id then return end
    self.account_id, self.mode, self.page, self.query = id, "series", 1, ""
    self.books, self.memories, self.parent, self.series = {}, {}, nil, nil
    self.sort_mode, self.filter_mode = "recent", "all"
end

function Navigation:setBooks(books)
    self.books = books or {}
    if not self.series then return end
    local prior = self.series
    self.series = nil
    for _, card in ipairs(self:items(self.books)) do
        if card._series and card._series.key == prior.key then self.series = card._series; return end
    end
    self:back()
end

function Navigation:_state()
    return {page=self.page, query=self.query, sort_mode=self.sort_mode, filter_mode=self.filter_mode}
end

function Navigation:_restore(state)
    state = state or {page=1, query="", sort_mode="recent", filter_mode="all"}
    for key, value in pairs(state) do self[key] = value end
end

function Navigation:switch(mode)
    if mode ~= "series" and mode ~= "volumes" and mode ~= "downloaded" then return false end
    if self.parent then self:back() end
    self.memories[self.mode] = self:_state()
    self.mode = mode
    self:_restore(self.memories[mode])
    return true
end

function Navigation:enter(series)
    if self.series or type(series) ~= "table" then return false end
    self.parent, self.series = self:_state(), series
    self.page, self.query = 1, ""
    return true
end

function Navigation:back()
    if not self.parent then return false end
    self:_restore(self.parent)
    self.parent, self.series = nil, nil
    return true
end

function Navigation:items(visible)
    local result, allowed = {}, {}
    for rank, item in ipairs(visible) do allowed[item] = rank end
    if self.series then
        for _, item in ipairs(self.series.books) do if allowed[item] then result[#result+1] = item end end
        return result
    end
    if self.mode ~= "series" then
        for _, item in ipairs(visible) do
            if self.mode ~= "downloaded" or self.storage:isDownloaded(item) then result[#result+1] = item end
        end
        return result
    end
    local entries, by_id, invalid = {}, {}, {}
    for _, item in ipairs(self.books) do
        local entry = Entry.normalize(self.account_id, item)
        if entry then
            if not by_id[entry.id] then entries[#entries+1] = entry; by_id[entry.id] = item end
        else invalid[#invalid+1] = item end
    end
    local groups, ungrouped = SeriesIndex.group(entries)
    if #ungrouped > 0 then
        local group = {key=Entry.key(self.account_id, "ungrouped"), title="未分类", volumes={}, volume_count=#ungrouped}
        for _, entry in ipairs(ungrouped) do group.volumes[#group.volumes+1] = {versions={entry}} end
        groups[#groups+1] = group
    end
    for _, group in ipairs(groups) do
        local members, downloaded, matched, rank = {}, 0, false, math.huge
        for _, volume in ipairs(group.volumes) do
            local local_volume = false
            for _, entry in ipairs(volume.versions) do
                local item = by_id[entry.id]
                members[#members+1] = item
                matched = matched or allowed[item] ~= nil
                rank = math.min(rank,allowed[item] or math.huge)
                local_volume = local_volume or self.storage:isDownloaded(item)
            end
            if local_volume then downloaded = downloaded+1 end
        end
        if matched then
            local card = {}
            for key, value in pairs(members[1]) do card[key] = value end
            card.vol_name = group.title
            card._series = {key=group.key, title=group.title, books=members,
                volume_count=group.volume_count, downloaded_count=downloaded,rank=rank}
            result[#result+1] = card
        end
    end
    if self.sort_mode ~= "title" then
        table.sort(result,function(a,b) return a._series.rank < b._series.rank end)
    end
    for _, item in ipairs(invalid) do if allowed[item] then result[#result+1] = item end end
    return result
end

return Navigation
