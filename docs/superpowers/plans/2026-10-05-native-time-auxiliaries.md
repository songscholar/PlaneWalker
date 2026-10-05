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

**Architecture:** An independent deterministic auxiliary module stores accepted Slash marks and hit receipts. Boss schema10 snapshots own that module; native Effects authenticate accepted damage and Player applies the strongest active mark before subsequent Time damage. Projectile contact creates a finite semantic slow projection; Freeze owns a bounded regeneration modifier through Player's existing modifier authority.

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

- [x] Connect Boss schema10 state with exact schema1/9 historical normalization; active schema9 response ledger and next-frame continuation survive unchanged.
- [x] Authenticate Effects/Actor accepted-hit receipts and apply strongest mark to all Time damage before flat defense; visible production watch indicator retires with owner.
- [x] Carry sealed physical Bolt contact into semantic r16/180frame slow zone with shared hazard budget; forged contact cannot create a zone.
- [x] Add bounded Player/TimeManager regeneration modifier and compensated Collapse spend with exact energy revision and quiet refused-frame signals.

## Task 3: Verification And Retention

- [x] Real Player cast lifecycle, refused-frame compensation/retry, death/disposal and physical Save/typed Replay reconstruction; cold Boss, Effects and full Player next-frame states equal uninterrupted branch.
- [x] Verify complete35frame Blink and Slash warnings, collision-safe locked facing landing, native raster projection and retained Stop command inside Freeze.
- [ ] Export the focused retained source and repeat native/domain/shared checks independently from other current work.

## Current Evidence

- Native auxiliary/domain2/2GREEN: `build/time-auxiliary-final-native2`; added Bolt leave-zone criterion also passes native Metal capture.
- Schema1/9 migration and strict current state checks: `build/time-auxiliary-domain-migration`.
- Native response1/1GREEN: `build/time-auxiliary-final-response`; shared projectile domain1/1GREEN: `build/time-auxiliary-shared-payload-final`.
- Four authentic production Profiles1/1GREEN each: `build/time-auxiliary-profile-{stop,rewind,accelerate,rift}`.
- Native Compatibility renderer on Apple M4 Pro: Slash mark, Bolt impact and Freeze at640x360,1280x720,2560x1080; captures are in `build/visual-evidence/time-auxiliary/`.
- `python3 -m pip_audit -r requirements-dev.txt` reports no known vulnerabilities.
- Only intentional World publication refusal logs at Slash35 and Freeze120 are accepted; no script errors or leak diagnostics in final passing runs.

## Reversible Decisions

- Bolt slow0.70 is a bounded conservative value because the approved regular Bolt recipe specifies slow but no multiplier. It adds no extra damage and ends immediately on exit.
- Collapse follows the canonical three locked circles. Authored `timeline_echo` final bursts retain their independent35frame explosion warning; this integration creates no additional unspecced summon recipe.
- A one-frame native replay fixture advances both live and freshly reconstructed branches; explicit tests account for that accepted frame.
