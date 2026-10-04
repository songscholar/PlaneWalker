# Plane Walker Actual Content Compatibility Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Exact actual-content migration allowlist
- Applies To: ActualContentCompatibilityLedger and authenticated SaveService rebinding callers
- Owner: Runtime integration agent
- Last Verified: 2026-10-05
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16k-content-rebinding-evidence.md`, `docs/current/2026-10-05-p16-production-profile-boot-evidence.md`, `docs/current/2026-10-05-p16-hub-business-evidence.md`
- Evidence Status: Verified Locally
- Certification Status: Exact compatibility policy and physical service boundary verified; GameState routing owned by root integration

## Delivered Boundary

`ActualContentCompatibilityLedger.trusted_sources(target_binding, catalog_fingerprint)` returns detached complete prior snapshots only for two explicitly recorded transitions to the current Narrative-localization Base binding. It never reads a save file to authorize its own declared source. The caller must configure a strict source SaveService, inspect the genuine complete primary under that binding, and pass the independently obtained preimage to `rebind_profile_content`.

The audited JSON contains three exact bindings, full source commit IDs, Profile v4, the unchanged Meta catalog fingerprint, reasons and the only permitted changed file. Two archived complete Base descriptors are retained as provenance, not as loadable content packs. The runtime pins the reviewed ledger's byte hash, verifies each descriptor's actual Godot canonical fingerprint and complete snapshot aggregate, authenticates current Meta semantics and legacy references, and proves entire descriptors differ only in `localization/translations.csv`. Altered or unrecorded targets, mods, catalog fingerprints, schemas and reverse transitions return an empty candidate list. There is no caller-provided ledger configuration.

| Binding | Provenance | Pack Fingerprint | Aggregate |
| --- | --- | --- | --- |
| Original actual P16 | `5bee8ef`, `54bee98`, `c48116a` share the same complete descriptor | `5f71d5f2974f4b6927594397e593acb75bef7d9806d0fbf0d028f15dc2efc99e` | `359f78795637dac50112df36f8be804e28f6700ef2a2d8efe52e174dd0d3a47c` |
| Hub localization | `100d754` | `46e09bb02ab515c6ad2944b4c8d30f561fca7fcfe3e28b56afc38fc1154d2903` | `de23d7d6c778f8f6f26fe4163270bfd840dfc758df8ce9c8f855f3ca2e969b5b` |
| Narrative localization target | `b6e6a2c` | `35b38b70f84c80df5433475c385344b5206eb9922164f8a7aa82277baaca18f7` | `897d72f310a123362093fcd27d31eac692689ab0a1583177d3d807abf6407a49` |

All use Meta fingerprint `cba6d5e7eb2e8b574d240ebb6f06b35f909e1b4e8e0f840f5f0f89309b36217d`. The historical descriptors are copied directly from Git. The separate Node audit compares their complete objects to every recorded source commit, authenticates every historical authored content file against its declared SHA, and checks unchanged Meta Profile, Catalog, Factory, SaveEnvelope and legacy reference bytes against the current checkout. Godot performs its own canonical numeric JSON hashing; the Node audit does not approximate that encoding.

## Verification

Meaningful missing-policy API RED: `build/test-logs/p16-actual-compatibility/api-red` and `final-target-red`. The expanded physical fixture's intermediate GDScript type-inference failure is retained under `physical` and is not a behavioral RED.

Physical policy/service GREEN: `build/test-logs/p16-actual-compatibility/physical-fixed`. It checks both exact sources against every existing Save fault point, authenticated retry, post-promotion reconciliation, no ordinary implicit mismatch acceptance, unchanged original primary bytes on pre-promotion faults, complete Meta and authentic frozen launch/config preservation, creation identity, exactly one sequence increment, malformed full preimages, genuine concurrent writes, unknown self-declared sources, recomputed unknown targets, additional packs, schema/version changes, reverse targets, different Meta semantics and detached output mutation.

`node tools/save/validate_actual_content_compatibility.mjs` passes: three committed descriptor proofs, two exact localization-only transitions, unchanged Meta semantics and Profile v4 schema. `git diff --check` passes. The separate eight-key Narrative localization checkpoint `b6e6a2c` passed localization validation and Godot editor import before the target was frozen. Godot line coverage is unsupported; no percentage is claimed.

Existing `content_rebinding` and `save_service` regressions also pass, one scene each, under `rebinding-regression` and `save-regression`. All three focused scenes contain no script errors or object leaks.

## Retention And Future Updates

Retain this focused local policy commit. GameState/Main integration is deliberately separate. The ledger grants no general compatibility across versions and performs no catalog or Save-schema migration. Existing historical synthetic-profile migration remains a separate previously approved policy.

A future content fingerprint change requires another explicit descriptor proof, exact source/target entry, documented compatibility reason, updated runtime ledger byte pin, historical audit and physical failure tests. A target absent from the ledger fails closed even if its catalog fingerprint happens to match. Unsupported old gameplay snapshots continue to refuse strict source inspection. No remote publication or dependency change was performed.
