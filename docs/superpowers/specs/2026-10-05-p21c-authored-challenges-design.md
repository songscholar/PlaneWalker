# P21C Native Authored Challenges

- Status: Approved / Current
- Document Role: Current focused implementation specification
- Authority Level: Executable authored mode scope
- Applies To: Five fixed-Build three-Boss trials, objectives and isolated history
- Owner: Runtime integration lane
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

## Scope And Approach

Five first-party authored trials each bind one weapon, two time abilities, three
Launch passive items, a blessing, a curse and an ordered three-Boss route. Every
stage starts a fresh Wanderer at standardized 100 HP before installing actual
content effects. Meta, forge, talents and assistance do not change the Build.
The base domain and an earned final-Boss victory gate admission. There is no
daily attempt cap and no optional online dependency.

The Sword trial limits total committed frames to 18000. Bow allows six incoming
damage events across the route. Gun limits each stage to 6000 committed frames.
Staff requires at least 70 percent HP at each Boss clear. Gauntlets requires no
incoming damage events. The exact numeric rules and Build are visible before
admission. Authenticated completion that fails a rule is OBJECTIVE_FAILED,
distinct from native death, abandonment and successful VICTORY.

Three approaches were considered: reuse the native arena with an independent
authored domain; configure an entire five-floor dungeon; or generalize every
existing mode into one engine. The first matches the existing native Boss modes
and permits objective-specific persistence without changing ordinary RunState.
Full dungeon presets and a shared all-mode engine would broaden unrelated
runtime and save changes. This choice is reversible at the authored domain.

## Data And Runtime

AuthoredChallengeCatalog validates `authored_challenges.json`: exact fields,
unique IDs/weapons, exactly three ordered distinct production Bosses per set,
supported effects, Launch content categories, stable seeds and bounded rules.
It returns detached definitions, actual arena stages, native requests and effect
definitions. One fingerprint covers the complete authored catalog.

AuthoredChallengeSession is independent of nodes. It validates deterministic
Profile/set/sequence/stage identity, strict native receipts, rule metrics,
ordered completed stages, terminal status and bounded per-set history. Ten
terminal attempts per set are retained. Fresh objective victories rank by total
frames ascending, damage events ascending, final HP descending and sequence.
Best fresh victory is stored separately from the rolling history so pruning does
not discard a lifetime best. Each set owns at most one detached best record.

NativeAuthoredChallengeFlow reuses NativeBossArenaBuilder, actual Player actions,
HostileFrameBridge and authored Boss scenes. Each positive committed Player frame
advances time once; pause stops every descendant. Damage counts use the bound
actual HealthComponent.damaged signal. Stage clear requires exact bound Boss,
run/source/death receipt, terminal runtime and positive native frames. Forged UI
or Boss notices cannot complete a stage. All three authenticated receipts must
exist before evaluating successful completion.

## Physical Boundaries

A separate SaveService aggregate binds Profile, base domain, actual content
snapshot and mode fingerprint. Admission persists before native construction;
stage clear persists before advancing; terminal persistence precedes publishing
history/best. Pre-promotion failure preserves physical state, post-promotion
ambiguity resolves only through primary equality, and explicit lost CAS refuses
even equal competing candidates. Pending terminal save freezes the native arena
and keeps its exact candidate for retry. Stale writers must reload the primary.

Save and return, or physical restart at ACTIVE/STAGE_CLEAR, marks the attempt as
continued practice before reconstructing a stage. Practice history remains
visible and cannot replace a fresh best. A current-process native construction
failure can retry its admitted stage without another sequence or practice mark.
Stage frames include accepted work before save-and-return; resumed stage timing
starts separately, while cumulative time preserves already accepted frames.
Explicit abandonment records one result. No ordinary Profile currency, statistics,
settlement source or local board is mutated.

## Product Interface And Acceptance

AuthoredChallengeCoordinator exposes configure(registry, service, root_path),
open(), is_open(), runtime(), panel(), handle_input(event), return_to_hub(), and
closed. The native council gateway opens it. Its panel exposes a set selector,
Build/objective/Boss route, fresh best and recent attempts, start/next/resume,
save-and-return, abandon, save retry, physical reload and native retry. Commands
remain visible outside scrolling details. Controller pause and focus survive
every projection. Retired controls cannot launch or advance twice. Chinese and
English at 640x360/1280x720 with text scales 1.0/1.5 receive interaction and native
screenshot verification using actual production atlases and pixel checks.

RED precedes implementation. Required tests cover catalog corruption/tampering,
all five objective boundaries, fixed native effects and real weapon damage,
forged completion refusal, victory/death, strict physical fault/CAS/retry,
fresh reload, practice classification, pruning and retained best, actual Main
entry, controller commands and supported native layouts. No dependency is added.

The P21C completion claim covers these five authored trials. Daily's remaining
special mechanics/rewards, carried-Build Boss Rush, five-floor endless, cosmetic
acquisition and online boards remain separate authorized milestones.
