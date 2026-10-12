-- SPDX-License-Identifier: AGPL-3.0-only
local Xml = require("koobone.vendor.xml")
local Epub = {}
Epub.__index = Epub

local function safeMember(path)
    if type(path) ~= "string" or path == "" or path:sub(1,1)=="/" or
            path:find("[%c\\:]") or path:find("//",1,true) then return false end
    for part in path:gmatch("[^/]+") do if part=="." or part==".." then return false end end
    return true
end

local function parse(data, callback)
    assert(type(data)=="string" and #data<=1024*1024, "metadata missing or too large")
    local parser = Xml.xmlParser{
        starttag=function(_, name, attributes) callback(name:match("([^:]+)$"),attributes or {}) end,
        endtag=function() end,
        dtd=function() error("DTD is not supported") end,
    }
    parser:parse(data)
end

local function resolve(base, href)
    assert(type(href)=="string" and href~="" and not href:find("[?#:]"), "non-local manifest resource")
    href = href:gsub("%%(%x%x)",function(value) return string.char(tonumber(value,16)) end)
    assert(href:sub(1,1)~="/" and not href:find("[%c\\:%%]"), "invalid resource URL")
    local components = {}
    for part in (base..href):gmatch("[^/]+") do
        if part==".." then assert(#components>0,"manifest path escape");table.remove(components)
        elseif part~="." then components[#components+1]=part end
    end
    local result = table.concat(components,"/")
    assert(safeMember(result),"invalid resource path")
    return result
end

function Epub:new(options)
    assert(options.reader and options.writer and options.filter and options.validate_image,"EPUB dependencies required")
    return setmetatable(options,self)
end

function Epub:_index(reader)
    local files, by_path, total = {}, {}, 0
    for entry in reader:iterate() do
        assert(safeMember(entry.path) and not by_path[entry.path],"unsafe or duplicate ZIP member")
        local size = tonumber(entry.size)
        assert(size and size>=0 and size<math.huge and size==math.floor(size) and size<=64*1024*1024,
            "ZIP member exceeds budget")
        assert(entry.mode=="file" or entry.mode=="directory","ZIP links and special entries rejected")
        total=total+size
        assert(total<=16*1024*1024*1024 and #files<100000,"ZIP exceeds archive budget")
        files[#files+1]=entry;by_path[entry.path]=entry
    end
    assert(not reader.err,"ZIP header validation failed")
    assert(not by_path["META-INF/encryption.xml"],"encrypted EPUB is not supported")
    return files,by_path
end

function Epub:_read(reader, entry)
    assert(entry and entry.mode=="file","missing EPUB resource")
    local data=reader:extractToMemory(entry.path)
    assert(type(data)=="string" and #data==tonumber(entry.size) and not reader.err,"ZIP data/CRC validation failed")
    return data
end

function Epub:_manifest(reader, by_path)
    assert(self:_read(reader,by_path.mimetype)=="application/epub+zip","invalid EPUB mimetype")
    local package_path
    parse(self:_read(reader,by_path["META-INF/container.xml"]),function(name,attributes)
        if name=="rootfile" then
            assert(not package_path,"multiple package documents are not supported")
            package_path=attributes["full-path"]
        end
    end)
    assert(package_path and safeMember(package_path),"invalid EPUB package path")
    local base=package_path:match("^(.*[/])") or ""
    local images, ids, references = {}, {}, {}
    parse(self:_read(reader,by_path[package_path]),function(name,attributes)
        if name=="item" then
            local id,media=attributes.id,attributes["media-type"]
            assert(type(id)=="string" and id~="" and not ids[id] and media,"invalid manifest item")
            local path=resolve(base,attributes.href)
            assert(by_path[path] and by_path[path].mode=="file","manifest resource missing")
            ids[id]=path
            if media=="image/png" or media=="image/jpeg" then
                assert(not images[path] or images[path]==media,"conflicting image type")
                images[path]=media
            end
        elseif name=="itemref" then references[#references+1]=attributes.idref or false end
    end)
    assert(#references>0,"EPUB spine is empty")
    for _, id in ipairs(references) do assert(ids[id],"broken EPUB spine") end
    return images
end

function Epub:process(source, output, options)
    options=options or {}
    if type(source)~="string" or type(output)~="string" or source==output then return nil,"separate output required" end
    local reader, writer, validation
    local function cancelled() assert(not options.cancelled or not options.cancelled(),"cancelled") end
    local ok,result=pcall(function()
        reader=self.reader();assert(reader:open(source),"cannot open source EPUB")
        local files,by_path=self:_index(reader)
        local images=self:_manifest(reader,by_path)
        local total=0
        for _ in pairs(images) do total=total+1 end
        assert(total>0,"no supported image pages")
        cancelled()
        writer=self.writer();assert(writer:open(output,"zip"),"cannot create output EPUB")
        if options.created then options.created() end
        assert(writer:setZipCompression("store"),"ZIP compression unavailable")
        assert(writer:addFileFromMemory("mimetype","application/epub+zip"),"cannot write mimetype")
        assert(writer:setZipCompression("deflate"),"ZIP compression unavailable")
        local processed=0
        for _, entry in ipairs(files) do
            cancelled()
            if entry.path~="mimetype" and entry.mode=="file" then
                local data=self:_read(reader,entry)
                local media=images[entry.path]
                if media then
                    data=assert(self.filter(data,media,options.profile),"image processing failed")
                    assert(type(data)=="string" and self.validate_image(data,media),"processed image invalid")
                    processed=processed+1
                end
                assert(writer:addFileFromMemory(entry.path,data),"EPUB write failed")
                if media and options.progress then options.progress(processed,total) end
            end
        end
        writer:close();assert(not writer.err,"EPUB close failed");writer=nil
        cancelled()
        if options.validating then options.validating() end
        validation=self.reader();assert(validation:open(output),"cannot validate output EPUB")
        local output_files,output_index=self:_index(validation)
        self:_manifest(validation,output_index)
        local original_files=0
        for _, entry in ipairs(files) do if entry.mode=="file" then original_files=original_files+1 end end
        assert(#output_files==original_files,"output member set changed")
        for _, entry in ipairs(output_files) do
            cancelled()
            local original=by_path[entry.path]
            assert(original,"extra output resource")
            local data=self:_read(validation,entry)
            if images[entry.path] then assert(self.validate_image(data,images[entry.path]),"output image invalid")
            else assert(data==self:_read(reader,original),"EPUB document structure changed") end
        end
        return {validated=true,processed_pages=processed,total_pages=total}
    end)
    for _, handle in ipairs({reader or false,writer or false,validation or false}) do
        if handle then pcall(handle.close,handle) end
    end
    if not ok then return nil,tostring(result) end
    return result
end

return Epub
