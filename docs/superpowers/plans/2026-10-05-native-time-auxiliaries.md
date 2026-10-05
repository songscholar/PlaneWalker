# Native Time Sovereign Auxiliaries Implementation Plan

- Status: In progress
- Document Role: Current
- Authority Level: Execution details below approved P15
- Applies To: Regular Time Sovereign native cast auxiliary effects
- Owner: Native enemy auxiliary implementation lead
- Depends On: `AGENTS.md`, `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Authentic casts, accepted-hit receipts, exact rollback, finite expiry and cold reconstruction pass.

**Goal:** Complete Slash mark, Bolt impact slow, Freeze regeneration and Collapse energy effects.

**Architecture:** An independent deterministic auxiliary module stores accepted Slash marks and hit receipts. Boss snapshots own that module; native Effects authenticate accepted damage and apply the strongest active mark before subsequent Time damage. Projectile contact creates a finite semantic slow projection; Freeze owns a bounded regeneration modifier through Player's existing modifier authority.

**Tech Stack:** Godot 4.6.1, GDScript, accepted 60 Hz frames, existing native raster projections.

## Constraints

- Slash accepted HP loss refreshes one mark per target, multiplier1.15 and240frames; prevented damage cannot mark.
- Bolt physical target/world impact creates r16/TTL180 slow zone; use0.70 movement until a more specific approved value exists, with no extra damage.
- Freeze owns regeneration factor0.50 only while inside its active r80 field; input/loadout ownership remains intact.
- Collapse accepted HP loss removes at most10energy and leaves at least1energy when the hit starts with positive energy; prevented damage costs0.
- Authoritative snapshots reject unknown/missing fields and duplicate receipts; exact historical Boss schema1/9 migrates to empty auxiliary state.
- Frame refusal compensates module, Player modifiers, energy revision, health and effect claims.

## Task 1: Executable Domain Criteria

- [x] Add failing pure module tests for accepted/prevented Slash, refresh/expiry, Collapse allowance, duplicate receipt and strict reconstruction; executable RED is `build/time-auxiliary-criteria-red.log`.
- [x] Implement pure auxiliary module using immutable identities, finite marks and bounded receipt storage; focused GREEN1/1 is `build/time-auxiliary-hooks-green` with no unexpected errors/leaks.

## Task 2: Native Integration

- [ ] Connect Boss state with exact historical normalization after the response milestone is retained.
- [ ] Authenticate Effects/Actor accepted-hit receipts and apply strongest mark to Time damage.
- [ ] Carry authentic Bolt contact into semantic r16/180frame slow zone with shared hazard budget.
- [ ] Add bounded Player/TimeManager regeneration modifier and compensated Collapse spend.

## Task 3: Verification And Retention

- [ ] Real Player cast lifecycle, refused-frame compensation/retry, death/disposal and cold Save/Replay reconstruction.
- [ ] Verify retained warning durations, native raster projection and unaffected time input.
- [ ] Run focused shared regressions, scan logs and retain precise commit with evidence.
