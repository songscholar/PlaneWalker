# P20B Offline Local Records Evidence

- Status: Verified / Current
- Document Role: Current milestone retention evidence
- Authority Level: Focused executable acceptance record
- Applies To: Settled Profile, pending local records, physical boards, Main and Hub
- Owner: Runtime integration lane
- Depends On: `../superpowers/specs/2026-10-05-plane-walker-p20b-local-records-design.md`
- Last Verified: 2026-10-05

The native Hub mirror now shows an independent physical local leaderboard from real durable Run settlements. Optional board faults do not prevent settlement, Hub return or the next native launch. Pending sources survive that launch and a fresh Main/Profile reload, and retry consumes them only after confirming the board physically.

## Implementation

- Profile settlement writes an authenticated pending source with its original content snapshot in the same transaction as core settlement. Launch and abandon preserve it.
- Pending retention and board retention both use the shared score, positive time and stable record identity ordering. Each retains at most 1000 records; pending overflow increments `omitted_count` without rejecting core settlement. An overflow fixture physically loads 1000 independently authenticated sources before settling Run 1001.
- Boards are separated by canonical actual-content snapshot and save domain, including historical pending content. Mod records say Local / Unranked. Each board has at most 1000 Profile watermarks, with full Run ID and receipt digest to preserve deduplication after entry eviction.
- Acknowledgement verifies the complete board protocol and its canonical physical ID. The watermark must match a queued authenticated source and cannot exceed the Profile's launch sequence. Future watermarks, foreign IDs and failed promotion retain pending sources.
- SaveService compares primary preimages before preparing and immediately before promotion. Interleaved in-process writers are detected. This is not a cross-process file lock.
- The actual refresh command reloads the physical board during an active Run. Native focus waits for focus scrolling before revealing the first record, while guarding retired panel generations.
- Supplemental configured `community.csv` supplies English and Simplified Chinese labels without changing content-pack fingerprints.

## Verification

All paths below are under `build/test-logs/p20b-local-records/`.

| Evidence | Result |
| --- | --- |
| `auth-red` | Meaningful initial RED: missing durable authentication and record writer |
| `storage-certified-release` | Physical restart, full identity, ranking, top-1000 board and pending limits, faults, reentry, interleaved CAS, actual-content/Mod isolation, source digest, future/foreign acknowledgement, failed acknowledgement retry, legacy abandon fallback |
| `main-outbox-final` | Actual native death, optional board fault, second launch, fresh Main physical reload, recovery, Hub refresh, linked focus and bilingual labels |
| `visibility-final` | All 8 combinations of 640x360 / 1280x720, English / Simplified Chinese, text scale 1.0 / 1.5; first real record enclosed by native scroll region |
| `native-render-final/godot.log` | Native OpenGL raster, 8 nonblank screenshots with displayed authentic record |
| `profile-final` | Profile currency, launch, settlement and abandon regression |
| `rebind-final` | Save content rebinding regression |

`python3 tools/validate_localization.py` and `git diff --check` pass. `python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt` reports no known vulnerabilities. Final logs are scanned for script/parse/resource errors and ObjectDB/RID leaks. Native screenshots are retained in `build/p20b-records-screenshots/`; `zh_CN-1.5-640x360.png` and `en-1.0-1280x720.png` were visually inspected and show the actual Wanderer/Sword record and score.

## Limits And Recovery

This milestone supplies local records for the canonical launch Run. Daily, Boss Rush and endless identities remain separate follow-up work and receive no invented records. Local boards and pending queues are bounded histories, not a permanent archive. Online and cross-device rankings remain unavailable. Existing macOS certificate lookup diagnostics in sandboxed headless tests are environment noise; they are not script errors.

The focused local commit is the rollback point. This change adds no project dependencies and does not publish, push or use external accounts. Later combined clean-checkout certification is owned by the integration lane.
