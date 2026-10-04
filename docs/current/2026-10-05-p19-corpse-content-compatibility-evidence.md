# P19 Corpse Content Compatibility Evidence

- Status: Verified Locally / Current
- Document Role: Current content compatibility evidence
- Authority Level: Exact audited content transition evidence
- Applies To: Titan corpse tuning Base descriptor and historical Profile bindings
- Owner: Project integration lead
- Depends On: `AGENTS.md`, ActualContentCompatibilityLedger, P15D semantic effects
- Last Verified: 2026-10-05

## Retained Binding

The exact previous Base descriptor is preserved in
`data/save/compatibility/base_p19_before_corpse_tuning.json`, matching commit
`2b25db38f330c51769f879562e6f492b2c08d2bb`. The current descriptor pins
`content/enemies.json` to SHA-256
`1723d8ff1de6ce389c03d43162c57d858a729fbc000e5127cb407d954d5b1845`.
This is the canonical finite Titan corpse-pool tuning retained in `0587e43`.

Current descriptor fingerprint:
`b758d96e29137ee904948483a186ef0df50b8348f8138217ed1b70d83f9b284f`.
Current aggregate:
`751f794bfbbb3e562c0862b314654d20efa82970ad29dff4537689c0eded1371`.
The ledger has six exact bindings and five audited transitions. The newest
transition permits only `content/enemies.json`; earlier reviewed file boundaries
remain explicit. Unknown snapshots and altered Meta semantics still refuse.

## Verification

Both actual-content compatibility and production Profile boot scenes passed
again against the retained final content bytes:

- `build/test-logs/p19-corpse-compat-final`: one scene passed, zero failures.
- `build/test-logs/p19-corpse-boot-final`: one scene passed, zero failures.

The runner scans engine and stdout logs; no script errors or leaks were found.
Official Godot line coverage remains unsupported and no percentage is claimed.
Native active-checkpoint content migration is a separate implementation gate.

The tutorial coordinator also now derives its Meta catalog from the actual
Profile registry, completing the P18 isolated-content catalog connection.
P19's earlier release-startup diagnostic is a startup certificate, not a full
five-floor playthrough or a certificate of this later source tree.
