# Plane Walker Native Narrative and Retention Evidence

- Status: Implemented / Current
- Document Role: Focused implementation evidence
- Authority Level: Native narrative contact, Profile persistence, and retained Run boundary
- Applies To: ProfileRuntimeService and RunSettlementAuthority
- Owner: Runtime integration agent
- Depends On: `AGENTS.md`, native floor entry commit `17dbe8e`, narrative domain commit `55c4ce9`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused integration passed; Main placement and whole-product certification pending

## Delivered Behavior

ProfileRuntimeService persists authored dialogue, contact-backed source collections and choices, authenticated endings, and credits through the existing strict Profile ticket and physical primary-promotion transaction. Read-only Settlement methods authenticate real Run snapshots, frozen Meta policy, launch identity, retained sources, canonical Boss correspondence, and terminal facts without changing payout.

Native collection and choice occurrences are service-created Area2D nodes beside the static validated room tree. Execution checks the actual Player, bound Room and Marker identities, native collision geometry and mask, unchanged room transform, current floor/node binding, center distance, and physical overlap. A default M1 Player sharing the launch string cannot bind. Final-floor collections remain possible after authenticated Victory and before settlement so the final heart fragment can be collected.

Vera's max-HP effects prepare detached full Player reward state and a complete cloned Run before writing. Existing Event Health participants are synchronized in the candidate. The primary contains Meta Profile, complete Run, and complete reward participants together. Native state changes only after the actual primary proves commit. Promotion ambiguity is reconciled by inspecting the exact primary candidate. Native reward, Run, identity, or generation drift requires explicit recovery and does not repeat an already saved narrative grant.

General `retain_active_run` and `restore_active_run` use actual Run and Player types, authenticated launch/config/loadout/projection/source checks, clone restore preflight, and current physical-primary equality. Refused writes do not advance Profile or modify native participants. Recovery refuses an obsolete service instance.

Launch preparation saves `pending_meta_run_projection` and normalized `pending_run_config` in the same envelope as the receipt. The configuration retains milestone, selected talents, and accessibility choices. Detached getters support physical restart before native bootstrap. Invalid or receipt-inconsistent configuration is refused. Terminal settlement and abandonment retire both pending extensions. Historical payloads without the configuration extension remain readable; unavailable historical pre-bootstrap choices are not inferred.

## Verification

Meaningful RED for missing durable native config: `build/test-logs/p16-native-narrative-retention/pending-config-red` (`T5yR7h`). Meaningful RED for pure collection publication drift: `build/test-logs/p16-native-narrative-retention/collection-drift-red` (`PC6SFh`). Fixture initialization and typing mistakes are not counted as feature RED.

Final GREEN: `build/test-logs/p16-native-narrative-retention/final` (`2QbD0h`), one real native scene with physical JSON save/reload and promotion-fault injection. It covers authentic Launch Player construction in production Host order, immutable pending launch restart, malformed/foreign projection and config refusal, native retention failure/retry/recovery, stale service refusal, issued contact-token tampering, collection and Vera failure/retry/drift, actual authored Event authority/choice transactions on generated routes, final Victory fragment, ending failure/retry, settlement, terminal reload, and credits.

Regression GREEN: `profile-regression` (`tlrNJI`), `settlement-regression` (`JlTRbm`), `workshop-regression` (`pOGp3d`), `migration-regression` (`2rQLAZ`), and `material-regression` (`zUx8F9`) under the same log directory. Existing settlement positive controls now use the actual Base catalog, preserving historical Run shape and payout assertions instead of relaxing production fingerprint validation. Logs contain no script errors or object leaks. Godot line coverage is unsupported; scene counts are not a coverage percentage.

Independent read-only review by the onboarding integration agent identified pure-collection drift and publication reconfiguration gaps; both were repaired and the final scene passed.

## Remaining Boundaries

This API retains full Run and the existing full reward participants. It does not save or restore the complete Player Replay position, action frame, or World state and is not a full gameplay resume certificate.

Boss sources in the narrative integration scene are canonical settlement contract fixtures after real route completion, not five native Boss kills. Native Boss kits and full dungeon combat are not certified here.

Authored narrative `location_id` values still need a concrete placement policy in Main. The service accepts a caller-selected valid native anchor on the matching floor; it proves physical contact at that issued occurrence, not final spatial content placement. Native Void-exposure observation also remains unintegrated.

Recovery has native restore preflight and Player compensation on a failed Run restore; injected compensation-failure coverage is still absent. Main/UI activation, combined suites, formal exports, packaged startup, and human gameplay review remain separate milestones. No remote publication was performed.

## Retention Decision

Retain this focused commit as the reversible service boundary. The public launch API adds an optional third configuration argument; omitted configuration derives the receipt-compatible Launch defaults. Rollback is a focused local revert of this milestone after dependent Main/Host work is accounted for.
