# Native Replay Read Ownership Plan

- Status: Approved / Current
- Document Role: Current focused replay read memory investigation and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Private physical whole-run replay chunk observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-unified-recording-600-evidence.md`
- Last Verified: 2026-10-06

## Investigated Path

The frozen `546779f` 600-frame native probe samples 2,292,629,504 bytes of
process RSS across admission, recording and retention. A complete 120-frame
late chunk in the measured 601-observation tape has 92,224 compressed bytes and
3,851,564 raw delta bytes; the one-frame final chunk has 1,607,468 raw bytes.
Compressed or delta size does not bound the expanded observation object tree.

Codec decoding already returns owned data without a final deep copy. Each
observation is reconstructed independently through keyframe or delta copies;
its original validation and physical digest checks remain required. The Store
adds a complete chunk deep copy when receiving decoded observations into its
cache and another complete chunk deep copy when returning a cache hit through
its generic success helper. Public `read` then independently copies the selected
single observation. The two Store copies are the narrow investigated target.

## Proposed Ownership

Keep Codec unchanged. Transfer its successful owned observation array directly
into the private Store cache. A private cached return may borrow that array;
only `read` and `transition_rows` consume this private helper and neither mutates
the array. Public `read`, transition rows, identities, manifests and other
results retain their existing detached projections. Do not freeze public
observations or introduce shared mutable outputs across frames.

Every private cache hit still reads actual disk bytes and verifies their exact
length and compressed hash before borrowing. A corrupt or missing file cannot
be hidden by a positive cache. Reload clears the cache. Cross-chunk replacement,
physical failure recovery and public failure codes retain their original
behavior. Chunk size, storage quotas, compressed bytes and retention status are
unchanged.

## Executable Acceptance

The focused RED scene uses a real admitted Player identity and physically
persists a 120-observation chunk plus a second partial chunk. Cold and warm
private returns must own/borrow the same retained array, exposing the two old
whole-chunk copies without hardware-dependent timing assertions. All public
returns must remain detached through nested dictionaries, typed arrays,
StringName keys, typed dictionaries and packed values. Different decoded
frames, subsequent public reads and authenticated compressed bytes remain
independent. Transition rows, cross-chunk seeks, reload, corruption, missing
bytes and restoration require contracts.

An isolated original-versus-borrowing diagnostic must read the same immutable
large native chunk, retain exact typed output hashes, and report elapsed cold
and warm reads, expanded typed-byte volume, actual Godot static allocation and
actual macOS RSS. It is diagnostic evidence only. Implement after those results
confirm the duplication cost, then run replay, storage, package/import, platform
sharing and native recorder contracts. Final improvement requires the complete
uninstrumented native recording probe with physical endpoint readback, scoped
RSS and unchanged frame/capacity gates. Copy counts or isolated memory results
cannot certify overall FPS, the 2 GB memory gate, rendering or human playtesting.
