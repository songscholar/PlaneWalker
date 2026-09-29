# Plane Walker Export Executor and Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- Status: Current
- Authority: `AGENTS.md` and the approved full-product completion design
- Depends On: `da3ab1d`, `data/toolchain/export_targets.json`, `tools/export/preflight.py`
- Scope: P7 export execution/evidence contract followed by P9 detached-checkout orchestration contract
- Evidence Boundary: No target is marked exported unless Godot exits successfully, logs are clean, and the expected artifact is hashed from the current invocation
- Implementation Status: Tasks 1 and 2 complete; Task 3 remains the next independent P9 slice
- Task 1/2 Verification: 27 export contracts passed; local execution stopped before export with three `template_missing` blockers; project validation passed 48 of 49 scenes with one unrelated untracked RoomRuntime test missing its implementation

**Goal:** Add a real export executor that fails before export when the local toolchain is incomplete, records deterministic file/directory hashes for successful artifacts, and produces machine-readable evidence suitable for later detached-checkout certification.

**Architecture:** `artifact_evidence.py` owns deterministic artifact hashing and export-log classification. `build_exports.py` owns target selection, local preflight, stale-artifact removal, Godot process execution, status reduction, and atomic report writing. A later certification orchestrator will consume the executor report from a clean local clone; it will not duplicate export logic or reinterpret blocker states.

**Tech Stack:** Python 3 standard library, Godot 4.6.1 command-line export, SHA-256, JSON evidence, `unittest`, fake executable fixtures.

## Global Constraints

- The executor never downloads templates or dependencies.
- A missing Godot executable, incompatible Godot version, missing template, dirty worktree without explicit candidate allowance, non-zero export exit, fatal log signature, missing artifact, or artifact type mismatch fails closed.
- Artifact paths remain below `build/` and come only from the validated target manifest.
- A previous artifact is removed before invoking Godot so a stale file cannot satisfy the evidence gate.
- Windows and Linux artifacts are files; the macOS `.app` artifact is a directory tree.
- Directory hashes include sorted relative paths, regular-file contents, and symbolic-link targets but exclude timestamps and absolute paths.
- Reports distinguish `pass`, `blocked`, and `failed`; only `pass` contains artifact evidence.
- `pass` while `--allow-dirty-candidate` is active is classified `non_release_dirty_candidate`, never release evidence.
- Signing, notarization, Steam identities, remote upload, and public publication remain external operations.

---

### Task 1: Deterministic artifact and log evidence

**Files:**

- Create: `tools/export/artifact_evidence.py`
- Create: `tests/contract/export/test_export_executor.py`
- Modify: `data/toolchain/export_targets.json`

**Interfaces:**

- Produces: `describe_artifact(path: Path, project_root: Path, expected_kind: str) -> dict[str, object]`.
- Produces: `scan_export_logs(paths: Sequence[Path]) -> list[dict[str, str]]`.
- Adds manifest field: `artifact_kind`, exactly `file` or `directory`.

- [x] **Step 1: Write failing evidence tests**

Tests must prove:

```python
def test_file_evidence_contains_sha256_size_and_relative_path(self) -> None:
    artifact.write_bytes(b"plane-walker")
    evidence = describe_artifact(artifact, root, "file")
    self.assertEqual(evidence["sha256"], hashlib.sha256(b"plane-walker").hexdigest())
    self.assertEqual(evidence["size_bytes"], 12)
    self.assertEqual(evidence["path"], "build/windows/PlaneWalker.exe")

def test_directory_digest_is_creation_order_and_mtime_independent(self) -> None:
    first = describe_artifact(first_app, first_root, "directory")
    second = describe_artifact(second_app, second_root, "directory")
    self.assertEqual(first["sha256"], second["sha256"])

def test_log_scanner_reports_script_errors_and_leaks(self) -> None:
    log.write_text("SCRIPT ERROR: broken\nObjectDB instances leaked at exit\n")
    self.assertEqual(
        {entry["code"] for entry in scan_export_logs([log])},
        {"script_error", "object_leak"},
    )
```

- [x] **Step 2: Run tests and capture the missing-module failure**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_executor -v
```

Expected: import failure for `artifact_evidence`.

- [x] **Step 3: Implement the evidence library**

The file digest is ordinary SHA-256. The directory digest is `sha256-tree-v1`: for every non-directory entry in sorted relative-path order, update the hash with one type byte (`F` or `L`), the UTF-8 relative-path length as an unsigned eight-byte big-endian integer, the path bytes, then either the SHA-256 bytes of file content or the UTF-8 symbolic-link target length and bytes. Return `kind`, repository-relative `path`, `sha256`, `digest_algorithm`, `size_bytes`, `file_count`, and `symlink_count`.

The log scanner reads every supplied UTF-8 log with replacement and emits one record per unique `(code, path, line)` for these signatures:

```python
FAILURE_SIGNATURES = (
    ("script_error", re.compile(r"SCRIPT ERROR:|Parse Error:|Failed to load script")),
    ("resource_error", re.compile(r"Failed loading resource|Cannot open file .*\\.(?:gd|tscn|tres)")),
    ("invalid_call", re.compile(r"Invalid (?:call|get|set)(?:\\.| )")),
    ("object_leak", re.compile(r"ObjectDB instances leaked at exit|RID allocations leaked at exit")),
    ("assertion_failure", re.compile(r"Assertion failed|Smoke test failed")),
)
```

- [x] **Step 4: Add artifact kinds to the manifest and preflight**

Set `artifact_kind` to `file`, `file`, and `directory` for Windows, Linux, and macOS. The preflight rejects any other value and includes it in each target report.

- [x] **Step 5: Run focused tests**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_preflight tests.contract.export.test_export_executor -v
```

Expected: all preflight and artifact-evidence contracts pass.

### Task 2: Fail-closed export executor and structured report

**Files:**

- Create: `tools/export/build_exports.py`
- Modify: `tests/contract/export/test_export_executor.py`
- Modify: `tools/validate_project.sh`

**Interfaces:**

- Produces: `run_exports(project_root: Path, target_ids: Sequence[str], godot_bin: str, templates_dir: Path | None, evidence_output: Path, log_dir: Path, timeout_seconds: int, allow_dirty_candidate: bool) -> tuple[dict[str, object], int]`.
- CLI: `python3 tools/export/build_exports.py [--target ID] [--godot-bin PATH] [--templates-dir PATH] [--evidence-output PATH] [--log-dir PATH] [--timeout-seconds N] [--allow-dirty-candidate]`.
- Exit `0`: every selected target exported, logs were clean, and artifacts were hashed.
- Exit `2`: repository contract or arguments were invalid.
- Exit `3`: local toolchain or clean-worktree requirement blocked execution before export.
- Exit `4`: Godot ran but an export, log, or artifact gate failed.

- [x] **Step 1: Write failing executor tests**

Use a fake Godot executable with two paths:

```bash
if [[ "${1:-}" == "--version" ]]; then
  printf '4.6.1.stable.official.fixture\n'
  exit 0
fi
while (( $# > 0 )); do
  case "$1" in
    --log-file) engine_log="$2"; shift 2 ;;
    --export-release) preset="$2"; artifact="$3"; shift 3 ;;
    *) shift ;;
  esac
done
printf 'exported %s\n' "${preset}" >"${engine_log}"
case "${artifact}" in
  *.app) mkdir -p "${artifact}/Contents/MacOS"; printf 'fixture' >"${artifact}/Contents/MacOS/PlaneWalker" ;;
  *) mkdir -p "$(dirname "${artifact}")"; printf 'fixture' >"${artifact}" ;;
esac
```

Tests assert:

- absent templates yield exit `3`, a `blocked` report, null commands, and no artifacts;
- complete fake templates plus fake Godot yield exit `0` and three non-empty artifact hashes;
- a zero-exit fake Godot that writes `SCRIPT ERROR:` yields exit `4` and no artifact evidence;
- a non-zero fake Godot yields exit `4` even if it writes an artifact;
- an existing stale artifact is removed, and if Godot creates nothing the target fails `artifact_missing`;
- an unknown `--target` yields exit `2` without invoking Godot;
- stdout JSON equals the atomically written evidence file.

- [x] **Step 2: Implement preflight-first execution**

Execution order is exact:

1. Run `validate_contract`.
2. Validate target IDs.
3. Collect `git rev-parse HEAD` and `git status --porcelain --untracked-files=all`.
4. Run `validate_local_environment`.
5. If contract, target, clean-worktree, or local-toolchain checks fail, write evidence and return without any export command.
6. For each selected target, remove only its already-validated artifact path, create its parent and log directory, then invoke Godot.
7. Scan stdout and engine logs.
8. Require exit `0`, no failure signatures, expected artifact kind, and successful hash evidence.
9. Atomically write the final report after every terminal path.

Each target record contains:

```json
{
  "id": "windows-x86_64",
  "status": "pass",
  "preset": "Windows Release",
  "artifact": "build/windows/PlaneWalker.exe",
  "artifact_kind": "file",
  "command": ["godot", "--headless", "--path", "<root>", "--log-file", "<log>", "--export-release", "Windows Release", "<artifact>"],
  "exit_code": 0,
  "logs": {
    "stdout": "build/export-evidence/logs/windows-x86_64/stdout.log",
    "engine": "build/export-evidence/logs/windows-x86_64/engine.log",
    "failures": []
  },
  "artifact_evidence": {
    "kind": "file",
    "path": "build/windows/PlaneWalker.exe",
    "sha256": "<64 lowercase hex characters>",
    "digest_algorithm": "sha256",
    "size_bytes": 7,
    "file_count": 1,
    "symlink_count": 0
  }
}
```

- [x] **Step 3: Make the export suite part of project validation**

Replace the single export unittest invocation with:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
    tests.contract.export.test_export_preflight \
    tests.contract.export.test_export_executor
```

Project validation runs contracts only; it does not run local exports or require installed templates.

- [x] **Step 4: Verify the real missing-template path**

```bash
python3 tools/export/build_exports.py \
  --evidence-output build/export-evidence/local-blocked.json
```

Expected: exit `3`, status `blocked`, three `template_missing` blockers, no export commands, and no target artifact.

- [x] **Step 5: Run regressions and commit Task 1/2 together**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tests.contract.export.test_export_preflight \
  tests.contract.export.test_export_executor -v
./tools/test_ci_contract.sh
git diff --check
git add \
  data/toolchain/export_targets.json \
  docs/superpowers/plans/2026-09-29-plane-walker-export-executor-evidence.md \
  tests/contract/export/test_export_executor.py \
  tools/export/artifact_evidence.py \
  tools/export/build_exports.py \
  tools/export/preflight.py \
  tools/validate_project.sh
git commit -m "feat(export): record fail-closed artifact evidence"
```

### Task 3: Detached-checkout certification orchestrator

**Files:**

- Create: `tools/export/certify_checkout.py`
- Create: `tests/contract/export/test_certify_checkout.py`
- Create: `docs/current/2026-09-29-p7-p9-export-certification-evidence.md`

**Interfaces:**

- Consumes only a committed source tree, the project validation entrypoint, and `build_exports.py`.
- Creates a local `git clone --no-local` in a temporary directory; it does not use remotes or network access.
- Produces one report containing source commit, clone commit, clean-clone status, validation exit/log hash, nested export evidence, and final `pass|blocked|failed` state.
- Missing templates produce `blocked` after clean import/tests; they do not produce P7/P9 completion.

- [ ] **Step 1: Build fake-repository contract tests**

The fixture repository contains executable fake `tools/validate_project.sh` and `tools/export/build_exports.py`. Tests prove clone HEAD equality, a clean detached checkout, propagation of validation failure, propagation of export blocker state, and refusal to certify a dirty source without `--allow-source-dirty-candidate`.

- [ ] **Step 2: Implement local-clone orchestration**

Use `tempfile.TemporaryDirectory`, `git clone --no-local --no-checkout`, and `git -C <clone> checkout --detach <commit>`. Run validation first and export second. Preserve stdout/stderr logs outside the clone until the final report is atomically written. Never invoke export after validation failure.

- [ ] **Step 3: Run the repository against the missing-template boundary**

Run the orchestrator at committed HEAD. If validation passes and templates remain absent, record `P7/P9 Candidate — Export Templates Pending`. If concurrent committed regressions break validation, record `P7/P9 Candidate — Validation Repair Pending`. Neither state is complete certification.

- [ ] **Step 4: Commit certification contracts separately**

```bash
git add \
  docs/current/2026-09-29-p7-p9-export-certification-evidence.md \
  tests/contract/export/test_certify_checkout.py \
  tools/export/certify_checkout.py \
  tools/validate_project.sh
git commit -m "feat(export): certify detached checkout evidence"
```

## Self-Review

- Every export success requires a current-invocation artifact and clean logs.
- Missing templates stop before Godot export and still produce inspectable evidence.
- File and directory hashes are deterministic across absolute checkout paths and timestamps.
- Dirty candidate mode is explicitly non-release.
- Detached certification consumes, rather than recreates, executor semantics.
- No step downloads templates, signs, notarizes, publishes, or claims cross-platform startup without evidence.
