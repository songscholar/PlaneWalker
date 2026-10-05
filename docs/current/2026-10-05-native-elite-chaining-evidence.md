# Native Chaining Elite Evidence

- Status: Verified focused gate
- Document Role: Current retention evidence for native Chaining behavior
- Authority Level: Evidence below approved P15 specification
- Applies To: Native revision eight, authenticated Player damage, finite ally controls, compensation, persistence and presentation
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 enemies and bosses design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), section 6

## Verified Behavior

The native affix compiler defaults to revision eight. Explicit historical
revisions one through seven keep metadata-only Chaining and their original
definition signatures. Current configuration has a separate signature, digest
and closed native state with ordered damage claims and settled grant receipts.

Only actual accepted positive Player Health damage can record a Chaining trigger.
The existing Health weapon-control call owns the exact DamageInfo and finalized
amount during application. A public Actor call outside that context cannot grant
Chaining. The real Player/current run, registered source and shared ReplayWorld
authenticate production compatibility identities; missing/foreign targets,
unowned sources, non-Player attackers and prevented damage cannot mint grants.
The actual configured Sword delivers its production DamageInfo through Hurtbox
at its authored active boundary, grants the native ally buff and passes late
World compensation/retry.

The first accepted hit owns a trigger; later accepted hits cannot trigger again
until120 accepted frames after that trigger. A trigger selects up to two living
native allies within96 pixels of the recorded source position. Selection orders
actual distance, then stable hostile identity. It excludes the source, terminal
bodies, another ReplayWorld and recipients without native control capacity.
No eligible ally records an empty grant and still consumes that source cooldown.
This finite selection/no-recipient policy is a reversible implementation choice.

The existing hostile FrameBridge settles grants against its owned actor map
before any Actor prepares movement or attack facts. Existing strongest-only
attack controls apply1.15, so an ordinary12-damage action emits13.8 damage. A
simultaneous1.20 source emits14.4, not a product of both multipliers. The control
is effective for frames1 through90 after a frame-one trigger and is removed
before frame91 attack preparation. Stop does not extend the accepted-frame buff
deadline or source cooldown. Damage at2 and120 cannot refresh the first trigger;
accepted damage at121 creates the next grant.

Accepted lethal Player damage can grant its last finite ally buff. The source
then becomes terminal, hides its cue and admits no future damage triggers. The
recipient's independent90-frame control still expires after source retirement.
No recursive trigger, child spawn, reward or permanent ally control is created.

An authentic positive hit outside a Player frame defers recipient selection to
the next owned native frame. Pending selection cannot be exported as accepted
cold state. If that out-of-frame hit immediately retires the owner, cancellation
closes the pending receipt with zero recipients; it cannot leave permanent
pending work on a terminal source. This reversible retirement boundary is kept
explicit while the complete all-weapon physical-contact gate remains open.

Bridge checkpoints precede weapon/world hits and include every source/recipient.
Injected late World failures at frame1 and actual Sword frame5 restore exact
source Health, grant identities/cooldown, recipient control and complete Player.
The original accepted frame retries once. Recipient buffs do not publish an
extra Health/body-hit observation.

Typed cold state retains source and recipient identities, actual control expiry,
selected positions and settled receipts. Erased grants, future/pending settlement,
an out-of-radius recipient and a self-recipient refuse reconstruction. Actual
SaveService retains the typed source/recipient aggregate and a fresh instance
recovers it exactly. The pure domain gate fills all4096 damage-claim slots,
authenticates reconstruction and refuses a4097th receipt without mutation.
Extended whole-room high-hit balance remains separate from this capacity gate.

## Presentation

The native linked-lightning icon distinguishes ready, triggered and cooldown
states. A16-frame trigger flash is a reversible projection choice; it does not
change gameplay clocks. High contrast and1.5x scaling mutate only presentation.
Compatible Nullified and Chaining cues retain44 pixels between centres.

Eight native Metal screenshots in
`build/visual-evidence/native-elite-affixes/chaining-*.png` cover triggered,
high-contrast triggered, high-contrast cooldown and a high-contrast Nullified
pair at640x360 and1280x720. Dimension and actual icon-pixel checks pass; all eight
captures were visually inspected for visible shapes and overlap. The Actor keeps
its existing authored raster, while Godot draws the small native gameplay icon.

## Executable Evidence

- Valid metadata-only RED: `build/test-evidence/elite-chaining-certified-red`, actual accepted Player body damage under retained revision seven has no native ally buff or source ledger.
- Native core GREEN: `build/test-evidence/elite-chaining-native-stable`,1/1.
- Actual Sword, attack facts, typed/physical persistence and presentation GREEN: `build/test-evidence/elite-chaining-full-native`,1/1.
- Final terminal/capacity GREEN: `build/test-evidence/elite-chaining-terminal-bounded`,1/1, including prior native probes.
- Final outside-frame lifetime GREEN: `build/test-evidence/elite-chaining-lifetime-corrected`,1/1, including prior native probes, terminal retirement and the full4096-receipt capacity boundary.
- Shared elite GREEN: `build/test-evidence/elite-eight-final`,8/8.
- Final shared retention GREEN: `build/test-evidence/elite-eight-retention`,8/8 after the outside-frame lifetime correction.
- Health GREEN: `build/test-evidence/elite-eight-health`,1/1.
- Final Health observation GREEN: `build/test-evidence/elite-eight-health-observations`,1/1.
- Native Actor transaction GREEN: `build/test-evidence/elite-eight-native-transaction`,1/1.
- Physical combat checkpoint GREEN: `build/test-evidence/elite-eight-native-checkpoint`,1/1.
- Production encounter GREEN: `build/test-evidence/elite-eight-production`,1/1.
- Native Metal GREEN: `build/test-evidence/elite-chaining-native-visual.log`, all assertions and capture-pixel checks pass.

The expected injected failures retain existing frame1/5 settlement-rejection
diagnostics. Successful retained logs contain no script/parse errors, warnings,
orphan nodes or leaks. Installed Godot does not support line coverage. No project
dependencies or authored content fingerprints changed.

## Remaining Gates

Native Splitting and Mirroring remain pending. The complete legal-pair matrix,
all-weapon physical contacts, combined whole-room balance and full P15
certification remain separate. The distinct duplicate body-settlement defect
discovered during testing is repaired and verified by the focused
[native body settlement evidence](2026-10-05-native-body-settlement-evidence.md).
Its production weapon, source ownership, compensation, history and finite
capacity gates complement this once-only Chaining grant gate.
