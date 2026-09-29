# P3 ContentRegistry v2 Completion Evidence

- Status: Verified / Completed
- Authority Level: Foundation certification evidence
- Applies To: P3 versioned content packs, declarative effects, runtime content activation, and SaveService content fingerprints
- Verified On: 2026-09-29
- Certified HEAD: `43b0f9a` plus the later documentation-only certification commit
- Rollback Point: `72093bd` (`refactor(save): route GameState through SaveService`)
- Next Gate: P4 Single RunState / RoomRuntime

## Completion decision

P3 is complete. The required base pack is validated before activation; optional pack failures can be isolated; gameplay effects are restricted to a closed declarative catalog; runtime drafting and compatibility pools read activated registry definitions; hard-coded reward arrays and `RewardDataLoader` are retired; and SaveService receives a deterministic active-pack fingerprint.

This certification does not claim that Mod discovery, DLC entitlement, commercial delivery, or arbitrary third-party content is released. It certifies the shared versioned content-pack boundary those later systems must use.

## Implemented commit chain

| Commit | Deliverable |
|---|---|
| `41cce70` | Frozen content-pack v2 and entry contracts |
| `01b9ed1` | Version range, integrity, dependency, and deterministic pack resolution |
| `913ad06` | Closed declarative effect catalog and value validation |
| `4d30f5a` | Save-compatible `ContentSnapshotProvider` |
| `6014fed` | Normalized base content pack |
| `d0d55a7` | Required-pack activation, isolation, validation metadata, and registry queries |
| `b4e776f` | Runtime boot and draft cutover to the activated registry; hard-coded arrays and legacy loader removed |

## Activated base pack

- Pack ID: `base`
- Pack version: `0.4.0-dev`
- Pack schema: `2`
- Game range: `>=0.4.0-dev <1.0.0`
- Active definitions: 33
  - Items: 20
  - Blessings: 4
  - Curses: 6
  - Talents: 3
- Fingerprint SHA-256: `c07344a6920022981d5de586f4aceffa983c317c442aeec8443857b975f026a7`
- Aggregate content snapshot SHA-256: `a286c7da6616ec301f681399ac1802759c27346a7bedb2469f73f31d5b9c86cb`

The snapshot shape remains the frozen SaveService v1 contract:

```text
aggregate_sha256
packs[]: pack_id, pack_version, schema_version, fingerprint_sha256
```

Pack rows are sorted deterministically and all public registry/snapshot results are deep copies.

## Validation evidence

Focused P3 regression commands passed before certification:

```text
./tools/run_tests.sh --filter content_runtime_cutover
./tools/run_tests.sh --filter draft_service
./tools/run_tests.sh --filter reward_system_smoke
./tools/run_tests.sh --filter run_runtime_facade
./tools/run_tests.sh --filter m1_runtime_smoke
./tools/run_tests.sh --filter legacy_run_adapter
```

A detached clean clone of committed HEAD then passed `./tools/validate_project.sh` twice:

| Run | Log directory | Result |
|---|---|---|
| A | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.VT0839` | PASS |
| B | `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.eNLh8J` | PASS |

Each run produced:

- 45 / 45 Godot scene tests passing;
- 7 / 7 localization contract tests passing;
- 13 / 13 playtest-data contract tests passing;
- 27 / 27 M1 release-gate contract tests passing;
- 10 / 10 export contract tests passing;
- bootstrap import and clean second import passing;
- no new script error, invalid call, missing resource, RID leak, or ObjectDB leak;
- one retained and classified warning from `tests/reward_system_smoke.tscn`.

Static runtime-source audits also passed:

```text
rg -n 'const (REWARDS|BLESSINGS|TALENTS|CURSES)|RewardDataLoader' scripts data/content_packs
rg -n '"script_path"\s*:' data/content_packs
```

Both commands returned no matches.

## Failure behavior and trust boundaries

- A missing, invalid, incompatible, or integrity-mismatched required base pack blocks runtime boot with structured diagnostics.
- Invalid optional packs are isolated when their failure does not invalidate a required dependency.
- Duplicate IDs, dependency cycles, missing localization keys, invalid references, invalid availability, and unknown or out-of-range effects fail validation before activation.
- Activated content may invoke only approved declarative effect IDs. Content data cannot name or execute arbitrary GDScript.
- A save whose active-pack fingerprint differs returns `CONTENT_MISMATCH`; it is not silently loaded against a different content set.
- Initial supported Mods remain data-only. Unsafe script Mods, storefront entitlements, paid DLC delivery, signing, and public publishing remain outside this repository-only certification.

## P4/P5 handoff

P4 owns the single mutable `RunState`, room lifecycle, and retirement of GameState run mirrors and `LegacyRunAdapter`. P5 owns exactly-once typed gameplay publication. Neither phase may add a second content loader, cache mutable registry definitions, bypass the effect catalog, or weaken the saved content fingerprint.
