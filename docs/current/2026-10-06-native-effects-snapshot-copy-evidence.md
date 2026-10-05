# Native Effects Snapshot Copy Evidence

- Status: Focused verified / Integrated performance pending
- Document Role: Current gameplay performance evidence
- Authority Level: Below AGENTS.md and the native performance specification
- Applies To: LaunchHostileEffectAuthority.snapshot construction only
- Owner: Native observation lane
- Last Verified: 2026-10-06
- Depends On: [Snapshot copy plan](2026-10-06-native-effects-snapshot-copy-plan.md), [Unified hotpath diagnostic](2026-10-06-native-unified-hotpath-diagnostic-evidence.md)

## Narrow Production Change

The retained Effects state contains already composed payload, semantic and
summon snapshots after commit, compensation and restore. Previously snapshot
deep-copied these cached child histories and immediately overwrote them with
fresh child-authority snapshots. It now shallow-copies the retained envelope,
replaces existing child values with null, deep-copies the remaining envelope,
then obtains the same three fresh full children.

Replacement occurs in place so accepted restored field insertion order remains
unchanged, including arbitrary reordered top-level dictionaries. Unconfigured
empty state and the initial four-field configured envelope retain their original
behavior. No commit, restore, compensation, child authority, ticket, equality,
protocol, schema, history limit or gameplay-value change is included.

## Actual Preproduction RED and GREEN

`tools/p15/effect_snapshot_copy_probe.py` uses existing pinned gdtoolkit 4.5.0
AST metadata. It transforms only snapshot's literal deep dictionary-copy
receiver into an instrumented wrapper, removes the duplicate global class name,
and preserves the rest of the actual source. The wrapper records nonempty
payload/semantic/summon branches supplied to the real deep duplicate and then
performs that original operation. Original/transformed source hashes and exact
AST call expressions/positions are retained. Production has no probe counters.

The actual scene runs original production and transformed implementations in
separate deterministic workflows. It verifies full typed bytes and key order
against the original composition, live parent/child immutability, returned
nested ownership, complete compensation and deterministic retry, mutation
refusal, consumed tickets and successful publication. It restores 32 claims
with deliberately reordered top-level keys and uses the existing typed replay
JSON codec for cold restoration. Plain JSON loses required integer types and
is not an accepted typed checkpoint representation.

The rich fixture executes 46 real authored frames for Corrosive Moth projectile,
Rewind Priest semantic histories and Forest Caller summons in a validated native
room with a real Player and effect roots. The Moth flight is held by a genuine
Time Stop source. Nested projectile control, observed HP history and summon
projection mutations cannot affect live child authorities. A direct real summon
restore changes fresh child claims while leaving the retained envelope stale;
public composition still reads the fresh child. Complete original/transformed
rich snapshot bytes match.

Nine explicit snapshot contexts are inspected: unconfigured, configured,
committed, compensated, published, reordered restore, typed JSON restore,
authored histories and fresh child over stale cache. Before production edits,
the valid final fixture fails only the zero-redundant-copy criterion: 21 observed
discarded child inputs across seven populated-envelope snapshots. All behavior,
ownership and typed-byte assertions pass. After the narrow production edit,
the exact same fixture passes with zero such inputs. Complete snapshot sizes
are unchanged; the rich snapshot is 17,912 bytes before direct child restoration
and 17,984 afterward. These serialized sizes are not allocation or RSS measures.

The first fixture setup attempts are retained at `red/`, `red-acceptance/` and
`red-setup2/`. They exposed fixture errors in typed JSON restoration, requested
action distances and canonical source ordering. They are not optimization RED.
The accepted actual preproduction RED is `red-setup3/`; its classifier permits
exactly the single observed failure21 assertion and validates every remaining
line with the runtime validator. Both raw logs match exactly. The original
uninstrumented functional baseline at `original-behavior/` passes before the
production edit; candidate `green/` passes afterward.

The scene's default invocation performs the real functional workflows and
explicitly reports `copy_traversal_certified: false`. Copy traversal acceptance
requires the generated actual-source probe supplied below. Clean scene discovery
does not depend on an ignored generated resource being present.

```sh
build/toolchain/gdscript-coverage-venv/bin/python \
  tools/p15/effect_snapshot_copy_probe.py \
  --output build/native-effects-snapshot-copy-20261006/green-probe
PLANEWALKER_EFFECT_SNAPSHOT_PROBE=res://build/native-effects-snapshot-copy-20261006/green-probe/launch_hostile_effect_authority_instrumented.gd \
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
TEST_LOG_DIR=build/native-effects-snapshot-copy-20261006/green \
  bash tools/run_tests.sh --filter effect_snapshot_copy --timeout 180
```

Godot is `4.6.1.stable.official.14d19694e`. Five focused parser/probe Python
contracts pass with the pinned coverage interpreter. Development and coverage
requirements pass pip-audit with no known vulnerabilities; no dependency is
added. Statement coverage is not certified by the scene runner.

Eight subsequent actual scene regressions pass serially: native hostile Effects,
semantic effects, summon lifecycle, Moth payload, hostile frame Bridge, native
enemy spatial lifecycle, native combat checkpoint and the default functional
snapshot-copy scene. `final-runtime-validation.json` independently verifies all
ten passing stdout/engine pairs, including the original baseline and explicit
instrumented GREEN. Expected deliberate refusals are accepted only inside
exact completed TestSuite scopes; no script, parse, resource or leak failure is
accepted. The native combat checkpoint confirms the public full build path
still restores actual physical combat state.

## Receipt Identity and Review

All receipts are under `build/native-effects-snapshot-copy-20261006/`:

- `red-probe/manifest.json`, `green-probe/manifest.json`: exact original and transformed identities.
- `red-probe/production-source.txt`: retained original source, verified against the executed original hash.
- `preproduction-red-classification.json`: sole expected assertion21, matched raw logs, zero other errors and unchanged fixture provenance.
- `focused-runtime-validation.json`: original functional PASS and GREEN strict paired-log checks, source/transform identity and unchanged preproduction fixture.
- `final-runtime-validation.json`: all ten passing raw pairs, final source hashes and neighbor runner identity.
- `parser-tests.stdout.log`, `dependency-audit.json`: actual focused tooling checks.
- `neighbors/`, `neighbors-runner.stdout.log`: actual neighboring native scenes.

Original/final production SHA-256 values are respectively
`867c8943577c54f5871da2c2e1f6f64978b04d9ef2dc814f10a3e083c8771861`
and `e4295228482370a148a711a9bc427138eddeea85a51723227814b01995fb567b`.
Original/final transformed SHA-256 values are respectively
`98f2186a26b9a16c1a4e5ec93f1a8091a04ae492dde13cb38cb6f7fd2091bce6`
and `f303077aa864bf79f14f25ef71ff2e1d6f685d6efde471b364f1b4b8d9f13fa0`.
The unchanged RED/GREEN fixture has SHA-256
`4a064840d4b19d2ec67987e9db79bc8c2a63b467f4e0cae54b8e82ea0559ecbe`;
its scene has SHA-256
`70703fd51a3978ef586678142ddcca82878ee77c7a50cfd9a42dbbc34447616c`.
Both RED raw logs have SHA-256
`9a45d4cc8af60317efe4b5acd6608d358b6a20f4ea7c580e9746080574a87b68`;
both GREEN raw logs have SHA-256
`73883288c6fcd9d010558b8bb9ad989d846eab4d3501efb372d3fc8be1a0431e`.

The independent validation lane reviewed the production diff, actual fixture,
AST probe, strict RED classification and passing GREEN logs, then independently
reran all five parser tests. It found no actionable issues. The integrated
frame/RSS/recording/rendered gates remain owned by the integration lead.
This focused construction result does not certify FPS, full gameplay or UI;
the UI production phase remains unstarted.
