# Boss Action Validator Evidence

- Status: Focused Verified
- Document Role: Current narrow Boss restore validation optimization evidence
- Authority Level: Below approved full-product completion contract
- Applies To: `LaunchBossRuntime._can_restore_snapshot_uncached`
- Owner: Gameplay performance lane
- Last Verified: 2026-10-06
- Certification Status: No frame-budget, rendered, soak, full-matrix or human certification

## Change

`_validation_action_for_snapshot` only returns a template after
`_validation_action_matches` has accepted the exact typed Action snapshot. The
parent validator then repeated the same complete Action check before continuing
with Control, auxiliary, temporal and native-boundary checks. The redundant
parent call is removed. Empty templates still fail closed, and every remaining
child validator and accepted-boundary guard is unchanged.

The regression fixture subclasses the real Boss runtime and counts complete
Action-authority checks at each current and historical action boundary across
all five authored Boss definitions. It requires exactly one selected-template
check per full restore validation. Existing direct definition, typed field,
reconfiguration, cache, concurrency and ownership tests remain unchanged.

## Evidence

The RED run against the unchanged implementation is retained at
`build/boss-action-validation-once-red/`. It reports repeated assertions of
`expected 1, got 2`, with no parser, script or leak diagnostic. Its paired
stdout/Godot SHA-256 is
`9ea1f940750c7822f6956de9d3b691a8f41ca76589f153a3f14b16b22c6386c4`.

The GREEN focused scene is retained at
`build/boss-action-once-boss_action_validation_template/`, with one passing
suite, zero failures and strict paired logs. Its stdout/Godot SHA-256 is
`31d2c6ce473319bd9b389b9f9af5ceb6eea678a637282aa49dd2fed1a3d69f60`.

Adjacent Boss validation scenes also pass with the same strict log pair:

- `boss_snapshot_validation_cache`
- `boss_legacy_action_digest`
- `boss_parent_restore`

The native combat checkpoint and Main resume fixtures currently fail during
their own setup because their scenes have no `TutorialFlow` node; this is a
pre-existing fixture error and is retained separately from this focused change.

This slice removes one full Action authority traversal per accepted Boss
restore. It does not cache mutable configuration, change snapshot bytes, or
claim a 60 FPS result.
