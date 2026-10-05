# Native Validation Input Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Native cold, effect and semantic snapshot validation
- Owner: Project integration lead
- Depends On: `docs/current/2026-10-06-native-unified-hotpath-diagnostic-evidence.md`
- Last Verified: 2026-10-06

## Root Cause

Current cold validation calls the public deep-copy normalizer. That normalizer
deep-copies the complete aggregate and normalizes its effect subtree. Effect
validation repeats the effect copy and semantic normalization, while semantic
validation repeats its own copy. None of these validators modifies its input.
The retained diagnostic attributes 3.211 inclusive ms per frame to the cold
verifier. This attribution does not isolate normalization cost.

## Narrow Change

Add internal validation-input projections to these three existing boundaries.
A current canonical schema returns the original input for synchronous read-only
validation. Mixed current/legacy subtrees use a shallow envelope only where a
migrated child must be installed. Older root schemas keep the existing complete
normalizer. Public normalization continues returning detached complete copies.
All content, scalar, history, native, geometry and receipt validation remains
executable. Restores continue owning independent deep copies.

## Executable Acceptance

Before implementation retain a failing scene contract for the absent internal
projection. Use fully valid authored encounter/effect snapshots containing
180-frame semantic histories. GREEN must retain exact current input references
across all three boundaries, preserve every typed input byte through repeated
complete validation, and keep public normalization detached. Historical and
mixed-schema inputs must normalize to exactly the previous complete bytes
without mutating their source. Wrong fields, types, history values and identity
must still fail after successful validation. Existing native effect, semantic,
physical checkpoint and automatic replay regressions remain required.

Whole-frame performance, rendered load, sustained recording, coverage and human
playtesting are separate gates. This change introduces no validation cache.
