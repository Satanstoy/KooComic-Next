package.path = "./koocomic.koplugin/?.lua;" .. package.path
local available, Identity = pcall(require, "koobone.preprocess_identity")
assert(available, "preprocess identity is not implemented")
local source = { book_id = "book", source_fingerprint = "sha256:a", algorithm_version = "fft-1",
    profile = { strength = 0.8, width = 1272, height = 1696 } }
local first = assert(Identity.key(source))
local reordered = { book_id = "book", source_fingerprint = "sha256:a", algorithm_version = "fft-1",
    profile = { height = 1696, width = 1272, strength = 0.8 } }
assert(Identity.key(reordered) == first, "profile insertion order must not change identity")
source.source_fingerprint = "sha256:b"
assert(Identity.key(source) ~= first)
source.source_fingerprint, source.algorithm_version = "sha256:a", "fft-2"
assert(Identity.key(source) ~= first)
source.algorithm_version, source.profile.strength = "fft-1", 0.5
assert(Identity.key(source) ~= first)
assert(Identity.key{ title = "Not an identity" } == nil)
source.profile.strength = 0/0
assert(Identity.key(source) == nil, "non-finite parameters must be rejected")
source.profile.strength = 0.800000000000001
local close = assert(Identity.key(source))
source.profile.strength = 0.800000000000002
assert(Identity.key(source) ~= close, "distinct floating point parameters must retain their identity")
print("preprocess identity spec: OK")
