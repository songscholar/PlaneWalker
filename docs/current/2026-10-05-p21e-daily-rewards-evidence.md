# P21E Daily Rewards Retention Evidence

- Status: Verified / Current
- Document Role: Current retained evidence
- Authority Level: Evidence beneath the approved Daily specification and plan
- Applies To: Daily native reward proof, durable wallet, migration and exchange
- Owner: Plane Walker implementation team
- Depends On: `../superpowers/specs/2026-10-05-p21e-daily-rewards-design.md`, `../superpowers/plans/2026-10-05-p21e-daily-rewards.md`
- Last Verified: 2026-10-05

The independent Daily aggregate now owns one participation token per terminal
day, fifty separate mode gold per first native victory, seven/thirty-day permanent
participation entitlements, seven-day victory frame, and day-bound Perfect Walker
title. Authenticated native health loss permanently increments the attempt damage
counter; healing and invented health/frame notices cannot produce flawless proof.
The mode wallet does not invent conversion rates to ordinary Chronos shards.

Five-, ten- and twenty-token cosmetics use an atomic exchange command in the
actual Daily controller menu. Results, balances and owned IDs share one CAS save.
Failed promotion publishes neither money nor ownership; retry commits once,
stale writers refuse, and cold reload retains exact balances. Lifetime reward
accounting survives the rolling thirty-one-day result archive. Schema 1 migrates
explicitly; legacy victories carry unknown damage proof and cannot grant titles.

Verification:

- `./tools/run_tests.sh --filter daily_ --timeout 90`: 9/9 PASS, clean scanned
  `build/daily-rewards-green` logs. Covers actual weapon/Boss combat, admission,
  physical native terminal/fault/CAS, Main/controller/visual paths, UTC+8 calendar,
  closed wallet, schema migration, and sixty-five-day archive rollover.
- `./tools/run_tests.sh --filter daily_reward_native --timeout 90`: native
  earned-token controller purchase, failed exchange/retry, focus, disabled owned
  entry, actual damage/heal and physical restart; `build/daily-rewards-controller-green`.
- Required-domain RED retained at `build/daily-rewards-red`; missing physical
  exchange RED at `build/daily-rewards-native-red`.
- `git diff --check`: PASS. `python3 -m pip_audit -r requirements-dev.txt`:
  no known vulnerabilities found.

Integration APIs: `NativeDailyBossFlow.purchase_reward(id)` submits exact catalog
prices; `mode_reward_storage_scope()` returns root/save/owner/content identity.
`DailyBossSession.validated_reward_aggregate(payload, owner_id, mode_fingerprint,
registry)` independently verifies the physical aggregate and returns lifetime
participation/victories, entitlement IDs and exchange ownership. Root/platform
integration owns Profile challenge cosmetic activation and Main publication.

The five additional authored special conditions and optional authenticated
provider rank rewards remain separate follow-on work. Local rank estimates do
not grant provider prizes. These limits do not interrupt the authorized program.
