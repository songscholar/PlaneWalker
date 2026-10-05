# P21B Native Daily Boss Evidence

- Status: Verified / Current
- Document Role: Current milestone retention evidence
- Authority Level: Focused executable acceptance record
- Applies To: Native fixed-Build daily Boss, UTC+8 attempts, physical history and Hub controls
- Owner: Runtime integration lane
- Depends On: `../superpowers/specs/2026-10-05-p21b-native-daily-boss-design.md`
- Last Verified: 2026-10-05

The actual council gateway now opens one daily production Boss encounter. A
first-party JSON catalog and UTC+8 date select its Boss, fixed weapon, two time
abilities, three distinct passive items, blessing, curse and one or two supported
conditions. Admission requires an earned normal victory, completed final Boss and
the base save domain. The fixed Wanderer Build ignores ordinary Meta, forge,
talents and accessibility advantages. Ordinary Profile and local boards receive
no daily settlement.

## Retained Behavior

The actual Wanderer scene has 200 base HP. Daily applies its catalog's standardized
100 HP through PlayerRewardEffectRuntime before capturing the baseline; it then
commits all five authored content definitions and actual special-condition
effects. Frail multiplies maximum HP by 0.7. Melee and ranged specialization apply
the original 1.3/0.7 damage multipliers. Catalog validation rejects incompatible
weapon effects before any attempt can be admitted.

The independent physical SaveService binds Profile, save domain, content snapshot
and mode fingerprint. Admission saves before native construction and spends at
most three attempts per day. UTC+8 midnight exposes the next deterministic
challenge and seven-day preview. Crossing midnight retains the admitted day's
Build and result. Local clock rollback cannot reopen earlier attempts. History
retains the last thirty-one admitted days and survives physical restart with
integer domain-state normalization.

Explicit exit or abandonment consumes its already admitted attempt. An abrupt
crash leaves a cold admitted attempt that must be explicitly abandoned; cold
reload cannot retry the arena indefinitely. Construction failure allows retry of
that admitted attempt only in the current process. Terminal save refusal freezes
the encounter and retains its authentic result for retry. Stale writers must
reload the actual physical primary.

Victory requires the bound native Boss, run/source identity, actual terminal
runtime, zero Boss HP, positive committed frames and exact death receipt. Actual
Player death records defeat. Best results rank victory first, fastest frames,
remaining HP percentage and attempt index. A living fractional HP victory stores
at least one positive ranking unit rather than failing settlement after rounding.

Shared arena construction preserves the verified Boss Rush stage identities and
save schema. Both mode flows refuse an explicitly lost compare/exchange even when
the competing candidate bytes are identical; physical equality still resolves
ambiguous post-promotion faults. The losing writer cannot construct a second
native arena.

Daily's Start, Resume, Abandon, retry and reload controls stay outside the long
scrolling Build/calendar region. Retired callbacks cannot admit another attempt.
Controller Start pauses all native descendants and timing. The active Return
control explicitly says Abandon and return. Main supplies actual Boss and terminal
music cues and blocks content mutation while the mode is open.

## Verification

```sh
TEST_LOG_DIR=build/test-logs/p21b-daily/final-retained \
  ./tools/run_tests.sh --filter daily_boss --timeout 120
TEST_LOG_DIR=build/test-logs/p21b-daily/rush-final \
  ./tools/run_tests.sh --filter boss_rush --timeout 120
```

All six Daily and six Boss Rush scene suites pass. Daily executable coverage:

| Suite | Verified behavior |
| --- | --- |
| Catalog | UTC+8 midnight, deterministic date/seed/preset and seven-day preview |
| Fixed Build | Rich/lean Profiles produce the same actual native Build; standardized HP, all committed authored/condition effects and weapon compatibility |
| Native combat | Actual chosen Boss and weapon, physical damage, authentic victory/death, forged notice refusal, exactly three attempts and unchanged ordinary state |
| Physical checkpoint | Admission/terminal pre/post-promotion faults, retry, stale/interleaved/identical writers, cold admitted restart, midnight, 35-day rollover retaining 31 days, rollback refusal and fractional-HP victory |
| Main | Actual gateway controls, earned-victory/mod gates, retired callback, controller pause/focus, save retry, cold reload and Hub return |
| Native layout | English/Chinese, text scale 1.0/1.5, 640x360/1280x720; visible commands, honest abandonment label and fitted chrome |

The Build suite performs nine real weapon cases: all five weapons plus Gun against
all five distinct native Bosses. It uses actual Player actions and physics
collisions. Incoming Player damage is made invulnerable only after canonical
Build/effect checks to isolate those weapon assertions. Native and Main suites
separately verify actual Player death. Rich/lean fixture arenas are physically
separated to prevent overlapping geometry from changing collision evidence.

Meaningful RED evidence remains in `build/test-logs/p21b-daily/`: admission and
checkpoint failures, the identical-CAS race, `fractional-red`, archive reload in
`final`, and `visible-actions-red-stable`. Initial incompatible Gauntlets content
was corrected to production time/overdrive effects supported by that weapon.
Shared weapon collision and freed-target effect guards are independently retained
by the combat QA lane. `final-normalized` and `visible-actions-red` contain
transient shared-file parse errors during another lane's debris implementation;
they are failed runs, not certification evidence.

The final native OpenGL render exits 0 with all assertions passing under
`native-render-final/godot.log`. Its thirty-two screenshots in
`build/p21b-daily-screenshots/` cover menu, combat, pause and victory across all
eight combinations. Bitmap sampling verifies nonblank pixels and visible colors;
combat capture also verifies the actual loaded production character atlas. Final
Chinese 640x360 at scale 1.5 menu/pause/combat and English 1280x720 victory were
visually inspected with fitted labels, visible controls and authored actors.

Final Daily, Rush and render logs were scanned for script, parse, resource and
leak diagnostics. None remain; sandboxed headless runs retain only the existing
macOS certificate lookup diagnostic. Localization validation, document governance
and `git diff --check` pass. The required read-only
`python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt` audit reports
no known vulnerabilities. No dependencies were added. Combined clean-checkout
export and full-program certification are owned by the integration lane.

## Remaining Scope And Recovery

This verifies the offline native daily foundation and its three initial special
conditions. The original quick battle enrage, dodge-master count/i-frames, final
strike damage, time-chaos cooldown/effect scaling and bullet-hell projectile
mechanics remain separate unfinished work. Daily first-clear gold, streak avatar
frame, no-hit title, ranking rewards and any token/cosmetic routes are not granted
by this milestone. Global/friend boards and cloud merge are unavailable; local
attempt history and best results work offline.

The fixed authored presets are validated production content, not the complete
future challenge-set pool. Authored challenge sets, the actual five-floor endless
dungeon and the wider original Boss Rush carried-Build/reward rules remain
unfinished. Offline time uses the local system clock and is not a trusted global
competition clock.

The focused local commit is the rollback point. No remote push, publication, paid
service or external identity was used. The milestone is informational and does
not pause the authorized full-product program.
