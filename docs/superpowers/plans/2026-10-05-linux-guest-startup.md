# Linux Guest Startup Implementation Plan

- Status: Active
- Document Role: Current focused export verification plan
- Authority Level: P19 local platform verification
- Applies To: Authenticated Linux x86_64 release artifact in a Docker Linux guest
- Owner: Project owner
- Last Verified: 2026-10-05
- Implementation Status: In progress
- Depends On: [P19 packaged startup evidence](../../current/2026-10-05-p19-packaged-startup-evidence.md); [export tool contract](../../../tools/export/README.md)
- Exit Gate: Passing refusal contracts and real guest startup with clean logs

**Goal:** Execute the retained Linux release executable in an isolated Linux guest while preserving the distinction from a real Linux host.

**Architecture:** A host Python CLI validates the existing export contract and exact artifact evidence, inspects an already installed digest-pinned Linux amd64 Docker image, and launches only the executable in a read-only, network-disabled container. It reuses the existing native startup-result validator and strict export-log scanner. Source files and personal Docker configuration are never mounted.

**Tech Stack:** Python standard library, Docker CLI, official Godot 4.6.1 Linux x86_64 release executable.

The existing host verifier remains the host evidence authority. Extending it with an implicit container fallback would obscure what was actually run. A separate guest verifier records host OS, Linux guest architecture, image ID and immutable digest; the larger alternative of a virtual-machine installation adds no necessary evidence for this bounded startup check. The project owner's standing authorization permits this reversible local implementation without another design approval.

## Contracts And Implementation

- [x] Add `tests/contract/export/test_linux_guest_startup.py`; initial run failed with `ModuleNotFoundError: No module named 'verify_linux_guest_startup'`.
- [x] Add `tools/export/verify_linux_guest_startup.py` with `verify_linux_guest_startup(...) -> tuple[dict[str, object], int]` and a CLI.
- [x] Authenticate the Linux artifact before Docker launch and after execution. Refuse altered reports, paths, bytes, image identity, and incomplete startup receipts.
- [x] Refuse missing Docker, unavailable daemon/image, process failures/timeouts, script/resource/engine errors and leaks even when process exit is zero.
- [x] Verify the Docker command mounts only the artifact and fresh logs, uses empty personal-credential-independent configuration, disables network, and identifies the result as guest-only.
- [x] Run focused startup and all export contracts: 16 focused tests and all 75 export contracts passed. Documentation governance and whitespace checks passed; the three pinned dependency files have no known audit vulnerabilities.
- [x] Retain the CLI documentation and focused implementation commit with precise paths.

## Real Guest Evidence

- [ ] Obtain the final coherent committed source revision from the integration owner.
- [ ] Export all three targets from a clean retained checkout; authenticate host macOS startup.
- [ ] Inspect and record the public immutable guest image, then run Linux guest startup against those exact retained bytes.
- [ ] Record commands, source/report/artifact hashes, all 12 native checks, strict logs and remaining actual-host limits in current evidence.

This gate does not certify five-floor victories, visual layouts, controller interaction, actual Linux-host behavior, Windows-host behavior, signing, or publication. No downloaded image is pulled automatically by the verifier; an unavailable local image produces an explicit typed refusal.

The public ECR Debian image `public.ecr.aws/docker/library/debian@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251` was inspected as Linux amd64, image ID `sha256:db9f02c6bde9fa90cc8074c92754b2b046947392f1a857726e77f041febb7b82`. It executed the official Linux release template's `--version` as `4.6.1.stable.official.14d19694e`. The default Docker Hub pull timed out; no mutable tag is used by the verifier.
