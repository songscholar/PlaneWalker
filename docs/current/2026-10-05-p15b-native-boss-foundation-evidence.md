# P15B Native Boss Foundation Evidence

- Status: Approved / Current
- Document Role: Current focused native Boss foundation verification evidence
- Authority Level: Local verification evidence below approved P15
- Applies To: Five Boss domain runtimes, native actors, conversion components and Player frame compensation
- Owner: Project native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p15b-native-boss-runtime.md`
- Last Verified: 2026-10-05
- Implementation Status: Domain and native adapter foundation verified; full production mechanisms remain active
- Exit Gate: Closed definitions, real native actors and Player compensation pass local gates

## Implemented Foundation

`LaunchBossRuntime` parses all thirteen closed runtime projection fields through
the existing authored `BossDefinition` checks. It preserves collision dimensions,
HP thresholds, all 48 primary action schedules, weighted seeded decisions,
consecutive-action budgets, accepted-frame enrage and frozen action regimes.
Damage transitions retire committed primary geometry and impose the authored
60-frame cue. Stop converts to bounded warning/recovery delay and 45-frame
exposure; Rift validates positive inputs before applying the 0.70 Boss floor.
Long fights retain a bounded 512-hit history while current-frame validation
rejects evicted old facts instead of exhausting future damage acceptance.

`BossConversionRuntime` owns bounded weapon sources, poise and schema-one
Character exposure claims. A Character tail waits for the original Stop or
recovery window, resumes on accepted frames, and immediately suspends if a new
Stop source grants another base window. Ordinary restoration preserves the
monotonic claim floor; opaque native Replay authority can restore an exact bound
checkpoint. Complete hostile transaction snapshots contain the whole component.
Weapon conversion preserves committed warning, bounds extensions and deduplicates
sources. Poise source lifetime covers the final granted recovery/exposure window.
Staff freeze/blind grant twelve/eight frames without hard-freezing or randomly
canceling Boss attacks; Gauntlets retain the authored 1.40 poise factor.

Five native scenes use actual CharacterBody2D, CircleShape body/Hurtbox,
HealthComponent and the existing original raster atlas projection. The adapter
provides Player time/weapon/Character endpoints and legacy Boss HUD fields with
authored phase/HP/name/enrage facts. Physics projection never advances gameplay.
The coordinated P15N commit `ba1e5fa` retains the default enemy runtime/status
factories and the real-Health death guard. A forged public death signal cannot
retire a live Boss or remove its control group.

## Verification

- Missing runtime/collision RED: `planewalker-tests.B96Pec`.
- Invalid Rift and phase-selection RED: `planewalker-tests.6L8XhL`; repaired foundation GREEN: `planewalker-tests.wrwglk`.
- Forged Boss control/consecutive snapshots RED: `planewalker-tests.RygUGr`; authored-action/enrage foundation GREEN: `planewalker-tests.E7YfRx`.
- Missing five native scenes RED: `planewalker-tests.sv3pEc`; actual native actor foundation GREEN: `planewalker-tests.hzFSwC`.
- Missing Player conversion endpoints RED: `planewalker-tests.1e3oJI`; native Staff/Gauntlets/Character endpoints GREEN: `planewalker-tests.CYYmro`.
- Immediate new-Stop tail suspension RED: `planewalker-tests.uDxtKI`.
- Independent review found premature poise-source expiry; `planewalker-tests.OImDOI` records the failing lifetime/reentry assertions. Final lifetime is computed after the threshold conversion grant.
- Final foundation gate: `./tools/run_tests.sh --filter launch_boss --timeout 120`, `planewalker-tests.0wfsSk`, 2/2 passed. The domain test exercises all 48 primary schedules including five exact enrage thresholds, malformed definitions/identities/snapshots, HP transitions, Stop/Rift, active/pending Character tails and long damage histories.
- Native actor gate instantiates all five real scenes. Actual Player and actual LaunchHostileEffectAuthority prove frame-start HP/control/action/conversion compensation, no rejected damage observations, exact real threat-prefix rollback, retry, global publication seal and one accepted Boss frame. Actual Health ledger restore is single-use; final Health death emits one counted receipt and retires the body.
- Existing native enemy regression: `planewalker-tests.qkm2aV`, 1/1 passed. BossDefinition regression: `planewalker-tests.qcnNpT`, 1/1 passed.
- Final native rendering uses isolated `PLANEWALKER_TEST_DATA_DIR=/private/tmp/plane-walker-p15b-native-data` and the GL compatibility renderer. Exit 0, `PASS: all assertions succeeded`, and no script errors, parse errors or leaks in `build/test-logs/p15b-native-boss-foundation/engine.log`.
- Ten screenshots under `build/visual-evidence/p15b-native-boss-foundation/` cover every actual Boss at 640x360 and 1280x720. Dense sampling requires at least five colors and more than 300 visible foreground pixels; images were inspected. The first graphics run used a color-count floor higher than the small authored palettes and is excluded from the final rendering gate.
- Documentation governance and `git diff --check` pass before precise local staging. No new dependencies are introduced; the pinned direct development dependency audit returned no known vulnerabilities during this milestone. Formal GDScript coverage remains unsupported and no percentage is asserted.

## Active Production Gates

This foundation does not certify complete Boss gameplay. Persistent zones,
healing, summons, walls, arena constructs, blink/self-rewind, four Time Sovereign
responses, root/cover/cooling/core state and secondary hazards require executable
transactional production handlers. Full loadout matrices, hostile Save/Replay,
strict production Boss HUD ViewState, all phase-specific art tracks and all
accessibility/ultrawide captures remain active gates. The shared effects router
still refuses an unsupported handler; no inert-success fallback is added. Human
playtests remain 0/20. No remote publication occurred.

## Authored Projectile Gate

Foundation retained in `5e05ad2`. The next focused gate preserves Boss-authored
finite warning ranges: Forge lava toss stays 192px and Void shard projection
stays 256px. Existing enemy finite envelopes remain unchanged. Payloads retain
up to the authored eight penetrations, distinct target claims and complete native
collision exceptions through rejected-frame compensation. All projectiles still
retire at a finite range, lifetime, wall contact or exhausted penetration budget.

- Authored range/penetration RED: `planewalker-tests.GZpa7N`.
- Payload domain GREEN: `planewalker-tests.1s80xH`, 1/1 passed.
- Actual Forge P3 sword-wave scene, real room and two real Player bodies: `planewalker-tests.5AGxH5`, 1/1 passed. Each body receives one 30-damage hit; first penetration rejection restores Health, payload claims and physical collision exceptions, and retry publishes once.
- Combined Boss foundation/payload GREEN: `planewalker-tests.gb8POQ`, 3/3 passed.
- Existing Moth actual native flight/death/Rift/wall regression: `planewalker-tests.ynqPer`, 1/1 passed.
- Effect and bridge regressions: `planewalker-tests.YSYCoS` and `planewalker-tests.4qWfmZ`, each 1/1 passed.
- Coordinator regression: `planewalker-tests.rtLCLU`, 1/1 passed. Coordinated blink landing envelope RED `planewalker-tests.tZb0St` and full enemy-domain GREEN `planewalker-tests.Q0O1iU` verify locked normal/Rift landings.

All final listed gates have clean engine logs. No new dependency was introduced.
The production projectile raster still uses the previously certified acid atlas;
distinct Boss/element raster projections remain active visual work. Persistent
zones, healing, summons and arena mechanisms are not certified by this gate.
