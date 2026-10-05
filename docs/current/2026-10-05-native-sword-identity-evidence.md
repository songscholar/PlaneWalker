# Native Sword Damage Identity

- Status: Focused native implementation retained; combined certification pending
- Document Role: Current
- Authority Level: Focused retention evidence below approved P15 specification
- Applies To: Sword damage producers and historical active action compatibility
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [native summon evidence](2026-10-05-native-summon-evidence.md)

## Retained Behavior

Consecutive ordinary Sword actions previously emitted their Coordinator callback
epoch as the body damage generation. Completion advances action tokens without
advancing that callback epoch, so genuine native bodies admitted only the first
attack. Each new cast now freezes `damage_identity_revision: 2` inside its adapter
attack, emits source `player_sword_v2`, and uses its unique monotonic action token
as the damage generation. Callback and Replay Coordinator epochs retain their
existing behavior.

Historical attacks without the optional marker retain source `player_sword`.
Restored WINDUP retains its historical epoch when it becomes ACTIVE; restored
ACTIVE uses its already-frozen damage token and generation. The historical source
namespace and spent receipts remain exact. Future ordinary inputs use revision 2,
including when their token reaches an opaque historical epoch receipt. Unknown
or incorrectly typed revisions and mismatched frozen identities refuse atomically.

No top-level snapshot schema changes. The optional nested marker survives typed
Replay encoding and physical SaveEnvelope integer normalization. Persisted zone
and wave DamageInfo remains frozen to its original producer source.

## Executable Evidence

- Actual ordinary input RED: `build/native-summon-wraith-input-position`, eight accepted light Sword inputs left the genuine Wraith alive with one admitted damage claim.
- Historical collision RED: `build/native-sword-legacy-collision-red`, future normal token 5 collided with the spent historical epoch 5 after typed cold reconstruction.
- Historical WINDUP/ACTIVE migration and genuine new collision GREEN: `build/native-sword-legacy-collision-green`, 1/1.
- Current cancellation-heavy ACTIVE restore and revision forgery refusal GREEN: `build/native-sword-versioned-runtime-green`, 1/1.
- Legacy M1 parity GREEN: `build/native-sword-versioned-parity`, 1/1.
- Full Player Replay GREEN: `build/native-sword-versioned-full-player`, 1/1.
- Weapon Replay/observable restore matrix GREEN: `build/native-sword-versioned-replay`, 5/5.
- Isolated real input GREEN: `build/native-sword-versioned-input-isolated`, 1/1. All five weapons physically damage genuine children and two separate ordinary actions damage a genuine elite body; actual light Sword retires Wraith/Spore through Driver receipt handling and leaves two unrewarded children.
- Isolated native body rollback GREEN: `build/native-sword-versioned-body-isolated`, 1/1.
- Final shared native input and body regression GREEN: `build/native-sword-versioned-input-final` and `build/native-sword-versioned-body-final`, each 1/1 after concurrent hostile changes completed.
- Physical current ACTIVE recovery GREEN: `build/native-sword-current-physical`, 1/1.
- Physical historical ACTIVE recovery GREEN: `build/native-sword-legacy-physical`, 1/1.
- Existing physical fighting checkpoint GREEN: `build/native-sword-versioned-checkpoint`, 1/1.

The two physical active cases launch an actual Main, drive a genuine Sword cast,
settle its immutable damage against a real native body, persist through SaveService,
and reconstruct another Main. Both preserve the exact full Player/native aggregate,
refuse the spent cast, and match the uninterrupted next accepted frame. The isolated
source contains retained HEAD plus the focused Sword changes to prevent unrelated
concurrent source edits from changing the tested program while Godot loads scripts.

Successful logs contain no script/parse errors or leaks. Installed Godot cannot
collect line coverage. Terminal summon fixtures are explicitly synthetic native
encounters; natural elite Wraith/Spore route selection requires the separate
versioned additive encounter content milestone.
