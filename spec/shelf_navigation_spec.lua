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
assert(type(nav.rowKey)=="function","navigation must expose stable refresh identities")
assert(nav:rowKey(books[1])~=nav:rowKey({vol_id=1,file_md5="different",vol_name=books[1].vol_name}))
local old_key=nav:rowKey(books[1])
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
assert(nav:rowKey(books[1])~=old_key,"refresh anchors must be account isolated")
assert(nav.mode == "series" and nav.page == 1 and nav.query == "" and #nav:items({}) == 0)
local sorted = {
    {vol_id=4,file_md5="d",vol_name="Z",vol_series="Z",vol_author="Author"},
    {vol_id=5,file_md5="e",vol_name="A",vol_series="A",vol_author="Author"},
}
nav:setBooks(sorted)
assert(nav:items(sorted)[1]._series.title == "Z", "recent/progress series order must follow visible member ranks")
nav.sort_mode = "title"
assert(nav:items(sorted)[1]._series.title == "A")
local versions={{vol_id=10,file_md5="v1",vol_name="Original",vol_series="Versions",vol_author="A"},
    {vol_id=10,file_md5="v2",vol_name="Original revised",vol_series="Versions",vol_author="A"},
    {vol_id=11,file_md5="v3",vol_name="Original",vol_series="Versions",vol_author="A"}}
nav:setBooks(versions)
assert(type(nav.versions)=="function","trusted file versions must be exposed to production details")
assert(#nav:versions(versions[1])==1,"same vol_id without evidence must not merge versions")
nav.identity_options=function() return {volume_id_verified=true} end
assert(#nav:versions(versions[1])==2 and nav:items(versions)[1]._series.volume_count==2)
assert(#nav:versions(versions[3])==1,"same title on another volume is not a version")
print("shelf navigation spec: OK")
local covers={{file_md5="first",vol_name="Volume 1",vol_series="Cover series",vol_author="A",vol_index=1},
    {file_md5="second",vol_name="Volume 2",vol_series="Cover series",vol_author="A",vol_index=2,_koobone_cover_path="/cache/second.png"}}
nav:setBooks(covers)
assert(nav:items(covers)[1].file_md5=="second","missing first cover must fall back to another available volume")
nav.sort_mode="recent"
assert(nav:items({covers[2],covers[1]})[1].file_md5=="second","cover choice must not follow refresh/download order")
