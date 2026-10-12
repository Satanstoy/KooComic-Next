package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, SeriesIndex = pcall(require, "koobone.series_index")
assert(available, "series indexing is not implemented")
local CatalogEntry = require("koobone.catalog_entry")

local entries = {}
for _, version in ipairs({ "a", "b" }) do
    entries[#entries + 1] = assert(CatalogEntry.normalize("42", {
        vol_id = "1", file_md5 = version, vol_name = "Source title",
        vol_series = "Series", vol_author = "Author", vol_index = "1",
    }, { volume_id_verified = true }))
end
local groups, ungrouped = SeriesIndex.group(entries)
assert(#groups == 1 and #ungrouped == 0)
assert(groups[1].volume_count == 1, "versions must not inflate the volume count")
assert(#groups[1].volumes[1].versions == 2)
assert(entries[1].title == "Source title", "grouping must not rename books")

local unordered = {}
for _, number in ipairs({ "10", "2", "12.5", "01" }) do
    unordered[#unordered + 1] = assert(CatalogEntry.normalize("42", {
        vol_id = number, file_md5 = "v" .. number, vol_name = "Volume " .. number,
        vol_series = " Series ", vol_author = "Author", vol_index = number,
    }))
end
groups = SeriesIndex.group(unordered)
local volumes = groups[1].volumes
assert(volumes[1].versions[1].volume_label == "01", "volumes must sort numerically")
assert(volumes[2].versions[1].volume_label == "2")
assert(volumes[3].versions[1].volume_label == "10")
assert(volumes[4].versions[1].volume_label == "12.5")
assert(unordered[1].title == "Volume 10")

unordered[#unordered + 1] = assert(CatalogEntry.normalize("42", {
    file_md5 = "other", vol_name = "Other", vol_series = "Series", vol_author = "Other author",
}))
unordered[#unordered + 1] = assert(CatalogEntry.normalize("42", {
    file_md5 = "unknown", vol_name = "Unknown", vol_series = "   ",
}))
groups, ungrouped = SeriesIndex.group(unordered)
assert(#groups == 2 and #ungrouped == 1, "different authors and unknown series must stay separate")

local no_index = {}
for _, title in ipairs({ "Extra 10", "Extra 2", "Extra 1" }) do
    no_index[#no_index + 1] = assert(CatalogEntry.normalize("42", {
        file_md5 = title, vol_name = title, vol_series = "Extras", vol_author = "Author",
    }))
end
groups = SeriesIndex.group(no_index)
assert(groups[1].volumes[1].versions[1].title == "Extra 1")
assert(groups[1].volumes[2].versions[1].title == "Extra 2")
assert(groups[1].volumes[3].versions[1].title == "Extra 10")

local uncertain = {
    assert(CatalogEntry.normalize("42", { vol_id = "a", vol_series = "Same name" })),
    assert(CatalogEntry.normalize("42", { vol_id = "b", vol_series = "Same name" })),
}
groups, ungrouped = SeriesIndex.group(uncertain)
assert(#groups == 0 and #ungrouped == 2, "unknown series identity must remain unclassified")
local trusted = {}
for _, id in ipairs({ "a", "b" }) do
    trusted[#trusted + 1] = assert(CatalogEntry.normalize("42", {
        vol_id = id, vol_series_id = "series-1", vol_series = "Known series",
    }, { series_id_verified = true }))
end
groups, ungrouped = SeriesIndex.group(trusted)
assert(#groups == 1 and #ungrouped == 0, "verified series ids must group without an author")
print("series index spec: OK")
