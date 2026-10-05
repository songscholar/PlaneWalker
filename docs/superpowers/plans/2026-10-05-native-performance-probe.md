# Native Main Performance Probe Plan

- Status: Active / Development probe verified / Final certification pending
- Document Role: Current executable verification plan
- Authority Level: Below approved native performance probe specification
- Applies To: Production Main timing and exact automatic recording retention
- Owner: Plane Walker verification lane
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Report contracts and actual bounded native smoke pass without script errors or leaks

## Execution

- [x] Add failing Python contracts for missing executable and honest measured report validation.
- [x] Run `python3 -m unittest tests.contract.performance.test_native_performance_probe`; require missing executable RED.
- [x] Add tools/p15/native_performance_probe.py/.gd/.tscn. Use actual Main, owned physical Profile, Route fixture prerequisites, real Sword phase admission, automatic recorder and fresh physical store.
- [x] Run the contracts; require typed timing/sample/retention rejection cases GREEN.
- [x] Double-import isolated runtime source at `38423c7`, overlay only the new probe, and run actual 120-frame combat and first-floor Boss development samples.
- [x] Require complete actual samples, clean logs and exact first/last physical observations.
- [ ] After coherent source retention, repeat on an untouched committed archive; add rendered, later-phase and sustained samples separately.
- [ ] Retain focused source and evidence with exact file staging; integration owner indexes these documents.

Application hot-path changes are a later independently failing measurement and
correctness contract. This probe must not change the domain or native validators.
