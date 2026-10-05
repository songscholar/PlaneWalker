# Native Effects Snapshot Copy Plan

- Status: Focused verified / Integrated performance pending
- Document Role: Current gameplay performance plan
- Authority Level: Below AGENTS.md
- Applies To: LaunchHostileEffectAuthority.snapshot only
- Owner: Native observation lane
- Last Verified: 2026-10-06
- Depends On: [Native unified hotpath diagnostic](2026-10-06-native-unified-hotpath-diagnostic-evidence.md)

## Completion Criteria

The actual snapshot deep copy must receive no cached payload, semantic or summon
dictionary that is immediately replaced. The returned full snapshot must retain
the original typed bytes and field order, fresh child state and deep isolation.
Configure, commit, compensation, deterministic retry, publication, full equality,
restore and all child/protocol APIs remain unchanged.

## Failing Acceptance Before Production Edits

Use the existing pinned gdtoolkit 4.5.0 AST parser to instrument only actual
snapshot deep-copy calls in an isolated generated copy. The wrapper records
nonempty cached child branches submitted to the real deep dictionary duplicate;
it then performs the original duplicate. Record source/transformed hashes and
observed AST receivers. No production counter or timing threshold is added.

The focused native scene exercises real transactions and populated authored
payload, semantic history and summon state. Compare instrumented/uninstrumented
typed snapshots, original construction parity, untouched live authority and
mutated outward snapshot isolation. Include reordered accepted restores,
existing typed JSON-codec restored data and direct child-authority changes that leave
retained envelope children stale. The unchanged source must fail only the
zero-redundant-child-copy criterion. Retain paired raw logs and exact failure.

## Implementation

Shallow-copy the retained state and replace existing cached child values with
inert placeholders before deep-copying the envelope. Replacing in place keeps
the accepted top-level key insertion order. Fill fresh child snapshots exactly
as before; initial four-key configure and unconfigured empty snapshots retain
their original behavior. Do not erase/reappend existing keys or alter commit,
restore, compensation, outward tickets, history limits or gameplay values.

Run the focused acceptance and immediate native Effects, semantic, payload,
summon, Bridge and checkpoint neighbors. Retain strict paired-log validation,
source hashes, dependency audit and independent review. Commit only owned paths
after the integration lead grants the shared-index window. No FPS or full
gameplay/UI-completion claim follows from this focused result.
