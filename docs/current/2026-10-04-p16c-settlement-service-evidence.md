# Plane Walker P16C Settlement and Durable Profile Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Inactive settlement and profile service contracts
- Applies To: RunSettlementAuthority, ProfileRuntimeService, MetaCatalogFactory, and focused native tests
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16a-profile-domain-evidence.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Focused domain and physical JSON service only; schema-4 migration, native defeat grant producer, Player and Main activation pending

## Implemented Boundary

RunSettlementAuthority reuses SaveEnvelope's full active-run validator through a narrow public helper, with persisted integer normalization. Matching run ID, seed, difficulty, character, weapon, time pair, phase, positive gameplay time, floor prefix, cleared-room facts, immutable launch projection, and retained source ledger are required. Canonical floor/Boss associations cannot be swapped. Preparation is side-effect free.

Shard arithmetic is integer-only and rounds once after difficulty multiplication. Genuine death without floors pays 3; two-floor death pays 63; full victory pays 235/352/587 on normal/hard/nightmare. Each previously unresolved canonical Boss grants two imprints once per profile. Material imprints are not multiplied. Remaining soul uses the launch-frozen 30/50/70 percent retention, not later profile purchases. Overflow, malformed/fractional material values, summons, foreign run/loadout, unvisited rooms, invented/missing/duplicate ledger sources, and repeated terminal settlement refuse.

Material identities bind the run, launch sequence, floor, node, principal source, and P15 native defeat receipt. Renaming a source cannot duplicate the same native defeat, including across nodes. The native producer that seals actual defeat/material facts into RunState is still pending. The tests use actual FloorPlan and RunState traversal plus explicit domain source fixtures; they do not certify full native combat or a cryptographic anti-cheat boundary.

ProfileRuntimeService prepares a validated profile candidate, writes one existing SaveService envelope, and only then commits the live authority. Failed pre-promotion writes leave live state unchanged and retry safely. If SaveService reports an error after primary promotion, the service verifies that exact primary and publishes its already committed candidate once. An unpromoted pending file does not prove successful commit. A second service with old state cannot overwrite a newer durable profile. Compatibility mirrors derive from the nested authority and contradictory values refuse.

Launch persists a monotonic sequence and immutable receipt before dungeon installation, refuses a second active launch, and retires the prior terminal payload. Terminal settlement retains the current terminal snapshot for future resumable ending flow. Explicit abandon consumes the sequence and records statistics with zero payout. Legacy statistics imports deduplicate by actual run identity rather than caller-supplied source names and grant no currency or imprints.

MetaCatalogFactory projects the P16B production JSON into the strict domain catalog without fixture content: 42 nodes, 50 existing Launch items, 15 enchantments, 10 artifacts, 21 records, 5 endings, 10 lessons, 15 hints, 6 training tasks, and 8 archetypes. P13B's certified 50-item pool is authoritative; the P16 specification's old seventy-item wording does not expand the combat pool.

## Verification And Retention

Initial missing implementation RED logs: `planewalker-tests.xg4knM` and `planewalker-tests.8YUKfq`. Physical JSON restart exposed float/integer mirror comparison drift; profile normalization and JSON semantic mirror comparison corrected it. Independent review reproduced swapped Boss maps, omitted loadout checks, renamed material claims, and repeated legacy imports. Named adversarial regression RED is retained in `planewalker-tests.Wu8NEu`.

Final settlement GREEN: `planewalker-tests.uRQeDM`; physical service GREEN: `planewalker-tests.hbE0rn`; production catalog GREEN: `planewalker-tests.a98SzY`. Each is one native scene, zero script errors and leak warnings. Godot line coverage remains unavailable. These focused results do not replace combined repository certification.

The clean detached `cf03870` snapshot completed 243 scenes: 241 passed and two failed (the overly generic native observation method name and an incomplete talent loadout fixture). The precise fixes are local commits `2fb623c` and `7ab956d`. Its formal certification remains failed, with coverage, exports and packaged startup uncollected; later fixes require a new reviewed snapshot.

The service is inactive and temporarily uses the extensible schema-3 payload for focused persistence tests. Schema-4 validation/migration, Registry-authoritative reference loading, native profile commands, real hostile material facts, Player projection installation, crash-to-ending resume, and Hub integration remain required before production activation. No remote publication or real-player certification is claimed.
