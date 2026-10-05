# P22C Physical Run Replay Stream Evidence

- Status: Focused Verified / Partial milestone
- Document Role: Current physical streamed replay evidence
- Authority Level: Below the P22C streamed run replay specification
- Applies To: Scoped manifests, immutable compressed chunks and physical recovery
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22c-streamed-run-replay-design.md`
- Last Verified: 2026-10-05

The stream archive binds game version, exact activated content, Profile and save
domain in its physical storage identity. A SaveService compare-exchange retains
the JSON manifest only after authenticated immutable Zstandard bytes exist.
Player identity uses object-disabled Variant bytes, preserving original types.
Chunk metadata revalidates contiguous ranges, SHA-256, declared lengths and
aggregate budgets before state publication. Exact observations remain in the
codec, outside the JSON manifest.

Clean missing-store RED: `planewalker-tests.iHMNjd`. Expanded physical GREEN:
`planewalker-tests.qkwZMg`, one scene with clean runtime/leak diagnostics. It
records 245 actual Player observations in three chunks, cold reloads and seeks
0/119/120/239/244, refuses stale append/finalization/removal resurrection,
preserves committed state before a failed promotion, reconciles a verified
post-promotion error and reuses authenticated orphan bytes on retry. Corrupt
or missing bytes refuse reads; missing bytes cannot finalize as COMPLETE.
Profile/game/domain isolation and independent returned projections also pass.

The archive retains at most 20 runs, 164048 observations per run, 2048 chunks
per run, 64 MiB compressed per run and 256 MiB of referenced archive bytes.
A separate physical 256 MiB admission check counts every scoped chunk file,
including removed, orphaned and temporary files. The test fills the physical
quota with a sparse temporary file and verifies failed admission preserves the
manifest. Deleted entries retain bytes because SaveService backups can still
reference them. Garbage collection is a separate maintenance task; deletion
does not currently promise immediate disk reclamation. Admission is synchronous
within one process; a concurrent multi-process reservation is not certified.

This milestone certifies storage. Automatic production recording, private
complete-world playback and synthetic 45-minute performance budgets remain
separate P22C gates. No complete 45-minute gameplay or coverage claim is made.
