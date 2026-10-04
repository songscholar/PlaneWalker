# P16R Native Combat Cold Checkpoint Plan

- Status: Verified Locally / Current
- Document Role: Current execution plan for native combat reconstruction
- Authority Level: P16R specification subordinate implementation
- Applies To: Production native combat checkpoint lifecycle
- Owner: Project runtime implementation lead
- Depends On: `../specs/2026-10-05-plane-walker-p16r-native-combat-checkpoint-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual native combat cold reconstruction and focused regressions pass

1. Retain actual Main warning/fighting/payload checkpoint refusal RED.
2. Introduce portable cold Actor state without Health transaction freeze tokens.
3. Capture and strictly validate the sealed native encounter aggregate, including
   live native hostile payloads and stable status-source bindings.
4. Extend checkpoint version two while preserving version-one safe restoration.
5. Stage native reconstruction inside the existing Player/scene restore
   transaction and compensate every rejected aggregate or publication.
6. Verify cold continuation against an uninterrupted accepted-frame branch,
   tampering, failure compensation and existing safe/native/event regressions.
7. Retain executable evidence, fixture limits and a focused local commit.

All seven steps are complete. Retained evidence:
`docs/current/2026-10-05-p16r-native-combat-checkpoint-evidence.md`.
