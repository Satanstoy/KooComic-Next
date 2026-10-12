package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, Navigation = pcall(require, "koobone.ui.shelf_navigation")
assert(available, "series navigation is missing from the production shelf")
local books = {
    {vol_id=1, file_md5="a", vol_name="Original 10", vol_series="Series", vol_author="Author", vol_index=10},
    {vol_id=2, file_md5="b", vol_name="Original 2", vol_series="Series", vol_author="Author", vol_index=2},
    {vol_id=3, file_md5="c", vol_name="Other"},
}
local storage = {isDownloaded=function(_, item) return item.file_md5 == "b" end}
local nav = Navigation:new{account_id="42", storage=storage}
nav:setBooks(books)
local cards = nav:items(books)
assert(nav.mode == "series" and #cards == 2)
assert(cards[1]._series.volume_count == 2 and cards[1]._series.downloaded_count == 1)
assert(cards[1]._series.books[1] == books[2], "series volumes need natural ordering")
nav.page = 3
assert(nav:enter(cards[1]._series))
local replacement = {}
for index, book in ipairs(books) do
    replacement[index] = {}
    for key, value in pairs(book) do replacement[index][key] = value end
end
nav:setBooks(replacement)
assert(nav:items(replacement)[1] == replacement[2], "series contents must survive refreshed table identities")
nav:setBooks(books)
assert(nav:items(books)[1] == books[2] and nav:back() and nav.page == 3)
nav:switch("volumes")
nav.page, nav.query = 2, "Original"
nav:switch("downloaded")
assert(#nav:items(books) == 1 and nav:items(books)[1] == books[2])
nav:switch("volumes")
assert(nav.page == 2 and nav.query == "Original")
assert(books[1].vol_name == "Original 10", "navigation must not rewrite titles")
nav:setAccount("99")
assert(nav.mode == "series" and nav.page == 1 and nav.query == "" and #nav:items({}) == 0)
local sorted = {
    {vol_id=4,file_md5="d",vol_name="Z",vol_series="Z",vol_author="Author"},
    {vol_id=5,file_md5="e",vol_name="A",vol_series="A",vol_author="Author"},
}
nav:setBooks(sorted)
assert(nav:items(sorted)[1]._series.title == "Z", "recent/progress series order must follow visible member ranks")
nav.sort_mode = "title"
assert(nav:items(sorted)[1]._series.title == "A")
print("shelf navigation spec: OK")
