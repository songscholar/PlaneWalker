# P19 Temporal Frontiers Expansion Enemies

- Status: Historical
- Document Role: Historical P19 implementation specification
- Authority Level: Milestone design
- Applies To: Temporal Frontiers optional Expansion enemy pack
- Owner: Project owner
- Last Verified: 2026-10-05
- Depends On: P15 native hostile frame authority; P18 local content management
- Scope: Five authored Expansion enemies, playable native encounters, optional local pack
- Base preservation: No Base pack bytes or canonical Launch counts change
- Implementation Status: Implemented and verified locally
- Completion Evidence: `docs/current/2026-10-05-p19-temporal-frontiers-evidence.md`

Temporal Frontiers is a bundled, data-only, freely licensed optional pack. Players install and enable it through the retained local content manager; its exact assembly receives an isolated save domain. Disabling it retains that domain and returns to Base.

The pack contains exactly five enemies, one on each floor: Echo Lancer (locked delayed double thrust), Mire Cantor (warned target-locked slowing pool), Parallax Guard (diverging beams with a central safe lane), Cinder Drake (charge and fan volley), and Prism Seer (three sequential locked projectile lanes). Every damaging move has at least 30 warning frames, 15 recovery frames, visible authored pixel art, and fixed committed geometry. No package script, scene, executable resource, or external account is required.

Two closed specialized categories, `expansion_enemy_definition` and `expansion_encounter_profile`, keep the Launch catalog of 22 ordinary enemies authoritative. Trusted repository code supplies one generic native Actor scene and an Expansion runtime subclass using the existing frame, action, control, damage, and snapshot boundaries. Per-pack parsers reject unsupported IDs, mismatched floors, schedules, missing assets, unsafe references, and partial five-enemy collections.

Only newly created Expansion runs with the active complete pack select encounter revision 3. Explicit revisions 1 and 2 retain their current deterministic selections. Revision 3 adds the five authored combat recipes to their matching floor pools; each recipe is available on the established open-field template and uses validated entry clearance. A missing pack cannot cold-restore a revision-3 run or silently substitute actors.

Completion requires: contract RED before implementation; exact pack integrity and safe installation; all five distinct action schedules; strict deterministic domain continuation and malformed-snapshot refusal; all five real native actors producing accepted physical damage; Stop and Rift participation; native checkpoint continuation in the selected save domain; Base fingerprint and physical save preservation; actual screenshots at supported resolutions; clean imports/logs; documentation and focused local commits.
