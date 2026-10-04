# Plane Walker Hub Business Boundary Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Profile-backed Hub workflow boundary
- Applies To: HubRuntimeFacade, HubViewStateProjector and HubViewState
- Owner: Runtime integration agent
- Last Verified: 2026-10-05
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`, `docs/current/2026-10-05-p16e-save-v4-workshop-service-evidence.md`, `docs/current/2026-10-05-p16j-native-narrative-retention-evidence.md`
- Evidence Status: Verified Locally
- Certification Status: Business boundary verified; native panel certification belongs to the Main integration milestone

## Delivered Boundary

`configure(registry, profile_service, providers)` accepts the actual Registry and ProfileRuntimeService classes, derives its Meta catalog through `MetaCatalogFactory.from_registry`, and authenticates the Profile catalog fingerprint. Three districts and nine destinations come from validated authored descriptors. The facade keeps presentation workflow state independent from native nodes and never reconfigures the service's active tutorial or narrative bindings.

`travel(district_id, expected_revision, expected_epoch)` and `command({epoch, function_id, operation, payload}, expected_revision)` reject stale Profile revisions, stale Hub epochs, foreign destinations and operations from another panel. Callback reentry and configuration replacement refuse while commands execute. A refused transaction preserves the complete Profile, selected loadout, district, panel and Hub epoch. Successful workflow changes retire previous view epochs.

Meta, forge, enchantment, tempering, build and narrative commands pass through the actual durable Profile service. The projector probes isolated existing Profile, ForgeRuntime and BuildLibrary candidates to derive availability, exact authored costs and refusal keys without changing the owned Profile. Build-save and build-remove capability are also projected rather than inferred by UI capacity checks. Each weapon has its own upgrade, enchantment and two-payment tempering rows. All returned dictionaries are detached and validated against a closed nested view contract.

The selected configuration comes from the 150 validated actual Launch loadouts and current Profile ownership. Saved builds convert persisted lexical time-ability order back to canonical Run order. `launch` returns a complete normalized LAUNCH RunConfig with the requested deterministic seed; Main remains responsible for durable `prepare_launch` and Host startup. An active launch refuses another gateway launch.

NPC dialogue is restricted to the current authored destination's NPC. Archive, gallery and mirror rows reflect actual artifacts, environment records, discovered items and earned endings. Daily, leaderboard and social rows start explicitly `UNAVAILABLE`. Optional injected providers must return a closed validated view row; malformed or missing providers return the offline state and cannot prevent preparing a normal launch. No live online provider, Hub commerce or training assignment is claimed here.

Both localization CSVs contain the Hub names, costs, commands and refusal text in English and Chinese. The Base pack's localization digest is updated mechanically. This milestone also adds the missing dependency metadata and README indexes for the earlier content-rebinding and physical-tutorial-service evidence.

## Verification

Meaningful missing-facade API RED: `build/test-logs/p16-hub-facade/api-red`. Meaningful missing BuildLibrary action projection RED: `build-actions-red`. GDScript type inference and JSON numeric normalization intermediate failures are retained separately and not counted as behavioral RED.

Final workflow GREEN: `build/test-logs/p16-hub-facade/final`. One scene consumes the actual validated Base Registry and real physical SaveService. It exercises Meta purchase failure and retry, exact cost, callback reentry refusal, stale revision and epoch immutability, authored district/panel ownership, forge upgrade, build save and selection, canonical time order, ownership refusal, NPC dialogue, malformed provider fallback, complete offline Launch configuration, actual JSON restart and the real durable launch boundary. The earlier workflows also passed under `cost-normalized` and `build-actions-green`.

Existing physical regressions GREEN: `workshop-regression` and `profile-regression`, one scene each. These logs contain no script errors or object leaks. Godot line coverage is unsupported; no percentage is claimed. `python3 tools/validate_localization.py` and `git diff --check` pass. Repository-wide documentation governance was checked and identified only concurrent Main/Timer indexes and the other agent's in-progress tutorial-flow metadata at the time of this check.

## Remaining Scope

Native Hub panel rendering, interaction, controller focus and Main routing are owned by the separate root integration milestone. Training assignments and guided policy are later boundaries. Online provider adapters and Hub commerce remain explicitly unavailable. Updating the full Base pack fingerprint also requires an explicit compatible-content ledger for already saved actual-content profiles; the storage migration API alone cannot infer that compatibility.

## Retention Decision

Retain the focused local commit. It adds Profile-backed orchestration and detached display projection without changing Main or GameState. No dependencies or remote publication were added.
