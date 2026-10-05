# Native Static Elite Affix Evidence

- Status: Accepted / Partial Milestone
- Document Role: Current milestone retention evidence
- Authority Level: Below P15 hostile specification
- Applies To: Native Frenzy/Fortified, production construction and physical cold checkpoints
- Owner: Plane Walker implementation team
- Depends On: `../superpowers/plans/2026-10-05-native-elite-affixes.md`, `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Static native and physical checkpoint regressions pass; dynamic affixes remain tracked in the implementation plan

## Verified Behavior

The canonical `EliteAffixDefinition` rows are retained by the production catalog
and compiled before actual Actor construction. Frenzy scales authored elite hits
by 1.25, movement by 1.15 and incoming damage by 1.20. Fortified scales elite HP
by 1.50, movement by 0.80 and knockback displacement by 0.80. Collision dimensions
remain authored; the elite sprite silhouette is 1.15. Warning schedules do not
change. The actual sentinel elite has 160 HP, or 240 with Fortified; Frenzy's
actual Router strike removes 18.75 HP from the actual Player.

The compiler hashes sorted canonical rows and floor into an optional runtime
definition signature. Even dynamic-only metadata cannot lose its configuration
and impersonate a historical Actor. Immutable configuration is carried through
frame compensation and typed cold restoration. The historical closed V1 Actor
variant has no affix extension and must match its original unmodified digest.
It retains its original behavior for that restored room. Authored content hashes
and Save schema stay unchanged.

## Reproducible Evidence

Native missing-configuration RED: `planewalker-tests.2sIA3w`.
Production Driver RED: `planewalker-tests.KScW0v`, actual elite configuration
was empty before Driver integration. That RED also invokes the absent historical
constructor signature; neither run is accepted as leak-free evidence.

- Native affix actual Actor/Router/Player/Health, rollback and forgery refusal:
  `./tools/run_tests.sh --filter launch_elite_affix --timeout 45`, GREEN `WpZ2HQ`;
  includes dynamic-only signature stripping refusal and pair-order invariance.
- New physical elite checkpoint through actual Profile/Save/fresh Main:
  `PLANEWALKER_CHECKPOINT_CASE=elite ./tools/run_tests.sh --filter native_combat_checkpoint --timeout 90`, GREEN `kH6UpL`.
- Historical metadata-only physical elite checkpoint and stripped-new-config refusal:
  `PLANEWALKER_CHECKPOINT_CASE=elite_legacy_affixes ./tools/run_tests.sh --filter native_combat_checkpoint --timeout 90`, GREEN `ksQQiN`.
- Existing native Actor regression: `launch_enemy_actor`, GREEN `YZBWtp`.
- Existing real production encounter regression: `production_launch_encounter`, GREEN `rYKOM2`.
- Complete physical native combat checkpoint scene, including 15 internal cases:
  `./tools/run_tests.sh --filter native_combat_checkpoint --timeout 150`, GREEN `aKgsdg`.

Runner reports one scene for each focused invocation; 15 internal cases are not
15 scene tests. GDScript line coverage is unsupported by that Godot build and
was not collected. Engine logs were checked by the strict runner for script
errors and ObjectDB/RID leaks. The sandbox CA-store diagnostic is the runner's
existing platform diagnostic allowance, not a gameplay error waiver.

## Retention And Remaining Scope

This focused milestone is reversible through its exact local commit. It does not
claim all ten affixes, final affix cues, child ownership, or full P15 completion.
Regenerating, Teleporting, Splitting, Shielded, Nullified, Anchored, Chaining and
Mirroring remain explicit pending configuration IDs in this static slice.
Their implementation continues under the approved full-product authorization.
