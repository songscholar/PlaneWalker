# Native Matrix Nested Source Evidence

- Status: Focused Verified / Full 750-case certification pending
- Document Role: Current native matrix frozen-checkout source validation evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native matrix committed-source authentication in retained checkouts
- Owner: Gameplay certification lane
- Depends On: `docs/current/2026-10-06-native-matrix-resume-evidence.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No full matrix, FPS, coverage or human certification

## Reproduced Failure

An untouched archive of commit `9616bec` at
`build/retained-checkout/gameplay-certification-9616bec-20261006/` imports with
the registered first-import translation bootstrap diagnostics. Its second
editor import passes strict paired stdout and Godot log validation. Before any
native gameplay starts, the one-case matrix command rejects every runtime
source as outside the selected commit.

Inside a nested archive without its own Git directory, Git uses the enclosing
repository and `ls-tree` applies the current-directory prefix. The original
command returns zero bytes; the same command with `--full-tree` returns the
complete selected commit tree. Source authentication now explicitly asks for
that full tree. Its two-way scope comparison and exact byte checks are retained.

## Regression Evidence

The new contract creates a real committed repository and a nested frozen source
copy without its own Git directory. The copy must authenticate successfully,
then changing one runtime file must fail its byte comparison. This reproduces
the production boundary independently of mocked Git output.

- RED: `build/native-matrix-nested-source-20261006/red.log` fails the expected
  exact-copy assertion with both files incorrectly outside the commit scope.
- GREEN: `build/native-matrix-nested-source-20261006/green.log` passes all
  27 matrix report contracts, including dirty-source and resume refusals.
- `git diff --check` passes for the changed wrapper and contract.

The failed pilot contains no gameplay result. A new committed-source archive
must be used for the next matrix run because the launcher itself belongs to the
authenticated runtime source scope. Partial or older-revision case receipts
cannot be transferred to the new source identity.

## Committed Source Verification

The untouched archive at
`build/retained-checkout/gameplay-certification-d195fe7-20261006/` freezes
`d195fe786f326fa89c913f1156a6abc972556f9e`. Both directions of the committed
source check pass. The matrix runtime/runner aggregate is
`0a0f1413e94685c9d3887871d444751b91d871eb174baa0009cfb3de787dcf59`.
First-import classification accepts the 11 regenerated configured CSV
translation pairs with zero remaining errors. No script, parse or leak
diagnostic appears. The second import passes strict paired log validation.

The first canonical case passes at 797 accepted frames, terminal Boss HP zero
and zero runner errors in 11.807 seconds. Its aggregate report is
`build/pilot-001.json` in that archive, SHA-256
`8d1f68b9d740e42d9f37953a51ad72411781a9f15995495808d93b16baed3d8d`.
The original failing Forge case 338 independently passes all three authored
phases, both paid Time casts, physical mid-action cold restoration and exact
next-frame continuation. It finishes at frame 2051, HP zero, in 44.945 seconds.
Its `build/case-338-pilot.json` SHA-256 is
`1a2bfa15706f155f697a236fee03d361a4dbfd6ba97fe1419a7e17561b264335`.
Both pilot stdout/engine pairs are strict clean. Neither bounded result is a
750-case certificate.

The native persistence integration scene passes 1/1 with strict paired logs
under `build/native-matrix-persistence-verification/` in the same archive.
The matrix, performance and coverage quick Python contracts pass 52/52.
Pinned development, coverage and production-art requirements report no known
vulnerabilities in
`build/native-matrix-nested-source-20261006/dependency-audit.json` in the main
workspace. No dependency changes are introduced.

## Actual Main Five-Floor Result

The same frozen source passes the actual Main five-floor integration scene.
The retained `build/p15-five-floor-native-run.json` reports 21 rooms, 12,153
accepted combat frames, all five canonical Bosses, `shattered_freedom`, victory
settlement and fresh physical Profile settlement verification. Ending and
credits completion remain assertions in the unchanged scene. Its SHA-256 is
`a744f898fbf147a0f0a6b339175eafc539be6ab0ad68febe047c628d8f3e3b06`.
The wrapper exits zero; both logs at `build/five-floor-current-verification/`
pass strict error/leak validation. The declared survival fixture remains
active, `unassisted_victory=false` and authentic human playtests remain zero.

## Intentionally Interrupted 750-Case Attempt

The complete requested range `[0, 750)` starts with five 150-case shards.
After the integration lead directs moving final certification to the later
art/UI/performance source, the owned wrapper is stopped before terminating its
five child processes. All are then killed; no test process remains. The wrapper
session exits 137. Its retained executions honestly stay `status=running`
without an exit receipt; there is no finalized aggregate and no completion
claim.

Exact source-bound partial receipt and strict paired-attempt validation accepts
63 canonical cases: shard prefixes 14, 12, 14, 14 and 9. All have empty
failures. Raw partial manifests, receipts, engine logs and stdout logs remain
untouched under `build/native-750-logs/` in the archive. In-flight, uncommitted
case work is excluded. A same-source continuation can use:

```sh
python3 tools/run_p15_hostile_matrix.py \
  --source-revision d195fe7 --count 750 --jobs 5 --timeout 28800 \
  --output build/native-750.json --logs build/native-750-logs --resume
```

Run it from that exact archive. New source commits or Base Pack bytes require a
fresh complete attempt. This recoverable old-source partial is diagnostic only;
it does not close final gameplay, frame-budget, coverage, export or human gates.
