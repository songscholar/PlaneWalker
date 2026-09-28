# Plane Walker M1 放行报告

- Status: M1 Candidate — External Validation Pending
- Evidence Schema: M1 seed matrix `1.0.0` / playtest session `1.0.0` / observation `1.0.0`
- Build Version: `0.4.0-dev`
- Commit: `52953720365a16fc8a6f0208d12ffad0fce27b0e`
- Content Version: `m1.encounters.v1`
- Evidence Classification: Current integrated-worktree candidate; clean final cohort regeneration required

## 正式结论

**M1 Candidate — External Validation Pending**

30 Seed 当前集成工作树门禁：**PASS**；真实外部试玩：**0 / 20**；匹配结构化观察：**0 / 20**。

Synthetic 数据只用于验证工具、稳定性和确定性，永久不计入真实玩家门禁。当前证据不足时，不得据此声称手感、公平性或重玩意愿已验证。

本报告生成时，Wave 4D 工具链已经提交为 `5295372`，但并行完成的 Wave 4B/4C 运行时代码尚未全部进入同一个干净 commit。下述两轮结果真实来自当前集成工作树，并非伪造或静态 JSON；它们是候选诊断证据。最终给外部测试者的构建完成并形成干净 commit 后，必须重新运行相同命令，以新的 exact cohort commit 和 digest 替换本节，旧结果不得与新 cohort 混用。

## 30 Seed 稳定性

- Matrix digest: `44cd5152b48085105e90c383792e15cd5d69e592202aa81bddfb1705017541c8`
- Seed records: 30
- Failed seeds: 0
- Gate: PASS

执行命令：

```bash
python3 tools/m1/run_seed_matrix.py \
  --seed-start 0 --seed-count 30 \
  --output /tmp/planewalker-m1-seeds-5295372.json
python3 tools/m1/run_seed_matrix.py \
  --seed-start 0 --seed-count 30 \
  --output /tmp/planewalker-m1-seeds-5295372-repeat.json
python3 tools/m1/compare_seed_reports.py \
  /tmp/planewalker-m1-seeds-5295372.json \
  /tmp/planewalker-m1-seeds-5295372-repeat.json --json
```

第二轮同样得到 `44cd5152b48085105e90c383792e15cd5d69e592202aa81bddfb1705017541c8`，`changed_seeds=[]`。0–29 全部通过真实 `main.tscn`、Legacy Adapter、Run Runtime Facade、权威五房 plan、Encounter Catalog 与 Encounter Runner，记录房间、遭遇、spawn、offer、选择、终局和 duration proxy；30 局均为 `victory`，无 failure code。Godot stdout 与 engine log 未出现脚本错误、资源解析错误、ObjectDB leak 或 RID leak。

首次矩阵运行暴露了 Wave 4C 合成音频快速退出时的真实生命周期缺陷：最终活跃 `AudioStreamPlaybackWAV` 持有 `AudioStreamWAV`。生产修复为 voice 结束/全停时清空 stream、Run 瞬态反馈重置、autoload/audio `_exit_tree` 兜底，并移除会残留的 hit-pause SceneTreeTimer。探针随后通过生产 `reset_transient_feedback()` 清理每局，不通过过滤日志或关闭音频掩盖问题；修复后的两轮日志均清洁。

## 外部试玩与玩法阈值

| 指标 | 实测 | 门槛 | 结果 |
|---|---:|---:|---|
| `successful_run_duration_8_12_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `time_stop_usage_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `time_rewind_usage_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `build_comprehension_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `boss_time_interactions_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `unexplained_harm_rate` | 0.0% | < 10.0% | PENDING/FAIL |
| `responsiveness_4plus_rate` | 0.0% | >= 80.0% | PENDING/FAIL |
| `replay_intent_rate` | 0.0% | >= 60.0% | PENDING/FAIL |

## 调参输入契约

- Schema: `1.0.0`
- Evidence class: `repository_stability_only`
- Human tuning authorized: `false`

结构化失败签名：

- 当前没有足够的结构化失败签名。

当前禁止的结论：

- 手感或响应性已经达到正式放行标准
- 受伤、公平性与死亡原因已被真实玩家验证
- 构筑理解、Boss 时间交互与重玩意愿已被验证
- 基于 synthetic 数据进行体验型数值调优

## 未满足项与风险

- requires 20 valid authentic human sessions; found 0
- requires 20 matching structured observations; found 0

因此当前没有依据执行体验型数值调优，也不能从 Bow、Time Rift 或 Time Accelerate 中提升新的 Current。只有真实 cohort 导入并达到全部阈值后，才能生成 `M1 Go` 和数据驱动的 post-M1 ADR。

## 验证记录

```text
PASS  python3 -m unittest tests.contract.m1.test_m1_gate          (11 tests)
PASS  python3 -m unittest tests.contract.playtest.test_playtest_data (13 tests)
PASS  python3 -m py_compile tools/m1/*.py
PASS  30 Seed first run:  30 victory / 0 failure
PASS  30 Seed repeat run: 30 victory / 0 failure
PASS  deterministic compare: changed_seeds=[]
PASS  Godot log scan: no script/resource errors and no ObjectDB/RID leak
```

报告生成命令：

```bash
python3 tools/m1/generate_release_report.py \
  --seed-report /tmp/planewalker-m1-seeds-5295372.json \
  --output docs/current/2026-09-28-m1-release-report.md \
  --json-output /tmp/planewalker-m1-decision-5295372.json \
  --tuning-output /tmp/planewalker-m1-tuning-5295372.json
```

## 保留/回滚说明

- 报告由机器可读 Seed Matrix、已校验会话 JSONL 和已校验观察 JSONL 生成。
- 自由文本、未校验表格和 synthetic fixture 不进入放行计算。
- 数值改动必须引用本报告调参输入中的指标或失败签名，并记录旧值、新值、预期影响和回归测试。
- 在真实 20 局同 cohort 证据完整前，状态保持 `M1 Candidate — External Validation Pending`；这不妨碍继续完成已授权的仓库内工作。
- Wave 4D 工具链回滚点：`5295372` 的父提交；只回滚该精确 commit，不回滚 Wave 4B/4C 的独立提交。
- Wave 4C 音频生命周期修复是 30 Seed 清洁退出的依赖，由 Wave 4C lane 独立提交；最终集成报告必须记录其确切 commit。
- 最终干净 cohort 生成后，本报告中的候选 commit 与 matrix digest 需要整体替换，不得把候选 digest 当成外部试玩构建指纹。
