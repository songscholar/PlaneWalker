# Native Enemy Spatial Evidence

- Status: Focused native implementation verified; combined certification pending
- Document Role: Current
- Authority Level: Focused evidence below approved P15 specification
- Applies To: Bramble Mage and Web Weaver cage walls, Web Weaver links, Plane Ripper portals
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), [spatial implementation plan](../superpowers/plans/2026-10-05-native-enemy-spatial.md)

## Native Behavior

All five canonical ordinary or elite spatial actions pass their complete original
warning and native impact frame. Three cage segments surround the frozen target
with a48px passage, each with native static collision and separate destructible
HP. Bramble uses30HP/TTL240; Web uses25HP/TTL360. Construction has its own complete
declared50/55frame collision warning, which restarts after unsafe or over-budget
deferral. Existing canonical action geometry and historical digests are retained.

Links select two deterministic living enemy or elite recipients. Native raster
and Hurtbox geometry follows their accepted positions. HP15/TTL480 links grant
ATK1.15/speed1.10 through existing strongest-only status aggregation. Breaking a
link, retiring its owner, or losing either recipient removes its modifiers.
One owner cannot exceed three active links. Five normal Player weapon input
producers physically damage both wall and link Hurtboxes. Construct damage uses
the Player's authentic component/run scope and exact once-only damage identities.
Spatial targets are admitted by the shared weapon target policy without enemy
reward aliases.

Plane portals form one native pair per owner, TTL720, with endpoints96px apart.
The both-team and enemy-only raster symbols are distinct. Native CharacterBody2D
transit requires endpoint contact,12accepted-frame cooldown, body-safe room bounds,
physics clearance and48px clearance from another Player. Anchored or stopped
enemies remain fixed. An exit offset prevents stationary bouncing. Owner death
retires transit and reserves two authentic45frame warnings before20Void damage
explosions of radius32; the pair retires at that exact boundary.

Spatial, arena and Ruin debris construction share the8active construct budget.
Owned and global shortages retain finite pending work and restart complete
warnings. Retired history is compacted only when bounded reservation storage
requires capacity. Room disposal removes native bodies and owned modifiers.

## Persistence And Compensation

Semantic schema2 adds strict nested spatial state. Exact schema1 migrates to empty
spatial state and invents no historical constructs. Unknown current fields,
forged wall geometry, altered canonical parameters and malformed clocks are
rejected. The existing Effects envelope normalizes nested semantics before cold
validation.

Physical SaveService and typed Replay preserve native actor envelopes and Effects
state. Fresh native authorities rebuild walls, links and both portal team rules,
then accept the next frame with the same spatial settlement as the continuing
world. Historical reconstruction removes current projections. A late real World
commit refusal restores Player position and transaction, owner state, spatial HP,
claims and work. The same portal frame retries once with the correct team rule.

## Executable Evidence

- Meaningful RED: `build/native-enemy-spatial-red2`, native wall/link/portal active-frame refusal.
- Domain, all five cast routes, real Player lifecycle and cold next-frame equality: `build/enemy-spatial-current-head`,3/3 green.
- Physical cold reconstruction: `build/native-enemy-spatial-cold2`,1/1 green.
- Shared semantic behavior: `build/enemy-spatial-shared-semantic`,2/2 green.
- Shared native summons: `build/enemy-spatial-shared-summon`,4/4 green; Void Player frame: `build/enemy-spatial-shared-void`,1/1 green.
- Actual compatibility-renderer lifecycle, fresh next-frame settlement and15 screenshots: `build/native-enemy-spatial-render-green.log`, PASS.
- Raster artifacts: `build/visual-evidence/enemy-spatial/*-640x360.png`, `*-1280x720.png`, `*-2560x1080.png`.
- Art source: `tools/production_art/generate_enemy_spatial_atlases.py`; provenance and hashes: `assets/production/enemy_spatial/manifest.json`; license: `CC0-1.0`.

The intentional late-frame refusal emits two expected fixed-frame settlement
errors in lifecycle logs. Successful runs contain no script errors, leaked
objects or resources still in use. This focused evidence does not certify the
750Boss/loadout matrix or natural five-floor packaged completion. Parallel
content-version migration and shared production checkpoint certification remain
separate integration gates.
