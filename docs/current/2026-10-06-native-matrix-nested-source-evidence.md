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
