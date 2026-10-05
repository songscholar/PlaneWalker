# P15B Native Time Watch Weakpoint

- Status: Verified Locally; full Boss arena and time-response scope remains active
- Document Role: Current implementation and verification evidence
- Authority Level: retained milestone evidence below the approved P15 Boss specification
- Applies To: Time Sovereign native Watch proxy, accepted damage, interruption, rollback and cold reconstruction
- Owner: Plane Walker native Boss implementation lead
- Depends On: `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, P15B temporal runtime `738a252`, P16R native combat checkpoints `4b27f42`
- Last Verified: 2026-10-05

## Accepted Behavior

Time Sovereign now owns an actual `WatchHurtbox` child with a CircleShape2D and an original four-state pixel atlas. It replaces the scene's primary weapon Hurtbox on collision layer 4 while preserving the single Boss target identity, native HealthComponent, frame participant and encounter receipt. Its 80 HP interrupt value projects the existing authoritative rewind damage state; it has no independent enemy roster, Health ledger or reward source.

Every accepted hit damages the real Boss body. During the committed self-rewind warning, distinct accepted damage also contributes to the authored 80 HP interruption threshold. A break cancels the pending landing/heal and preserves 55 complete accepted punishment frames, including a break staged in the next Player frame before the Boss domain advances. Frame 55 remains nonattacking; frame 56 can start a fresh authored warning.

The proxy rejects repeated damage identities before touching Health. Existing weapon payloads using the legacy `runtime` run marker must come from an actual PlayerController (or subclass) bound to this Boss run. A foreign Node with a matching `current_run_id()` method cannot impersonate that Player. Candidate native geometry changes are rejected before Boss state advances; shape resources are instance-owned.

The Watch projection is derived from existing Boss domain state and reconstructs after commit, rejection, death and cold restore. It introduces no new saved Boss fields. Buffered lethal Watch damage still commits one real Boss terminal frame, retires the collision, restores it on rejection and publishes exactly one counted Boss death on acceptance.

## Verification

- Missing actual child-proxy RED: `planewalker-tests.vGWjiw`.
- Buffered punishment boundary and actual Bow/Gun compatibility RED: `planewalker-tests.YesJtY`.
- Actual Player-script impersonation RED: `planewalker-tests.Daaij5`.
- Final Watch native GREEN: `planewalker-tests.ZqCM0n`, `boss_watch_native`, 1/1, no script/load failures or known leaks.
- The native fixture executes the real Sword Hitbox, Bow PlayerArrow, GunProjectile, StaffProjectile and GauntletsHitExecution collision handlers against the actual Watch. Each route reduces real Health, contributes exactly its accepted amount to the Watch threshold and deduplicates the same target. These focused callback tests do not claim certification of the full 750 loadout/Boss combinations.
- Later real weapon collision integration changed Gauntlets area settlement to a deferred callback. The combined certification run `build/test-logs/native-collision-replay/validation.stdout.log` correctly rejected the old synchronous Gauntlets fixture assertion. Only that callback branch now awaits one process frame before its real Health/threshold and duplicate checks. Focused rerun `planewalker-tests.4O4pgP`,1/1, passes with no script errors or known leaks; other weapon routes retain immediate duplicate checks.
- Five immutable weapon damage identities test 80 cumulative accepted HP, complete frame rejection/retry, five once-only accepted observations, zero Watch death receipts and fresh native cold reconstruction.
- Native lethal acceptance/rejection tests exactly one Boss death and restores actual layer-4 collision after rejection.
- Boss runtime/Actor/payload regression: `planewalker-tests.nkN8Ni`, 3/3. Temporal domain and actual historical landing/heal regression: `planewalker-tests.XLH4qb`, 2/2. Production native combat cold checkpoint regression: `planewalker-tests.4PKy7m`, 1/1.
- Final Watch geometry and projection changes preserve all Boss Actor/payload/runtime gates: `planewalker-tests.SF2lDD`, 3/3; temporal domain/native gates: `planewalker-tests.8oyhaH`, 2/2. Production native combat cold reconstruction was rerun against the retained current binding: `planewalker-tests.sgr9CD`, 1/1, without script errors or known leaks.
- Actual historical Time Boss migration: `planewalker-tests.0YmeYk`, `native_content_migration`, 1/1, without script errors or known leaks. The physical Profile launches through Host, traverses the actual first two floor routes with explicitly injected prerequisite completion receipts, reaches the authored third-floor Time Sovereign and waits for its naturally selected self-rewind warning. Every trusted historical descriptor promotes the entire unchanged payload, reconstructs a fresh current Boss scene with one real Watch collider and one body Health/reward owner, preserves the complete Watch/native state and accepts the same next Player/native frame as the uninterrupted branch. The saved Boss cast is never fabricated or patched into a checkpoint.
- Native GL compatibility rendering passed at 640x360 and 1280x720. Four warning/broken screenshots are retained under `build/visual-evidence/p15b-native-watch/`; sampled Watch pixels require at least five colors and more than 200 foreground pixels. Screenshots were inspected. `build/test-logs/p15b-native-watch/engine.log` reports `PASS: all assertions succeeded` without script errors or leaks. The sandbox graphics launch did not initialize macOS WindowServer; the permitted local native renderer run provides the verified evidence.
- Independent QA found the next-frame punishment boundary and Player-script authentication issues; both have explicit RED/GREEN regressions. The focused final review found no additional actionable Watch issue.
- `git diff --check` passed. No dependency changed; the P15E audit records the sandbox DNS limitation of the unchanged pinned development dependency. GDScript line coverage is unavailable, so no coverage percentage is claimed.

## Content Binding And Remaining Work

The final Time Sovereign scene SHA-256 is `721c2016e96cc98674c4d6ced337ad28c90ddeacd9568ed44ed573cbb308bb07`. The Base descriptor currently declares the Boss room scene, not this code-owned native actor scene, so this change does not alter the content fingerprint or introduce a descriptor transition. The seven authenticated historical bindings and six reviewed transitions remain intact. Explicit declaration of the complete native actor/art asset surface remains a separate content-pack closure gate; this evidence does not claim that it is already complete.

This milestone closes the native self-rewind Watch proxy. Counter-Stop Watch thresholds and the four time-response integrations, remaining Boss arena cover/walls/roots/vents/cores, specialized phase mechanics, complete safe-route certification, phase art and the full loadout matrix remain separate active gates.

No remote push, publication or purchase occurred. The focused local commit preserves the runtime, scene, raster reproduction source and tests for review and rollback.
