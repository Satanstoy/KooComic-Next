-- SPDX-License-Identifier: AGPL-3.0-only
local ffi = require("ffi")
local Archive = require("ffi/archiver")
local BB = require("ffi/blitbuffer")
local Jpeg = require("ffi/jpeg")
local Png = require("ffi/png")
local Epub = require("koobone.preprocess_epub")
local Files = require("koobone.preprocess_files")
local Profile = require("koobone.preprocess_profile")
local Backend = {}
Backend.__index = Backend

ffi.cdef[[int koocomic_filter(unsigned char *, int, int, int, int, float, size_t, size_t);]]
local turbo = ffi.loadlib("turbojpeg", "0.5.0", "turbojpeg", "0.4.0", "turbojpeg", "0.3.0", "turbojpeg")
local init = pcall(function() return turbo.tj3Init ~= nil end) and turbo.tj3Init or function(kind)
    return turbo.tj3InitVersion(kind,turbo.TURBOJPEG_VERSION_NUMBER)
end

local function readFile(path)
    local file=assert(io.open(path,"rb"))
    local data=file:read("*a");file:close()
    return assert(data,"image read failed")
end

local function writeFile(path,data)
    local file=assert(io.open(path,"wb"))
    local ok,err=file:write(data)
    local closed=file:close()
    assert(ok and closed,err or "image write failed")
end

local function be32(data,index)
    local a,b,c,d=data:byte(index,index+3)
    assert(d,"truncated PNG header")
    return ((a*256+b)*256+c)*256+d
end

function Backend:_dimensions(data,media)
    local width,height
    if media=="image/png" then
        assert(data:sub(1,8)=="\137PNG\13\10\26\10" and data:sub(13,16)=="IHDR","invalid PNG header")
        width,height=be32(data,17),be32(data,21)
    else
        assert(media=="image/jpeg","unsupported image type")
        local handle=assert(init(turbo.TJINIT_DECOMPRESS),"JPEG header decoder unavailable")
        local ok=turbo.tj3DecompressHeader(handle,ffi.cast("const unsigned char*",data),#data)==0
        if ok then width,height=turbo.tj3Get(handle,turbo.TJPARAM_JPEGWIDTH),turbo.tj3Get(handle,turbo.TJPARAM_JPEGHEIGHT) end
        turbo.tj3Destroy(handle)
        assert(ok,"invalid JPEG header")
    end
    local padded_w,padded_h=width+width%2,height+height%2
    assert(width>0 and height>0 and padded_w*padded_h*96+#data*3+64*1024*1024<=self.memory_budget,
        "page exceeds memory budget")
    return width,height,padded_w,padded_h
end

function Backend:_decode(data,media)
    if media=="image/jpeg" then return Jpeg.openDocumentFromMem(data,true) end
    writeFile(self.page_path,data)
    local ok,image=Png.decodeFromFile(self.page_path,4)
    assert(ok,"PNG decoding failed")
    local buffer=BB.new(image.width,image.height,BB.TYPE_BBRGB32,image.data)
    buffer:setAllocated(1)
    return buffer
end

function Backend:_image(data,media,profile,validate_only)
    assert(self.files:isSafe(self.page_path) and not self.files:exists(self.page_path),"unsafe or existing codec temporary file")
    local original,scaled,padded,cropped
    local ok,result=pcall(function()
        local width,height,padded_w,padded_h=self:_dimensions(data,media)
        original=self:_decode(data,media)
        assert(original:getWidth()==width and original:getHeight()==height,"image dimensions changed")
        if validate_only then return true end
        local parameters,profile_error=Profile.normalize(profile)
        assert(parameters,profile_error)
        local target_width,target_height=Profile.dimensions(width,height,parameters)
        assert(target_width,target_height)
        local image=original
        if target_width~=width or target_height~=height then
            scaled=require("ffi/mupdf").scaleBlitBuffer(original,target_width,target_height)
            assert(scaled,"image resampling failed")
            image=scaled
            width,height=target_width,target_height
            padded_w,padded_h=width+width%2,height+height%2
        end
        padded=BB.new(padded_w,padded_h,BB.TYPE_BBRGB32)
        padded:blitFrom(image,0,0,0,0,width,height)
        local pointer=ffi.cast("unsigned char*",padded.data)
        if padded_w>width then
            for row=0,height-1 do
                ffi.copy(pointer+row*padded.stride+width*4,pointer+row*padded.stride+(width-1)*4,4)
            end
        end
        if padded_h>height then ffi.copy(pointer+height*padded.stride,pointer+(height-1)*padded.stride,padded.stride) end
        local strength=parameters.strength
        assert(type(strength)=="number" and strength==strength and strength>=0 and strength<=1,"invalid filter strength")
        local status=self.native.koocomic_filter(pointer,padded_w,padded_h,padded.stride,1,strength,
            self.memory_budget,padded.stride*padded_h)
        assert(status==0,"native filter failed: "..tonumber(status))
        cropped=BB.new(width,height,BB.TYPE_BBRGB32)
        cropped:blitFrom(padded,0,0,0,0,width,height)
        local encoded,err
        local encoded_pointer=ffi.cast("unsigned char*",cropped.data)
        if media=="image/png" then encoded,err=Png.encodeToFile(self.page_path,encoded_pointer,width,height,4)
        else encoded,err=Jpeg.encodeToFile(self.page_path,encoded_pointer,width,height,4,95,cropped.stride,turbo.TJSAMP_444) end
        assert(encoded,err or "image encoding failed")
        return readFile(self.page_path)
    end)
    for _, buffer in ipairs({original or false,scaled or false,padded or false,cropped or false}) do if buffer then buffer:free() end end
    os.remove(self.page_path)
    if not ok then error(result) end
    return result
end

function Backend:new(options)
    local library=assert(options.native_library)
    assert(require("libs/libkoreader-lfs").attributes(library,"mode")=="file",
        "原生去彩纹组件缺失："..tostring(library))
    local object=setmetatable({native=ffi.load(library),
        memory_budget=options.memory_budget or 256*1024*1024,
        page_path=assert(options.workspace).."/page.codec",
        files=options.files or Files:new{roots={options.workspace}}},self)
    assert(object.native.koocomic_filter,"checked native entry required")
    object.processor=Epub:new{reader=function() return Archive.Reader:new() end,
        writer=function() return Archive.Writer:new() end,
        filter=function(data,media,profile) return object:_image(data,media,profile) end,
        validate_image=function(data,media) return object:_image(data,media,nil,true) end}
    return object
end

function Backend:process(source,output,options)
    if not self.files:isSafe(source) or not self.files:isSafe(output) or self.files:exists(output) then
        return nil,"unsafe or existing EPUB output"
    end
    return self.processor:process(source,output,options)
end

return Backend
