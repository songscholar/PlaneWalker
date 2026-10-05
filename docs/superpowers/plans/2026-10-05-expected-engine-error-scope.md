# Expected Engine Error Scope Plan

- Status: Active / Focused native verification complete
- Document Role: Current executable verification plan
- Authority Level: Below approved full-product completion contract
- Applies To: Intentional native rejection tests and strict stdout/engine-log validation
- Owner: Plane Walker verification lane
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Exact expected operations pass while unexpected errors, malformed scopes, script failures and leaks fail

## Completion Criteria

Production errors remain unchanged. TestSuite exposes a synchronous helper
whose scope declares one exact operation, expected message/count and matching
completion with a false refusal result. The parser forbids nested, duplicated,
malformed, unmatched or unclosed scopes, missing/excess errors, and every script
error or leak. Scope handling is explicitly enabled only for scene tests.
Each stdout and engine log must independently pass; missing logs fail.

- [x] Add parser counterexamples and confirm missing-parser RED.
- [x] Implement strict structured parser and opt-in TestSuite helper.
- [x] Migrate only intentional operations that really emit errors; preserve silent refusal checks.
- [x] Confirm seven parser contracts GREEN, six actual instrumented-provider contracts GREEN and all focused native refusal scenes GREEN.
- [x] Runner owner integrates parser arguments and failing zero-exit stdout/engine-only error regressions.
- [ ] Retain focused files/evidence and repeat full suites on a coherent untouched archive.
