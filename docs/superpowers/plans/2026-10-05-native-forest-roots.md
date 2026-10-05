# Native Forest Roots Implementation Plan

- Status: Completed / Historical for the focused root interaction slice
- Document Role: Historical implementation and verification plan
- Authority Level: Execution details below the approved P15 specification
- Applies To: Six Forest root constructs, independent HP,45-frame body exposure and permanent P2 retirement
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05
- Implementation Status: Verified locally and retained in commit `adf97fb`
- Completion Evidence: `docs/current/2026-10-05-p15b-native-forest-roots-evidence.md`, root native/pure contracts and four inspected OpenGL screenshots
- Exit Gate: Native root hit, refused-frame retry,45-frame exposure, deterministic P2 retirement, exact current/historical cold recovery, logs and raster screenshots pass; full Forest action and loadout gates remain separately recorded.

**Goal:** Retain an actual Forest root interaction with strict pure state, native collision and cold recovery. This slice does not certify the entire Forest arena.

**Architecture:** A dedicated Forest arena domain owns stable root rows, damage receipts, exposure and once-only deterministic P2 retirement. The existing Boss runtime and native Actor project it through the same arena transaction interface. Six circle12 root colliders remain uncounted arena targets. Current Forest Boss runtime schema2 carries the arena; exact historical schema1 receives an explicit default root migration, including P2 retirement when the historical Boss phase requires it.

## Tasks

- [x] Add meaningful pure and native RED tests before implementation.
- [x] Implement sixHP100/radius12 root rows preserving48px central/perimeter routes, permanent damage facts,45 accepted exposure frames and once-only deterministic three-survivor P2 retirement.
- [x] Project original pixel-art root bodies/Hurtboxes with stable weapon identities; never count roots as enemy deaths or rewards. Keep the trunk always hittable.
- [x] Integrate accepted whole-frame compensation, root geometry tamper rejection, current/historical native cold state and owner death retirement.
- [x] Verify native break/retry, phase transition/retry, cold recovery, existing Ruin/Watch/Boss/Host checkpoint regressions and native640/1280 visual evidence.
- [x] Retain [focused evidence](../../current/2026-10-05-p15b-native-forest-roots-evidence.md) and precise local commit. Keep full five-weapon and combined750 loadout/Boss certification open until executed.

## Remaining Forest Closure

Selected surviving-root sweep origin/segment ownership, sacs and interrupted seeds, flowers, bounded cages, erosion, drain actual-loss healing and sapling lifetimes remain distinct execution gates. Their declarations do not count as native certification.
