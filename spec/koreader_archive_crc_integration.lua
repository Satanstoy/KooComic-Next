require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local ffi=require("ffi")
local Archiver=require("ffi/archiver")
local Epub=require("koobone.preprocess_epub")
local directory="/tmp/koocomic-epub-crc-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
local source=directory.."/source.epub"
local writer=Archiver.Writer:new();assert(writer:open(source,"zip"));assert(writer:setZipCompression("store"))
for _,entry in ipairs({
    {"mimetype","application/epub+zip"},
    {"META-INF/container.xml",'<container><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'},
    {"OPS/book.opf",'<package><manifest><item id="page" href="page.png" media-type="image/png"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>'},
    {"OPS/chapter.xhtml","<html><body>CRC chapter marker</body></html>"},
    {"OPS/page.png","PNG fixture"},
}) do assert(writer:addFileFromMemory(entry[1],entry[2])) end
writer:close()
local validator=Epub:new{reader=function() return Archiver.Reader:new() end,validation_only=true}
assert(validator:validate(source))
local bytes=assert(files:read(source));local at=assert(bytes:find("CRC chapter marker",1,true))
local corrupted=bytes:sub(1,at-1).."X"..bytes:sub(at+1)
local bad=directory.."/corrupted.epub";assert(files:write(bad,corrupted))
local valid,err=validator:validate(bad)
assert(not valid and tostring(err):find("CRC",1,true),"downloaded EPUB validation must reject an actual resource CRC mismatch")
local filtered=0
local processor=Epub:new{reader=function() return Archiver.Reader:new() end,writer=function() return Archiver.Writer:new() end,
    filter=function(data) filtered=filtered+1;return data end,validate_image=function() return true end}
local result,error_message=processor:process(bad,directory.."/result.epub")
assert(not result and tostring(error_message):find("CRC",1,true) and filtered==0,
    "preprocessing must reject corrupt structure resources before filtering images")
assert(files:read(source)==bytes and files:read(bad)==corrupted,"CRC rejection must not alter input files")
print("KOReader shared EPUB resource CRC validation: OK")
