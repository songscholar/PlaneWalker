# Plane Walker M1 真人试玩、证据导入与调参协议

- Status: Approved / Ready for external execution
- Applies To: Wave 4D authentic playtest cohort, M1 release decision, evidence-driven tuning
- Evidence Minimum: 20 valid human sessions from one exact build/content cohort
- Privacy: anonymous identifiers only; no names, email, platform ID, IP, device name, notes, recordings, or free text in release evidence
- Synthetic Policy: synthetic and automated evidence is always excluded from the human gate

## 1. 目的与不可替代边界

30 Seed 探针证明五房权威运行时在固定输入下可以重复完成，并用于发现崩溃、脚本错误、泄漏、软锁、无法结算与确定性漂移。它不证明手感、公平性、可理解性、Boss 可读性或重玩意愿。

正式 M1 还需要至少 20 局真实外部试玩。推荐由至少 10 名非开发测试者各完成两局；同一测试者的两局仍是两个独立匿名 `session_id`。任何自动运行、模拟 Fixture、开发者代填或 AI 生成记录必须标为 `synthetic`，并且永远不能补足 20 局门槛。

缺少真实证据时，唯一诚实状态是 `M1 Candidate — External Validation Pending`。工具链完成不等于真人 Gate 已完成。

## 2. Cohort 冻结

开始招募前冻结以下三项：

1. `build.version`：给测试者的可执行版本号。
2. `build.commit`：构建来源的 7–40 位小写 Git commit。
3. `build.content_version`：M1 encounter catalog 的 `plan_id`。

Seed Matrix、20 局会话和观察表必须完全匹配同一 cohort。修复 P0/P1 或任何会改变玩法、内容、输入、UI 理解的改动后，必须重新构建并开启新 cohort；不得把旧 cohort 的真人局拼进新版本。

## 3. 每局执行流程

1. 观察员创建随机匿名 `session_id`，格式为 `pws_` 加 32 位小写十六进制；不要从姓名、邮箱或平台 ID 派生。
2. 测试者独立启动指定构建。观察员只解释键位与“完成一局”的目标，不解释构筑答案、Boss 解法或技能用途。
3. 完整记录会话事件：Seed、输入设备、开始/结束时间、房间进入/完成、伤害、失败代码、构筑选择和终局。
4. 局后立即完成结构化观察，不加入自由文本。问题通过稳定 `issue.code`、严重度、系统和房间索引记录。
5. 同一 `session_id` 必须同时出现在 session JSONL 与 observation JSONL 中。

## 4. 结构化观察定义

模板：`docs/current/templates/m1_observation.template.json`。复制后替换占位符，每行一个 JSON 对象写入 observation JSONL。

字段判定：

- `time_stop_used` / `time_rewind_used`：本局至少成功触发一次对应能力。
- `build_described`：不提示答案时，测试者能说出至少一个核心方向以及一项选择如何支持它。
- `boss_time_interactions_identified`：测试者能指出的不同 Boss/时间能力交互数量；同义描述只计一次。
- `unexplained_damage_or_death`：观察员确认测试者无法从画面、声音或规则解释一次关键受伤/死亡。
- `responsiveness_rating`：测试者给出的 1–5 分响应性评分。
- `replay_intent`：只允许 `restarted`、`would_replay`、`would_not_replay`、`unknown`。
- `issues[].severity`：`p0` 数据/安全/无法运行；`p1` 放行阻断；`p2` 明显缺陷但有替代路径；`p3` 轻微改进。
- `room_index`：0–4；跨局或未知位置填 -1。

观察模板包含占位 issue；没有问题时必须把 `issues` 改成空数组，而不是保留模板占位值。

## 5. 数据导入与匿名化

原始会话不得直接提交到仓库。先在仓库外的临时目录处理：

```bash
mkdir -p /tmp/planewalker-m1-human
python3 tools/playtest/deidentify_sessions.py \
  /path/to/private/raw_sessions.jsonl \
  /tmp/planewalker-m1-human/sessions.jsonl \
  --salt "LOCAL_SECRET_NOT_COMMITTED"
python3 tools/playtest/validate_sessions.py \
  /tmp/planewalker-m1-human/sessions.jsonl --json
python3 tools/m1/validate_observations.py \
  /tmp/planewalker-m1-human/observations.jsonl --json
python3 tools/playtest/evidence_gate.py \
  /tmp/planewalker-m1-human/sessions.jsonl \
  --minimum-human 20 \
  --build-version "BUILD_VERSION" \
  --commit "BUILD_COMMIT" \
  --content-version "CONTENT_VERSION" \
  --json
```

任一校验错误都必须修复来源记录；不得删除失败行后假装 cohort 完整。不得提交匿名化 salt、原始身份映射、录屏路径或私人招募信息。

## 6. 30 Seed 与正式报告命令

```bash
python3 tools/m1/run_seed_matrix.py \
  --seed-start 0 --seed-count 30 \
  --output /tmp/planewalker-m1-seeds.json
python3 tools/m1/run_seed_matrix.py \
  --seed-start 0 --seed-count 30 \
  --output /tmp/planewalker-m1-seeds-repeat.json
python3 tools/m1/compare_seed_reports.py \
  /tmp/planewalker-m1-seeds.json \
  /tmp/planewalker-m1-seeds-repeat.json --json
python3 tools/m1/generate_release_report.py \
  --seed-report /tmp/planewalker-m1-seeds.json \
  --sessions /tmp/planewalker-m1-human/sessions.jsonl \
  --observations /tmp/planewalker-m1-human/observations.jsonl \
  --output docs/current/2026-09-28-m1-release-report.md \
  --json-output /tmp/planewalker-m1-decision.json \
  --tuning-output /tmp/planewalker-m1-tuning-input.json
```

如果真人数据尚未提供，省略 `--sessions` 与 `--observations`；生成器必须输出 `M1 Candidate — External Validation Pending`，不能手改成 Go。

## 7. M1 自动决策规则

`M1 Go` 需要同时满足：

- 0–29 共 30 个 Seed 全部到达 victory；无失败代码、脚本错误、泄漏或 digest 漂移。
- 至少 20 个唯一、有效、真实 human session 匹配 cohort。
- 至少 20 个有效 human observation 与这些 session 一一匹配。
- 成功局 8–12 分钟占比至少 80%。
- Time Stop 使用率和 Time Rewind 使用率分别至少 80%。
- 构筑可描述率、至少两项 Boss 时间交互识别率、4/5 以上响应性占比分别至少 80%。
- 无法解释的关键受伤/死亡低于 10%。
- 主动重开或明确愿意再玩的比例至少 60%。

仓库 Gate 或完整真人 cohort 的阈值失败为 `M1 No-Go`。真人 session/observation 数量不足且仓库 Gate 通过时为 `M1 Candidate — External Validation Pending`。

## 8. 调参审计

调参模板：`docs/current/templates/m1_tuning_decision.template.json`。每个保留或回退的数值改动都必须记录：

- cohort、`decision_id`、权威数据/代码路径与系统 ID；
- 触发它的 `metric_id` 或结构化失败签名以及 `evidence_refs`；
- `old_value`、`new_value` 与可证伪的 `expected_effect`；
- 精确 `regression_test`；
- `disposition`（`retained` 或 `reverted`）、`revert_reason`、最终 commit。

Synthetic Seed 只授权修复确定性、崩溃、脚本错误、泄漏、软锁和确定性预算。真实玩家 cohort 完整前，不得用 synthetic 数据声称“更好玩”“更公平”“更易懂”，也不得据此做体验型数值调优。

每批调参只处理一个主导失败签名。修改后必须重跑相邻测试、两轮 30 Seed 和同 cohort 报告；若改善一个指标却破坏前摇、时长、构筑多样性或稳定性 Gate，则回退并记录。

## 9. Issue Triage 与现实限制

- `p0` / `p1` 或 `blocks_release=true`：立即进入 No-Go；先修复并开启兼容的新 cohort。
- 重复出现的 `p2`：按频次、房间与系统聚合，作为下一批调参输入。
- 单次 `p3`：记录但不以它单独改动核心数值。
- 自由文本可用于团队讨论，但不进入自动 Gate；需要进入 Gate 的观察必须转成上述结构化字段或稳定 issue code。

仓库当前能够完成工具、格式、导入、30 Seed 和候选报告。真实 20 局只能由真实外部测试者提供，自动化代理不能替代、模拟或伪造这一现实证据。
