# Native Summon Import Evidence

- Status: Verified Locally
- Document Role: Current focused clean-import evidence
- Authority Level: Below approved full-product specification
- Applies To: Autoload dependency loading and actual summon scene instantiation
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/plans/2026-10-05-native-complete-gameplay-certification.md`
- Last Verified: 2026-10-05
- Completion Commit: `d96b558dfbaef2b8d9a4e57ac758f3666ea64071`

## Root Cause And Repair

The autoload dependency chain reaches LaunchSummonActor during bootstrap import.
Its constant PackedScene preload loads the Sentinel texture before Godot has
imported that texture. Fresh checkouts at `9c5d517` and `936d2f9` emit an
unexpected `Failed loading resource: .../shattered_sentinel.png` during autoload
creation. Later texture import and a clean second import cannot make that first
import pass the strict project gate.

The summon actor now keeps the template's resource path and loads its PackedScene
only when an actual summon is instantiated, after normal project import. The
runtime still requires both the texture and the template, and uses the same
physical scene, script, reward exclusion and lease behavior. No import-error
allowlist was widened.

## Exact-Source Evidence

A new detached local clone at the completion commit is retained under
`build/lazy-summon-import-green/`, without source overlays or previous `.godot`
state. Its first import exits zero. The existing generated-translation validator
classifies only the eleven declared CSV pairs, confirms both derivatives were
regenerated and leaves zero unclassified errors. The second import exits zero
and passes the strict stdout/engine runtime parser with no errors or leaks.

Both actual summon scenes pass under strict dual-log checks in the original
workspace: `native_summon_test` and `native_summon_lifecycle_test`. Their logs are
under `build/test-evidence/lazy-summon-native-green/` and
`build/test-evidence/lazy-summon-lifecycle-green/`.

This evidence certifies the demonstrated import repair and focused native summon
behavior. Full clean-checkout scene/coverage certification, a final rebuilt
package and complete gameplay remain separate active gates. Human sessions remain
zero.
