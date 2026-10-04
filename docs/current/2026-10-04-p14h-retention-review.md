# Plane Walker P14H Retention Review

- Status: Implemented / Current
- Document Role: Current milestone retention review
- Authority Level: Local P14 integration evidence, below product completion criteria
- Owner: Project integration lead
- Applies To: Native dungeon interactions, reward compensation, event lifetime, Save/Replay, simulations, and local packaging
- Depends On: `AGENTS.md`, `docs/current/2026-10-04-p14g-production-flow-evidence.md`, `docs/current/2026-10-04-p14-event-lifetime-replay-evidence.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Focused verification complete; immutable combined repository gate pending

## Implemented boundary

The six native dungeon panels and production coordinator support five-floor route, merchant, event, treasure/rest, map, and floor-transition flows. Physical saves retain the original pre-reward Player baseline even before the first merchant. Current and legacy effect histories continue through fresh Player/Facade restores, merchant transactions, and later room clears. Full Launch Player Replay is schema 7; weapon Replay remains 6 and M1 remains 2.

Reward compensation now verifies actual restored snapshots for passive effects, talents, and active items. A participant falsely returning successful restoration is rejected, while provisional publication still closes. The focused transaction test passed in `planewalker-tests.NfVnEz`; real dungeon rewards and merchant active rewards passed in `planewalker-tests.5pxcc8` and `planewalker-tests.jG2z6A`. Earlier false-success RED evidence is `planewalker-tests.u6XLKl`.

## Deterministic report evidence

Eight Python dungeon report contracts passed in 300.645 seconds. Retained `build/dungeon-evidence/p14h-final-a.json` and `p14h-final-b.json` are byte-identical, with SHA-256 `98cd7dd5294f7e394975f84cf909a7a3f2c4c9a50fd0ccd9b5f551e456e9e2ae`, report digest `e5146cc9e36569b206b93d9cd5f690c85c97d67814ea0ec3ddab22a4561550d4`, and content digest `e17305ac16790b59dc6fcaab042a115a2b9c29938e550454309566f597ab8bc0`.

These reports precede the PlayerRewardTransaction compensation hardening. They identify that frozen production revision only; the final repository gate generates its own report from its committed checkout.

Thirty deterministic runs complete 150 floors with zero invalid plans or negative balances, 161 purchases, and 167 event consequences. Spending is below/within/above the authored target on 91/41/18 floors. Remaining gold exceeds its target on 140 floors. These synthetic flow results do not establish human difficulty or economy balance; no mandatory purchases or invented income were added to meet the target.

## Local package and persistence

`build/portable/PlaneWalker-macos-p14-final/PlaneWalker.command` launches the real Main using a complete upstream-signed Godot.app runtime bundle and project-local unsigned launcher. It includes engine licenses and separate application persistence. PCK SHA-256 is `b0f5005d3c853fbf1fd406d0bbc0ad799548221e0e5ad0f7e931f6cf25ac13c2`; package tree digest is `762659e95c3d305f082813632bf87e255306ac621f6849b5a6bf2e30ed7effac`. The startup report is `build/export-evidence/portable-p14-final-report.json`, SHA-256 `f4f0e5ff7e2cfba2ff7e958fa6f0a84d8bc1a99aad6139543a56ad515d8073af`.

The package was built before the compensation hardening and requires rebuilding for the later reviewed revision. It is a local editor-runtime fallback, not formal three-platform release certification. The project now redirects default application Save and input paths through `PLANEWALKER_USER_DATA_DIR` or `PLANEWALKER_TEST_DATA_DIR`; explicitly supplied persistence roots remain explicit. The engine may still create its normal empty userdata directory.

## Certification and next work

The immutable committed checkout must pass the full repository gate, including the 150-loadout dungeon matrix. This review records focused results and does not mark that gate passed before it runs. P15 native enemy/effect/Player transaction integration, remaining enemies and five Bosses, P16 Hub/meta/narrative, final presentation, and Expansion systems remain active work. Human playtests remain 0/20; GDScript line coverage and official three-platform template exports remain unavailable. No remote publication occurred.
