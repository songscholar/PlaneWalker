# Plane Walker Physical Tutorial Service Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Native onboarding persistence boundary
- Applies To: ProfileRuntimeService tutorial integration
- Owner: Runtime integration agent
- Last Verified: 2026-10-05
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-05-p16i-native-tutorial-evidence.md`
- Evidence Status: Verified Locally
- Certification Status: Physical service verified; Main routing and guided policy remain separate

## Delivered Boundary

`enable_tutorial(entries)` and `tutorial_progress_view()` expose the authored tutorial domain through the current Meta Profile. `execute_tutorial(command, expected_revision)` physically saves skip and suppression preferences without changing the active launch receipt, frozen Meta projection, or pending Run configuration.

`bind_tutorial_run(run, player)` validates the actual Run, complete reward participants, native Replay snapshot, launch identity, frozen configuration, and native source history. It returns `context.adapter`, an exact service-created TutorialNativeAdapter. `observe_tutorial(adapter, expected_revision)` refuses caller-created observers and obtains the sealed receipt from its owned observer internally. Arbitrary receipt dictionaries and foreign candidates are not accepted.

The observation candidate stores Meta progress, the complete current Run snapshot, and full native Player reward participants in one physical envelope. Before-promotion failures leave the queued receipt retryable and publish no progress or hint. Post-promotion faults reconcile only an independently read primary that exactly matches the intended candidate. Only then does the service confirm the adapter receipt and return authored `context.hints`, `completed_lessons`, `completed_tasks`, and the detached `receipt`.

The service compares actual native Replay state, reward state, Run state, and native instance identities before and after saved notification. Native drift exposes `NATIVE_PUBLICATION_PENDING` and prevents every Profile command from overwriting the recovery point. Saved-notification callbacks run under a publication guard; configure, command reentry, rebinding, and observer retirement cannot replace the active transaction. A saved callback that detaches its observer consumes the already committed receipt once and requires recovery.

`restore_tutorial_run()` authenticates the complete current primary, restores the existing saved Run and reward participants, retires the old observer, and returns a replacement `context.adapter` initialized from the saved watermark. Recovery adds no progress grant. `retire_tutorial_run()` preserves the native binding while recovery is pending.

Initial character talents are authenticated against the Player's frozen initial Replay identity as a set, so Host canonical ordering is accepted while a foreign initial selection is refused. Legitimate native talent acquisition can extend the live loadout without changing the frozen initial selection.

## Caller Contract

Main consumes successful authoritative Player frames through the issued adapter. It drains pending observations through `observe_tutorial` and feeds only successful returned authored hints into `TutorialViewModel.project_hint`. The adapter's `observation_saved(receipt)` signal denotes an already saved receipt; it is not a request to submit another observation. After `restore_tutorial_run`, callers replace their observer reference with `context.adapter` and recheck the current Run before rendering a hint. A general `restore_active_run` caller must also establish a fresh tutorial observer before resuming observations.

## Verification

Meaningful missing-API RED: `build/test-logs/p16-tutorial-service/api-red`. Meaningful canonical initial-talent binding RED: `native-binding-red`. Meaningful missing-native-World participant RED: `talent-order-red-fixed`. Fixture initialization, typing mistakes, and interrupted runs are not counted as feature RED.

Final GREEN: `build/test-logs/p16-tutorial-service/final-earned-talent`. One real native Player uses production Host construction order, actual Base Registry content, actual generated floor, actual complete Event/economy participants, physical JSON files, and injected save faults. The test covers three native movements and one accepted dash completing `movement_dodge`, delayed entry-hint publication, unchanged state on failed writes, committed-primary reconciliation, skip/suppression failure and retry, frozen launch preservation, physical watermark restart, foreign adapter and initial-talent refusal, missing native World refusal, canonical talent order, real native talent acquisition, promotion-time drift, saved callback detachment and reward drift, recovery, stale service refusal, and guarded reentry/configuration/retirement.

Focused regressions: `narrative-binding-regression`, `profile-regression`, `workshop-regression`, and `onboarding-regression` (four scenes). Eight focused scenes passed with no script errors or object leaks. Godot line coverage is unsupported; no coverage percentage is claimed. Independent read-only service review found no blocking issue; final talent and native-World checks were added after that review and passed.

Dependency audit was attempted against the existing pinned `requirements-dev.txt`. The ordinary pip-audit path could not prepare its pip environment; the no-install `--disable-pip --no-deps` path could not resolve `pypi.org`. Dependency vulnerability status is unverified in the offline environment. This change adds no dependencies.

## Remaining Scope

This checkpoint restores Run and reward participants, not complete Player position, action clock, World state, or a full resume of the whole native game. The full Replay snapshot is used as an in-memory publication drift seal only. Guided damage and warning policy, guided completion, native training assignment, authored training contexts, and Main/Hub routing are separate stages. This service does not treat arbitrary actions as evidence for those contexts.

## Retention Decision

Retain this focused, reversible local commit. It connects existing pure tutorial and native observer components through the authenticated physical Profile service. No remote publication was performed.
