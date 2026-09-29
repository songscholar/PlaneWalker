# Plane Walker P7/P9 Export Certification Evidence

- Status: External Validation Pending / Current
- Document Role: Current evidence record
- Authority Level: P7/P9 local certification evidence
- Applies To: Reproducible desktop exports, detached-checkout validation, coverage, templates, and packaged startup
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, commits `da3ab1d`, `7732731`, `60a086f`, and `ff3fa7c`
- Last Verified: 2026-09-29
- Evidence Status: External Validation Pending
- Classification: `coverage_and_export_templates_pending`
- Verified Commit: `ff3fa7c44e727fd763700a921f84e8dc1e9a443e`
- Evidence Date: 2026-09-29
- Authority: `AGENTS.md` and `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Certification Result: Not certified; no platform export or packaged startup is claimed

## Outcome

The committed export toolchain now supports:

- an offline tracked contract for Windows x86_64, Linux/Steam Deck x86_64, and macOS universal exports;
- fail-closed local Godot and export-template preflight;
- stale-artifact removal before each export invocation;
- fatal log scanning, process-exit validation, and expected artifact-kind validation;
- deterministic SHA-256 evidence for files and `sha256-tree-v1` evidence for directory bundles;
- local `git clone --no-local` detached-checkout validation and export orchestration;
- explicit coverage, export, and packaged-startup completion gates.

The repository is not P7/P9 complete. The verified detached clone passed import, contracts, and every committed scene test, but code coverage was not collected and the three required Godot export templates were absent. The executor therefore issued no platform export commands and recorded no artifact hashes.

## Reproduction

Command:

```bash
python3 tools/export/certify_checkout.py \
  --commit HEAD \
  --allow-source-dirty-candidate \
  --evidence-output build/export-evidence/certification-report.json \
  --log-dir build/export-evidence/certification-logs
```

The source-candidate flag was required because the shared worktree contained two unrelated, untracked RoomRuntime test files from a concurrent lane. Those files were not present in the local clone. The cloned revision was exactly `ff3fa7c44e727fd763700a921f84e8dc1e9a443e` and was clean before validation and after export preflight.

## Detached Validation Evidence

| Check | Result |
|---|---|
| Clone method | `git clone --no-local --no-checkout`, then detached checkout |
| Clone commit | `ff3fa7c44e727fd763700a921f84e8dc1e9a443e` |
| Clean before validation | Pass |
| Localization contracts | 7 passed |
| Playtest contracts | 13 passed |
| M1 release-gate contracts | 27 passed |
| Export/certification contracts | 34 passed |
| Bootstrap import | Pass; generated translations reproduced from tracked CSV |
| Clean second import | Pass |
| Godot scene tests | 48 passed, 0 failed |
| Known warnings | One classified legacy `reward_system_smoke` ObjectDB leak |
| Clean after execution | Pass |
| Validation exit | `0` |
| Validation duration | 141,027 ms |
| Validation stdout SHA-256 | `8e24e9d0e3defe04634270b27672b1746ef1187b48d1beed444c761899f82dd4` |

The full ignored machine report was written to `build/export-evidence/certification-report.json`. Its SHA-256 for this run was `d3d4c16e2ed23c6c215aa706397e7f6d5998aa96d253de7b06f60ca81d54eae6`.

## Current Blockers

### Coverage

The validation runner reported:

```text
Code coverage: not collected (scene execution counts are not code coverage)
```

The certification orchestrator records `coverage_not_collected` and cannot mark P9 complete until a real coverage report is generated and retained.

### Export templates

Godot itself passed local preflight:

```text
4.6.1.stable.official.14d19694e
```

The following required files were absent from the Godot `4.6.1.stable` export-template directory:

- `windows_release_x86_64.exe`
- `linux_release.x86_64`
- `macos.zip`

All three target records remained `blocked` with `command: null`, `exit_code: null`, and `artifact_evidence: null`. No stale or synthetic output was accepted as an export.

### Packaged startup

Packaged startup remains a separate Gate after real artifacts exist. This run did not attempt startup because there were no verified export artifacts.

## External Release Boundary

Signing, notarization, Steam identities, remote uploads, store publication, and public release remain external operations. Their absence does not block repository implementation, but they are not represented as locally verified.

## Next Certification Run

The next P7/P9 run must:

1. produce an actual code coverage report from the clean detached checkout;
2. use matching official Godot 4.6.1 export templates;
3. export all three targets with clean logs and artifact hashes;
4. execute host-compatible packaged-startup checks and retain their logs;
5. rerun from a clean source worktree without the candidate allowance.
