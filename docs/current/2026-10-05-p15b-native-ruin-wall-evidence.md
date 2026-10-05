# P15B Native Ruin Walls And Warned Collapse

- Status: Verified Locally; full Boss arena scope remains active
- Document Role: Current implementation and verification evidence
- Authority Level: Retained milestone evidence below the approved P15 Boss specification
- Applies To: Ruin wall geometry, actual construct HP, accepted-frame compensation and focused cold reconstruction
- Owner: Plane Walker native Boss implementation lead
- Depends On: `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05

## Accepted Behavior

The actual Ruin P2 `guardian_wall` action retains its two authored frozen line segments throughout the complete55-frame warning. Each segment is64px long with150HP and a600-accepted-frame lifetime. Two rectangular64x12 native bodies preserve the nominal32px opening between their flat endpoints. Walls expose actual weapon Hurtboxes but never join counted enemy or Boss groups, create HealthComponent death receipts, or award room rewards.

During the warning the Boss moves31px opposite its committed aim so its24px body can clear the frozen wall. Player or Boss overlap at the activation boundary extends that same warning and preserves both threat facts. Frozen geometry outside declared room bounds, or an unreachable retreat destination outside those bounds, completes the original warning and safely cancels its action instead of rejecting every following frame. Bounds are inclusive: a legal segment endpoint exactly atY354 remains admissible. Other obstacles and combined path clearance remain part of the later arena certification gate.

Wall HP and damage provenance are authoritative arena state. The shared damage ledger rejects duplicate weapon identities and reconstructs exact remaining HP. Sibling refusal restores the Boss position, action generations, warning facts, wall HP and physical nodes; the same frame and weapon fact can then retry. Dynamic reconstruction replaces native wall children when their stable identities differ.

An intact wall expires at `spawn_frame + 600`, removes its physical collider, and requests one authenticated40-frame collapse warning through the shared semantic zone authority. The final native physical hit deals8HP within radius24. Already weapon-broken walls never request a collapse. Shared capacity preserves the full warning if admission is pending. Prepared Actor requests authenticate wall creation and collapse; the accepted modifier range6.4 through12 covers the existing debuff, buff and enrage multipliers.

The nested arena snapshot moves from schema1 to schema2 with explicit `walls` and `wall_claims`; the owning Ruin Boss remains at schema2. Exact historical covers-only arena1 snapshots normalize to empty walls. Exact historical Boss runtime1 normalization remains supported. Current snapshots reject unknown fields, altered HP, age, geometry and generation provenance. Current cold reconstruction recreates the accepted native walls without resurrecting a broken collider.

The original locally generated CC0 wall raster has three states: intact, damaged and debris. Its192x24 atlas, reproducible generator and SHA256 provenance are retained in the constructs manifest. Artwork loads lazily through a typed Texture2D endpoint so clean bootstrap does not require an imported raster at script parse time.

## Verification

- Creation, real HP, rollback/retry and focused cold reconstruction GREEN: `planewalker-tests.bKQAkl`,1/1.
- Missing collapse warning/damage RED: `planewalker-tests.fZnfQW`; TTL/collapse GREEN: `planewalker-tests.RNIGr6`,1/1.
- Full wall, occupied Player activation and malformed cold state GREEN: `planewalker-tests.7791x4` and `planewalker-tests.Z9sXFD`,1/1 each.
- Outside-room placement RED: `planewalker-tests.0MR0n2`; exact legal endpoint regression RED: `planewalker-tests.qx4xc1`; fixed edge GREEN: `planewalker-tests.GBCuqH`,1/1.
- Final wall suite including safe cancellation when a left-edge Boss cannot retreat GREEN: `planewalker-tests.OmF3sH`,1/1. It checks creation at115, damage at116, expiry at715, the complete collapse warning through754 and one8HP native hit at755. It also checks refusal/retry at creation, wall damage, expiration and final collapse damage.
- Existing complete cover/enrage/aftershock regression: `planewalker-tests.CNEpMd`,1/1. The Gauntlets fixture now waits one process frame for its retained deferred area callback; immediate projectile duplicate checks remain immediate.
- Existing physical native checkpoint regression: `planewalker-tests.yslk6S`,1/1. Boss runtime: `planewalker-tests.AYQDP1`,1/1. Semantic effects/router: `planewalker-tests.8jo8hP`,2/2.
- Native GL fixture passes with clean `build/test-logs/p15b-native-wall/engine.log`. Inspected intact, broken, collapse-warning and collapsed captures are retained under `build/visual-evidence/p15b-native-arena/ruin-wall-*-640x360.png` and `ruin-wall-*-1280x720.png`; raster foreground pixel checks pass at both resolutions.
- Final focused logs contain no script errors, deferred callback errors or known leaks. Ordinary scene runs report `godot_line_coverage_unsupported`; no line-coverage percentage is claimed.

## Remaining Work

Ruin HP20/TTL480/cap4 debris and combined48px escape certification remain open. The wall suite is a focused native Actor/Player/effects fixture: only phase-cue warmup advances the pure runtime, and the Player is placed outside later AI attacks during most of the lifetime before returning for the final collapse. It does not certify arbitrary wall angle/pathfinding, the five-weapon wall contact matrix, or a fresh production Host checkpoint containing live walls and collapse work.

Forest, Forge and Void constructs, authentic Time ability responses and the complete750 loadout/Boss matrix remain open. Base descriptor bindings and content fingerprints are unchanged; declaring the code-owned native Actor/art asset surface remains a separate content-pack closure gate.

No dependency changed, remote push, publication or purchase occurred. Source, tests, generator, artwork and this focused evidence are retained through a precise local commit.
