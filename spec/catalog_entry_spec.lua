package.path = "./koocomic.koplugin/?.lua;" .. package.path

local available, CatalogEntry = pcall(require, "koobone.catalog_entry")
assert(available, "catalog normalization is not implemented")

local item = {
    vol_id = "12", file_md5 = "hash-a", vol_name = "Original title 01",
    vol_series = "A series", vol_author = "Author", vol_index = "01",
    file_url = "https://files.example.test/private?signature=secret",
    cookie = "private", file_size = "100", count_page = 50,
}
local entry = assert(CatalogEntry.normalize("42", item))
assert(entry.title == item.vol_name, "the source title must be preserved")
assert(entry.file_url == nil and entry.cookie == nil, "catalog must exclude credentials")
assert(entry.source.vol_id == "12" and entry.source.file_md5 == "hash-a")
assert(entry.account_id == "42" and entry.remote_size == 100)
assert(item.file_url ~= nil, "normalization must not mutate the source")

local other_account = assert(CatalogEntry.normalize("99", item))
local revised = assert(CatalogEntry.normalize("42", {
    vol_id = "12", file_md5 = "hash-b", vol_name = item.vol_name,
}))
assert(entry.id ~= other_account.id, "entry identity must be account scoped")
assert(entry.id ~= revised.id, "file versions must keep independent entry identities")
assert(entry.volume_id ~= revised.volume_id, "unverified volume ids must not merge versions")
local verified = { volume_id_verified = true }
local first = assert(CatalogEntry.normalize("42", item, verified))
local second = assert(CatalogEntry.normalize("42", {
    vol_id = "12", file_md5 = "hash-b", vol_name = item.vol_name,
}, verified))
assert(first.volume_id == second.volume_id, "verified versions must share a volume")
assert(first.id ~= second.id)
assert(CatalogEntry.normalize("42", { vol_name = "No identity" }) == nil,
    "titles must not be used as identities")
assert(CatalogEntry.normalize(nil, item) == nil)
assert(CatalogEntry.normalize("42", false) == nil)
local blank = assert(CatalogEntry.normalize("42", { vol_id = "", file_md5 = "a" }))
assert(blank.source.vol_id == nil)

print("catalog entry spec: OK")
