# Plane Walker P0 Foundation Baseline Implementation Plan

- Status: Completed / Historical
- Document Role: Current implementation plan
- Implementation Status: Verified by `9faa1e2`, `bac5e74`, `d92b1ed`, and evidence record `docs/current/2026-09-28-foundation-baseline-evidence.md`
- Approved On: 2026-09-28
- Completion Gate: A clean detached checkout imports and passes the complete discovered test suite using only tracked sources
- Next Automatic Phase: Wave 4A playtest recording and Wave 4B encounter mechanics; P2–P9 continue as supporting foundation lanes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve and validate the current localization/Godot 4.6 work, establish an executable localization contract, checkpoint all intended changes precisely, and prove that the baseline reproduces from a clean checkout.

**Architecture:** `data/localization/translations.csv` is the only tracked localization source; Godot-generated `.translation` binaries remain reproducible build artifacts. A headless contract test validates catalog structure, language completeness, placeholder compatibility, literal `tr()` references, and manifest-backed content keys. P0 does not refactor runtime ownership; it creates a clean, evidence-backed starting point for P1–P9 and the continuous Wave 4A–Expansion program.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, Godot CSV translation importer, native headless scene tests, Git detached worktrees.

> **Execution record:** The approved implementation used `tools/validate_localization.py` plus `tests/contract/localization/test_validate_localization.py` instead of duplicating the catalog parser in GDScript. The Python contract covers static and derived runtime keys, JSON content references, placeholder compatibility, duplicate keys, and language completeness; it runs through the same `tools/validate_project.sh` entrypoint as Godot import and scene tests. The task steps below remain the original planning record; the evidence document is authoritative for the completed implementation.

## Global Constraints

- This is the first gate of the same continuous delivery program that completes P1–P9, Wave 4A–4D, formal M1 release, post-M1 promotion, Next, Launch, and Expansion; execution does not stop at M1.
- The full-product scope and Product Complete Gate are defined by `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`.
- Preserve the intent of every existing modified file; do not reset, discard, or blindly rewrite the current worktree.
- Track `data/localization/translations.csv`; ignore generated `*.translation` files and `.import` metadata under the existing import policy.
- Use Godot 4.6.1 for import and test evidence.
- Stage exact paths only. Never use `git add .`.
- Exit code zero is insufficient; scan every log for script errors, assertion failures, ObjectDB leaks, and resources still in use.
- The known legacy `tests/reward_system_smoke.tscn` ObjectDB warning may be recorded, but no new test may introduce a leak warning.
- Do not push, publish, purchase, or use unavailable credentials.
- Human-playtest evidence is outside P0. Wave 4D must create the repository toolchain and report template and must never represent synthetic sessions as authentic players.

---

## File Map

### Create

- `tests/contract/localization/localization_contract_test.gd`
- `tests/contract/localization/localization_contract_test.tscn`
- `docs/current/2026-09-28-foundation-baseline-evidence.md`

### Modify and checkpoint after inspection

- `.gitignore`
- `data/localization/translations.csv`
- `project.godot`
- `data/blessings/mvp_blessings.json`
- `data/curses/mvp_curses.json`
- `data/items/mvp_items.json`
- `data/talents/mvp_talents.json`
- `scripts/curses/curse_pool.gd`
- `scripts/dungeon/debug_room.gd`
- `scripts/dungeon/room_controller.gd`
- `scripts/main.gd`
- `scripts/rewards/blessing_pool.gd`
- `scripts/rewards/reward_pool.gd`
- `scripts/rewards/talent_pool.gd`
- `scripts/ui/combat_hud.gd`
- `scripts/ui/curse_selection.gd`
- `scripts/ui/event_selection.gd`
- `scripts/ui/pause_menu.gd`
- `scripts/ui/reward_selection.gd`
- `scripts/ui/run_end_overlay.gd`
- `tests/reward_system_smoke.gd`

P0 may include another path only when inspection proves it is already part of the same uncommitted localization baseline. The evidence document must name that path and the reason.

---

### Task 1: Make generated translation policy executable

**Files:**

- Modify: `.gitignore`
- Verify: `data/localization/translations.en.translation`
- Verify: `data/localization/translations.zh_CN.translation`
- Verify: `data/localization/translations.csv.import`

**Interfaces:**

- Consumes: Godot's CSV translation importer.
- Produces: a repository policy where the CSV is tracked and generated translation/import artifacts are ignored.

- [ ] **Step 1: Prove the generated binary policy is missing**

```bash
git check-ignore -q data/localization/translations.en.translation
```

Expected before the change: non-zero exit status.

- [ ] **Step 2: Add the generated translation rule**

Add beside the Godot import rules in `.gitignore`:

```gitignore
*.translation
```

Do not ignore `*.csv` or `data/localization/`.

- [ ] **Step 3: Verify source/artifact separation**

```bash
git check-ignore -v data/localization/translations.en.translation
git check-ignore -v data/localization/translations.zh_CN.translation
git check-ignore -v data/localization/translations.csv.import
git check-ignore -q data/localization/translations.csv
```

Expected: the first three identify ignore rules; the final command exits non-zero.

- [ ] **Step 4: Verify generated translations are not tracked**

```bash
git ls-files 'data/localization/*.translation' 'data/localization/*.import'
```

Expected: no output.

---

### Task 2: Add the localization contract test

**Files:**

- Create: `tests/contract/localization/localization_contract_test.gd`
- Create: `tests/contract/localization/localization_contract_test.tscn`
- Test: `data/localization/translations.csv`
- Test: `data/content_manifest.json`
- Test: manifest-backed JSON and `scripts/**/*.gd`

**Interfaces:**

- Consumes: CSV key/en/zh_CN rows, literal `tr("KEY")` calls, and manifest source definitions.
- Produces: one headless test that exits `0` only when keys are unique, both languages are non-empty, placeholders match, and discoverable references exist.

- [ ] **Step 1: Create the scene before its script exists**

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/contract/localization/localization_contract_test.gd" id="1"]

[node name="LocalizationContractTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Verify the red state**

```bash
godot --headless --path . --scene res://tests/contract/localization/localization_contract_test.tscn --log-file /tmp/plane_walker_p0_localization_red.log
```

Expected: non-zero exit or parse failure because the script is absent.

- [ ] **Step 3: Implement the test harness and catalog checks**

The test uses `tests/support/test_suite.gd`, defers `_run()`, and performs these exact assertions:

```gdscript
var header := file.get_csv_line()
suite.assert_equal(Array(header), ["keys", "en", "zh_CN"], "catalog header is exact")
suite.assert_true(not key.is_empty(), "catalog row has a key")
suite.assert_true(not catalog.has(key), "localization key is unique: %s" % key)
suite.assert_true(not english.strip_edges().is_empty(), "%s has English text" % key)
suite.assert_true(not chinese.strip_edges().is_empty(), "%s has Chinese text" % key)
suite.assert_equal(placeholder_signature(english), placeholder_signature(chinese), "%s placeholders match" % key)
```

Use a `RegEx` compiled from this expression after removing literal `%%`:

```text
%(?:[0-9]+\$)?[-+0 #]*(?:[0-9]+)?(?:\.[0-9]+)?[sdf]
```

This supports `%s`, `%d`, `%f`, `%.1f`, `%.0f`, width, flags, and positional formatting.

- [ ] **Step 4: Add literal `tr()` reference validation**

Recursively scan `res://scripts` for `.gd` files and match:

```text
\btr\("([A-Z0-9_]+)"\)
```

For every match, assert that capture group 1 exists in the catalog. Dynamic keys remain covered by their producer's unit/integration tests and explicit fixture assertions; the static scanner must not pretend to resolve runtime concatenation.

- [ ] **Step 5: Add manifest-backed content validation**

Parse `data/content_manifest.json`, open each declared source, require an array root, and inspect these fields when present:

```gdscript
const LOCALIZED_FIELDS := [
	"name", "description", "name_key", "description_key", "title_key", "message_key"
]
```

Each present field must be a non-empty string and must resolve in the catalog. Preserve stable content IDs and report the source path, content ID, field, and missing key in the assertion label.

- [ ] **Step 6: Run the contract and repair facts, not assertions**

```bash
godot --headless --path . --scene res://tests/contract/localization/localization_contract_test.tscn --log-file /tmp/plane_walker_p0_localization_green.log
rg -n "SCRIPT ERROR|ERROR:|assert|ObjectDB instances leaked|resources still in use" /tmp/plane_walker_p0_localization_green.log
```

Expected: exit `0` and no contract error or leak. Missing or incompatible keys are repaired in `translations.csv` or at the invalid reference; assertions are not removed to force green.

---

### Task 3: Audit and preserve the existing dirty baseline

**Files:**

- Review: every modified path in the File Map.
- Modify: only invalid localization, JSON, Godot 4.6 parser, or regression behavior.

**Interfaces:**

- Consumes: the owner's uncommitted localization, data, legacy UI, main-flow, project, and smoke-test work.
- Produces: one coherent baseline with no unrelated churn or lost behavior.

- [ ] **Step 1: Capture the exact inventory**

```bash
git status --short
git diff --stat
git diff --check
```

- [ ] **Step 2: Inspect configuration and content**

```bash
git diff -- project.godot data/blessings/mvp_blessings.json data/curses/mvp_curses.json data/items/mvp_items.json data/talents/mvp_talents.json
```

Verify that `project.godot` registers localization without unrelated churn; content IDs remain stable; localized fields resolve; and archetype, role, effect, rarity, and availability fields remain intact.

- [ ] **Step 3: Inspect runtime pools and flow**

```bash
git diff -- scripts/curses/curse_pool.gd scripts/dungeon/debug_room.gd scripts/dungeon/room_controller.gd scripts/main.gd scripts/rewards/blessing_pool.gd scripts/rewards/reward_pool.gd scripts/rewards/talent_pool.gd
```

Verify stable keys, intentional fallback behavior, and no new duplicate content authority.

- [ ] **Step 4: Inspect UI and smoke behavior**

```bash
git diff -- scripts/ui/combat_hud.gd scripts/ui/curse_selection.gd scripts/ui/event_selection.gd scripts/ui/pause_menu.gd scripts/ui/reward_selection.gd scripts/ui/run_end_overlay.gd tests/reward_system_smoke.gd
```

Verify that visible strings use keys, format arguments match placeholders, locale switching updates live UI, and smoke assertions test behavior rather than exact English copy.

- [ ] **Step 5: Parse every modified JSON source**

```bash
python3 -m json.tool data/blessings/mvp_blessings.json >/dev/null
python3 -m json.tool data/curses/mvp_curses.json >/dev/null
python3 -m json.tool data/items/mvp_items.json >/dev/null
python3 -m json.tool data/talents/mvp_talents.json >/dev/null
```

Expected: all commands exit `0`.

- [ ] **Step 6: Confirm generated artifacts remain ignored**

```bash
git status --short --ignored data/localization
```

Expected: `translations.csv` is trackable; `.translation` and `.import` files are ignored.

---

### Task 4: Run the complete P0 verification gate

**Files:**

- Test: every `tests/**/*.tscn` scene discovered after Task 2.
- Log: `/tmp/plane_walker_p0_logs/`.

**Interfaces:**

- Consumes: the complete candidate baseline.
- Produces: editor-import evidence, one log per test scene, an explicit scene count, and a classified log scan.

- [ ] **Step 1: Import with Godot 4.6.1**

```bash
mkdir -p /tmp/plane_walker_p0_logs
godot --headless --editor --path . --quit --log-file /tmp/plane_walker_p0_logs/editor_import.log
```

Expected: exit `0` with no parser or script error.

- [ ] **Step 2: Record discovered scenes**

```bash
rg --files tests -g '*.tscn' | sort | tee /tmp/plane_walker_p0_logs/test_scenes.txt
wc -l /tmp/plane_walker_p0_logs/test_scenes.txt
```

Expected: the previous 26 scenes plus the localization contract unless another authorized lane has added a valid test. The discovered count is evidence and is never reduced to hide a failing scene.

- [ ] **Step 3: Run every discovered scene**

```bash
while IFS= read -r scene; do
	log_name=$(basename "$scene" .tscn)
	if ! godot --headless --path . --scene "res://$scene" --log-file "/tmp/plane_walker_p0_logs/${log_name}.log"; then
		echo "FAILED: $scene"
		exit 1
	fi
done < /tmp/plane_walker_p0_logs/test_scenes.txt
```

Expected: every scene exits `0`.

- [ ] **Step 4: Scan logs independently from exit codes**

```bash
rg -n "SCRIPT ERROR|Parse Error|Smoke test failed|Assertion failed|expected .* got|ObjectDB instances leaked|resources still in use|Invalid call" /tmp/plane_walker_p0_logs
```

Expected: no new error. If the legacy `reward_system_smoke` ObjectDB warning remains, record its exact filename and message.

- [ ] **Step 5: Repeat the content and localization contracts**

```bash
godot --headless --path . --scene res://tests/contract/content_schema/content_registry_test.tscn --log-file /tmp/plane_walker_p0_logs/content_contract_repeat.log
godot --headless --path . --scene res://tests/contract/localization/localization_contract_test.tscn --log-file /tmp/plane_walker_p0_logs/localization_contract_repeat.log
```

Expected: both exit `0`; repeated loading does not depend on editor state.

---

### Task 5: Create precise reversible checkpoints

**Files:**

- First checkpoint: `.gitignore`, localization CSV, localization contract script/scene.
- Second checkpoint: the reviewed runtime/data/UI/project/smoke paths.

**Interfaces:**

- Consumes: the green P0 candidate.
- Produces: focused local commits separating source policy/contracts from runtime localization integration.

- [ ] **Step 1: Review candidate diffs**

```bash
git diff --check
git diff --stat
git status --short
```

Expected: no unknown path or generated artifact.

- [ ] **Step 2: Commit source policy and contract**

```bash
git add .gitignore data/localization/translations.csv tests/contract/localization/localization_contract_test.gd tests/contract/localization/localization_contract_test.tscn
git diff --cached --check
git diff --cached --stat
git commit -m "test: enforce localization source contract"
```

Expected: only these exact paths are committed.

- [ ] **Step 3: Stage the reviewed runtime baseline**

```bash
git add project.godot data/blessings/mvp_blessings.json data/curses/mvp_curses.json data/items/mvp_items.json data/talents/mvp_talents.json scripts/curses/curse_pool.gd scripts/dungeon/debug_room.gd scripts/dungeon/room_controller.gd scripts/main.gd scripts/rewards/blessing_pool.gd scripts/rewards/reward_pool.gd scripts/rewards/talent_pool.gd scripts/ui/combat_hud.gd scripts/ui/curse_selection.gd scripts/ui/event_selection.gd scripts/ui/pause_menu.gd scripts/ui/reward_selection.gd scripts/ui/run_end_overlay.gd tests/reward_system_smoke.gd
git diff --cached --check
git diff --cached --stat
```

If a concurrent lane changed one of these paths after Task 3, unstage that path, inspect the merged diff, and rerun affected tests. Preserve both intended changes.

- [ ] **Step 4: Commit the runtime baseline**

```bash
git commit -m "feat: checkpoint localized Godot runtime"
```

- [ ] **Step 5: Confirm P0-owned paths are clean**

```bash
git status --short
git log -2 --oneline
```

Expected: no P0-owned path remains only in the worktree. Concurrent unrelated lane changes may remain and are named in evidence rather than staged into P0.

---

### Task 6: Prove clean detached-checkout reproducibility

**Files:**

- Create: `docs/current/2026-09-28-foundation-baseline-evidence.md`
- Verify: `/private/tmp/plane-walker-p0-verify`.

**Interfaces:**

- Consumes: the P0 commits.
- Produces: evidence that import and tests are independent from untracked editor state and generated translation binaries.

- [ ] **Step 1: Create a detached verification worktree**

```bash
git worktree add --detach /private/tmp/plane-walker-p0-verify HEAD
```

Expected: a clean detached checkout.

- [ ] **Step 2: Verify source-only localization state**

Run from `/private/tmp/plane-walker-p0-verify`:

```bash
git status --short
test -f data/localization/translations.csv
test ! -f data/localization/translations.en.translation
test ! -f data/localization/translations.zh_CN.translation
```

Expected: clean status; CSV exists; generated binaries do not exist before import.

- [ ] **Step 3: Import and regenerate artifacts**

```bash
mkdir -p /tmp/plane_walker_p0_clean_logs
godot --headless --editor --path . --quit --log-file /tmp/plane_walker_p0_clean_logs/editor_import.log
```

Expected: exit `0`; import artifacts regenerate without tracked changes.

- [ ] **Step 4: Run every clean-checkout test**

```bash
rg --files tests -g '*.tscn' | sort > /tmp/plane_walker_p0_clean_logs/test_scenes.txt
while IFS= read -r scene; do
	log_name=$(basename "$scene" .tscn)
	if ! godot --headless --path . --scene "res://$scene" --log-file "/tmp/plane_walker_p0_clean_logs/${log_name}.log"; then
		echo "FAILED: $scene"
		exit 1
	fi
done < /tmp/plane_walker_p0_clean_logs/test_scenes.txt
```

Expected: every discovered scene exits `0`.

- [ ] **Step 5: Scan clean logs and Git status**

```bash
rg -n "SCRIPT ERROR|Parse Error|Smoke test failed|Assertion failed|expected .* got|ObjectDB instances leaked|resources still in use|Invalid call" /tmp/plane_walker_p0_clean_logs
git status --short
```

Expected: only the classified legacy warning may appear; Git status remains clean because generated artifacts are ignored.

- [ ] **Step 6: Write actual evidence**

Create `docs/current/2026-09-28-foundation-baseline-evidence.md` with these headings and replace every evidence value with direct command output before committing:

```markdown
# P0 Foundation Baseline Evidence

- Status: Verified
- Verification Date: 2026-09-28
- Godot Version: 4.6.1
- Baseline Commits: localization-contract commit and runtime-baseline commit
- Discovered Test Scenes: integer reported by the clean test scene list
- Test Result: all discovered scenes exited 0
- Clean Checkout: detached worktree reproduced import and tests
- Known Warning: exact reward smoke warning, or None

## Commands and Results

Record the exact import, test-loop, log-scan, JSON-parse, and Git-status commands with their result summaries.

## Log Classification

Classify each matched line as failure, accepted pre-existing warning, or false-positive text. Only the documented legacy reward smoke leak can be accepted.

## Worktree Integrity

Record that the CSV is tracked, generated translations are ignored, and the detached checkout remained free of tracked modifications.
```

The evidence record must contain hashes, integers, and exact warning text rather than example or synthetic values.

- [ ] **Step 7: Remove the temporary worktree**

Run from the main worktree:

```bash
git worktree remove /private/tmp/plane-walker-p0-verify
```

- [ ] **Step 8: Commit certification evidence**

```bash
git add docs/current/2026-09-28-foundation-baseline-evidence.md
git diff --cached --check
git commit -m "docs: certify P0 foundation baseline"
```

---

## P0 Completion Gate

P0 is complete only when:

- `translations.csv` is the tracked authority and generated translation/import artifacts are ignored;
- localization keys are unique and both language cells are non-empty;
- English/Chinese placeholders are compatible;
- every literal `tr()` reference and manifest-backed localization key resolves;
- every current dirty baseline path has been inspected and preserved intentionally;
- all modified JSON parses;
- Godot 4.6.1 editor import passes;
- every discovered test scene exits `0`;
- log scanning finds no new error or leak;
- precise local commits exist without `git add .`;
- a detached clean checkout reproduces import and tests with clean Git status;
- evidence contains actual results and does not fabricate human, platform, or release evidence.

## Automatic Continuation

After the P0 evidence commit, continue directly to P1 Test and CI Foundation. The continuous authorized sequence is:

`P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → P9 → Wave 4A → Wave 4B → Wave 4C → Wave 4D → M1 decision → Bow/third-time promotion → Next → Launch → Expansion → Product Complete Gate`.

No new scope authorization or M1 stopping point is required. External human playtests, platform credentials, signing, publishing, and commercial activation are recorded honestly and never fabricated; their absence does not prevent completion of all remaining in-repository implementation and verification work.
