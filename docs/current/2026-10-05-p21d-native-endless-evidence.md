# P21D Native Endless Retention Evidence

- Status: Verified / integration pending
- Document Role: Current retained evidence
- Authority Level: Evidence beneath approved specifications and plans
- Applies To: Native Endless mode and shared authentic Boss settlement sources
- Depends On: `../superpowers/specs/2026-10-05-p21d-native-endless-design.md`, `../superpowers/plans/2026-10-05-p21d-native-endless.md`
- Last Verified: 2026-10-05
- Owner: Plane Walker implementation team

Endless uses actual production five-floor dungeons, native encounter actors,
routes, rewards, events and shops. Each completed cycle carries the exact Build
and player reward effects to the next deterministic seed. The source Profile is
unchanged. Cycle count has no 160-floor limit; HP/damage scaling saturates at
3x/2x and only the most recent 32 cycle summaries are retained.

Difficulty uses one validated enemy projection for all 22 normal and elite
species. Outgoing acid pools, burn, residual ticks, explosions and collapses
scale with primary attacks; incoming-damage thresholds and multipliers retain
their authored meanings. The projection preserves its original mechanism
recipe, so native configuration, cold restore and acid payload reservation can
reject forged auxiliary values. Current elite affix signatures coexist with
the difficulty marker. Daily barrage support expands the maximum distinct
debris landing index to nine while retaining the four-live-body arena cap.

The independent Profile service atomically commits the private Profile and mode
aggregate with native checkpoints through compare-and-exchange. Cold restore,
pre/post-promotion failures, stale writers, interrupted first native startup,
retry and controller focus are covered. Authentic production boss deaths now
append an identity-bound settlement source before encounter completion, fixing
the missing-Boss-fact checkpoint failure shared with normal runs.

Verification:

- `./tools/run_tests.sh --filter endless --timeout 120`: 5/5 PASS.
  Durable logs: `build/endless-green`.
- `./tools/run_tests.sh --filter native_boss_settlement_source --timeout 90`:
  PASS. RED `build/native-boss-source-red`; GREEN `build/native-boss-source-green`.
- `PLANEWALKER_CHECKPOINT_CASE=boss ./tools/run_tests.sh --filter native_combat_checkpoint --timeout 90`:
  PASS, `build/native-boss-cold-green`.
- Startup interruption RED `build/endless-startup-red`, GREEN
  `build/endless-startup-green`. Five-floor carry/cold cycle included in
  `build/endless-green`.
- Combined 5/5 logs scanned for ERROR, SCRIPT ERROR and leak diagnostics: none.
- Auxiliary-difficulty RED `build/endless-scaling-red`; complete 6/6 Endless
  GREEN `build/endless-scaling-green`. Tests cover all 22 species as normal and
  elite actors, actual native acid flight/pool damage, forged recipe refusal
  and cold state. Logs scanned clean.

Integration: instantiate `NativeEndlessFlow`, configure with the loaded registry,
ordinary Profile service and independent mode root, then bind `EndlessCoordinator`.
Register `scripts/modes/endless_localization.csv` translations. Parent integration
owns Main/Hub entry, clean checkout import/export, focused Git commit and broader
certification. No remote publication or external credentials are required.
