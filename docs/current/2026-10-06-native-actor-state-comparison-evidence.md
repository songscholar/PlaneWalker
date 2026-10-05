# Native Actor State Comparison Evidence

- Status: Focused Verified / Integrated performance pending
- Document Role: Current implementation and regression evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Hostile Actor commit admission and complete current-state equality
- Owner: Plane Walker integration lead
- Depends On: `2026-10-06-native-boss-state-comparison-plan.md`
- Last Verified: 2026-10-06

## Production Change

`LaunchHostileActor.can_commit_launch_frame` formerly generated a detached
complete Actor snapshot solely to compare it with the candidate's before-state.
It now delegates complete runtime equality to the runtime-owned
`matches_snapshot` predicate when present, then compares all original Actor
fields. Those fields still use their original snapshots and detached metadata.
The shared state builder preserves the public complete snapshot's original
shape, order and types. Runtimes without the predicate retain the original
complete-snapshot equality algorithm.

This boolean predicate never admits a restore, publishes a frame or supplies
a compensation checkpoint. Ticket ownership, actual health equality, complete
candidate validation, physical landing checks and historical restoration
remain unchanged. Integer/float equality retains the old Godot semantics.

Bridge sealing also uses the existing live Actor boundary query solely to read
the terminal flag. Its full compensation-validation and discard checks still
execute first; runtimes without narrow queries keep the existing fallback.

## Executable Evidence

RED at `build/test-evidence/hostile-state-comparison-red/` prepares real
candidates for all five authored Bosses. Their original two commit guards
never invoke the counted comparison predicate: all five operation-count
assertions fail, expected two calls but actual zero. Candidate preparation,
changed live control/body refusal, commit and complete rollback already pass.
The retained pre-change Actor SHA-256 is
`aa74654b663d330ebba63287fc89a3a9aca099811b445f31541cbf86f7979db3`.
The retained RED fixture SHA-256 is
`5e0bc096a21628f996c635b671d5d467f7e5454fc81471db2f5c8e46a394d444`.

The initial GREEN at `build/test-evidence/hostile-state-comparison-green/` passes the
new integration scene with strict paired runtime logs. The strengthened test
also compares the old and new verdict for every missing top-level field,
unknown fields, nested Boss/metadata mutations, moved physical bodies and
equivalent integer/float values. Counted real Boss predicates take zero full
Boss observations in these equality-only calls. The query-less ordinary enemy
fallback still captures one complete original runtime snapshot. All five
candidates commit and roll back to byte-identical complete Actor state.

The extended seal RED at `build/test-evidence/hostile-seal-boundary-red/`
fails exactly one extra complete Boss observation for each of the five actual
Bridge seal operations. The full candidate preparation, publication and
continuation already pass. Final GREEN at
`build/test-evidence/hostile-state-comparison-final-green/` passes both the
comparison and seal assertions with strict paired logs. Sealing takes zero
complete Boss observations and leaves the next native boundary ready.

Final Actor / Bridge / fixture SHA-256 are respectively
`bb1e856ee60ab3b629ac89ffc335fd9e5a352c162cc6f6534e45fee67fd3b78f`,
`c6b18dd1882c192be56e08cad13d8042b15eae387a5866a0c342863e8c2edad0`,
`1219db3f133444b62dd68229ffbfaf2126683815731ae22dbc4cb345b12a5cfe`.

`build/test-evidence/hostile-state-comparison-neighbor-bridge/` independently
passes the existing HostileFrameBridge scene with strict paired logs. Its
frame-start weapon damage, sibling refusals, exact compensation, deferred
publication, same-frame death and irreversible-seal checks remain intact.
The same neighbor is repeated after the seal change under
`build/test-evidence/hostile-state-comparison-final-neighbor-bridge/`.
Boss predicate and leaf-authority validation evidence is retained separately.

## Retention Boundary

This focused operation-count result does not certify a millisecond benefit,
rendered FPS, saturation, long-duration recording or complete product coverage.
The ordinary scene runner explicitly reports line coverage as unsupported;
the separate instrumented provider remains required. Public snapshot/restore
APIs, serialized content and save/replay formats are unchanged.
