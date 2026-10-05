# P19 Temporal Frontiers Native Expansion Evidence

- Status: Verified Locally
- Document Role: Current milestone retention evidence
- Authority Level: Local implementation and verification evidence
- Applies To: Optional five-enemy Temporal Frontiers content pack
- Owner: Project owner
- Last Verified: 2026-10-05
- Depends On: Retained P15 native frame authority; P18 local content management
- Implementation Status: Implemented and locally verified
- Source Commit: `bc80b5e126c4fa0d7b0478cfef31c953a37c6ffd`
- Human Playtests: 0
- Full Product Certification: Not claimed

The retained implementation adds exactly five optional Expansion enemies, one per floor, with six distinct authored moves: Echo Lancer's delayed double thrust, Mire Cantor's slowing pool, Parallax Guard's diverging rays, Cinder Drake's charge and simultaneous three-lane fire fan, and Prism Seer's independently timed projectile lanes. Authenticated JSON, PNG, and CSV bytes are the entire package; trusted repository code supplies the Actor and deterministic runtime. Its generated pixel art is project-authored CC0. The pack is installable through the actual localized Hub content manager, including from the exported PCK.

The Base pack and its Launch count of 22 enemies remain unchanged. New selected Expansion runs freeze selection revision 3. Historical revisions 1 and 2 retain identical recipes. Enabling the pack uses an isolated `mod_` save domain; disabling preserves that domain and restores the original Base profile. The native integration test begins with a valuable 73-shard Base save and verifies its physical bytes remain identical after five Expansion runs, five fresh Main cold restores, settlements, and disable.

## Retained Changes

- `8ba3dcb`: keep the Time auxiliary test override compatible with the shared generation-identity fixture.
- `1d3a98e`: five-enemy data-only pack, closed parsers, generic native Actor, versioned encounter selection, actual content manager installation, physical/domain/save tests, generator and design.
- `bc80b5e`: generate UTF-8 LF CSV bytes and authenticate the normalized bytes, preventing clean Git checkout hash divergence.

The first pack contract was RED before implementation. An additional real Cinder fan test exposed a one-lane schedule behind three visible warnings; its authored schedule now emits all three native physical bodies only after the full paused warning and accepts real central-lane Player HP loss. No Base data was edited.

## Exact-Source Verification

All results below use `git archive bc80b5e` in `build/test-source/temporal-frontiers-retention`, without copying dirty runtime files from peers. The archive passed the pack contract, five enemies' domain continuation/corruption test, all six real native attacks, five actual Main install/route/save/reload/settlement cases, the Time fixture regression, five existing Launch encounter suites, and the content-manager viewport/controller suite: 10/10 Godot scene tests and 4/4 Python contracts GREEN.

The first clean archive import regenerated the configured translation derivatives, with only the repository's documented bootstrap missing-translation diagnostics. The second import `build/p19-retained-import-clean.log` is clean. Scene, visual, export, and startup logs were scanned for script/resource errors, generic errors, and leaked objects/RIDs; no unregistered failures remain. GDScript line coverage is unsupported by the native runner and is not claimed.

The native test uses the actual Player, trusted Actors, physical payload authority, threat registry, and shared frame bridge. It verifies actual HP loss, terminal weapon damage, Stop/Rift, typed cold snapshots, exact schedules and all three Cinder bodies. Its room is the actual open-field template bound to each corresponding floor palette. Fifteen Compatibility-renderer screenshots at 640x360, 1280x720, and 2560x1080 pass pixel checks and manual framing inspection under `build/visual-evidence/temporal-frontiers`. The exact-source visual log is `build/p19-retained-visual.log`.

The actual Main test finds each enemy through real seeded FloorGenerator/encounter-catalog selection, commits a genuine warning, physically persists it, reconstructs a fresh Main, and compares the next native and full Player frames to the uninterrupted branch. Prerequisite rooms/Boss receipts used to reach the target floor are test fixtures; this is not an unassisted five-floor victory claim.

## Export And Limits

The exact archive exported macOS Universal with the local Godot 4.6.1 templates. Reports and clean logs are under `build/test-source/temporal-frontiers-retention/build/p19-retained-export`. Authenticated source export retained 106 declared raw files, including optional pack bytes. The artifact is `build/test-source/temporal-frontiers-retention/build/macos/PlaneWalker.app`; SHA-256 tree digest is `c49102a3d12ea1183ba010084007d6cc3638efb0d808565e20c1d816a42bc592`.

The official executable passed all 12 retained packaged-startup checks from an isolated empty working directory: production boot, real Hub navigation, Gateway launch, native combat actors, and durable checkpoint. Official release templates do not support overriding the main scene. The same-version editor therefore ran the five-floor Main test against the actual release PCK in an empty directory, with isolated saves and no workspace resource fallback. This verifies bundled pack installation and native continuation from packed bytes without changing the production entry point.

The archive export is intentionally classified `non_release_dirty_candidate` because the existing export tool discovers the parent repository's active peer worktree; the exported source itself is fixed at the documented archive commit. This local milestone does not certify the full product, signing, publication, cross-platform runtime, or human playtesting. Rollback is the focused local commits above, and the pack can be disabled without changing Base content or deleting its recoverable save domain.

## Global Localization Contract Follow-Up

Commit `fb29f1c` repairs the global localization validator's handling of optional pack catalogs. It now validates the pack's declared `localization/strings.csv` and dependency catalogs for that pack's content, while core literal `tr()` checks retain the configured runtime catalog scope. An unrelated optional catalog cannot hide a missing core or pack key, and the Base catalogs remain unchanged. Seven new fixtures cover declared/undeclared sources, transitive dependencies, missing/cyclic dependencies, absent optional dependencies, duplicate pack keys, malformed CSV and pack path/symlink escapes. All 23 localization/import contracts and the whole-project localization CLI passed. This tool-only follow-up is separate from the earlier archived native/export source certification.
