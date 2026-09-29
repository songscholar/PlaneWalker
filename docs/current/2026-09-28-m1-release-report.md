# Plane Walker M1 放行报告

- Status: External Validation Pending / Current
- Document Role: Current evidence record
- Authority Level: Formal M1 release decision evidence
- Applies To: M1 repository stability, authentic human-playtest gate, and first post-M1 promotion decision
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-09-28-m1-playtest-protocol.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Evidence Schema: M1 seed matrix `2.0.0` / playtest session `1.0.0` / observation `1.0.0` / external attestation `2.0.0`
- Build Version: `0.4.0-dev`
- Commit: `79a20fd183fb57b8bdf62019ab80ff3f6e430635`
- Content Version: `m1.encounters.v1`
- Evidence Origin: `godot_authoritative_probe`
- Evidence Classification: `release`
- Probe Version: `2.0.0`
- Worktree Clean: `true`
- Tree Digest: `c331ac2309d11b8dda656447adb17167ed905cb6`
- Probe Digest: `85a654b1f387d50b9074428673db66e37f75208b1efa54fce7859048c7a0a3c8`
- Godot Version: `4.6.1.stable.official.14d19694e`
- Content Digest: `237fb15accef5a23f805c6b63d217691a57cd1051df99acbd162820e15a860f6`

## 正式结论

**M1 Candidate — External Validation Pending**

30 Seed 仓库门禁：**PASS**；真实外部试玩：**0 / 20**；匹配结构化观察：**0 / 20**。

Synthetic 数据只用于验证工具、稳定性和确定性，永久不计入真实玩家门禁。当前证据不足时，不得据此声称手感、公平性或重玩意愿已验证。

## 30 Seed 稳定性

- Matrix digest: `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`
- Seed records: 30
- Failed seeds: 0
- Live Godot verification: true
- Gate: PASS
- Release eligible: true

## 外部试玩与玩法阈值

| 指标 | 实测 | 门槛 | 结果 |
|---|---:|---:|---|
| `human_completion_rate` | 0.0% | >= 80.0% | PENDING |
| `successful_run_duration_8_12_rate` | 0.0% | >= 80.0% | PENDING |
| `time_stop_usage_rate` | 0.0% | >= 80.0% | PENDING |
| `time_rewind_usage_rate` | 0.0% | >= 80.0% | PENDING |
| `build_comprehension_rate` | 0.0% | >= 80.0% | PENDING |
| `boss_time_interactions_rate` | 0.0% | >= 80.0% | PENDING |
| `unexplained_harm_rate` | 0.0% | < 10.0% | PENDING |
| `responsiveness_4plus_rate` | 0.0% | >= 80.0% | PENDING |
| `replay_intent_rate` | 0.0% | >= 60.0% | PENDING |

独立外部证明：**PENDING/INVALID**；证明 ID：``。

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
- signed independent external attestation is required for M1 Go

## 保留/回滚说明

- 报告由机器可读 Seed Matrix、已校验会话 JSONL 和已校验观察 JSONL 生成。
- 自由文本、未校验表格和 synthetic fixture 不进入放行计算。
- 数值改动必须引用本报告调参输入中的指标或失败签名，并记录旧值、新值、预期影响和回归测试。
- 状态保持 `M1 Candidate — External Validation Pending`，直到正式干净 Seed Matrix、真实 20 局和独立外部证明全部齐备；Candidate 不等于放行。
