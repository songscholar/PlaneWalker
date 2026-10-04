# P16E Narrative Sources and Candidate Domain Evidence

- Status: Focused domain GREEN; durable native integration pending
- Document Role: Current P16E authored source and narrative domain evidence
- Authority Level: Evidence beneath the approved P16 specification
- Applies To: Canonical narrative catalogs, dialogue, pickups, choices, endings, bounded exposure observations
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`
- Last Verified: 2026-10-05

## Authored sources and reachability

The existing 57 narrative definitions remain unchanged. A separate closed
`narrative_source_definition` catalog contains thirteen one-time sources:
five Phia markers in the Ruins, three Walker letters across the Ruins, Forest,
and Forge, and five heart fragments bound to the canonical floor/Boss pairs.
Every source has an explicit receipt ID, floor, distinct location, requirement,
and English/Chinese name, description, and journal text. Thirty-nine matching
keys were added to both localization CSVs.

Markers and letters are granted through their own authenticated pickup path;
one environmental record does not stand in for five markers and an unrelated
artifact does not stand in for a letter. Predicate counts enumerate the
configured source definitions and their consumed receipt IDs. Heart pickup
requires the matching Boss fact from the current native run, even if that Boss
was defeated in an earlier campaign.

## Interfaces and transaction boundary

`NarrativeRuntime.configure(entries, source_entries, meta_catalog)` consumes
the real catalogs. Configuration rejects unknown nested fields, malformed
requirements/effects, duplicate sources, invalid floors/references, and wrong
counts; failure removes its old content. `prepare_command(profile, command,
expected_revision, native_context = {})` returns a detached complete candidate
without publishing, spending, or touching scene actors.

Closed command kinds are `narrative_dialogue`, `narrative_collect`,
`narrative_choice`, `narrative_ending`, and `narrative_credits`. Dialogue consumes
one source per node, so alternative replies and repeated reads cannot farm
affinity or faction standing. The 104 authored nodes provide intro, first
death, five floor reactions, five sequential depth conversations, and one
resolution for each of eight NPCs. All effects come from the catalog.

Collection and event contexts have exactly
`{run_id, launch_sequence, floor_id, boss_ids, max_hp, current_hp}` and must
match the active profile launch receipt. The native adapter must authenticate
the location/source, current Boss facts, and actual Player health before
supplying this context. The domain does not treat a UI dictionary as proof.
Pickups, hidden steps, and event choices consume fixed profile sources.
All fifteen hidden steps enforce order and authored requirements.

Vera `defer` returns `{ok: true, context: {deferred: true,
temporary_max_hp_cost: 0}}` without a candidate, source consumption, or state
change. `listen` prepares five temporary maximum HP of cost, clamps current HP
to the remaining positive capacity, and returns a `run_effect` with before and
after health. The profile service must persist the candidate and active-run
health in one transaction before applying it to a real Player. Five accepted
conversations provide eighty affinity; repeat sources cannot pay again.
Nemesis stores five ordered spare/attack decisions, with exact authored flags
and faction changes.

## Endings and bounded exposure

`EndingEvaluator.evaluate(profile, run_facts)` consumes the closed
`{run_id, launch_sequence, terminal_reason, boss_ids}` facts supplied after
native terminal authentication. The facts must name a victory with Void
Throne in that run and match the current active launch, or the last settlement
when no launch is active. A prior victory cannot reopen final choice during a
newer active run. All five choices remain visible with exact missing
requirements; Shattered Freedom is the available fallback after victory.

One replaceable `ending-choice:<sequence>:<ending_id>` source permits one
choice for that terminal run. Discovered endings and completed credits are
distinct existing profile fields; interrupted credits resume after JSON
restoration. Gallery reads do not execute the final-choice transaction again.

`prepare_void_observation(profile, observation, expected_revision)` consumes
exactly `{run_id, launch_sequence, from_frame, through_frame,
void_active_frames}`. Authenticated observations must continue the previous
current watermark, belong to the active launch, and contain no more active
frames than elapsed frames. The native adapter counts only unpaused Void
gameplay, excluding Hub, menus, and pause. One replaceable
`void-watermark:<sequence>:<frame>` source persists deduplication without
per-frame command history. New launch sequences begin at frame zero.

## Verification

RED evidence:

- `ending_evaluator` missing script:
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.wGvxz4`.
- `narrative_runtime` missing script:
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.8Ks2Bq`.
- The four Python source contracts failed before the source catalog/schema
  existed.

Final focused GREEN on Godot 4.6.1:

- `tools/run_tests.sh --filter narrative/`, 2/2,
  `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.1wGID5`.
- P16 Hub/source Python contracts, 13/13.
- `python3 tools/validate_localization.py`, PASS.
- `git diff --check`, PASS.

The complete-domain test reaches all eight NPC resolutions, all thirteen new
sources, ten artifacts, twenty-one records, five Nemesis choices, five Vera
conversations, and fifteen hidden steps through real prepared commands. It
then verifies hidden-ending eligibility. The exact ending matrix covers
eligible/ineligible boundaries, each NPC threshold, collection completeness,
Sibyl depth exclusion, distinct balance sources, and physical JSON equivalence.
Exposure regression advances a thousand additional observations while keeping
one source and zero per-frame completed-command IDs. Duplicate, stale,
other-run, insufficient-capacity, and malformed-content refusals are covered.
Independent read-only reviews of the four domain scripts and two tests found
no blocking candidate-domain issue. Cross-launch watermark replacement,
retired launches, noncanonical/duplicate watermarks, later victory discovery,
alternative same-victory choices, repeated credits, closed context types, and
revision/history overflow were added after review.
Final engine logs contain no script errors or leaked objects. Godot line
coverage is unsupported by this engine build.

The dependency audit command `python3 -m pip_audit -r requirements-dev.txt`
was attempted at the preceding domain commit; its temporary environment
could not upgrade pip/wheel/setuptools. No dependency was changed, and an
online dependency vulnerability audit is therefore unverified.

## Remaining certification gates

Source locations still require real native placement and signed observations.
Registry/pack activation, immutable native story Replay, atomic Vera profile
and run-health persistence, native ending/credits/gallery panels, sound/music,
controller/visual QA, Main return/relaunch, and clean offline import/export
remain integration work. This is a domain reachability result and is not
complete P16 certification or a claim that the shipped Main scene exposes it.
