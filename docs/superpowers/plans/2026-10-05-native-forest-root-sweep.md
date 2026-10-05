# Native Forest Root Sweep Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Execution details below the approved P15 specification
- Applies To: Surviving-root selection, frozen sweep geometry, permanent segment gating, native cancellation and cold compatibility
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`, `docs/current/2026-10-05-p15b-native-forest-roots-evidence.md`
- Last Verified: 2026-10-05
- Exit Gate: Deterministic pure root selection/receipts, actual root-origin warning/damage, broken-root cancellation/retry, translated room origin, current/explicit historical cold recovery, semantic burn and affected regressions pass. Sacs, flowers, cages, drain and saplings remain separate gates.

**Goal:** Make the authored45/12/40 root sweep originate from a specific surviving root. Damaging/breaking that root can remove its segment without changing the Player's history or inventing enemy rewards.

**Architecture:** Forest arena state records deterministic nearest-root selection, stable-slot tie breaking and the exact damage/phase boundary at commitment. The Boss Action coordinator retains its existing strict geometry schema, receiving the selected root world origin as the frozen source. Native composition supplies the validated room translation. Explicit arena/Boss version normalization preserves exact previously retained rootless/root-bearing snapshots and any historical in-progress trunk-origin sweep.

## Tasks

- [ ] Add meaningful pure and native RED tests for root-origin sweep and permanent segment gating.
- [ ] Add versioned Forest sweep ownership receipts and strict historical normalization, including translated native room origin.
- [ ] Bind explicit and automatic action selection to surviving roots within the authored96px selection range, preserving stable ties and frozen target geometry.
- [ ] Cancel selected-root warning/active geometry on accepted root destruction; retire generations within the existing whole-frame compensation and retry boundary.
- [ ] Verify actual20/26 damage,45-frame warning, burn semantics, current/historical isolated recovery, native screenshots and affected Boss/Host regressions.
- [ ] Retain focused evidence and precise local commits. Complete Forest/P15 and750 loadout/Boss certification remain open.
