# P15 Synthetic Domain Matrix

- Status: In Progress
- Document Role: Current focused certification plan
- Authority Level: P15 Task 12 execution plan
- Applies To: Deterministic synthetic Boss behavior traces
- Owner: Project owner
- Last Verified: 2026-10-05
- Depends On: P15 native Boss runtime; retained Launch character/weapon profiles; native matrix certification
- Exit Gate: 22,500 unique synthetic cases, byte-identical repeats, 48 primary moves and four paid responses, typed cold continuation, strict budgets, clean logs and retained source

- [x] Inspect P15 Task 12 and existing Boss, response, profile, and payload domains.
- [x] Define failing report contracts before the independent probe and driver.
- [x] Enumerate 30 canonical seeds, 150 real parsed profile combinations, and five Bosses.
- [x] Execute rotated authored moves, both equipped time inputs, profile-derived synthetic damage, full enrage thresholds, and typed mid-warning continuation.
- [x] Compare full deterministic repeated traces and reject unsupported snapshots without mutation.
- [x] Run adversarial payload capacity/expiry probes and retain bounded allocation evidence.
- [ ] Run all 22,500 cases with fail-closed aggregation; certify retained exact source and document limits.

The separate tool owns only synthetic domain evidence. It instantiates the authoritative `LaunchBossRuntime`, resolves actual Launch character/weapon definitions, and uses explicit synthetic observations and damage receipts. Both equipped time abilities influence each trace through actual Boss controls, paid Time Sovereign receipts, or declared profile-derived synthetic attack observations. This does not instantiate a Player or execute physical weapon collision, and therefore reports `synthetic=true`, `production_case_count=0`, `human_playtests=0`, and no unassisted victory.

One authored move is rotated per case. At least one case per seed/Boss advances the entire authored enrage threshold; no field mutation invents enrage. Each complete case compares a second full run byte for byte and restores a typed mid-warning snapshot into a fresh runtime before comparing the exact next frame and state. Dedicated payload probes authenticate capacity and eventual expiration independently from case totals. Partial ranges are useful for debugging but cannot claim full certification. This tool does not alter the separate 750-case native driver.

The first full-seed pilot executed 750 cases in 73.05 seconds and reached all 52 actions. Six Python report contracts passed, including stale-output rejection, source binding, partial/full claim refusal, identity uniqueness, and semantic mutation refusals. Each shard additionally runs eight repeated positive Time Sovereign response probes across both phases and a dedicated adversarial capacity/expiry probe; these supplemental checks are not counted among the 22,500 matrix cases. Final certification runs from a retained source archive and hashes all domain scripts and Base definitions before and after execution.
