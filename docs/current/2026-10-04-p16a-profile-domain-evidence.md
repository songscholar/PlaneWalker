# Plane Walker P16A Profile Domain Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Isolated profile and immutable Meta projection contracts
- Owner: Project integration lead
- Applies To: MetaProgressionCatalog, MetaProfileState, MetaRunProjection, and isolated Godot tests
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/superpowers/plans/2026-10-04-plane-walker-p16-hub-meta-narrative.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Focused domain only; production content and shared Save/Player/Main integration pending

## Delivered contracts

MetaProgressionCatalog validates the complete forty-two-node identity set, exact shapes, integer costs, cross-references, cycles, and whole-percent bounded effects. P-04 references L-09. The full authored test tree costs 661 shards and five imprints. The fixture is isolated test content; a production catalog must come from the content pack before activation.

MetaProfileState has one defensively copied schema-1 snapshot for currencies, unlocks, proficiency, forging, affinity, factions, narrative, tutorials, build presets, monotonic launch/settlement receipts, and statistics. Every nested state has exact fields, bounded values, validated references, and duplicate-free canonical lists. Fresh state owns Wanderer, Sword, and Bow; time-ability selection remains the canonical four abilities and six pairs. Nonempty optional content references require the configured reference catalog.

Purchases prepare owner-bound opaque tickets without spending. Only the stored candidate can commit at its unchanged starting revision; mutation, foreign ownership, stale state, repeat commands, repeat purchases, missing prerequisites, and insufficient balances refuse. `candidate_snapshot` exposes a defensive candidate for a future service to save before live commit. `prepare_candidate` is a trusted internal service boundary, not a public arbitrary-state command endpoint. Prepared tickets are local and never serialized as profile authority.

MetaRunProjection freezes unlocked effects and all five forge bonuses. Meta HP is at most 5%, attack 3%, attack speed 2%, entrance recovery 2%, and void mitigation 2%, with a total direct Meta budget of 14%. Forge attack is at most 5%. `validate_combined` conservatively adds entrance recovery and void mitigation to each multiplicative character/Meta/forge stat benefit; canonical character caps keep the maximum at 30%. Unknown stats and excessive benefits refuse without clamping.

The projection uses whole percentages and integer counters for its digest, avoiding JSON float spelling changes. Validation requires the authoritative catalog and rederives all options/effects from unlocks; a rehashed payload cannot replace authored effects, even with a smaller in-budget benefit. Player installation and Save/Replay authentication of this projection are later boundaries and are not claimed here.

## Tests and limitations

Missing-domain RED is retained in `planewalker-tests.pm05YS`. A JSON projection round-trip assertion then exposed digest instability in `planewalker-tests.M9qDvm`. Independent native adversarial review exposed accepted fractional discounts and approximate retention tiers in `build/p16-review/projection-adversarial-red.log`; both now reject during catalog configuration and have named regression assertions. The final three domain scenes passed in `planewalker-tests.4USX3O`, with zero script errors and leaks. Coverage remains unsupported by the current Godot line-coverage tool.

These tests cover all forty-two legal purchases, full-tree reachability, cost/budget limits, malformed/stale/duplicate/foreign commands, atomic restore refusal, defensive copying, actual JSON profile/projection round trips, and later-profile independence of a frozen projection. They do not deliver the Hub scenes, forge transactions, native tutorials/dialogue, settlement service, profile-envelope schema-4 migration, final endings, or production launch integration.
