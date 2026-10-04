# Training Content Compatibility Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Exact Training localization compatibility policy
- Applies To: Base translations, ActualContentCompatibilityLedger and production Profile boot
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16-actual-content-compatibility-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Exact historical rebinding verified; combined product certification pending

Four Training UI keys are present in both source catalogs. The entire pre-training
Narrative descriptor is retained at
`data/save/compatibility/base_p16_narrative_before_training.json`. Localization
source checkpoint `14a1d3b0b0d39ce885f6366ddd9ff2894bc07d88` gives the new target
an independently verifiable Git provenance before the compatibility policy is
installed. That intermediate content checkpoint must be consumed together with
the following ledger update for historical Profile compatibility.

The ledger admits exactly the three previously authenticated actual-content
bindings to the Training target. It permits only the localization CSV hash to
change; every authored gameplay definition, Meta semantic source and Profile v4
schema remains authenticated against the recorded real commits. The current
four complete descriptors and three transitions are pinned by ledger byte hash.

Godot produced target pack fingerprint
`5410744506218905c156ee9a1ca868a1baa6bf16130602875e8d29aa3d3bbe0a`
and aggregate
`d484655161da5bbfddd7fd3fc82afd54b363fc0609020c2070eac7a885fde074`.
The read-only `tools/content/print_snapshot.gd` reports the actual authenticated
runtime snapshot; Node does not approximate Godot canonical JSON encoding.

## Verification

- `python3 tools/validate_localization.py .`: PASS.
- `node tools/save/validate_actual_content_compatibility.mjs`: four committed
  descriptor proofs, three exact localization-only transitions, unchanged Meta
  semantics and Profile schema, PASS.
- `build/test-logs/p16-training-compatibility`: physical failure/retry, all three
  historical sources, unknown sources, concurrent writers and full Profile
  preservation, one scene GREEN, no script errors or object leaks.
- `build/test-logs/p16-training-profile-boot`: actual production activation,
  fresh/legacy/current/three reviewed historical Profiles and unknown-content
  refusal, one scene GREEN, no script errors or object leaks.

No additional content compatibility is implied. Gameplay changes still require
their own reviewed migration rather than a catalog-fingerprint shortcut.
