# Production Main Native Resume Evidence

- Status: Approved / Current
- Document Role: Current focused Main continuation evidence
- Authority Level: Production Main and Hub native checkpoint integration
- Applies To: Main, Hub resume controls, DungeonFlow and native room presentation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16q-native-checkpoint-design.md`, `docs/current/2026-10-05-p16q-native-checkpoint-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Safe-stage native continuation verified; live combat and combined certification pending

The actual Hub gateway projects an authenticated resume command for an active
launch and keeps new launch and loadout selection disabled. Epoch and Profile
revision guards reject stale controls. Main restores the full physical checkpoint
into new native participants and binds Tutorial and Narrative services to that
same run. It preserves saved Player position when synchronizing the installed
room camera. Resumption does not create a launch, settlement or Profile revision.

Main retains the native entrance automatically and attempts checkpoints at
logical room/phase changes. A failed physical promotion retains the old durable
payload and is retried; explicit `checkpoint_current_run()` exposes the result.
Unsupported live encounters remain refused by the checkpoint authority. The
initial floor gateway centers the Player on the 640 by 360 canvas before room
selection, while confirmed room transitions use the actual PlayerEntry.

Dungeon panel replacement retains its selection safety lock while rendering
the new panel. Cold resume additionally uses Host's authenticated, single-use
presentation scope: the first panel may pause native participants without
cancelling the saved weapon, time or World state. The callback is checked against
the complete Run/Player checkpoint and Profile revision before the permission is
consumed. Actual Main preserves every Player Replay field, including action
generation after fifth-floor rewards and a saved Vera maximum-HP cost.

Main connects actual Hub training controls to a separately owned practice
Player. Revision and active-launch guards reject stale or incompatible requests;
closing practice returns to the same native Hub.

## Verification

- Missing production checkpoint command RED: `build/test-logs/p16-main-native-resume-red`.
- Physical failure/retry and full scene destruction/reload GREEN: `build/test-logs/p16-main-native-resume-durable-final`, one scene, no runtime failures or leaks.
- Main regression GREEN: `build/test-logs/p16-main-resume-regression`, seven scenes covering floor rules, final narrative, death settlement, native resume, Hub commands, Hub flow and layout contracts.
- Combined final regression GREEN: `build/test-logs/p16-main-combined-final`, nine scenes, zero failures and zero leak warnings. It includes actual native route/reward/floor handoffs to the final fragment, fifth-floor Vera save fault/compensation/retry and full cold Resume, entrance recovery, practice routing and existing Main/Hub regressions.
- The final-narrative fixture provides explicit combat/Boss source receipts and elapsed time before terminal publication. It exercises actual route and story handoffs; it is not five-Boss combat certification. The earlier zero-time terminal fixture RED is retained at `build/test-logs/p16-main-narrative-native-regression`.
- The fixture exercises the actual initial floor gateway. It does not certify arbitrary combat recovery or a five-Boss completion.

The earlier failed API conversion, fixture callback arity, incorrect entry-scene
assumption and mid-edit compile runs are retained as diagnostic evidence and
are not counted as passing checks. Full hostile production integration, combat
checkpoints, complete training, Expansion and distributable certification remain
separate active milestones.
