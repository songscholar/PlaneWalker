# Native Anchored Elite Evidence

- Status: Verified Locally / Combined certification pending
- Document Role: Current native elite verification evidence
- Authority Level: Below the approved enemy and Boss specification
- Applies To: Native Anchored control, frame rollback and historical cold restoration
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05

## Executable scope

- Compiler revision 3 executes Anchored on the actual native elite Actor. Fresh production encounters use revision 3.
- Actual weapon knockback has displacement multiplier zero. Accepted launch controls add 20 poise; every 100 poise spends the threshold and pauses native motion/actions for 20 unpaused accepted frames.
- An existing warning keeps its committed origin, target, shape and generations. The threat lifetime extends by exactly the accepted paused-frame count.
- Actual Stop and freeze pause the recovery budget; actual Rift retains native movement slowdown. Compatible regeneration continues during Anchor action recovery.
- Health admission and the existing launch-control token/generation claim must both succeed before poise increases. Duplicate facts, duplicate action tokens, stale generations, negative displacement, zero damage and ordinary hits cannot mint poise.
- Late rejection restores actual Health, poise, recovery, claims and species state. Whole Player late-World rejection preserves complete native Player and Actor state.
- Schema 2 carries bounded Anchor state. Typed cold validation refuses inconsistent poise/count/timeline/recovery/terminal state and future control admission. Candidate transactions still allow their in-flight next frame.
- Historical compiler revision 2 retains the original metadata-only Anchored signature and original displacement behavior. Current Actors refuse silently restoring that behavior.

## Tests and evidence

- Initial displacement/state RED: `planewalker-tests.TgL5h8`; minimal GREEN: `planewalker-tests.PLQsWC`.
- Accepted-cold future-control RED before guard: `planewalker-tests.nyxoCj`. Its only assertion failure was the forged future control frame.
- Full Anchor suite GREEN: `planewalker-tests.gh0BGq`.
- All three elite suites GREEN: `planewalker-tests.BMePM0`.
- Native Actor transaction suite GREEN: `planewalker-tests.xQI1Rg`.
- Production encounter suite GREEN: `planewalker-tests.9P57XI`.
- Native physical combat checkpoint suite GREEN: `planewalker-tests.ULb4HV`.
- Physical SaveService serialization, fresh Actor restoration and two independent accepted continuation branches are covered for revisions 2 and 3.
- Successful logs were scanned for script/deferred errors, physics-query mutation, invalid calls and ObjectDB/RID leaks. None were found. The intentionally injected late World rejection emits its expected rejection diagnostic.
- Stock Godot does not expose line coverage to these focused runs; the runner reports `godot_line_coverage_unsupported`. These results are behavioral evidence, not a coverage percentage.
- Independent read-only review by the boss-arena implementation lane found no additional confirmed Anchor issue.

## Limits and retained decisions

- The native portal displacement path is still pending. Knockback refusal does not certify portal integration.
- Shielded, Nullified, Teleporting, Chaining, Splitting and Mirroring remain pending native execution at this milestone.
- Authored encounters retain their current affix assignments; seeded affix selection remains pending.
- The shared Actor's generic native activation hook is retained for the separately tested Ruin wall work. This default hook returns false for ordinary Actors.
- Exploratory fixture failures before full GREEN are not acceptance evidence. Their initial warning registration and expected inclusive Stop endpoint were corrected before acceptance.
