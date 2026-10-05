# Windows Wine Guest Startup Evidence

- Status: Wine Guest Startup Verified / Actual Windows host pending
- Document Role: Current compatibility verification evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Authenticated Windows x86-64 local export startup in a Wine guest
- Owner: Plane Walker integration team
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## Verified Tooling

`tools/export/verify_windows_wine_guest_startup.py` accepts an already installed,
immutable Linux/amd64 image ID. It verifies the Docker image identity and the
export report, hashes the Windows executable before and after running, and
requires the exact twelve native startup checks. An error or engine-object
leak in either stdout or the independent engine log fails verification even
when the process exits zero.

The guest has no network, a read-only image, no Linux capabilities, no privilege
escalation, a non-root UID and an isolated temporary Wine prefix. Only the
authenticated executable and the in-workspace evidence directory are mounted.
Docker uses an empty configuration rather than host credentials. Timeouts
remove only this verifier's uniquely named guest.

Four contract methods cover success and refusal of changed artifacts,
duplicate exports, mutable/wrong-architecture/wrong-identity images, missing
Docker state, runtime failures, leaks, nonzero exits, incomplete receipts and
timeouts. Their GREEN log is
`build/windows-guest/logs/verifier-green.stdout.log`; the original missing-module
RED is `build/windows-guest/logs/verifier-red.stdout.log`. The contract module is
included in `tools/validate_project.sh`.

## Runtime And Artifact Boundary

The image recipe is `tools/export/docker/windows_wine_guest.Dockerfile`. It
uses Debian's digest-pinned official base and freely licensed Debian Wine,
Xvfb, Xauth and DejaVu packages. The local image build is retained in
`build/windows-guest/logs/image-build.stdout.log`. The selected base digest is
`sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251`.

CrossOver's x86-64 loader was unavailable on this host (`Bad CPU type in
executable`). No host translation runtime or personal CrossOver configuration
was installed or modified. The Docker amd64 guest is the reversible fallback.

The actual compatibility run uses the already retained export at
`build/certified/p15-final-source-9c5d517`, commit
`9c5d51799d4451039eaaa3fa1c18a8be4363af4d`. Its export report is
`build/export-evidence/p15-final-export.json`, classification
`local_export_candidate`. The selected `build/windows/PlaneWalker.exe` is
129,045,224 bytes with SHA-256
`b918b766b47adbf8b30edbfbceefcdadd3b82fe5e87558e7d2c12f9fed362973`.
The hash was independently rechecked before the guest run.

## Actual Compatibility Result

The image build completed successfully. Its immutable Linux/amd64 ID is
`sha256:6df128b4aff4babe6b13127640f6bba07ee94423831ab4d5d321ed2950a0efef`.
Package provenance at `build/windows-guest/logs/runtime-package-versions.stdout.log`
records Wine/libwine `8.0~repack-4`, Xvfb `2:21.1.7-3+deb12u13`, Xauth
`1:1.1.2-1` and DejaVu `2.37-6`.

The actual executable returned zero and passed all twelve exact native checks:
production boot, Hub first screen, craft, rift, council, profile-preserving
navigation, Gateway panel and launch control, durable launch, production
combat route, native combat actors and durable combat checkpoint. Both stdout
and the independent engine log passed strict error/leak scanning. The package
SHA-256 remains unchanged after execution and was independently rechecked.

The authoritative report is
`build/export-evidence/windows-wine-guest-startup-capacity.json`; its native
receipt and two logs are retained under
`build/export-evidence/windows-wine-guest-startup-capacity-logs/`.
The process and all uniquely named diagnostic containers have been removed;
all related execution sessions completed.

Earlier failed attempts remain intact. A PID-1 `xvfb-run` waited indefinitely
for its display-ready signal; Docker `--init` resolves that orchestration
issue. Wine then refused a root-owned temporary directory. The temporary
filesystem now belongs to the non-root verification UID/GID. Finally, the
512-MiB prefix filled completely and omitted `ucrtbase.dll`; diagnostic `df`
evidence is at `build/windows-guest/logs/diagnostic-prefix-capacity.stdout.log`.
The prefix now has a 1-GiB capacity with executable DLL mappings and a 2-GiB
container memory limit. All other isolation constraints remain. Contract RED
and GREEN logs for each correction are retained in `build/windows-guest/logs/`.
The final four-method contract run passes.

Wine logs an unavailable optional 32-bit bootstrap helper. This 64-bit target
still starts the authentic engine and produces the complete native receipt;
no Windows runtime files were downloaded or injected into the package.

The passing guest result is classified
`windows_wine_guest_packaged_startup_verified`, with
`actual_windows_host_verified=false` and `full_product_certified=false`.
This older candidate cannot certify the latest combined source or full-game
completion, real Windows host behavior, visuals, controllers or human playtests.
