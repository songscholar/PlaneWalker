# Boss Native Validation Pass Evidence

- Status: Focused Verified / Per-frame performance pending
- Document Role: Current focused validation and call-count evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Boss native cold snapshot validation
- Owner: Plane Walker performance lane
- Depends On: `2026-10-06-native-unified-hotpath-diagnostic-evidence.md`
- Last Verified: 2026-10-06

## Retained Behavior

`LaunchBossRuntime.can_restore_native_snapshot()` now passes the accepted-frame
constraint through one complete Boss validation. Each applicable arena or
auxiliary still runs its original complete validator on a cache miss. General
restore continues to permit authored staged next-frame events; native restore
continues to reject them. Positive cache keys retain the boundary mode as well
as exact detached typed configuration and snapshot bytes. Storage remains
bounded to four entries and protected by the existing mutex.

No gameplay state, save/replay schema, checksums, public snapshot isolation,
rollback installation, or validation guard was changed. Reconfiguration and
live arena context changes cannot reuse an earlier exact verdict. General
cache entries cannot certify the stronger native accepted-frame boundary.

## Executable Evidence

The original source is frozen from Git revision
`367fc9393c209e1a58035d3e21704f939a804885` under
`build/performance-native-validation/baseline-367fc93/`. The original runtime
SHA-256 is
`e7aaf2ac3b00526faf8d60c7224366ac393ee91fff1102336dbdd9758103d21d`.
The candidate runtime SHA-256 is
`f0bad83364cc0107b6b1c3e70c35c8c32022ea4c45c7ecdf5e403a1aba8c1f97`.
The identical focused regression source has SHA-256
`05ac3d14f8e02cf6a930f5fdf4e125fad778f24fcf5cd5752f766c75dba56668`.

`boss_native_validation_pass_test.tscn` uses counted subclasses that invoke
the real production child validators through `super`, plus uninstrumented
production authorities for concurrent validation. It exercises all five
authored Bosses, exact typed refusal, caller detachment, sequential historical
restoration, live context changes, a genuine staged flower event, mixed cache
modes, and three concurrent read-only workers.

| Applicable child validation | Original | Candidate |
| --- | ---: | ---: |
| First complete native validation | 2, general then strict | 1, strict |
| Eight exact warm native validations | 8, strict | 0 |
| Native after only a general positive cache entry | 1, strict | 1, strict |

The final original RED under `build/performance-native-validation/red-final/`
contains exactly 12 expected cold/warm call-count assertion failures. Its
behavioral assertions pass. Candidate GREEN is 1/1 under
`build/performance-native-validation/green/`. Initial fixture parse failures
and the first clean-checkout import's missing generated translations are
retained separately and are not classified as the behavioral RED. A second
baseline editor import still reports missing UI chrome assets referenced by
that revision; its complete import gate remains failed. The isolated focused
RED itself has only the 12 expected count failures and no script/leak failure.

The following existing scene regressions are GREEN with strict paired stdout
and Godot engine log validation in `build/performance-native-validation/`:

- Boss snapshot validation cache in `snapshot-cache/`.
- Native owned frame token in `native-token/`.
- Native combat checkpoint in `native-save/`.
- Boss exposure replay checkpoint in `replay/`.
- Hostile frame bridge rollback/publication in `bridge/`.
- Void auxiliary validation cache in `void-cache/`.

## Limits

The current actor invokes native validation from `normalize_native_cold_snapshot`
and `_cold_actor_state`, which serve native snapshot normalization/restoration.
The production per-frame preview and actor transaction paths use the general
validator. This fix therefore proves less duplicate work at the native cold
restore boundary; it does not demonstrate faster Player/Bridge frame work or
60 FPS. The frozen gameplay matrix applies to its recorded source revision and
cannot certify this changed runtime source.

The remaining general-validator hotspot repeatedly encodes the full live
configuration. Existing regressions intentionally mutate private definition
values, including an integer to a numerically equal float. Any context cache
must retain exact type-sensitive source invalidation and must be measured
against actual Boss definitions and arena initial states before adoption.
