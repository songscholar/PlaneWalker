# Final Clean Certification Evidence

- Status: Focused Verified / Full clean certification pending
- Document Role: Current bounded clean-checkout and macOS startup evidence
- Authority Level: Evidence only
- Applies To: Committed 83c379d ordinary baseline and 2cb0254 focused repair/export source
- Owner: Project owner
- Last Verified: 2026-10-06
- Certification date: 2026-10-06.
- Original certification checkout: `build/retained-checkout/final-certification-83c379d-20261006`, detached at `83c379d56f4f898c2277130c12412d6262e965ed`.
- Focused repair/export checkout: `build/retained-checkout/focused-recheck-20261006`, detached at `2cb0254abc5442affb3b7b16400808a7f174244a`.
- No frozen historical result is included in these totals.

## Clean Import

The original certification checkout ran two isolated Godot 4.6.1 imports with separate `PLANEWALKER_TEST_DATA_DIR`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME` values. The first import exited 0 and emitted only the expected missing generated translation diagnostics for 12 configured CSV stems; `validate_import_translations.py --phase bootstrap` classified all 96 diagnostic lines with zero remaining errors. The second import exited 0 with zero `ERROR:` lines; the clean classifier and `runtime_log_validation.py` passed both stdout and engine logs.

Raw import logs are retained under `build/retained-checkout/final-certification-83c379d-20261006/build/final-certification/logs/`.

## Ordinary Scenes

The original detached checkout discovered 543 scene tests. The bounded ordinary run covered all 334 non-integration, non-matrix scenes: 332 passed, 2 failed, and 0 timed out. The retained failures were:

| Scene | Result | Evidence |
| --- | --- | --- |
| `tests/contract/presentation/pixel_canvas_test.tscn` | Two 640x360 run-end panel fit assertions failed | `build/final-certification/ordinary/non-integration/contract/` |
| `tests/ui/hub_finish_layout_test.tscn` | Assertions passed but an `ObjectDB instances leaked at exit` warning failed strict log validation | `build/final-certification/ordinary/non-integration/ui/` |

The remaining ordinary scene logs and exact batch summaries are retained under the original checkout's `build/final-certification/ordinary/non-integration/`. A short integration batch was interrupted at the requested pause and is not included in the 334 count. The 750 native matrix and long smoke/integration groups were not started.

The fixes are `183e138` (compact run-end overlay) and `2cb0254` (Hub test playback retirement). A separate clean checkout at `2cb0254` imported twice and reran only the affected scenes. `pixel_canvas_test` and `hub_finish_layout_test` each passed 1/1; paired stdout/engine strict validation returned 0 with zero leak lines. This is 2/2 focused evidence at the new source, not a same-source 334/334 result. Initial attempts before importing the new clone retained missing-resource failures; their logs remain under `build/focused-recheck/{pixel_canvas,hub_finish_layout}/` and are not accepted as repair verification.

The accepted focused logs are under `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/focused-recheck/pixel_canvas-after-import/` and the adjacent `hub_finish_layout-after-import/` directory. Both retained checkouts are detached and `git status --short` remains empty.

## Export and Startup

Contract preflight passed. Local preflight initially reported missing templates when resolving the default Godot directory. This was a toolchain-location issue, not missing external assets. Re-running with `/Users/songzuoqiang/Documents/games/PlaneWalker/build/toolchain/godot-4.6.1/templates/4.6.1.stable` passed all Windows, Linux, and macOS target checks.

The macOS release was exported from the focused checkout with the explicit templates directory and an isolated HOME template link. `build_exports.py --target macos-universal` passed with artifact tree SHA-256 `913f8c5b41b392108d1e9088402181c0e3b116b23e1d51f8afa8ee3214e5a849` (217,891,540 bytes, eight files). The export command included `--allow-dirty-candidate`, but the report records `worktree_clean=true`, `dirty_paths=[]`, and `classification=local_export_candidate`; source cleanliness was not downgraded. The packaged macOS executable then passed all 12 native startup checks with exit code 0 and no strict export/startup log failures.

Accepted absolute artifact/report paths:

- `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/macos/PlaneWalker.app`
- `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/focused-recheck/macos-export-report.json`
- `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/focused-recheck/macos-startup-report.json`
- `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/focused-recheck/macos-export-logs/macos-universal/`
- `/Users/songzuoqiang/Documents/games/PlaneWalker/build/retained-checkout/focused-recheck-20261006/build/focused-recheck/macos-startup-logs/`

The root portable `--quit-after 300` fallback failed audio retirement. Its failure is independent of the passing formal startup adapter above; the portable fallback is not certified.

The packaged startup report is host macOS evidence only; it does not certify Windows/Linux host startup, sustained 60 FPS, the full game, signing, notarization, publication, or human playtesting.

Remaining gates include a complete same-source 543-scene rerun, current-source instrumented line coverage, all 750 native matrix cases, full-game completion and rendered interaction QA. These focused results do not replace those gates.

## Mac Compatibility Boundary

Existing same-Mac renderer evidence shows both Metal (`forward_plus`/`metal`) and OpenGL compatibility (`gl_compatibility`/`opengl3`) complete a bounded 120-frame workload. The measured roughly 33-34 ms Player CPU advance and synchronous recording subscribers are CPU/diagnostic overhead, not evidence of a renderer incompatibility. Both complete-frame means remain above 16.667 ms, so sustained performance certification remains open.
