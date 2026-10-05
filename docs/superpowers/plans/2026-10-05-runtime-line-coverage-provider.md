# Runtime GDScript Line Coverage Provider Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: P7/P9 measurement implementation
- Applies To: AST instrumentation, isolated runtime execution and exact-source coverage evidence
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `tools/coverage/README.md`
- Last Verified: 2026-10-05
- Exit Gate: Real Godot branch/loop/lambda/failure fixtures and parser closure pass; original source remains unchanged; per-file runtime hits and original SHA-256 values pass the existing collector; full instrumented scene tests and uninstrumented clean checkout pass before final coverage certification.

## Measurement Contract

Use pinned MIT-licensed `gdtoolkit` 4.5.0 for the GDScript syntax tree. Instrument
an isolated project copy, never the production checkout. Executable lines are
statement starts and evaluated initializers identified by the parser. Declaration
headers without evaluated expressions, comments, blank lines and structural
`else`/match-pattern delimiters are not executable lines. Multiline expressions
belong to their original statement-start line. Every supported runtime script
with executable code is included, including scripts with zero observed hits.
Unsupported syntax fails measurement instead of silently shrinking its scope.

Runtime counters use original project-relative paths and original line numbers.
Counter storage and flushing must not alter gameplay state, RNG, Save/Profile,
Replay or EventBus. A real Godot fixture must exercise ordinary and multiline
statements, empty and nonempty loops, branches, early returns, lambdas and rejected
frames. A deliberately unvisited branch must remain uncovered. Normalized reports
reuse `collect_gdscript_coverage.py`; scene totals are not coverage.

## Tasks

- [x] Add failing parser/instrumentation and actual Godot measurement fixtures.
- [x] Add the isolated counter, AST transform and bounded per-process report.
- [x] Verify transformed source parses and preserves observable fixture results.
- [x] Aggregate physical runtime reports and verify exact original source digests.
- [x] Add a reproducible optional coverage invocation to validation/certification.
- [ ] Run the complete instrumented scene suite and uninstrumented regression.
- [ ] Record measured coverage, unsupported cases, logs and a focused commit.

Dependencies remain project scoped under `build/toolchain/`; PyPI identifies
`gdtoolkit` 4.5.0 as MIT with upstream
`https://github.com/Scony/godot-gdscript-toolkit`. Its license text and transitive
dependency metadata are retained during local provisioning.
