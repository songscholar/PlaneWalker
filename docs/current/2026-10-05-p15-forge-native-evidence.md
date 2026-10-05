# P15 Forge Native Arena Evidence

- Status: Focused Verified / Full program active
- Document Role: Current
- Authority Level: Milestone validation evidence under standing authorization
- Applies To: Native Forge Colossus arena, authored auxiliary attacks, cold save and replay
- Owner: Plane Walker project owner
- Depends On: `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `../superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05
- Exit Gate: Authenticated native damage, finite hazards, rollback, strict cold reconstruction, physical save and raster checks pass

## Delivered

The Forge arena has one independent deterministic domain, nested in Boss runtime
schema6. Four actual HP120 anvil bodies share the existing construct Hurtbox and
critical-damage boundary. Four permanent cooling pools and four fixed vent
fixtures have strict native geometry and raster identity checks. Vents delegate
damage to the existing P14 ForgeVents rule; native fixtures never create a second
damage origin. Original CC0 anvil, vent and cooling rasters have a reproducible
Pillow generator and SHA256 manifest.

Accepted hammer damage applies a finite source-owned burn, with10 damage at
60/120/180 frames. Entry to a cooling pool removes only this Boss's burn and
modifier, with a30-frame per-actor cooldown. Occupancy, damage, burn and cooling
receipts reconstruct the domain during cold validation. Cooling survives all
forms and enrage. Terminal state and effect disposal retire owned modifiers.

Sealed native slam, spray, eruption and ultimate hits reserve finite ground
pools. Slam uses r32/TTL180/tick8 per60frames, spray retains its locked96x32cone
and TTL120, eruption retains six r24/TTL120 circles, and ultimate retains three
TTL300 strips. Ground pools have no hidden initial tick. Lava toss uses its real
projectile collision to create the authored r32/TTL300/tick8 per60frames pool.
Form transitions retire the prior source's persistent zones and projectiles.

Furnace devour uses the existing transactional semantic-zone authority. Its
source modifier supplies collision-bounded pull, capped at32px/sec even when
multiple pulls overlap. Ordinary movement escapes after bounded hitstun. The
inner r16 deals40 once per target/generation. Existing thrust damage executes its
authored32knockback, and cyclone now moves48px/sec from its first active frame
along the committed route. The vertical48px corridor connecting the top/bottom
cooling pools and the cooling pools themselves remain safe from ultimate hits
and persistent strip ticks.

## Validation

- `build/forge-arena-domain-red`: no authoritative Forge domain before changes.
- `build/forge-arena-native-red`: production Boss lacked native Forge state API.
- `build/forge-arena-domain-green3`: domain admission, duplicate damage,
  source ownership, cooldown, phase persistence and snapshot tampering pass.
- `build/forge-arena-native-contracts2`: meaningful native testing exposed late
  cyclone movement; the subsequent gate verifies movement from first active frame.
- `build/forge-arena-disposal-green`: native/domain2of2 pass. Actual Health,
  anvil colliders, finite burn, cooling, devour pull/inner-once, eruption spacing,
  real lava impact, thrust reaction, frozen cyclone, spray3x12 and12600-frame
  enrage survive the accepted native frame protocol. Late refusals restore
  Boss, Player HP, source modifiers, cooling receipts and effect claims.
- Native cold snapshots validate exact closed state. Physical SaveService
  round-trips the typed Replay codec, and a fresh Boss in an isolated World2D
  reconstructs exact constructs, burns, cooling and phase provenance.
- `build/forge-boss-regression2`: existing Boss actor, projectile penetration
  and runtime3of3 pass. The penetrating-wave fixture uses the actual clear
  y180 route so newly authored anvil collisions do not intercept its target.
- `build/forge-arena-weapon-input2`: normal Player input for all five production
  weapons hits the actual anvil Hurtbox and preserves separately positioned
  Boss body HP. Bow/Gun may also hit a body placed behind the anvil when their
  authored penetration allows it; that body is kept outside this fixture's ray.
- `build/forge-native-render.log`: actual OpenGL scene assertions and pixel
  checks pass.21 retained screenshots cover seven states at640x360,1280x720,
  and1920x1080 in `build/visual-evidence/forge-arena/`.
- Dependency audit: no known vulnerabilities in the existing development,
  coverage and production-art requirements. No dependency was added.

## Retention Boundaries

This evidence covers the Forge arena and authored auxiliary behavior. The full
product program remains active. Shared Boss/Health-effect/semantic adapters are
retained by the coordinated Forest/Void/Forge milestone, while Forge domain,
rasters, native fixture projection, Player pull boundary and focused tests have
their own precise local retention. Nothing is pushed or published.

P14 remains the sole fixed-vent damage authority. Optional mode drivers must
install their normal floor-rule adapter to receive that hazard schedule. Player
feel and balance still need real playtesting; the automated suite establishes
mechanical values, ownership, recovery and reproducibility.
