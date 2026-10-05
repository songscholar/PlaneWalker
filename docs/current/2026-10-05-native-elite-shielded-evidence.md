# Native Shielded Elite Evidence

- Status: Verified focused gate
- Document Role: Current retention evidence for native Shielded behavior
- Authority Level: Evidence below approved P15 specification section 6
- Applies To: Native revisions five through seven, actual Health absorption, authenticated weapon components, accepted-frame compensation, physical persistence and presentation
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [approved P15 enemies and bosses design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), section 6

## Verified Behavior

Shielded entered native execution at revision five; the compiler now defaults to
revision eight for native Chaining; revision-seven Shielded behavior is retained.
Shielded absorbs damage
after incoming modifiers and flat defense from a pool of30% actual maximum HP.
The real sentinel elite has160HP and48shield;20 damage spends20shield without
HP loss, then40 damage consumes28shield and removes12HP. A fractional0.25shield
remainder against the existing minimum-one resolved hit produces0.75HP loss;
no second minimum-damage floor inflates overflow.

Each break opens45 frames of20% incoming exposure. The first break starts a1200
accepted-frame deadline that continues under Stop. The deadline regenerates the
full pool once; the second break schedules no further regeneration. Exposure
magnitude and deadline-from-break semantics are reversible tuning decisions
where P15 is silent. The native2400-frame test verifies the complete deadline
and absence of a second regeneration. Historical revisions one through four
retain their original metadata-only Shielded behavior and signatures.

The new optional Health boundary prepares a closed post-defense decision,
authorizes its commit and compensates the owner if a later Health application
refuses. A refused commit leaves Health and shield untouched. A later invalid
lethal transition restores the already committed absorption; the same damage
identity then retries successfully. External callers cannot commit a prepared
receipt without Health's owned context. Full absorption uses the existing
prevented-resolution observation policy, so it does not publish body damage or
body hit confirmation. Overflow keeps the existing Health/control pipeline.

For the approved compatible Shielded/Anchored pair, a Health-authenticated fully
absorbed launch still admits the incoming weapon control. The existing base
control validator admits only matching action/source generations, finite
nonnegative launch displacement and a fresh action token. Anchor then gains20
poise; the fifth legitimate control spends100poise and owns20 recovery frames.
The enclosing accepted frame spends one of those frames, leaving19. The native
species damage-fact endpoint is not called for this absorbed control; its body
damage ledger and HP remain unchanged. Duplicate shield hits, reused controls,
malformed controls and a refused absorption commit cannot mint poise. Partial
overflow admits control only through the ordinary Health pipeline, once.
Unpaired Shielded retains the existing fully absorbed control policy.

Typed cold state retains the pair's shield, poise and weapon claims. A synthetic
authenticated launch inside the real Player/Bridge is rejected by a late World
fault; complete Player and pair state return exactly, then the original identity
retries once. This focused pair gate does not replace production gauntlet contact
coverage. Physical SaveService also retains the accepted pair state.

Revision-seven shield admission receipts bind actual owner run/source, incoming
source, generation, hit index and damage type. Bow and Gun emit physical and Time
components with the same generation/hit index; each component consumes shield
once, while repeated components cannot spend shield or HP after depletion.
The real Sword adapter emits`legacy_run`; Bow, Gun, Staff and Gauntlets emit
`runtime`. Their actual Player, registered weapon source, current run and shared
ReplayWorld authenticate these compatibility identities. Pending targets and
the current target's authored stable descriptors are accepted only on that
owned path. Foreign source nodes, player-group/method impostors, a Player from
another ReplayWorld, wrong targets and absent targets refuse without mutation.
No Node identity or absolute path enters persisted shield state.

Explicit historical revisions five and six retain their original single-hit
component identity and compatibility admission rules. Their exact snapshots
restore only under the corresponding historical configuration. Revision seven
has a distinct definition signature/configuration digest and refuses those
snapshots, so previously paid damage cannot silently gain a new receipt identity.

Compatible Frenzy scales incoming damage before absorption. Fortified's240HP
body derives72shield. Nullified exposure/echo feeds actual absorption and overflow,
while its vulnerability combines with shield break through existing modifiers.
Cold reconstruction validates ordered once-only damage receipts, both break
frames, pool consumption and regeneration epoch. Forged pool or erased break
receipts refuse. Candidate future receipts remain private to a frame; accepted
cold restore refuses them. Physical SaveService retains exact typed state.

An actual hostile Bridge compensates Health, shield and receipts on outer frame
refusal. The actual Player/Sword test delivers the adapter-built DamageInfo at
its authored active boundary inside the hostile participant. A late World fault
restores complete Player/Sword and shield snapshots; retry admits one receipt.
This is an actual producer/Health/frame integration probe, not a physics contact
or every-weapon contact certification.

The real Bow/Gun/Staff projectile scenes and Gauntlets execution call their
production delivery methods against actual native Hurtbox/Health. Bow/Gun each
spend20 physical plus5 Time from the48 pool, retain two component receipts, reject
duplicate delivery and reconstruct exact typed cold state. These are production
delivery-boundary probes; they do not certify every weapon's physical contact.

## Presentation

The authored gold contour distinguishes intact and cracked shield states and
shows remaining absorption. High contrast and1.5x danger scaling change only
presentation. Enlarged Shielded/Nullified cues occupy separate positions.
Eight native Metal captures under`build/visual-evidence/native-elite-affixes/`
retain intact, broken, high-contrast broken and combined high-contrast states at
640x360 and1280x720. Capture pixel checks verify dimensions and nonblank cue
regions; all eight were visually inspected for readable shapes and overlap.
The existing Actor raster remains; native Godot draws the small in-game contour.

## Executable Evidence

- Absorption RED: `build/test-evidence/elite-shielded-native-red`, actual20HP loss and missing pool.
- Cue RED: `build/test-evidence/elite-shielded-cue-valid-red`, missing gold contour.
- Actual Sword identity RED: `build/test-evidence/elite-shielded-actual-sword-red`, the original explicit-only admission incorrectly refused production Sword compatibility identities.
- Native focused GREEN: `build/test-evidence/elite-shielded-actual-sword-green`,1/1.
- Shared elite GREEN: `build/test-evidence/elite-five-final`,5/5.
- Health GREEN: `build/test-evidence/elite-five-health-regression`,3/3.
- DamageResolution GREEN: `build/test-evidence/elite-five-damage-resolution`,1/1.
- Native Actor GREEN: `build/test-evidence/elite-five-final-actor`,1/1.
- Production encounter GREEN: `build/test-evidence/elite-five-final-production`,1/1.
- Physical combat checkpoint GREEN: `build/test-evidence/elite-five-final-checkpoint`,1/1.
- Player weapon/progression integration GREEN: `build/test-evidence/elite-five-final-player-weapons`,5/5.
- Sword Launch/M1/runtime GREEN: `build/test-evidence/elite-five-final-sword`,4/4.
- Native Metal GREEN: `build/test-evidence/elite-shielded-native-final-visual.log`, all assertions and pixel checks pass.
- Shielded/Anchored RED: `build/test-evidence/elite-shield-anchor-red`, missing absorbed-control poise and threshold recovery.
- Shielded/Anchored GREEN: `build/test-evidence/elite-shield-anchor-corrected`,1/1 with full/partial control, duplicate/malformed control, typed/physical save and real Player late rollback/retry.
- Pair native Actor GREEN: `build/test-evidence/elite-shield-anchor-native-actor`,1/1.
- Pair Actor transaction GREEN: `build/test-evidence/elite-shield-anchor-native-transaction`,1/1.
- Production identity RED: `build/test-evidence/elite-shield-producers-auth-red`, four actual production compatibility identities cannot reach the shield.
- Production identity GREEN: `build/test-evidence/elite-shield-producers-auth-green`,1/1.
- Component identity RED: `build/test-evidence/elite-shield-components-red`, Bow/Gun Time is incorrectly deduplicated and revision-six state has no new-version boundary.
- Revision-seven component GREEN: `build/test-evidence/elite-shield-components-green`,1/1, actual four delivery methods plus inherited Sword/Player compensation, identity refusal, typed cold and historical5/6 probes.
- Revision-seven shared elite GREEN: `build/test-evidence/elite-seven-final`,7/7.
- Revision-seven Actor transaction GREEN: `build/test-evidence/elite-seven-native-transaction`,1/1.
- Revision-seven physical checkpoint GREEN: `build/test-evidence/elite-seven-native-checkpoint`,1/1.
- Revision-seven production encounter GREEN: `build/test-evidence/elite-seven-production`,1/1.

Deliberate World failure emits the existing expected`Fixed-frame event buffer
settlement rejected runtime frame 5` diagnostic. The pair rollback probe adds
the same expected frame1 diagnostic. Existing elite tests similarly
retain their deliberate frame1/120 rejection diagnostics. Retained logs contain
no script/parse errors, warnings, orphan nodes or leaks. Installed Godot reports
line coverage as unsupported. No dependency or authored content fingerprint changed.

## Remaining Gates

Native Splitting and Mirroring remain pending. Chaining has its separate
[retained native gate](2026-10-05-native-elite-chaining-evidence.md). Teleporting has its
separate [retained native gate](2026-10-05-native-elite-teleporting-evidence.md). The full
legal-pair/control matrix, all-weapon physics contacts, extended4096-receipt
capacity, whole-room balance and full P15 certification remain separate gates.
The focused Shielded/Anchored absorbed-control gate is complete; production
gauntlet physics contacts remain included in the open all-weapon matrix.
