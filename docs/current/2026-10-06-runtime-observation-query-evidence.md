# Native Runtime Observation Query Evidence

- Status: Focused Verified / Full gameplay certification pending
- Document Role: Current native gameplay performance retention evidence
- Authority Level: Implementation evidence below the gameplay completion plan
- Applies To: Host exports and event-player synchronization
- Owner: Plane Walker integration lead
- Depends On: `docs/current/2026-10-06-runtime-observation-query-plan.md`
- Last Verified: 2026-10-06
- Contract References: `tests/integration/application/native_runtime_observation_query_test.gd`

## Retained Behavior

Orchestrator provides detached event health and complete event exports, and
projects temporary modifiers using the existing authenticated lifetime authority.
Stable health synchronization reads only its participant. Changed physical HP
still creates and validates the complete event candidate before the original
RunState commit. Pending route and terminal behavior retain their existing guards.

RunState already constructs a detached full snapshot, including every nested
mutable export. Orchestrator and Host now return that export without making two
additional deep copies. There is no snapshot cache, skipped validation, new state
writer, save schema or time rule.

## Verification

The valid RED at `build/test-evidence/runtime-observation-query-red-valid` shows
36 full Run exports for 12 stable Host reads, and missing narrow queries. Earlier
test-authoring parse errors are not the product RED. Final focused GREEN is
`build/test-evidence/runtime-observation-query-green-retained`.

The actual Main regression proves one full export per stable read, exact complete
state, deep caller isolation, detached event observations, changed physical HP,
authenticated active modifier projection, projection mutation isolation and
terminal modifier retirement. The modifier participant is explicitly synthetic;
Main, physical Player health and Host exports are real production participants.

- Host integration: 1 scene passed.
- Event contracts, lifetimes, compensation, native encounters and Save: all 20 scenes passed.
- Native replay recorder, backpressure, terminal, history, storage and library: all 9 scenes passed.
- Native combat physical checkpoint and exact continuation: 1 scene passed.
- Facade regression initially exposed an already expected injected rollback error without an exact TestSuite scope. Its separate test-only repair is retained in `959696e` and passed strict dual logs.
- All three pinned dependency requirement files passed `pip-audit` without known vulnerabilities.
- Two independent read-only reviews found no actionable production regression. The UI lane independently passed the isolated scene at `build/test-evidence/runtime-query-independent-review`.

## Frozen Pair

Before: `build/retained-checkout/runtime-query-before-20261006`, report
`build/runtime-query-floor2-before/report.json` inside that checkout.

After: `build/retained-checkout/runtime-query-after-20261006`, report
`build/runtime-query-floor2-after/report.json` inside that checkout. It overlays
only the three application runtime files on the same committed before source;
source fingerprints identify the actual overlays. It is not a clean final
certification checkout.

Both retain 600 actual accepted Player frames, floor-2 Boss phase 0, 12 Hub frames,
concurrent recording and fresh physical tape readback. Content, encounter,
sample range, entity peaks and exact first/last tape hashes match.

| Metric | Before mean | After mean | Before p95 | After p95 |
|---|---:|---:|---:|---:|
| Host process | 2.399 ms | 1.008 ms | 5.533 ms | 2.265 ms |
| Player advance | 26.487 ms | 27.216 ms | 46.766 ms | 48.162 ms |
| Physics wait | 3.445 ms | 1.386 ms | 6.497 ms | 2.327 ms |
| Probe observer | 0.730 ms | 0.831 ms | 1.388 ms | 1.758 ms |

This pair ran headless fixed-FPS during other verification work. Results are
mixed: the directly changed Host path improves and has an executable reduction
from three full materializations to one, while Player/observer timings do not
improve. It is not evidence of overall 60 Hz certification. The 16.667 ms rendered
budget, complete native matrix, five-floor run and full coverage remain pending.
Human playtesting remains 0/20. UI runtime implementation has not started.
