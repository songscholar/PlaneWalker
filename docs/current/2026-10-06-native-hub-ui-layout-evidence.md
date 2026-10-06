# Native Hub UI Layout Evidence

- Status: Partial UI milestone retained; full UI finish remains active
- Document Role: Current local Hub layout evidence
- Authority Level: Execution evidence below the approved UI design
- Applies To: Native Hub page layout and focus preservation
- Owner: UI completion agent
- Depends On: [Native UI finish design](../superpowers/specs/2026-10-06-native-ui-finish-design.md)
- Scope: Shared bounded shell and nine dedicated Hub page layouts
- Authority: `AGENTS.md` and the 2026-10-06 native UI finish specification
- Last Verified: 2026-10-06

## Retained Behavior

The Gateway displays five character portraits, a selected actor preview,
legal character/weapon/time-pair selectors, the equipped weapon and two time
glyphs, four secondary modes, and persistent launch/resume footer commands.
Council groups authoritative nodes into five branches, localizes prerequisite
names, and marks owned nodes. Forge displays five weapon images and level
pips beside its existing upgrade, enchantment and temper commands. Meditation
preserves name/share drafts, codec validation and clipboard availability while
showing graphical saved builds. Archive, gallery and mirror display collection
grids; provider records retain aligned scores and direct-child metadata for
existing local-record scrolling. Training uses its authored mode bitmap.

All mutations still use the existing operation, action identity, revision,
epoch and submission guards. Artwork resolves through the authenticated
production inventory and actor atlas projection, with nearest sampling.
The shared shell constrains modal width to 616 logical pixels, leaves content
scrollable, and keeps commands outside the scroll. Its positioning parent
does not propagate transient content minimum sizes into the viewport.

## Executed Checks

| Evidence | Result |
| --- | --- |
| `build/ui-hub-finish-red-corrected` | Expected RED for absent dedicated layouts/artwork |
| `build/ui-hub-finish-green` | Nine pages across 2 locales, 2 text scales and 4 resolutions GREEN |
| `build/ui-hub-bounded-red` | Expected RED for unbounded wide menus |
| `build/ui-hub-bounded-green` | Bounded-width contract GREEN |
| `build/ui-hub-finish-regressions` | Sharing, facade, streaming, commands, Main flow, dedicated layouts and native background checks GREEN; old Main visual exposed the transient centering defect |
| `build/ui-hub-main-bounds-diagnostic` | Retained precise geometry of that centering defect |
| `build/ui-hub-fixed-shell` | Original Main visual matrix GREEN after the shell correction |
| `build/ui-finish-current-suite` | All 26 then-discovered native UI scenes GREEN, including original HUD and panel contracts |

The runner gives each scene an independent `PLANEWALKER_TEST_DATA_DIR` and
checks both engine and stdout logs for script errors, unexpected engine errors
and leaks. Automated input checks certify the exercised input events and
focus contracts; they do not certify human acceptance on physical controllers.

## Visual Evidence and Remaining Work

The first native capture retained 144 images under
`build/ui-finish-hub-screenshots`. Inspection caught wide menu stretching and
Gateway focus scrolling past the roster. Those defects were corrected after
the capture. Those earlier images are retained diagnosis, not acceptance of
the final shell. Updated native captures and input/accessibility regressions
are required before the full presentation milestone closes.

This layout milestone does not claim final acceptance of the full 49-state
UI finish plan. Council graph links/focused details, Forge selection/anvil
composition, collection category/detail navigation, narrative-specific art,
other native overlays, shared mode combat chrome and final exported visual
certification remain in the active program. The UI program must not be
reported as complete on the basis of the checks above.

The changes remain local, use the existing native build path, and do not
require an online service. They can be reverted as a focused Hub milestone;
the prior Theme/font binding is retained separately in commit `367fc93`.
