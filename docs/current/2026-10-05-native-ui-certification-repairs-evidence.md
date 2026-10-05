# Native UI Certification Repairs

- Status: Focused Verified / Combined certification pending
- Document Role: Current native UI and reward overlay verification evidence
- Authority Level: Below the full product completion specification
- Applies To: Compatibility-menu controller flows, owned Launch loadouts, native dungeon panels and reward reconstruction
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

## Retained Behavior

- Each compatibility-menu UI scenario creates an isolated actual Profile. Main still opens the native Hub by default; the test explicitly opens the compatibility menu for that menu's navigation coverage.
- Complete Launch loadout coverage writes an actual unlocked Profile with SaveService, reloads the Profile runtime before Main creation, and drives real keyboard, mouse and controller input. All five authored weapons and the selected Time Guardian loadout reach the native runtime and Player.
- The partial-start failure fixture subclasses the actual Facade and replaces only the failing room boundary. Terminal focus uses actual native death reporting, the production result control and the real return to Hub.
- Standalone choice-focus coverage closes the previously active native route scope and freezes its automatic coordinator clock. Native dungeon focus and reward-selection precedence are covered separately by the five-floor panel test.
- The five-floor panel test preserves actors' physics spaces and advances accepted deterministic Player frames in both combat and Boss phases. Fixture damage retires actual hostile Health; actual route controls, rewards, shop, rest, events, floor handoffs and terminal cleanup run through production boundaries.
- Reward reconstruction directly copies an unchanged live field instead of recomputing `target + live - expected`. This retains exact floating values and avoids `LEDGER_PLAYER_MISMATCH` after accepted frames regenerate fractional energy. Changed reward fields still receive their authored numeric delta.

## Evidence

- Public reward authority clean RED: `planewalker-tests.uqtoGC`. Baseline energy `0.1` and live energy `0.2` caused reconfiguration to reject its live snapshot before the fix.
- Reward authority full scene GREEN: `planewalker-tests.Zl3urT`. Reconfiguration, removal ticket, accepted unrelated reward removal and rollback retain exact fractional energy; existing acquisition-order and atomicity cases remain passing.
- Owned Launch input flow GREEN: `planewalker-tests.iP2Xrg`.
- Controller focus and actual terminal Hub return GREEN: `planewalker-tests.KimVLj`.
- Five-floor native panel fixture GREEN: `planewalker-tests.GEF0Yo`. All authored floors, six room types, native panels, temporary modifier grants/expiry, physical Save and fresh Facade restore, legacy lifetime reconstruction, and terminal retirement pass.
- Accepted engine and stdout logs were scanned for script errors, invalid calls, physics-query mutation and ObjectDB/RID leaks; no such errors remain. These logs are retained under `build/test-logs/native-ui-certification-repairs/`.
- `git diff --check` passes. No dependency was added or changed. The pinned direct `requirements-dev.txt` audit was attempted with the repository's no-install pip-audit command but could not resolve `pypi.org` in the sandbox; a new online advisory result is unverified.

## Limits

- The five-floor result is an automated fixture: native hostile Health receives deterministic fixture damage. It is not evidence of a player's full-gameplay completion, combat balance, or real-world feedback.
- Focused verification does not certify the subsequent combined clean checkout, release export or newly extended project-wide controller defaults. Those are separate integration gates.
- Stock Godot reports `godot_line_coverage_unsupported`; no GDScript coverage percentage is asserted.
