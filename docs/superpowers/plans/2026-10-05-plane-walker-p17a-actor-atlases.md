# P17A Actor Atlases Implementation Plan

> For agentic workers: execute each focused task with an independent validation gate and precise local commit.

- Status: Approved
- Document Role: Focused production raster implementation plan
- Authority Level: Execution plan below P17A design
- Applies To: Original actor atlas production and verification
- Owner: Project pixel presentation lane
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p17a-actor-atlases-design.md`
- Last Verified: 2026-10-05
- Exit Gate: RED then GREEN asset contracts, actual PNG inspection and native Godot rendering

**Goal:** Produce ten original pixel animation atlases that can be consumed independently of gameplay.

**Architecture:** One deterministic Pillow generator owns raster source and manifest generation. A read-only validator checks actual files, frame geometry, hashes and provenance. Runtime presentation consumes only checked-in assets.

**Tech Stack:** Python, pinned Pillow 12.3.0, Godot 4.6.1 and PNG.

## Global Constraints

- Character cells are 48x48; boss cells are 80x80.
- Four columns, six rows: idle, move, attack, cast, hurt, death.
- Original project artwork, transparent padding and nearest-neighbor sampling.
- Do not mutate base pack, compatibility ledger, Meta catalog or Player Visual.

## Task 1: Deterministic Asset Library

- [x] Write failing contract tests for expected identities, visible animated frames, transparent padding, uniqueness, provenance, reproducibility and tamper refusal.
- [x] Run the test and retain its missing-tool RED.
- [x] Create `tools/production_art/generate_actor_atlases.py`, `requirements-production-art.txt` and checked-in `assets/production/actors/`.
- [x] Generate the ten atlases plus an inspectable contact sheet and sorted asset manifest.
- [x] Run focused tests, read-only validation and image inspection.
- [x] Record verification evidence and create a precise local commit.

## Task 2: Native Presentation

- [ ] Read existing PixelProxy and actual actor boundaries and define a failing native rendering test.
- [ ] Attach atlas projection without changing gameplay state or typed Visual.
- [ ] Preserve original weapon feedback, afterimages and accessibility flags.
- [ ] Verify actual OpenGL frames and gameplay snapshot neutrality, then create a separate commit.
