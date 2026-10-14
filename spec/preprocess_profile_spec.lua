package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Profile=pcall(require,"koobone.preprocess_profile")
assert(loaded,"explicit preprocessing scale/strength profile is missing")
local original=assert(Profile.normalize())
assert(original.strength==0.8 and original.scale_mode=="original" and original.order=="resize_then_filter")
local w,h=Profile.dimensions(1000,2000,original);assert(w==1000 and h==2000)
w,h=Profile.dimensions(1,20000,original);assert(w==1 and h==20000,"original dimensions must not inherit a target-size ceiling")
local fit=assert(Profile.normalize{strength=0.5,scale_mode="fit",target_width=600,target_height=800})
w,h=Profile.dimensions(1000,2000,fit);assert(w==400 and h==800)
w,h=Profile.dimensions(300,400,fit);assert(w==300 and h==400,"fit must never upscale small images")
for _,value in ipairs({false,{scale_mode=false},{order="filter_then_resize"},{resampler="unknown"},{algorithm_version="unknown"},
    {strength=0/0},{strength=2},{scale_mode="invented"},{scale_mode="fit",target_width=0,target_height=800},
    {scale_mode="fit",target_width=600.5,target_height=800},{scale_mode="fit",target_width=600,target_height=math.huge}}) do
    assert(not Profile.normalize(value),"invalid processing controls must be rejected")
end
local Identity=require("koobone.preprocess_identity")
local source={book_id="one",source_fingerprint=string.rep("a",64),algorithm_version="kissfft-f2892a2-v1",profile=original}
local id=assert(Identity.key(source));source.profile=fit;assert(Identity.key(source)~=id)
print("preprocess profile spec: OK")
