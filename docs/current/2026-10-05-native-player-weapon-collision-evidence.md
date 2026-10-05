# Native Player Weapon Collision Evidence

- Status: Accepted / Focused Verified
- Document Role: Current milestone retention evidence
- Authority Level: Below P11 weapon and P15 hostile specifications
- Applies To: Actual player weapon detection of native enemies, Bosses and legacy Hurtboxes
- Owner: Plane Walker implementation team
- Depends On: `../superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Five real weapons hit both supported Hurtbox layers, production Dungeon sword damage and Boss Rush loadouts pass without physics-query errors

## Verified Behavior

Player attacks detect Godot layer one and native hostile layer three. Sword's
scene Hitbox and dynamically constructed payloads, Arrow, Gun, Staff and
Gauntlets retain legacy target compatibility. Attack Areas have no collision
layer of their own; native Actor collision dimensions and layer contracts are
unchanged.

The three circular projectile paths use Godot's physical shape query to sweep
the authored hit width through each movement segment. This includes initial
overlap and prevents a fast Gun projectile from stepping completely across a
small native Hurtbox. Targets resolve in spatial order and the existing target
deduplication, pierce and retirement rules remain authoritative. A normal Gun
shot hits the nearest native target, does not pierce to a second target, and
does not damage a target outside its swept width.

Preconfigured Staff projectiles enable monitoring and physics when attached.
Staff retirement defers its monitoring change, and Gauntlets' area-entered
handler defers target execution until the physics query finishes. Real melee
feedback can therefore create its resulting zone without changing collision
shapes while Godot is flushing queries. The prior physical overlap regression
waits for that deferred settlement before observing damage.

## Reproducible Evidence

The pre-fix probe `planewalker-tests.8d1V2v` failed every native weapon HP
assertion and exposed the real Gauntlets physics-query mutation error. Its
Dungeon command was not yet released and is not used as Dungeon RED evidence.
Earlier fixture setup probes and incomplete intermediate runs are not retained
as successful validation.

- `./tools/run_tests.sh --filter player_native_weapon_collision_test --timeout 120`:
  GREEN `eMrovo`, ten actual Player input/physics/Health cases covering five
  weapons on native and legacy actors, nearest-target/non-piercing/off-path
  Gun behavior, and a natural Main route with a real spawned Dungeon target.
- `./tools/run_tests.sh --filter gauntlets_launch_execution_test --timeout 120`:
  GREEN `et7Df0`, including the deferred real melee collision and existing
  control, zone, echo and cold-state contracts.
- `./tools/run_tests.sh --filter gun_projectile_test --timeout 120`:
  GREEN `7h2PgL`.
- `./tools/run_tests.sh --filter staff_spell_runtime_test --timeout 120`:
  GREEN `GgftUo`.
- Independent native Boss Rush verification: all six scenes GREEN under
  `build/test-logs/p21a-boss-rush/final`, including six actual loadouts with
  all five weapons reducing the bound native Boss's HP, Guardian hit/guard,
  stage progression, Main/Hub, physical checkpoint and presentation.

Engine logs were explicitly scanned for script/deferred errors, physics-query
mutation errors and ObjectDB/RID leaks; none were found in the successful
runs. The stock runner reports `godot_line_coverage_unsupported`; these focused
runs do not provide line coverage.

## Retention And Remaining Scope

The focused local commit is reversible. It does not certify every enemy mix,
the entire 150-loadout production Dungeon matrix, all Boss arena constructs,
all dynamic elite affixes, complete gameplay tuning, or a release build. Those
remain under their existing full-product milestones and final validation Gate.
