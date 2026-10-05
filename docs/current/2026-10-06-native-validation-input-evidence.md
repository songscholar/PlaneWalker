# Native Validation Input Evidence

- Status: Implemented / Current
- Document Role: Current focused native validation and ownership evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native cold, effect and semantic snapshot validation
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-native-validation-input-plan.md`
- Evidence Status: Verified Locally
- Certification Status: No FPS, rendered, soak, combined coverage or human certification

## Verified Behavior

Three internal validation projections borrow canonical current snapshots for
synchronous read-only validation. Mixed-schema inputs copy only an envelope
whose migrated child differs. Earlier root versions still use the original
complete migration. Public normalizers and runtime restoration continue owning
independent deep copies. No validation predicate or historical data is removed.

The focused fixture uses a real authored encounter recipe and configured effect
authorities, with a complete 180-frame semantic health history. Sixteen repeated
complete validations retain the exact input references at all three boundaries
and preserve every typed input byte. Eight root/effect/semantic schema
combinations produce exactly the previous public-normalization bytes and leave
their source unchanged. Public normalizer results are still deeply detached;
editing an external normalized history cannot change its source.

Full validation rejects nonfinite history, impossible clocks, unknown fields,
numerically equal float schema versions, future integer versions at each child
and root, wrong run identity and wrong final frame after valid observations.
An independent read-only review traced the nested encounter, effects, spatial,
history, threat and geometry validators and found no caller writes or skipped
checks. Its requested future-version cases were added and passed.

## Retained RED And GREEN

The initial RED and first GREEN in `build/native-validation-input-red` and
`build/native-validation-input-green` contain a fixture mistake: a raw profile
was passed where an encounter recipe projection was required. Both failures
remain retained and do not count as acceptance evidence.

The corrected fixture is mechanically overlaid onto a clean detached
`546779f9af6f3efe7bf551734398a9a1a9a1b1d0` checkout at
`build/retained-checkout/validation-input-red-546779f`. Its production runtime
is untouched. `build/native-validation-input-red-final` inside that checkout
passes its complete authored source setup and fails exactly the three missing
internal-projection assertions. There are no script/parse failures or leaks.
Final GREEN is `build/native-validation-input-green-final` in the primary
workspace and passes the complete expanded scene and paired strict logs.

| Production Regression | Retained Logs | Result |
| --- | --- | --- |
| Complete validation projection and migration | `build/native-validation-input-green-final` | 1/1 strict PASS |
| Real hostile damage and compensation | `build/native-validation-input-launch_hostile_effect_authority` | 1/1 strict PASS |
| Real semantic healing, zones, status and cleanup | `build/native-validation-input-launch_semantic_effects` | 1/1 strict PASS |
| Automatic durable run replay recording | `build/native-validation-input-native_run_replay_recorder` | 1/1 strict PASS |
| All 25 physical native checkpoint cases | `build/native-validation-input-checkpoint` | 1/1 strict PASS |

Godot is `4.6.1.stable.official.14d19694e`. The focused runs do not collect
statement coverage and are not combined frozen-source certification. Their
runtime logs contain no unexpected engine/script errors or object/RID leaks.

## Remaining Gates

Reference identity proves avoided complete input copies; it does not measure
whole-frame savings. A later committed source must repeat native/rendered
performance, process memory, sustained recording and clean full validation.
UI polish remains pending, and authentic human playtests remain 0/20.
