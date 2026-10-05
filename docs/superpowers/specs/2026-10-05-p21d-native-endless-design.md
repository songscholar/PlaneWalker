# P21D Native Endless Dungeon Design

- Status: Approved / Current
- Document Role: Current focused specification
- Authority Level: Below the full-product completion specification
- Applies To: Offline native five-floor cycles, capped difficulty and independent recovery
- Owner: Plane Walker implementation team
- Depends On: `../../../AGENTS.md`, `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual native encounters, deterministic cycles, carried Build/resources, physical CAS recovery and controller controls pass with scanned clean logs

## Runtime

Every cycle executes the existing production five-floor generator, routes, events,
merchants, rewards, floor rules and native Bosses through RunRuntimeHost. A private
composition uses CombatRoom01, RoomSceneHost and DungeonFlowCoordinator. The source
Profile is read only; mode saves use their own namespace and the active content
fingerprint. Live player and hostile identities never use scene instance IDs.

Cycle seeds derive from the requested seed and zero-based cycle index through the
existing SeedService. Native actor projections multiply maximum HP by
`min(3.0, 1.0 + 0.15 * cycle)` and damage by
`min(2.0, 1.0 + 0.08 * cycle)`. Geometry, telegraphs, speed, wave counts and the
existing eight-hostile/payload budgets do not expand. Every multiplier is applied
before native Actor binding and identically during cold reconstruction.

Cycles continue after the scaling ceilings, including beyond 160 floors. Session
history retains the most recent 32 complete cycle summaries with their absolute
indices, while the accepted frame clock and cycle index use bounded integer
counters. Failed native construction can retry the already committed launch. A
run is never advanced by a synthetic summary or forged death signal.

## Carry And Persistence

The mode preserves the exact typed Build and Player reward-effect snapshot across
cycles, including current/max HP, time resources, weapon upgrades and modifiers.
The next cycle has a fresh world/action identity and cleans prior projectiles and
time zones. The private Profile retains its initial meta baseline; cycle endings
retire the active receipt without granting ordinary Profile rewards.

One atomic SaveService compare-exchange writes the private Profile, native
checkpoint and mode session together. Physical primary equality, rather than a
write return code, decides post-promotion success. Stale writers refuse even when
their candidate equals the winner. Pending writes freeze native participants and
retain an explicit retry command. Reload reads the physical winner. Room/floor
boundaries and manual return retain native checkpoints; active combat can also
checkpoint using the existing native authority. Pause changes no accepted clock.

Session data stores a mode/content identity, validated launch request, cycle,
accepted frames, continued category, completed cycle summaries, and typed carry
codecs. It is closed, bounded and versioned. Unsupported content or malformed
state refuses before playable native publication.

## Presentation And Verification

The coordinator exposes configure(registry, profile, root), open(request),
handle_input(event), is_open(), closed, panel() and runtime(). Its menu offers
start, continue, resume, next cycle, save-and-return, retry and physical reload.
The existing dungeon panels retain all standard keyboard and controller routes.
Native tests prove real spawn/death receipts, checkpoint restart, frame rollback,
save failures, source Profile independence and controller focus. Cycle/scaling
unit tests are separate from actual gameplay evidence. Extended natural
completion and global boards are not inferred from test fixtures.
