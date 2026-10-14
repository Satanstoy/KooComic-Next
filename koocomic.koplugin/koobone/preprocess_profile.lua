-- SPDX-License-Identifier: AGPL-3.0-only
local Profile={}
local function dimension(value)
    return type(value)=="number" and value>=1 and value<=16384 and value==math.floor(value)
end
function Profile.normalize(value)
    if value==nil then value={} end
    if type(value)~="table" then return nil,"invalid profile" end
    if (value.order~=nil and value.order~="resize_then_filter") or
            (value.resampler~=nil and value.resampler~="mupdf-v1") or
            (value.algorithm_version~=nil and value.algorithm_version~="kissfft-f2892a2-v1") then
        return nil,"unsupported processing pipeline"
    end
    local strength=value.strength
    if strength==nil then strength=0.8 end
    if type(strength)~="number" or strength~=strength or strength<0 or strength>1 then return nil,"invalid strength" end
    local mode=value.scale_mode
    if mode==nil then mode="original" end
    if mode~="original" and mode~="fit" then return nil,"invalid scale mode" end
    local result={strength=strength,scale_mode=mode,order="resize_then_filter",resampler="mupdf-v1"}
    if mode=="fit" then
        if not dimension(value.target_width) or not dimension(value.target_height) then return nil,"invalid target dimensions" end
        result.target_width,result.target_height=value.target_width,value.target_height
    end
    return result
end
function Profile.dimensions(width,height,profile)
    local function source_dimension(value)
        return type(value)=="number" and value>=1 and value<=2147483647 and value==math.floor(value)
    end
    if not source_dimension(width) or not source_dimension(height) then return nil,"invalid source dimensions" end
    local normalized,err=Profile.normalize(profile)
    if not normalized then return nil,err end
    if normalized.scale_mode=="original" then return width,height end
    local ratio=math.min(1,normalized.target_width/width,normalized.target_height/height)
    return math.max(1,math.floor(width*ratio)),math.max(1,math.floor(height*ratio))
end
return Profile
