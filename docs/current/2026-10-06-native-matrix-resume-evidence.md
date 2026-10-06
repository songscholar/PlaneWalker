# Native Matrix Resume Evidence

- Status: Focused Verified / Full 750-case certification pending
- Document Role: Current source-bound persistence and crash-resume evidence for the native P15 matrix
- Authority Level: Below approved full-product completion contract
- Applies To: `tools/run_p15_hostile_matrix.py` and `tests/support/p15_native_boss_matrix_runner.gd`
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-05-native-boss-matrix-evidence.md`, `docs/current/2026-10-06-native-owned-hotpath-diagnostic-evidence.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No 750-case completion claim; no FPS, soak, coverage or human certification

## Failure Reproduction

The frozen run at
`build/retained-checkout/p15-native-full-abd5b6f-20261006/` has no aggregate
report, no shard report and no runner stdout. Its five engine logs contain
517 completed case markers: 104, 103, 104, 104 and 102 per shard. Each log
stops during the next case with no script error, leak or parse diagnostic.
The wrapper's normal timeout path writes `stdout.log` and an aggregate report;
neither exists here. The retained files therefore prove an abruptly terminated
producer before wrapper finalization, but do not identify a signal or certify
the missing 233 cases.

## Persistence Contract

Each accepted case writes a typed case receipt under the shard's `cases/`
directory and then atomically replaces a partial manifest. The receipt binds
the exact source identity, Base Pack snapshot, canonical case identity, full
row and a `Replay.encode_replay_json` payload. The manifest binds the ordered
contiguous prefix, receipt byte hashes, requested range, production 60 Hz clock
and incomplete status. A receipt written before a manifest update is treated as
an uncommitted orphan and is retained for inspection; it cannot be imported.

`--resume` refuses a missing or redirected manifest, duplicate JSON fields,
parent or receipt symlinks, changed receipt bytes, foreign source/revision,
changed content snapshot, non-contiguous identities, failed rows, stale logs or
an unmatched stdout/engine log pair. It resumes only the next canonical index.
The final aggregate remains failed unless every requested case is present,
the completing attempt and every earlier `finished` attempt exit with code 0,
interrupted or timed-out attempts retain their explicit incomplete state, and
strict paired logs validate. Partial data is useful recovery evidence and never
a completion claim.

The Python wrapper records an atomic source manifest before launching a shard.
It refuses dirty working-tree content that is not byte-identical to the selected
Git commit. Each attempt also records its source, range, timeout and lifecycle
in `execution.json`; stdout is streamed directly to disk while Godot runs.

## Bounded Physical Slice

The integration scene
`tests/integration/playtest/native_matrix_persistence_test.tscn` passes with
strict paired logs. It verifies an empty partial, typed integer and packed-array
round trip, recomputed outer hashes, typed/JSON mismatch refusal and orphan
retention.

These are pre-commit working-tree mechanism probes with a recorded parent
revision and exact source aggregate, not clean-commit gameplay certificates.
The one-case probe's parent revision is
`ea35dc7f907370ddb68fe0d0659ba6b9be06f381`, while the crash-resume probe's parent
revision is `3a12ebf85ccc46019ac1b603e09041ee56434219`. Both retain source aggregate
`d40dd37630e36a722d5489b3770a175e5769551904cc5583986eb8ecf00bc12e`; the current
CLI intentionally refuses to call this dirty working-tree aggregate committed
source until a frozen checkout is rebuilt after the implementation commit.
The first one-case report is
`build/p15-resume-native-v3/native-000-001/report.json` (SHA-256
`8bbbfd9bb7849b0f485a635c26b7cc1c50754ffc57135f5428cbf0953c652d16`), with
one terminal case and zero failures. A zero-work same-source resume rewrites
the final report with no errors.

The crash-resume slice is
`build/p15-resume-hard-stop-native/native-000-002/`. The producer and Godot
child are forcibly terminated after case 0's atomic receipt and manifest. The
same source then resumes case 1 and exits zero. The final report contains exactly
indices 0 and 1, both terminal with `final_hp=0` and empty failures. Its report
SHA-256 is `aabd2dd3d7b992064d0530e023035c94bc7f288ba65711363c4040e399d5a404`.
The retained partial SHA-256 is
`92f1ccddbf67effa614ecdd517c4ca56657d49bd6566d2cfb5057530b78062d5`.

The two attempts have strict paired logs. Attempt `000` was intentionally
SIGKILL-terminated and remains an interrupted `status=running` execution with
no normal exit receipt; its unflushed next case is not counted. Attempt `001`
records `resumed_case_count=1`, `status=finished`,
`exit_code=0`; its final report and all retained attempt logs validate cleanly.
This bounded run validates the resume mechanism and its failure semantics; it
does not certify the full matrix.

## Tests

- `python3 -m unittest tests/contract/playtest/test_native_boss_matrix_report.py`: 26 passed after the hardening follow-up below.
- `tests/integration/playtest/native_matrix_persistence_test.tscn`: passed.
- `python3 tools/runtime_log_validation.py` over both attempt stdout/engine pairs: passed.
- `git diff --check`: passed.

## Frozen Source Pilot

After commit `f5d6833cec91114bb7909bcb59c93ac8450b3bb9` incorporated the
native frame observation change, a detached checkout was imported with
Godot headless editor startup; the follow-up editor startup passes strict
paired logs. The first pilot before import failed during
Godot resource loading because generated translation and script cache artifacts
were absent; it produced no gameplay rows and is retained as an import
prerequisite failure, not a gameplay result.

The imported frozen checkout then ran `--start 0 --count 2 --jobs 1` to
`build/native-matrix-pilot-imported/`: both canonical cases completed, strict
paired logs passed, and the aggregate had zero errors. A same-source
`--resume` rerun completed without reexecuting gameplay (`resumed_case_count=2`)
and also had zero errors. The fresh and resumed report hashes are
`fb20ca8727c444e2f1ede7bf0eb8af27649e57b4862d94541183fd64c8f3c846` and
`a897a84a45ef8bf9d93a7993a8cbc607f1fd1f326228ecdcb480e2b7ea16cbd0`.

The same frozen checkout also executes a committed-source hard-stop probe at
`build/native-matrix-hard-stop-committed/`. Its producer process group is killed
after the first case manifest reports exactly one committed row. Attempt `000`
therefore remains `running` with no exit code; it cannot claim completion. A
same-source resume runs only case 1, records `resumed_case_count=1`, finishes with
exit code zero, and produces exactly indices `[0, 1]` with both final HP values
zero. Strict paired logs for both attempts pass. The resumed aggregate SHA-256
is `761a56800f1af78caf32ed6696bc82575af3bd7f72770459354dc34ab8306292`.

This is a clean-commit bounded pilot only; it does not certify the 750-case
matrix or human playability.

## Resume Hardening Follow-Up

The wrapper now checks the selected commit's entire runtime source scope in
both directions. Missing and extra paths both refuse before any process launch
or source-manifest write. Every retained attempt requires the same requested
range and source. A `finished` attempt requires integer exit code 0, `timed_out`
requires integer exit code 124, and an interrupted `running` attempt must have
no exit-code field. Prior nonzero finished executions cannot be relabeled as
successful by a later resume.

Output, manifest, attempts, attempt directories, retained logs and atomic-write
temporary files refuse symlink redirection before writing or launching Godot.
The persistence scene additionally compares the restored row's complete
`var_to_bytes` representation with the original row, independently of numeric
Dictionary equality.

The five new regressions all fail against the unchanged wrapper from `0c78b98`
(SHA-256 `4ab3854b6e23b7647b5f721d7d42a3c231701176f41cce9513ce81a624fb0b8e`).
The only test compatibility shim discards the newly added expected-range
arguments; it does not change the old validator implementation. The retained
RED log is `build/native-matrix-review-hardening-20261006/original-contracts-red-head.log`.
Candidate Python contracts pass 26/26. The updated native persistence scene
passes 1/1 with strict stdout and engine logs under
`build/native-matrix-review-hardening-20261006/persistence/`. These focused
results do not replace full-matrix or human-playtest certification.
