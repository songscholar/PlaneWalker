# P19 Retained Export And Linux Guest Startup Evidence

- Status: Approved / Current
- Document Role: Current focused export and guest startup evidence
- Authority Level: Local verification below full-product completion specification
- Applies To: Retained official three-platform exports, native macOS startup and Linux amd64 guest startup
- Owner: Project integration lead
- Depends On: [Linux guest plan](../superpowers/plans/2026-10-05-linux-guest-startup.md); [prior P19 startup evidence](2026-10-05-p19-packaged-startup-evidence.md)
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Conditional imported-source exports and two authenticated startup executions; clean bootstrap remains unverified for this revision
- Exit Gate: Exact retained bytes execute all 12 Main startup checks with no runtime errors or leaks

## Source And Import Boundary

The retained checkout `build/certified/p15-final-source-9c5d517` is a local
`git clone --no-local --no-checkout` detached at
`9c5d51799d4451039eaaa3fa1c18a8be4363af4d`. Its tracked and untracked state
was clean before import, before export, and after both startup executions.
Exports use the official `4.6.1.stable.official.14d19694e` editor and
workspace-installed `4.6.1.stable` release templates.

The first import was **not clean**. The 11 configured translation CSV catalogs
had their expected paired generated derivatives absent, which the existing
bootstrap classifier recognizes. A separate unapproved resource diagnostic
appeared during autoload creation:

```text
ERROR: Failed loading resource: res://data/content_packs/base/assets/enemies/launch/shattered_sentinel.png.
   at: _load (core/io/resource_loader.cpp:343)
```

This is retained in `build/p15-final-source-bootstrap.engine.log:184` and was
reported to the integration owner. It is not allowlisted or accepted as a
passing clean-checkout validation. The second import's stdout and engine logs
passed the strict scanner with zero failures. The evidence below therefore
certifies exports from this clean Git revision **after asset import**, and does
not certify reproducible first import or the complete validation/coverage gate.
The corrected later revision requires a fresh clone and rebuilt exports.

## Official Artifacts

All three targets exited zero, had empty fatal-log findings, and were classified
`local_export_candidate`. Paths below are relative to the retained checkout.

| Target | Artifact | Bytes | SHA-256 |
|---|---|---:|---|
| Windows x86_64 | `build/windows/PlaneWalker.exe` | 129045224 | `b918b766b47adbf8b30edbfbceefcdadd3b82fe5e87558e7d2c12f9fed362973` |
| Linux x86_64 | `build/linux/PlaneWalker.x86_64` | 95606552 | `be3ef9eeceaa342ec69cadeaceea763226a09776d4327270651708bf1be805a8` |
| macOS universal | `build/macos/PlaneWalker.app` | 208965412 | `0655baca337efbcb7fca6cfde0d3eb9b6a798e519f3cadb7cf331636584a9e06` |

The macOS digest uses `sha256-tree-v1` over all eight bundle files; Windows and
Linux use file SHA-256 with their PCK embedded. Existing packages were not
overwritten. The retained source's export report is
`build/export-evidence/p15-final-export.json`, SHA-256
`680e9be1ea1f1100cc192f4296630e4940aa2ca1f1f594e0c244e080e47d6916`.

## Actual Startup Executions

The actual macOS bundle passed `verify_packaged_startup.py` from an empty working
directory, with isolated application data and no source-project path. Its report
under the retained checkout is
`build/export-evidence/p15-final-macos-startup.json`, SHA-256
`fa19da25398f4f3b61db19c790b33f51db3946b721f66b077f43ac6b76a11ce8`.
Classification is `host_packaged_startup_verified`; process exit is zero.

The actual Linux executable passed the new verifier retained at
`a5203c6`, which authenticates the exact artifact before and after execution
and forces that executable as the container entrypoint. The real run used
Docker Desktop 4.38.0, Engine 27.5.1 and LinuxKit 6.12.5 on an arm64 guest host,
with Linux amd64 execution. The public image is immutable:

- Repository digest: `public.ecr.aws/docker/library/debian@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251`.
- Image ID: `sha256:db9f02c6bde9fa90cc8074c92754b2b046947392f1a857726e77f041febb7b82`.
- Guest report: workspace `build/export-evidence/p15-final-linux-guest.json`, SHA-256 `81504c2cbb9ad7a83e939d5939deec798acbeb2109d861d8279e0a8c2bced845`.
- Classification: `linux_guest_packaged_startup_verified`; `actual_linux_host_verified=false`; `full_product_certified=false`; process exit zero.

The container used an empty temporary Docker configuration, disabled network,
read-only root filesystem, no capabilities, non-root user and bounded temporary
storage. Only the authenticated executable and fresh output logs were mounted;
source files and personal Docker credentials were not available to it. Docker
Hub's pull timed out; the public ECR mirror supplied the image, and the verifier
itself never downloads images.

Both real executions completed the same 12 native Main checks: production boot,
native Hub first screen, Craft/Rift/Council districts, navigation preserving
Profile, gateway panel and launch control, durable native launch, production
combat route, native combat actors and durable combat checkpoint. Their native
content aggregate is
`838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`,
with Base fingerprint
`083658d9d4f7af04b6f980f341f948fb75da26b4815a55fbb5b00c7fea8fcdd7`.
All four runtime stdout/engine logs contain no fatal findings or leaks. Artifact
digests remained byte-identical before and after their executions.

## Refusal Contracts And Limits

The initial missing-module regression was observed before implementation.
All 75 export contracts passed, including nine guest contracts covering missing
Docker/daemon/image, mutable image or architecture/digest mismatch, altered
artifacts/reports, zero-exit errors/leaks, malformed/incomplete receipts,
timeouts/nonzero exits and isolated command construction. An additional RED
entrypoint assertion preceded the executable-entrypoint hardening; all nine
guest contracts then passed. Dependency audit found no known vulnerabilities in
the three pinned requirement files; whitespace and documentation governance
checks passed before evidence retention.

This proves conditional imported-source exports, macOS host startup and Linux
guest startup. It does not prove real Windows execution, actual Linux-host
display/input behavior, controller flows, five-floor victories, performance,
line coverage, human playtests, first-import reproducibility, or full-product
certification. Signing, notarization, publication and remote pushes were not
performed. The retained checkout and logs preserve the rollback/diagnostic point.
