# P21F Daily Native Conditions Evidence

- Status: Verified / Current
- Document Role: Current retained evidence
- Authority Level: Evidence beneath approved specifications and plans
- Applies To: Native Daily Player, Boss conditions, physical save migration and localization
- Depends On: `../superpowers/specs/2026-10-05-p21f-daily-conditions-design.md`, `../superpowers/plans/2026-10-05-p21f-daily-conditions.md`
- Owner: Plane Walker implementation team
- Last Verified: 2026-10-05

The deterministic Daily calendar now selects all eight authored conditions.
Native Boss projections independently validate sixty-second enrage, strict
below-ten-percent outgoing damage and 150-percent projectile counts rounded
up. The low-HP modifier reaches primary attacks, physical charge contact,
Ruin aftershocks and wall collapse. Any newly implemented auxiliary Boss
mechanisms must compose that same outgoing modifier.

The inherited production Daily Player grants one additional dash during
cooldown, subtracts exactly three invulnerable frames and retains the extra
charge inside Player frame rollback. Normal cooldown recharges both dashes.
Temporal Disorder doubles all four cooldowns after Build installation and
scales Stop/Rift/Acceleration duration and rewind history by 1.5. This duration
interpretation of the authored effect multiplier is recorded in the approved
focused specification.

Legacy schema1 and schema2 save fingerprints migrate through a physical
compare-and-exchange into the new identity. The original save stays intact as
a rollback point. Attempts, current admitted legacy definitions, wallet,
purchases and entitlements survive migration and cold reload. Historical
schema1 victories carry damage evidence -1 and cannot fabricate a flawless
title. After explicitly resolving a legacy admission, new attempts use the
current calendar.

Verification:

- Missing Daily Player RED: `build/daily-player-condition-red`.
- Authentic low-HP charge defect RED: `build/daily-charge-condition-red`.
- `./tools/run_tests.sh --filter daily_ --timeout 120`: 12/12 PASS,
  `build/daily-conditions-green`.
- `./tools/run_tests.sh --filter ruin_debris --timeout 120`: 2/2 PASS,
  `build/daily-debris-green`.
- `./tools/run_tests.sh --filter launch_boss_runtime --timeout 120`: PASS,
  `build/daily-boss-runtime-green`.
- Accepted frames3599/3600, exact10-percent/below thresholds, actual damage,
  every Boss volley, nine debris/twelve shard lane reservations, cold restores,
  forged projections, actual time effect outputs, dash spend/rollback/recharge,
  physical legacy migrations and controller exchange workflows are covered.
- All GREEN logs scanned for engine/script errors, warnings and leaks: none.
- `python3 tools/validate_localization.py`: PASS. English/Chinese reward and
  condition translations use the canonical language column order.

Main/Hub integration, fresh translation imports, exports and combined program
certification remain owned by the root integration milestone. No external
publication or account access is required for these rules.
