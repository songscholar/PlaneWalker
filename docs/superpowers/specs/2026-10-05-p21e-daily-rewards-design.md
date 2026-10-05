# P21E Daily Rewards And Exchange

- Status: Approved / Current
- Document Role: Current focused executable specification
- Authority Level: Below full-product completion scope
- Applies To: Native Daily mode reward state, migration and exchange
- Owner: Plane Walker implementation team
- Last Verified: 2026-10-05
- Depends On: `2026-10-05-p21b-native-daily-boss-design.md`

Authenticated terminal daily attempts award one participation token per UTC+8
day. The first actual victory of the day awards 50 mode gold. Mode gold remains a
separate persistent balance because canonical permanent progression uses Chronos
shards and existential imprints; no conversion rate is invented.

Participation streaks grant the seven-day frame and thirty-day Eternal Traveler
entitlement. Seven consecutive victorious days grant the Daily Walker frame.
An actual victory with zero physical damage events grants the Perfect Walker
title through the next UTC+8 reset. Healing cannot erase a recorded damage event.
Rank rewards require an authenticated optional provider result and cannot be
awarded from a local rank estimate.

The independent daily aggregate atomically owns results, mode gold, tokens,
streak counters, entitlement claims and exchange ownership. Five-, ten- and
twenty-token exchange entries spend tokens once, persist selected ownership and
refuse stale/interleaved writers or purchases during an active encounter.
Reward attempts have deterministic identities and are projections of physical
saved daily results; callbacks and caller quantities are never accepted as proof.

Daily session schema 2 migrates schema 1 explicitly. Legacy archived victories
retain their validated outcome, but lack proof of damage-free completion and
cannot retroactively grant the day title. Recent day records remain bounded while
lifetime counters and owned cosmetics survive archive rollover.

Acceptance requires native victory, actual damage followed by healing, repeat
attempts, physical restart, seven/thirty-day streak transitions, interrupted
promotion and retry, stale exchange writers and exact token-price accounting.
