# Native UI Core Finish Evidence

- Status: Implemented / Focused verification passed / Final visual certification pending
- Document Role: Current native UI implementation evidence
- Authority Level: Evidence below AGENTS.md and the native UI finish specification
- Applies To: Combat HUD, choices, dungeon panels, pause and build inspection
- Owner: Native UI implementation worker
- Last Verified: 2026-10-06
- Depends On: [Native UI finish design](../superpowers/specs/2026-10-06-native-ui-finish-design.md), [Native UI finish plan](../superpowers/plans/2026-10-06-native-ui-finish.md), [Hub finish evidence](2026-10-06-native-hub-ui-layout-evidence.md)

## Implemented Behavior

The combat HUD uses authenticated character, weapon and time artwork in fixed
resource slots, numeric resources, visible skill cooldowns and a compact boss
strip. Full equipment facts are shared with the read-only build inspector.
The inspector reads a validated complete RunViewState and detached canonical
content definitions, including all four owned content pools and eight launch
archetype scores. Its contents scroll by controller; Back remains outside the
scroll region.

Pause owns the inspector and returns focus to its Build action when inspection
closes. Actual Main supplies the accepted paused snapshot. LAUNCH dungeon
entrances now project an explicit entry room with index zero after checking
the canonical generated entry node, plan digest, seed and floor identity. The
runtime floor number is one-based; FloorPlan.floor_index is zero-based.
Malformed zero-index combat rooms and forged entry plans still fail closed.

Choices retain the existing offer/revision and one-shot submission checks.
Each card has authentic content art and a bounded detail scroll. Rarity uses
canonical localization keys. Language changes refresh existing labels while
preserving button identity, scroll, focus, pending active-item replacement and
submitted state. Real DraftService starter, reinforcement, talent and contract
offers are exercised, including the canonical decline option.

Dungeon maps consume only projected room knowledge, so unknown room glyphs
cannot reveal hidden types. Routes include a graphical preview, merchants
separate goods from services, rest and treasure show their actual landmarks,
events use exact authored event artwork and floor transitions show exact
floor resources. Existing command identities, payloads and presentation
epoch guards remain in use.

## Retained Verification

Each layout test covers 640x360, 1280x720, 1920x1080 and 3440x1440 with zh_CN
and en at text scales 1.0 and 1.5. These are assisted isolated production-view
matrices; they are not the final actual-Main 49-state certification.

| Verification | Passing retained log directory |
|---|---|
| HUD resource bounds and visible character cooldown | `build/ui-hud-finish-final-green` |
| Six dungeon compositions and protected map/event art identities | `build/ui-dungeon-finish-final-green` |
| Four authentic deterministic DraftService offer kinds | `build/ui-choice-authentic-green` |
| Live choice locale, replacement focus and submission guards | `build/ui-choice-locale-green` |
| Complete build inspection content and bounded controller scroll | `build/ui-inspector-green` |
| Pause matrix and return focus | `build/ui-pause-finish-green` |
| Verified entry projection and spoof refusal | `build/ui-entry-projection-green` |
| Actual Main pause-to-build-to-resume interaction | `build/ui-main-pause-inspection-green` |

Meaningful failing evidence is retained in `build/ui-hud-cooldown-red`,
`build/ui-dungeon-event-art-red`, `build/ui-choice-authentic-red`,
`build/ui-choice-locale-red`, `build/ui-inspector-red`,
`build/ui-pause-finish-red`, `build/ui-entry-projection-red` and
`build/ui-main-pause-inspection-red`. Focused GREEN checks include paired
stdout and Godot engine scans for script errors and resource leaks.

The broader UI regression run is retained in
`build/ui-finish-cohort-regressions`. During its launch-loadout scene the
runner was modified by another worker: scene assertions and engine logs
passed, but the running shell reported a syntax error. This particular run
cannot certify the complete runner cohort. The affected scene was rerun with
the stable runner and passed in `build/ui-cohort-runner-recovery-green`.
All 31 paired scene logs in the broader directory also pass a separate strict
log scan. A prior nonreproducing Hub ObjectDB leak is not claimed fixed by the
successful isolated retry. The three pinned project requirements were audited
with pip-audit and reported no known vulnerabilities; this UI cohort adds no
dependencies.

## Remaining Gates

Current core native screenshots must be recaptured and inspected. Earlier
Hub, HUD and choice captures predate final corrections; old choice captures
also used missing localization keys and are diagnostic evidence only. No
final screenshot certification is claimed here.

Results, narrative, credits, tutorial, training, settings and remapping remain
in the next owned UI cohort. Challenge/replay/platform/content views belong to
the parallel UI worker. The final combined source still requires controller
and accessibility regressions, final 49-state rendered/input evidence,
performance evidence and reproducible exported startup. Automated controller
checks do not certify real hardware acceptance or human player feedback.
