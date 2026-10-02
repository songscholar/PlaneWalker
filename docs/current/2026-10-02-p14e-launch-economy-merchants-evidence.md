# Plane Walker P14E Launch Economy and Merchants Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P14E economy, merchant, transaction, Save, Replay, and repository-certification evidence below the approved P14 design
- Applies To: One Launch economy profile, five merchant identities, deterministic inventory, eight merchant service operations, floor settlement, Player/Build/route compensation, SaveEnvelope schema 3, dungeon Replay schema 3, and Launch runtime restoration
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/superpowers/plans/2026-10-01-plane-walker-p14-five-floor-dungeon.md`, `docs/contracts/save-service-v3.md`
- Last Verified: 2026-10-02
- Evidence Status: Verified Locally
- Worktree Base HEAD: `459c0d0`
- Implementation Certification Commit: `af5280a`
- Certified Repository State: `af5280a` plus this documentation-certification commit
- Rollback Point: `459c0d0`

## Completion decision

P14E is locally complete. The repository now has one authoritative Launch economy ledger and production runtime support for all five authored merchants:

```text
merchant_wayfarer
merchant_chronomancer
merchant_forgekeeper
merchant_void_broker
merchant_echo_archivist
```

The implemented service set is:

```text
purchase_reward
reroll
heal
weapon_upgrade
health_trade
cleanse_curse
sell_reward
route_reveal
```

This evidence closes repository-local economy and merchant runtime behavior. It does not claim P14F event runtime, P14G player-facing merchant UI, real player balance feedback, export installation, public release, or external human playtest completion.

## Economy authority and floor settlement

`RunEconomyState` is the sole Launch gold writer. It rejects negative balances, stale revisions, duplicate transaction IDs, illegal positive purchase/service records, and tampered snapshots. Purchases, rerolls, paid services, positive income, reward sales, and floor decay use distinct typed operations.

Boss-floor completion applies the economy profile's cap and overflow decay exactly once through `tx_floor_<N>_settlement`. The ledger records a zero-amount `gold_decay` fact when the balance is already within the cap. Settlement, RunState commit, and floor completion failures restore the exact prior floor and economy snapshots.

## Deterministic inventory and merchant state

Merchant inventory generation is isolated by run seed, merchant ID, node ID, floor, and reroll count. Stable offer IDs, resolved reward definitions, integer prices, compatibility decisions, sold state, reroll count, completed transaction IDs, and content fingerprint are persisted in `MerchantRunState`.

Reopening or restoring a visited shop reads the persisted inventory. It does not regenerate or reroll offers. Duplicate purchase, reroll, and service IDs remain consumed after Save restore.

## Typed service authorities and compensation

The merchant runtime prepares costs and effects before committing participants. Gold, health, and reward costs are separate transaction kinds:

- gold services write `gold_service`;
- reward sales write a positive `gold_delta` with the same transaction ID, revision, and amount as the merchant fact;
- health trades write no fake economy entry and must remain nonlethal.

Purchase, healing, weapon upgrade, health trade, curse cleanse, reward sale, and route reveal use typed authorities with strict tickets, fingerprints, stale checks, snapshots, restore validation, receipts, and inverse rollback. Recoverable failure restores economy, inventory, Player, BuildState, route visibility, service state, and publication state in reverse order. Failed compensation escalates to a typed integrity path.

## Runtime overlay preservation

Reward sale and curse cleanse rebuild the remaining reward ledger from the run-start baseline, then overlay the live runtime difference before committing the reduced build. This preserves non-build Player state such as damage and merchant healing instead of silently resetting it while a reward is removed.

The real Wayfarer Facade path covers a non-full-health Player through purchase, reroll, healing, reward sale, exact ledger publication, Save capture, fresh-Facade restore, deterministic reopen, and duplicate-transaction rejection. Unit evidence also proves that an external numeric/runtime-history delta survives reward removal and exact rollback.

## RunState, Save, Replay, and active floor-rule restore

Economy and merchant snapshots commit atomically under one global RunState revision. Merchant facts cross-check their matching economy operation, transaction ID, amount, and economy revision. SaveEnvelope reconstructs and strictly validates both authorities after JSON-boundary normalization.

Dungeon Replay schema 3 seals economy digest, merchant digest, ordered merchant facts, sold state, reroll count, completed transaction IDs, and service-authority state. Reward-sale payout drift fails closed in capture and validation.

`restore_launch_run(snapshot, effect_authority)` now rebuilds a non-empty active floor-rule runtime before replacing the live Facade. The restored runtime retains the exact snapshot and can advance from the next monotonic frame.

## Focused verification

All P14E focused filters passed with zero unknown leak warnings:

```text
run_economy_state
shop_price_service
merchant_inventory_service
merchant_runtime
merchant_real_services
merchant_all_services
merchant_run_state
merchant_service_authority
merchant_weapon_upgrade_authority
merchant_health_trade_authority
reward_build_mutation_authority
floor_plan_visibility_authority
player_merchant_participant_adapter
run_merchant_state
merchant_facade_flow
run_floor_economy_atomicity
run_floor_lifecycle
save_envelope
run_dungeon_replay
save_service
game_state_save_integration
```

`git diff --check` passed before the implementation commit.

## Complete repository gate

The final local `./tools/validate_project.sh` run at `af5280a` passed:

- shell and CI contract: `197` discovered scenes;
- documentation governance: `30 / 30` Python tests and zero violations;
- content schema: `37 / 37`;
- localization: `8 / 8`;
- playtest data: `13 / 13` and `16 / 16`;
- Launch pool simulation: `8 / 8`;
- M1 release gate: `27 / 27`;
- GDScript coverage contract: `5 / 5`;
- export contract: `37 / 37` in contract mode;
- Godot bootstrap and clean second import: passed with approved sandbox diagnostics;
- Godot scene suite: `197 passed, 0 failed, 197 total`;
- project validation: `PASS`.

Retained validation log:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.00X40c
```

The only registered scene-suite warning remains `tests/reward_system_smoke.tscn` with its known ObjectDB leak.

## Certification boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`.
- Authentic external human playtests and matched observations remain `0 / 20`.
- Synthetic tests and agent-driven runtime verification are not represented as human feel, balance, comprehension, accessibility, or retention evidence.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)`.
- Export templates, real distributable export, packaged startup, signing/notarization, credentials, remote push, store configuration, and publication remain environment-dependent or external boundaries.
- P14F events and P14G map/shop/event/rest/transition UI remain active future slices.

## Next local program

P14F is now active. It will implement the fifteen regular and three special event runtimes, strict event state, deterministic eligibility/outcome selection, atomic cross-domain consequences, combat/reward continuations, Save/Replay restoration, and a UI-ready event view contract before P14G consumes it.
