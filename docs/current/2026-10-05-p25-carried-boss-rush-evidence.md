# P25 Carried Boss Rush Evidence

- Status: Verified native rules and production menu integration
- Document Role: Current
- Authority Level: Milestone validation evidence under standing authorization
- Applies To: Carried Boss Rush and shared Boss difficulty projection
- Owner: Plane Walker project owner
- Depends On: `../superpowers/specs/2026-10-05-p25-carried-boss-rush-design.md`, `../superpowers/plans/2026-10-05-p25-carried-boss-rush-plan.md`
- Last Verified: 2026-10-05

## Delivered

Production Main selects carried rules; the first ordinary victory unlocks the
entry. Legacy fresh-stage callers and saves keep their separate fingerprint.
The original five native arenas use validated HP1.2/damage1.1 projections.
BossDefinition authenticates canonical base, bounded multipliers, all primary
hits, phase damage overrides and auxiliary outgoing damage. Weakpoint and
self-damage thresholds remain authored. Projection JSON and cold Boss runtime
restore remain validated.

Carried sessions begin at HP100/gold100 with empty item/blessing lists. Real
native terminal receipts heal30% and generate deterministic blessing, rare item
and full restoration choices. Current Launch rare items are all active items;
the reward path equips their actual runtime and retains item ID plus remaining
cooldown. Portable stats, modifiers, HP, energy and character bonuses carry into
fresh stage identities. The current weapon action and temporary active effects
retire at a stage boundary. Rejected writes freeze gameplay and permit retry or
reload through the existing compare-exchange save boundary.

Authenticated victories record frames, HP, weapon, continuation, assistance,
damage and all five native terminal receipts. The last100 summaries remain
visible; archived counts and qualifying flags retain reward ownership after
older summaries retire. First clear, five clears, unassisted fresh no-damage and
unassisted fresh under600s achievements derive Walker Proof, entry/Eternal/Void
skins and Speedwalker Boots. The follow-on separate Profile reward collection
owns claiming/equipment, without changing the exact Launch50 item pool.

The native menu exposes three real reward buttons, lock state, carried build,
history, owned rewards, controller focus and save retry/reload controls. English
and Simplified Chinese production translations are registered by Main ownership.

## Validation

- `build/boss-difficulty-red`: executable missing-API failure before projection.
- `build/boss-difficulty-green`: five Boss projection and runtime contracts pass.
- `build/boss-carried-green3`: executable reward-selection failure exposed the
  active-only authored rare pool; actual equipment path fixed the failure.
- `build/boss-carried-green8`: carried native5Boss, heal/choice, equipment,
  physical history and active HP cold-continuation pass.
- `build/boss-carried-retain-final`: six combat/save/Main scenes pass; original
  visual fixture lacked a qualifying ordinary Profile and was corrected by root.
- `build/test-evidence/boss-carried-visual-green`: corrected production visual
  scene passes, including eligible physical Profile and required reward choice.
- `build/boss-carried-durability-green`: forged frame/HP notices refuse; failed
  promotion retains pending carried HP, retry/cold continuation preserves it,
  promoted faults reconcile and stale writers cannot replace a newer primary.

Successful logs were scanned for script/parse errors, ERROR lines, leaks and
orphans. Godot4.6.1 reports line coverage unsupported. Dependency audit command
`python3 -m pip_audit -r requirements-dev.txt` found no known vulnerabilities.

## Retention

Flow and Coordinator accept
`configure(registry, profile_service, root_path, carried=false)`; Main passes
true. Native Flow exposes `choose_reward(index)`, `uses_carried_rules`,
`is_unlocked`, `mode_reward_storage_scope` and `verified_reward_claims`.

An active saved Boss resumes at that stage entrance with carried HP/build and
continued status; it does not claim a midattack Boss checkpoint. Continued or
assisted runs retain ordinary first/five-clear rewards but cannot create the
competitive no-damage or speed entitlements. Optional global/friend rankings
remain in the offline platform adapter scope.
