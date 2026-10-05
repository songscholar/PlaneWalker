# P21E Daily Rewards Implementation

- Status: Verified / Current
- Document Role: Current focused implementation plan
- Authority Level: Below the approved Daily reward specification
- Applies To: Daily physical reward aggregate and native completion proof
- Owner: Plane Walker implementation team
- Last Verified: 2026-10-05
- Depends On: `../specs/2026-10-05-p21e-daily-rewards-design.md`
- Exit Gate: Closed wallet, schema migration, real damage, atomic exchange, cold restart, fault/CAS and controller tests pass with scanned clean logs

1. [x] Define missing reward-domain RED and closed-wallet counter/streak cases.
2. [x] Implement deterministic mode gold, daily tokens, streak entitlements and shop.
3. [x] Migrate the physical daily session and include rewards in the same CAS save.
4. [x] Count authenticated native damage and expose durable reward/storage APIs.
5. [x] Add focused native/fault/restart/controller tests and localization.
6. [x] Record exact clean GREEN evidence and hand presentation integration to root.
