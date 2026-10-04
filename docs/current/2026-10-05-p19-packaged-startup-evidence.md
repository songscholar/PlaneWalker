# P19 Release Export And Packaged Startup Evidence

- Status: Approved / Current
- Document Role: Current focused export and startup evidence
- Authority Level: Verification below full-product completion specification
- Applies To: Official Godot 4.6.1 release templates and native Main startup
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p19-packaged-startup.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Three release artifacts and host startup verified as a dirty development candidate
- Exit Gate: Authenticated real release executable completes native startup without runtime errors or leaks

## Actual Results

Godot rejected the old Linux/BSD platform while the previous contract accepted
the matching manifest and preset. The new regression reproduced that acceptance
failure. Both files now use the actual Godot 4.6.1 Linux/X11 name, and the
preflight pins the platform for each target. Export preflight/executor/checkout
contracts passed 38 tests; the subsequent startup and preflight run passed 19.

`build/export-evidence/p19-startup-candidate-final.json` records three successful
official release exports with no fatal export signatures:

| Target | Bytes | Artifact SHA-256 |
|---|---:|---|
| Windows x86_64 | 126347568 | `b73eba62202f83d1aa3ef71f19b41b768adc44dbfa8bdb94a557e1c2bebb43fb` |
| Linux x86_64 | 92908896 | `73c025ebade80526b21b27157ee5b5c0d8ccb9c543c7850596956002b0e4945c` |
| macOS universal | 206267756 | `b5143c3749bf8d923fd67cb4ce545c1ee4975e4b523314e78aa44dd6688149de` |

The macOS hash uses the established `sha256-tree-v1` bundle algorithm. File
targets embed their PCK. Artifacts include the current shared development state;
they are not attributed to a clean committed revision.

## Release Execution

The official release template rejects command-line scene overrides, including
with a zero process exit. That actual rejection is retained in
`build/test-logs/p19-packed-hub.log`; it is not accepted as successful startup.

The configured Main now handles the explicit
`--plane-walker-startup-check` user argument. Its diagnostic requires isolated
user data and a report path, uses the real native gateway controller with seed
20261005, and performs twelve checks: production content/Profile boot, native
first screen, all three Hub districts, navigation immutability, gateway panel
and available control, one durable launch, real combat route, native actors and
a physical combat checkpoint. It drains retired audio before exiting.

`tools/export/verify_packaged_startup.py` starts the actual bundle executable
from a newly created empty working directory. It authenticates the artifact
before and after execution and rejects process failures, zero-exit errors,
leaks, missing reports, malformed schemas and incomplete checks. These refusal
cases use synthetic process fixtures and are distinguished from the actual
release execution below.

`build/export-evidence/p19-packaged-startup-final.json` is GREEN. The exact macOS
bundle above executed all twelve native checks and exited zero. Both retained
logs have no script errors, engine errors or leaks. The actual packed Registry
aggregate is `e6575e275c0ba84658488bebf2681660d1e20b8c0b397d575e24a6969a9b8cda`.

## Remaining Gates

This is host startup evidence, not full-game completion. Windows/Linux native
execution is explicitly unexecuted on this macOS host. A clean committed clone,
combined gameplay/coverage certification, complete enemy/Boss mechanisms,
Expansion modes and authentic human playtests remain active program work.
No signing identity, publication or remote upload was used.
