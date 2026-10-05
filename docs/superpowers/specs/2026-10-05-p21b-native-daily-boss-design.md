# P21B Native Daily Boss

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Focused executable mode scope
- Applies To: Offline daily Boss, fixed Build, bounded attempts and independent save
- Owner: Runtime integration lane
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

## Rules And Identity

This implements the actual daily Boss rules from 3.7.7 and the attempt/save rules
from 8.5.5.3. The date changes at 00:00 UTC+8. A versioned, first-party JSON catalog
and the UTC+8 day deterministically select one production Boss, one fixed weapon,
exactly three distinct Launch passive items, one Launch blessing, one Launch curse
and one or two supported special conditions. The character is Wanderer, with the
same base 100 HP and two fixed time abilities for every participant; selected Hub
Meta, talents, forge and accessibility advantages do not affect this fixed Build.
The launch gate requires an actual completed normal victory and a base save
domain. Mod-enabled daily entry is unavailable.

The catalog validates production content, weapon capabilities, effects and scene
references. Presets install actual authored effects through the existing
PlayerRewardEffectRuntime. The initial condition pool is the original frail curse
(maximum HP times 0.7), melee specialization (melee damage times 1.3, ranged damage
times 0.7), and ranged specialization (the reverse). They apply actual stat effects
and are visible before launch. Unsupported conditions cannot enter the catalog.
The remaining original conditions require distinct native mechanics and are not
silently treated as descriptions or aliases.

Day identity, deterministic seed and preset are not accepted from UI callers. The
native session derives them from the catalog and its clock. Testing injects a
clock Callable; production uses system Unix time. Local clock rollback cannot
restore spent attempts or reset the latest observed day. Offline clock trust is
explicit, and optional provider time can replace the adapter later.

## Native And Durable Boundaries

The production Player, authored Boss room, actual Boss, HostileFrameBridge and
native Effects execute this single encounter. RunOrchestrator owns its native
phase. A shared arena builder removes duplicate construction with Boss Rush;
domain sessions continue to own mode-specific timing, attempts and results.
Native completion requires the bound actor, terminal runtime, zero health, exact
run/source/death receipt and positive accepted frames. Real Player death yields a
defeat. No UI notice can fabricate completion.

One independent daily SaveService aggregate binds Profile, save domain, actual
content snapshot and daily catalog fingerprint. At most three attempts are spent
per UTC+8 day. Attempt admission saves before native play; pre-promotion failure
does not spend a published attempt, and retry commits it once. Post-promotion
acceptance requires physical primary equality. Exit/abandon consumes the already
admitted attempt and records one terminal result. A crash leaves an active attempt
that must be explicitly abandoned before another starts; it cannot offer unlimited
entrance retries. Native construction failure retains the admitted attempt for a
same-attempt construction retry. Stale/interleaved writers refuse promotion and
provide physical reload. Terminal save failure freezes the encounter for retry.

Best results are independent of ordinary local boards. Victories rank by elapsed
committed frames ascending, then remaining HP percentage descending, then attempt
index ascending. Defeats and abandonments remain visible and never outrank a
victory. Current-day results and a bounded thirty-one-day archive are physical;
rollover preserves history and refuses a fourth attempt. An encounter admitted
before midnight keeps its original challenge identity through settlement.

## Actual Product Entry And Verification

The native council gateway exposes Daily alongside ordinary launch and Boss Rush.
Preview shows the date, Boss, weapon, three items, blessing, curse, time pair,
special rules, remaining attempts, countdown and best result. Keyboard/controller
Start, pause/resume, retry, reload, abandon and Hub return use actual native
controls with retired callback protection. English/Chinese and supported text
scales/resolutions receive interaction and screenshot QA.

Meaningful RED must precede implementation. Acceptance includes fixed UTC+8 date
boundary and seven-day deterministic preview, different Profile/Meta producing
the same Build, actual installed five-content effects and condition effects,
actual chosen native Boss and weapon damage, forged notice refusal, native victory
and death, all three attempts, failed admission/terminal promotion and retry,
physical restart, stale writer, rollback/day rollover and isolation from ordinary
Profile currency/boards.

This milestone does not certify the wider original daily reward/token/cosmetic
shop, online/friend ranking, cloud merge or the five additional special mechanics.
Authored challenge sets and the actual five-floor endless dungeon remain separate
subsequent work. A Boss survival loop cannot be labeled complete endless mode.
