# Native Narrative Checkpoint Regression Evidence

- Status: Approved / Current
- Document Role: Current focused native narrative regression evidence
- Authority Level: Executable acceptance record
- Applies To: Canonical narrative room fixtures and retired-ending cold recovery
- Owner: Runtime integration lane
- Depends On: `2026-10-05-p16o-native-narrative-evidence.md`, `../superpowers/specs/2026-10-05-plane-walker-p16o-native-narrative-flow-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Six native narrative scenes verified; combined product certification pending
- Exit Gate: Canonical routes, exact checkpoint recovery, one ending handoff and scanned narrative logs pass

The combined native verification exposed an obsolete narrative fixture. It
directly rewrote floor state and transitioned an unrelated room binding. Full
native checkpoint validation correctly refused its physical collection command,
leaving the expected Continue action unavailable. The original failed combined
run is retained under `build/test-logs/native-collision-replay/`.

The fixture now traverses the shared NativeLaunchRoute commands. Optional target
floor and cleared-Boss boundaries retain the helper's existing default behavior.
Route selection, authored rewards, room publication and next-floor entry remain
actual production operations. Combat completion and Boss source receipts are
fixtures, so this does not certify five real Boss fights.

The ending promotion regression retires its coordinator during the physical
write. The saved ending remains authoritative while the changed presentation
leaves native publication pending. A diagnostic run confirmed that reopening
selection safety cancels a transient action and advances weapon generation;
reward-only recovery cannot authenticate the full saved Player codec. The exact
checkpoint guard remains intact.

Recovery uses a fresh Main, physical Profile reload and the production
Host.restore_profile_checkpoint path. It verifies the complete saved Player
codec, canonical Run, physical payload and unchanged Profile revision before
binding a new coordinator. Saved ending presentation emits one handoff; repeated
terminal presentation emits none. Settlement and credits remain separate durable
steps. Missing-action failures now exit with useful assertions instead of
causing Nil access errors and timeout.

## Verification

The focused coordinator run at
`build/test-logs/p21c-narrative-regression/cold-retired-ending/` passes, with no
script, resource or leak diagnostics. Its earlier `recovery-diagnostic/` run is
retained as RED evidence.

```sh
TEST_LOG_DIR=build/test-logs/p21c-narrative-regression/final \
  ./tools/run_tests.sh --filter narrative --timeout 120
```

All six scenes pass: Main narrative handoff, coordinator, physical Main narrative
checkpoint, Profile narrative service, ending predicates and narrative domain.
The final focused and six-scene logs contain no script, parse, resource or leak
diagnostics; only the existing sandboxed macOS certificate lookup error remains.
`git diff --check` passes, and the required read-only pinned dependency audit
reports no known vulnerabilities. Official Godot still reports line coverage as
unsupported; passing scenes are not represented as line coverage. After Root
indexed this evidence, document governance passes with zero violations.

No dependencies, production authority checks, gameplay tuning or UI rendering
were changed. Native rendering evidence from the existing narrative milestone
remains separate. The focused local commit is the rollback point; no remote
push, publication or external identity is used.
