# P21A Native Boss Rush

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Focused executable mode scope
- Applies To: Native Boss Rush, independent durable challenge state and Hub entry
- Owner: Runtime integration lane
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

The first mode is a playable five-Boss sequence using the real launch Player, Boss scenes, authored room geometry, HostileFrameBridge and native Effects. Existing RunOrchestrator owns each stage's phases and terminal state. The aggregate challenge tracks validated loadout, deterministic seed, sequence, completed stages, frame-derived duration and result. It never creates ordinary Meta settlements or ordinary leaderboard records.

The challenge catalog is one first-party JSON source. Boss Rush has an explicit fresh-stage preset: selected character, weapon and two time abilities, base statistics, full health and cooldown reset at each Boss entrance. Unlocked Profile selections are validated. Accessibility assists form a separate timing category. Fresh and continued attempts are distinct categories.

SaveService stores the aggregate separately under actual content/domain and challenge-definition fingerprint. Launch writes before native play. Successful Boss stages are authenticated from bound native actor identity, health, terminal runtime and exact death receipt; emitted notices alone cannot advance. Completed stages and final summaries save before advancement. Faults freeze at a retryable boundary, and post-promotion success requires physical candidate equality.

P21A saves safe stage-boundary checkpoints. Save-and-return preserves earned stages and attempted frame time. Continuation reconstructs the current uncompleted stage at its entrance preset and marks the challenge continued. It does not claim mid-projectile cold restore; full mid-stage native recovery is a subsequent mode extension. No completed stage replays, no ordinary Profile currency changes and no mode records enter ordinary local boards.

Completion requires initial meaningful RED, real native five-stage progression, forged notification refusal, fresh physical reload, save fault/retry, real death summary, Hub entry/return, selected loadout and controller/locale/resolution QA. Offline daily seed derivation, authored challenges and endless scaling follow this first complete mode loop.
