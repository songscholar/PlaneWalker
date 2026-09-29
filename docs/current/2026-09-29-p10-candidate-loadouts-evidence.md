# Plane Walker P10A Candidate Loadouts Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P10A candidate-loadout and candidate-lab certification evidence
- Applies To: Canonical loadout catalogs, authoritative validation, player activation, Bow/Rift/Accelerate candidate runtime, two-slot HUD, Candidate Lab, six time pairs, lifecycle facts, reset, and M1 isolation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p10-candidate-loadouts.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified Implementation HEAD: `4173b4fa70a0a8137e89e16d45f54846e759878b`
- Certified Repository State: `4173b4f` plus this documentation-certification commit
- Rollback Point: `e36f78d90ebda19b6bb7464db8a28d6814d12c9c`

## Completion decision

P10A is locally complete. The repository now owns canonical identities for five characters, five weapons, and four time abilities; validates one character, one weapon, and exactly two distinct abilities per run; activates the accepted loadout on the Player; renders two data-driven HUD slots; exposes three isolated local candidates; and certifies all six legal unordered time pairs.

This is candidate implementation evidence, not a release or promotion decision. Formal M1 remains `M1 Candidate — External Validation Pending`, authentic external playtest evidence remains `0 / 20`, and the evidence-driven post-M1 promotion remains `Not started / Evidence-gated`. Bow, Rift, and Accelerate are not formally promoted to Current.

## Certified implementation chain

| Commit | Deliverable |
|---|---|
| `e36f78d90ebda19b6bb7464db8a28d6814d12c9c` | Freezes the P10 candidate-loadout plan and evidence boundaries |
| `f60a4222e2c2237ad4026b5bf68e95171017a5f8` | Registers canonical character, weapon, and time-ability definitions |
| `f8aa3a23c1ac4afab5a028096dd8dc0a582b6ce1` | Adds authoritative milestone and loadout validation |
| `fd4812a821874032709bf97aaa53eee5d88482d1` | Applies equipped loadouts and cross-run reset to the Player |
| `1295b59319258a8555a8eec3c27b9a2a593f686d` | Completes Stop/Rewind/Rift/Accelerate candidate runtime and cleanup |
| `0971f84fbedbbb7c2a6d461720b9e8793e521c3f` | Synchronizes loadout localization with the Base Pack catalog |
| `7d9d1699fe71ef5ecc5efdb0a8cf1c4b38dbc0b2` | Replaces fixed Stop/Rewind HUD labels with two validated equipped slots |
| `f732f705fbd0590d1a52334c2693038822b1730b` | Adds the controller-safe local Candidate Lab and preserves Quick Start |
| `4173b4fa70a0a8137e89e16d45f54846e759878b` | Certifies all six time pairs and repairs expired Rift reference cleanup |

## Canonical catalog and availability boundary

The Base Pack contains `5 / 5` character definitions, `5 / 5` weapon definitions, and `4 / 4` time-ability definitions. Together with the current 20 items, 4 blessings, 6 curses, and 3 talents, the manifest owns 47 validated content definitions.

Canonical ability IDs are `stop`, `rewind`, `rift`, and `accelerate`. Input and typed-fact IDs are `time_stop`, `time_rewind`, `time_rift`, and `time_accelerate`. One shared fail-closed mapping owns the relationship; unknown IDs, mismatched pairs, duplicate abilities, malformed categories, and unavailable milestone content are rejected before authoritative run mutation.

## Authoritative runtime and reset boundary

`RunRuntimeHost` applies the accepted deep-copied config to the Player exactly once after RunConfig and active-registry validation. Rejected validation or first-room startup publishes no accepted run lifecycle. Cross-run reset clears energy, cooldowns, action state, active Stop, expired or active Rift references, and Accelerate state before a later run is accepted.

Quick Start remains exactly:

```text
milestone M1
wanderer + sword + stop + rewind
```

The Candidate Lab exposes deep-copied local `NEXT` presets only:

```text
Bow:        wanderer + bow   + stop + rewind
Rift:       wanderer + sword + stop + rift
Accelerate: wanderer + sword + stop + accelerate
```

Main owns seed and accessibility-assist injection. Candidate failure keeps the panel open, displays a localized rejection, restores usable focus, and permits a single subsequent interaction to start the unchanged M1 Quick Start even if the failed Host was left terminal. Only a successful start closes the Candidate Lab and Start Menu.

## Four-ability action-clock evidence

All four abilities commit through the Player's single action clock. Stop and Rift retain source-aware cleanup; Rewind preserves resource cost and world consequences; Accelerate uses one Manager-owned duration/token. Pause, selection, terminal transitions, explicit cancellation, natural expiry, repeated cancellation, fixture disposal, and new-run reset cannot publish duplicate lifecycle facts.

The matrix exposed one real defect: a naturally expired Rift could leave a freed reference in `TimeManager._active_rifts`, making later cancel/reset assign an invalid instance. The certified implementation filters invalid values before typed Node access and cancels only valid, non-queued Rifts.

## HUD and Candidate Lab evidence

The Player snapshot and `RunViewState` schema 2 expose exactly two ordered `time_slots`. The contract rejects the legacy cooldown dictionary, unknown or mismatched IDs, duplicates, negative/non-finite cooldowns, and any slot count other than two. The HUD renders localized ability names with Ready/Cooldown state and redraws cached state on locale change without exposing internal input IDs.

Controller focus is closed and recoverable:

```text
Start:     Quick Start -> Candidate Lab -> Language -> Quick Start
Candidate: Bow -> Rift -> Accelerate -> Back -> Bow
```

The panel and its entry fit the 640×360 safe area. `interact` cannot pass through the modal and launch hidden M1 combat.

## Six-pair and exactly-once matrix

The deterministic smoke covers all six unordered pairs:

```text
Stop + Rewind
Stop + Rift
Stop + Accelerate
Rewind + Rift
Rewind + Accelerate
Rift + Accelerate
```

For every pair, both equipped actions commit once and both unequipped actions reject while preserving energy, cooldown, action state, facts, Rift nodes, and acceleration state. Each committed ability produces exactly one `time_skill_started` and one `time_skill_ended`. Repeated cancel, delayed expiry, and Player disposal add no later facts. Cleanup leaves no active Stop, Accelerate Manager state, Player acceleration, Rift reference, or Rift node.

## Verification evidence

Focused verification passed on Godot `4.6.1.stable.official.14d19694e`:

- loadout catalog, RunLoadoutPolicy, Player loadout, TimeManager runtime, and all six time pairs;
- Candidate Lab, controller focus, accessibility settings, M1 runtime isolation, HUD schema/rendering, and 640×360 pixel-canvas contracts;
- four-ability combat fact publication and run lifecycle ordering;
- localization validation and `7 / 7` localization unit tests;
- CI discovery contract with `65` stable scene tests;
- documentation governance with `30 / 30` tests and zero violations, baselined entries, new entries, or stale entries.

The final unified repository gate reports `65 / 65` Godot scenes passed, `0` failed, and only the registered `reward_system_smoke` ObjectDB warning. `git diff --check` passes. GDScript line coverage remains honestly reported as `not collected (godot_line_coverage_unsupported)`.

The retained validation logs are:

```text
/tmp/planewalker-p10a-task7-validation
/tmp/planewalker-p10a-final
```

## Honest remaining boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending`; authentic external sessions and matching observations remain `0 / 20`.
- Post-M1 promotion remains `Not started / Evidence-gated`; no synthetic or 30-seed result is presented as human feel evidence.
- Bow, Rift, and Accelerate remain `NEXT` candidates, not Current promotion.
- Product-level weapon/character depth, full archetype interactions, animation, audio, Boss-specific content, and balance work continue in later delivery stages.
- GDScript line coverage is not collected.
- Windows, Linux/Steam Deck, and macOS export templates, packaged startup, signing, platform credentials, remote push, and public publication remain pending where applicable.
- P7/P9 remains `External Validation Pending / Current`.

## Gate decision

P10A candidate-loadout implementation is `Verified Locally`. The P10 plan becomes Historical regression evidence. This gate does not change Quick Start, Formal M1, the evidence-based promotion decision, external release readiness, or the full-product completion state.
