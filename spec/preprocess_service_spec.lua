package.path="./koocomic.koplugin/?.lua;"..package.path
local available,Service=pcall(require,"koobone.preprocess_service")
assert(available,"downloaded-file preprocessing service is missing")
local disabled=Service:new{storage={},directory="/not-created-by-test"}
assert(disabled.available==false and type(disabled.reason)=="string")
assert(disabled:submit({})==nil and disabled:isActive()==false)
assert(disabled:jobs()[1]==nil and disabled:isLocked("/books/book.epub")==false)
assert(type(disabled.profile)=="function","processing service must freeze validated profile controls at enqueue time")
local profile=assert(disabled:profile())
assert(profile.scale_mode=="original" and profile.strength==0.8 and profile.discard_original)
disabled.profile_provider=function() return {strength=0.6,scale_mode="fit",target_width=600,target_height=800} end
profile=assert(disabled:profile());assert(profile.strength==0.6 and profile.target_width==600)
disabled.profile_provider=function() return {strength=math.huge} end
assert(not disabled:profile())
print("preprocess service spec: OK")
