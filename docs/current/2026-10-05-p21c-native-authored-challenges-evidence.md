# P21C Native Authored Challenges Evidence

- Status: Verified / Current
- Document Role: Current focused native mode milestone evidence
- Authority Level: Local authored-trial verification, not full-product certification
- Applies To: Five fixed-Build three-Boss trials, physical history and Main entry
- Implementation Status: Five authored trials verified locally; wider mode and complete gameplay certification remain separate
- Owner: Runtime integration lane
- Depends On: `../superpowers/specs/2026-10-05-p21c-authored-challenges-design.md`, `../superpowers/plans/2026-10-05-p21c-authored-challenges.md`
- Last Verified: 2026-10-05

## Retained Behavior

The actual council gateway opens five authored trials with a native selector,
objective, fixed Build and ordered Boss route. Each stage starts a new Wanderer
with 100 baseline HP, one selected weapon, two time abilities, three production
passive items, a blessing and a curse. Effects use the real native reward runtime;
ordinary Meta, forge, talents, assistance and cosmetic ownership do not modify
the fixed Build. Admission requires the base content domain and an earned normal
victory over the final Boss.

| Set | Weapon | Objective |
|---|---|---|
| `sword_timer` | Sword | Three Bosses in at most 18000 accepted frames |
| `bow_precision` | Bow | At most six incoming damage events across the route |
| `gun_pace` | Gun | Each Boss in at most 6000 accepted frames |
| `staff_resolve` | Staff | At least 70 percent HP at each clear |
| `gauntlets_flawless` | Gauntlets | No incoming damage events |

One independent physical aggregate binds Profile identity, base content domain,
actual registry snapshot and catalog fingerprint. Admission, stage clear and
terminal result use strict compare-and-exchange. Explicit lost CAS refuses even
identical competing candidates. Promotion ambiguity is accepted only after the
physical primary matches. A pending save freezes the native arena and retains
its exact candidate. Retrying saves publishes one result; stale writers reload.

Three authenticated bound Boss receipts are required for a successful result.
Objective failure, Player death and abandonment have different terminal states.
Ten recent results per set are retained alongside a separate lifetime fresh best.
Save-and-return or cold continuation is recorded as continued practice and cannot
replace that best. Same-process arena-construction retry preserves its admitted
sequence without creating a practice classification. Ordinary Profile statistics,
currency, settlement state and local boards receive no mode reward.

Main owns the entry, content lock, input and music dispatch, and returns to Hub
after an actual save. Retired commands cannot launch again. Start pauses, Resume
regains deferred focus, and controller B performs physical save-and-return.
Recovery keeps the panel open when persistence fails. Commands remain outside
scrolling Build/history details. Strict panel validation refuses damaged names,
loadouts, active/history/best records and flags before property reads.

## Verification

Focused logs are under `build/test-logs/p21c-authored/`. Meaningful RED evidence
includes missing catalog/session/native/coordinator/Main boundaries, `projection-red`,
`heal-notice-red` and `next-label-red-stable`. The latter two found an unchecked
healing notification that could alter the damage baseline and an unregistered
next-Boss caption. The flow now accepts only actual positive finite healing, and
the caption uses the registered bilingual key.

`final-caption` passes all eight authored scenes with no script, formatting,
resource or leak diagnostics. `daily-regression` and `rush-regression` each pass
six existing scenes. `native-render-caption/godot.log` reports all assertions
passing and exits 0. This final OpenGL render also has no script, formatting,
resource or leak diagnostics.

| Suite | Evidence surface |
|---|---|
| Catalog | Exact fields, five distinct weapons/objectives, production effects, detached definitions and invalid content refusal |
| Session | All five exact objective boundaries, ordered identity/receipts, malformed records, practice exclusion and retained best |
| Native | Actual Sword collision, authentic three-stage victory, fabricated frame/Health/Boss notice refusal and actual Player death |
| Build | All five actual fixed Builds, five weapon collisions against five distinct native Bosses, rich/lean Meta parity and real damage/HP objective failures |
| Checkpoint | Physical pre/post-promotion faults, reentrancy, equal/different CAS, pending clear, pause, cold continuation, history pruning and same-process construction retry |
| Coordinator/Main | Actual council entry, five-set focus, retired commands, controller pause/B, physical retry, ordinary Profile isolation and fresh Main reload |
| Native visual | English/Chinese, scale 1.0/1.5, 640x360/1280x720, visible commands, translated captions, loaded character atlas and nonblank pixel colors |

The Build test uses invulnerability only after fixed-effect and Meta assertions
to isolate actual weapon collisions. Its separate objective cases apply real
Health losses and healing. Player death is verified independently in Native and
Main suites. All five weapon/Boss pairs use actual Player actions and physics.
The long time-limit failure values are exact pure-domain boundary tests; they
are not recorded real-time multi-minute playthroughs.

Native stage-clear/victory fixtures call the actual Boss Health terminal after
accepted Player frames. These authenticate mode persistence and scene sequencing;
they do not prove a player can naturally beat every Boss or establish balance.
The screenshot victory times are fixture timings, not gameplay-duration evidence.

Forty retained PNGs in `build/p21c-authored-screenshots/` cover menu, combat,
pause, stage clear and victory across eight visual combinations. The native
OpenGL test waits for actual production character textures and samples bitmap
colors. Final small Chinese large-text menu/pause/combat/stage-clear and English
large-window victory were manually inspected with fitted labels and visible
commands. Scrolling details remain intentionally clipped within their viewport.

`coordinator-first` contains formatting errors before translation import and is
failed evidence. `main-green` contains a test timing failure before waiting for
deferred focus. `final-metrics` and `next-label-red` include a transient shared
Forest script compilation failure. These are not clean certification runs.
`native-render-first` used a relative test-root variable; its six generated
workspace saves were moved intact into its log directory. Final render uses an
absolute isolated test directory and no personal save data.

Official Godot does not supply line coverage. Passing scene counts are not line
coverage. Existing sandboxed headless macOS certificate lookup noise is an
environment diagnostic. Localization and `git diff --check` pass. The required
read-only `python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt`
audit reports no known vulnerabilities; sandbox DNS initially refused PyPI,
then the authorized read-only network audit passed. After concurrent milestone
indexing, document governance reports zero violations.

## Limits And Recovery

This milestone covers five fixed three-Boss authored trials. The wider authored
challenge pool, carried-Build Boss Rush, remaining Daily special rules/rewards,
five-floor endless, global/friend boards and online providers remain separate
authorized work. These trials do not award ordinary progression or cosmetic
currency. Native Boss mechanics continue through their own focused milestones.

Combined clean-checkout import/export, retained platform builds and complete
gameplay certification remain owned by the integration lane. Authentic external
human playtest evidence remains external; no sessions or commercial identities
are fabricated. No dependency, paid service, remote push or public publication
was introduced. The focused local commit is the reversible retention point.
