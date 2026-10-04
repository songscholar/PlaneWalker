# P16S Trusted Active Content Migration Evidence

- Status: Verified Locally / Current
- Document Role: Current trusted active/native Profile migration evidence
- Authority Level: Executable evidence below the P16S specification
- Applies To: Production activation, native probe and atomic content rebinding
- Owner: Project runtime implementation lead
- Depends On: `docs/superpowers/specs/2026-10-05-plane-walker-p16s-native-content-migration-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Compatible migration, exact continuation and incompatible refusal pass

## Verified Production Behavior

GameState authenticates the exact historical source through the compatibility
ledger before considering active content migration. ProfileRuntimeService verifies
the durable active Run and its original launch/settlement lineage. An invisible,
disabled native probe restores current production Facade state and, when a
checkpoint exists, actual Host, Player, authored room, Actor and effect owners.
The probe is synchronously freed before SaveService's existing compare-and-swap
content rebind promotes the unchanged payload.

`native_content_migration_test.tscn` uses all six currently authenticated sources.
For each source, physical sword, gun and staff combat checkpoints cold-restore
through a new production Main and match the uninterrupted next accepted Player
frame. A separately settled terminal checkpoint migrates and restores its
original completed lineage. These 24 cases preserve the entire physical payload,
including extension data, currency, Profile revision, launch sequence,
settlement receipt and checkpoint digest. Repeated activation consumes no
additional save sequence.

Two re-signed checkpoints pass structural authentication but fail actual current
reconstruction: an invalid Actor weapon claim order, and a changed authored
spawn offset with an updated encounter digest. Their primary bytes and
authoritative memory remain unchanged. Unknown content still refuses, and a
legacy placeholder binding cannot authorize an active Run even when its Run is
otherwise canonical. Only idle placeholder Profiles retain the earlier legacy
upgrade path.

The native probe publishes no spawn, launch, settlement or weapon resource
notifications and leaves no retained child nodes. Independent review exposed
temporary gun/staff resource notifications during loadout reset. A Player-owned
publication switch now suppresses those notifications inside the disposable
probe while preserving resource fact synchronization. Normal Player publication
remains enabled by default.

## Execution Evidence

Missing-compatible-active RED:
`build/test-logs/p16s-content-migration/active-red`.
Actual gun/staff resource publication RED, twelve notification failures across
six sources: `resource-publication-red` beneath the same log root.

Final GREEN scenes: `native-final`, `boot-final`, `compat-final`,
`gun-regression`, `staff-regression` and `resource-regression` beneath that root.
Every scene passed with zero known leak warnings. Scans found no script/parse
errors, missing physics spaces or leaked instances/RIDs. `git diff --check`
passed. No Godot line-coverage percentage is claimed.

The compatibility scene also validates SaveService fault injection, exact
preimage refusal, one-sequence promotion and reconciliation after a committed
primary write. Those existing atomic controls remain the envelope publication
authority for the native migration path.

Current target pack fingerprint:
`b14fc01a755799d8e546da96a6054397ae6b45ccf2d4f955b2975acbb367dc5d`.
Aggregate:
`cabe0979ad446caf8742ae8fb52aa46d704fb2d77207dc0bce13002be1c808ab`.
These values were captured from the actual activated Base registry in the final
physical tests; the test itself derives trusted sources dynamically.

## Boundaries

Historical envelopes contain compatible canonical current runtime fixtures.
They establish the compatibility decision and real cold continuation without
claiming undocumented older combat formats are convertible. Incompatible
authored state is refused until a separately authenticated converter exists.
Invulnerability and first-room routing are explicit test setup, not combat
balance evidence. External publication and future content compatibility edges
remain outside this milestone.
