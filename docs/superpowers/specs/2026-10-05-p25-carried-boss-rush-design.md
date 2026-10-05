# P25 Carried Boss Rush Design

- Status: Approved under standing project authorization
- Document Role: Current
- Authority Level: Executable milestone specification
- Applies To: Original Boss Rush rules and difficulty projection
- Owner: Plane Walker project owner
- Depends On: `2026-10-05-p21a-native-boss-rush-design.md`, `../../3.7_Boss设计.md`
- Last Verified: 2026-10-05

The native Boss Rush entry uses carried rules after a normal victory. Existing
fresh-stage sessions retain their own storage identity and verified behavior.
The five authored bosses remain in the original order, with HP multiplied by
1.2 and outgoing damage by 1.1. A validated projection retains its canonical
base and exact multipliers so malformed scaling cannot enter native runtime or
cold restoration. Stage damage overrides and auxiliary outgoing damage scale
with primary attacks; player damage to weakpoints and covers does not scale.

The carried session starts at 100 HP, 100 gold, no items and no blessings. Each
authenticated native victory heals 30 percent of maximum HP and offers one
deterministic available blessing, one rare or legendary item, and full HP/time
energy restoration. The chosen reward and portable Player reward state persist
before advancing. Each new native Player keeps its fresh run identity and
weapon action state while restoring carried stats, modifiers, HP, time energy
and character bonuses. Save/resume preserves portable state and marks the run
continued; active Boss encounter resumes at its stage entrance.

A bounded mode ledger records authenticated five-stage victories, elapsed
frames, remaining HP, weapon, assisted/continued status and damage history.
Reward ownership is durable and idempotent: first clear grants Walker Proof and
entry skin; five clears grants Eternal Walker; no-damage clear grants Void
Walker; a clear below 36000 frames grants Speedwalker Boots. Native menus show
history, owned rewards and real interstage choices. Local records remain
available offline; platform global/friend adapters are optional.

Executable exit gate: legacy Boss Rush regressions, five-boss difficulty
contracts, carried native HP/build/reward tests, cold restart, malformed saves,
fault injection, stale writers, controller menu flows and logs all pass. The
parent integrates Main/Hub and reward content into the production catalog and
records the focused commit and rendered QA in the consolidated retention review.
