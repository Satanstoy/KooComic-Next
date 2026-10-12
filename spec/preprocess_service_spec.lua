package.path="./koocomic.koplugin/?.lua;"..package.path
local available,Service=pcall(require,"koobone.preprocess_service")
assert(available,"downloaded-file preprocessing service is missing")
local disabled=Service:new{storage={},directory="/not-created-by-test"}
assert(disabled.available==false and type(disabled.reason)=="string")
assert(disabled:submit({})==nil and disabled:isActive()==false)
assert(disabled:jobs()[1]==nil and disabled:isLocked("/books/book.epub")==false)
print("preprocess service spec: OK")
