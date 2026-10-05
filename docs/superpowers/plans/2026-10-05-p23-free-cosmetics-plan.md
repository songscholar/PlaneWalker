# P23 Free Cosmetic Implementation Plan

- Status: Active
- Document Role: Current implementation plan
- Authority Level: Milestone implementation under standing project authorization
- Applies To: Free character appearances and native Hub gallery
- Owner: Plane Walker project owner
- Depends On: `../../../AGENTS.md`, `../specs/2026-10-05-p23-free-cosmetics-design.md`
- Last Verified: 2026-10-05

1. Define failing catalog and physical Save transaction tests for the fifteen appearances, authoritative unlock routes and equipment ownership.
2. Implement strict authored definition/catalog and versioned collection commands with exact Profile revision checks.
3. Generate original raster colorways and declare their source, license, hashes and localization in the Base content pack.
4. Validate collection payloads at physical Save boundaries and persist commands through the existing atomic Profile transaction.
5. Add native Hub cosmetic projection and gallery preview/control component while preserving discovered items.
6. Integrate actual launch/resume appearance with the native presentation projection, then verify locales, input, pixels, cold recovery and failed writes.
7. Run scoped regression/content/documentation checks, retain evidence and create a precise local commit.

## Exit Gate

The milestone is retained only after the authored catalog, actual atomic Save fault/cold-reload suite, native Hub preview/control flow and launch/resume appearance integration pass. Evidence must identify exact logs, raster provenance, old-save fallback, combat-state independence and remaining external limits.
