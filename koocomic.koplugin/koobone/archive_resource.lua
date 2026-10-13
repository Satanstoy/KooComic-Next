-- SPDX-License-Identifier: AGPL-3.0-only
local Resource={}
local ffi,archive
function Resource.read(reader,entry)
    local data=reader:extractToMemory(entry.path)
    if type(data)~="string" or #data~=tonumber(entry.size) or reader.err then return nil,"ZIP data/CRC validation failed" end
    if reader.verifyEnd then
        if not reader:verifyEnd() then return nil,"ZIP resource EOF/CRC validation failed" end
    elseif reader.archive then
        if not archive then ffi=require("ffi");archive=ffi.loadlib("archive","13") end
        -- A declared-length read may defer libarchive's ZIP CRC check until EOF.
        if tonumber(archive.archive_read_data(reader.archive,ffi.new("uint8_t[1]"),1))~=0 then
            return nil,"ZIP resource EOF/CRC validation failed"
        end
    end
    return data
end
return Resource
