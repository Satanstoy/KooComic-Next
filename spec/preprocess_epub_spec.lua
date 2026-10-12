package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, Epub = pcall(require, "koobone.preprocess_epub")
assert(available, "real EPUB page processing is missing")
local container = '<container><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
local opf = '<package><manifest><item id="p" href="images/p.png" media-type="image/png"/><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>'
local original = {{path="mimetype",data="application/epub+zip"},
    {path="META-INF/container.xml",data=container},{path="OPS/book.opf",data=opf},
    {path="OPS/chapter.xhtml",data="<html><img src='images/p.png'/></html>"},
    {path="OPS/images/p.png",data="PNG-original"}}
local archives = {source=original}
local processed, progress = 0, 0
local function reader()
    return {open=function(self,path) self.files=archives[path];self.entries={};return self.files~=nil end,
        iterate=function(self)
            local index=0
            return function()
                index=index+1;local item=self.files[index]
                if item then local entry={path=item.path,mode=item.mode or "file",size=#item.data,index=index}
                    self.entries[item.path]=entry;return entry end
            end
        end,
        extractToMemory=function(self,path) for _, item in ipairs(self.files) do if item.path==path then return item.data end end end,
        close=function() end}
end
local processor = Epub:new{reader=reader, writer=function()
    local output
    return {open=function(_,path) output={};archives[path]=output;return true end,
        setZipCompression=function() return true end,
        addFileFromMemory=function(_,path,data) output[#output+1]={path=path,data=data};return true end,
        close=function() return true end}
end, filter=function(data,media)
    processed=processed+1;assert(media=="image/png");return data.."-filtered"
end, validate_image=function(data) return data:find("PNG",1,true)==1 end}
local result = assert(processor:process("source","output",{progress=function(current,total)
    progress=current;assert(total==1) end}))
assert(result.validated and result.processed_pages==1 and processed==1 and progress==1)
assert(archives.output[4].data==original[4].data and archives.output[3].data==opf)
assert(original[5].data=="PNG-original", "processing must not mutate the source archive")
original[#original+1]={path="../escape",data="bad"}
assert(processor:process("source","rejected") == nil and archives.rejected==nil)
table.remove(original)
original[#original+1]={path="OPS/images/p.png",data="duplicate"}
assert(processor:process("source","duplicate") == nil)
table.remove(original)
original[#original+1]={path="META-INF/encryption.xml",data="encrypted"}
assert(processor:process("source","encrypted") == nil)
table.remove(original)
assert(processor:process("source","cancelled",{cancelled=function() return true end}) == nil)
processor.filter=function() error("codec failure") end
assert(processor:process("source","failure") == nil and original[5].data=="PNG-original")
assert(type(processor.validate)=="function","downloaded EPUBs need read-only structural and CRC validation")
local validator=Epub:new{reader=reader,validation_only=true}
assert(validator:validate("source") and original[5].data=="PNG-original")
original[#original+1]={path="../escape",data="bad"}
assert(not validator:validate("source"))
table.remove(original)
assert(not validator:validate("source",{cancelled=function() return true end}))
print("preprocess EPUB spec: OK")
