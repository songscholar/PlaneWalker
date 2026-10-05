# P20B Local Records Implementation

- Status: Verified / Current
- Document Role: Current implementation plan
- Authority Level: Focused execution plan
- Applies To: Offline local run records
- Owner: Runtime integration lane
- Depends On: `../specs/2026-10-05-plane-walker-p20b-local-records-design.md`
- Last Verified: 2026-10-05
- Exit Gate: `./tools/run_tests.sh --filter local_run_records`, `./tools/run_tests.sh --filter main_local_records`, `./tools/run_tests.sh --filter local_records_visual`, localization validation and clean Godot logs must pass before the focused commit.

1. Define executable physical storage and native flow checks; record missing-service RED.
2. Add read-only settled Profile authentication and narrow SaveService compare-exchange.
3. Implement bounded local boards, authenticated durable pending outbox, full-identity dedupe, deterministic top-1000 retention, restart and retry.
4. Forward optional providers through HubFlow, add a real refresh control, and integrate Main startup/settlement.
5. Add supplemental community localization and verify actual native UI, fault/reentry/refusal cases, forged acknowledgements, pending overflow, fresh Main recovery and logs.
6. Record evidence and commit the exact focused file set; root owns index and combined certification.
