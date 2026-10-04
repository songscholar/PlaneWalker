# P14 Event Effects, Room Lifetime, and Full Player Replay Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and regression evidence
- Authority Level: P14 event consequence physical projection, lifetime, and Replay compatibility
- Applies To: Native Player event effects, room lifetime, merchant continuation, Save and full Player Replay
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/save-service-v3.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Focused tests pass; combined gate and reviewed integration commit belong to the integration lead

## Physical event effects

`EventTemporaryModifierLayer` owns the strictly validated physical projection `{modifier_id, magnitude, source_transaction_id}`. It replaces a complete canonical projection atomically and idempotently. Unknown fields/IDs, duplicate modifier IDs, invalid magnitude, and missing source are refused. This layer remains separate from permanent reward snapshots and clears on Player reset or terminal run cleanup.

Weapon attack adapters, character/time attack contexts, and rewind echoes consume effective attack. Guard effects affect incoming damage, and tranquility affects TimeManager energy regeneration. The authoritative modifier record includes duration; the Player projection contains only active effects. Regranting one modifier ID refreshes its source and duration instead of stacking. Duplicate same-ID operations inside one transaction are rejected.

## Successful room lifetime

`EventModifierLifetime` projects authored grants against monotonic `room_completed_v1` facts. The source room consumes zero duration; each later successful room clear consumes one, including clears across floors. Authored grants remain in the consequence participant snapshot after physical expiry, preserving transaction authentication and Replay provenance.

Older snapshots that lack completion history receive `modifier_lifetime_baseline_v1` only for dismissed sources whose successful clear cannot be reconstructed. Pending/resolved sources receive none. Repeated restores preserve the original baseline; later clears expire the effect within its authored duration. Unknown historical elapsed rooms conservatively retain the bounded authored duration rather than guessing expiry. RunState, Save, and Facade reject malformed/duplicate facts, unsupported baseline sources, and history that conflicts with the current FloorPlan.

## Native Save and merchant continuation

The real Main/controller test grants an event effect, verifies source-room zero consumption, performs physical SaveService JSON I/O, restores into a fresh configured Player/Facade, continues through an authored merchant, and verifies exact expiry. Current and legacy completion-ledger variants repeat physical Save/Facade restore after every later clear. The native five-floor path also verifies terminal physical-layer cleanup.

This continuation exposed two integration defects repaired by the integration lead: binding an already-rewarded restored Player lost the original pre-reward merchant baseline, and JSON-loaded definition ledgers failed a typed Array cast. The run-start Player reward baseline is now persisted under `resources.player_reward_run_start_baseline` before the first reward and restored before merchant reconstruction. Typed ledger normalization preserves JSON round trips. Tests reject an unknown baseline field, a removed domain, and a removed nested field while proving that existing physical Save JSON, authoritative state, permanent rewards, and temporary effects remain unchanged.

## Full Player Replay schema 7

Full Launch Player Replay root/frame/snapshot schema is 7 and includes `event_temporary_modifiers`. Weapon-only Replay remains schema 6; M1 Replay remains schema 2. Validation uses the same strict projection contract. Player installation restores TimeManager first and the event projection before downstream participants; a later restore failure compensates to the previous physical projection.

Authenticated legacy Launch schema 6 migrates to 7 with an empty event projection without mutating caller input. Legacy digest authentication precedes migration. Schemas 4/5 remain fail-closed because their passive state cannot be authenticated completely. Tests cover active and expired checkpoints, attack/guard/regeneration, repeated restore, malformed rehashed projections, digest tampering, downstream compensation, and authenticated legacy schema 6.

## Focused verification

All listed focused runs completed with no script errors or unknown leaks. Later combined results take precedence when integration changes land.

| Suite | Scenes | Evidence directory |
|---|---:|---|
| Physical event Player layer | 1 | `/tmp/planewalker-event-player-layer-green-2` |
| Modifier refresh authority | 1 | `/tmp/planewalker-event-refresh-green-2` |
| Legacy lifetime normalization | 1 | `/tmp/planewalker-event-legacy-lifetime-green` |
| Full Player Replay focused | 1 | `/tmp/planewalker-event-full-replay-green` |
| Replay regression | 11 | `/tmp/planewalker-event-replay-regressions` |
| Native five-floor current/legacy Save continuation and malformed baseline refusal | 1 | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.0Rf1XE` |

GDScript line coverage remains `godot_line_coverage_unsupported`. Native combat uses real hostile HealthComponent death signals with disabled AI movement; it proves production integration and persistence, not human balance. Final P15 enemy/Boss gameplay, P16 Hub/narrative, final audio/art, and release certification remain distinct gates.
