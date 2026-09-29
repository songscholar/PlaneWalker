# Plane Walker 开发文档入口

- Status: Approved / Current
- Document Role: Current documentation index
- Authority Level: Documentation index and execution-status source
- Applies To: 全仓库设计、开发、测试、构建和发布准备
- Implementation Status: P2, P3, P4/P5, P6, P8, and P10A certified locally; P7/P9 continues with honest coverage/export blockers; formal state remains `M1 Candidate — External Validation Pending`
- Owner: Project integration lead
- Depends On: `AGENTS.md`
- Supersedes: 以无状态旧文档或已完成 Wave 计划作为当前执行入口
- Last Verified: 2026-09-29
- Contract References: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## 当前执行结论

Plane Walker 已进入“完整产品愿景全量完成”计划，不再把 Current、Next、Launch 和 Expansion 作为可被删减的产品选项。范围通过实施顺序和质量 Gate 控制，不通过删除角色、武器、楼层、Boss、Hub、剧情、回放、排行、Mod 或 DLC 能力来降低范围。

当前实施入口是：

1. [完整产品 Completion Spec](superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md)：定义最终范围、架构约束、内容数量和 Product Complete Gate。
2. [Wave 4 与 M1 放行计划](superpowers/plans/2026-09-28-plane-walker-wave-4-m1-release.md)：记录已完成的仓库 Gate、M1 Candidate 状态和外部证据边界。
3. `AGENTS.md`：定义持续授权、无需再确认的工作以及远程发布、真实付费和私密凭据等外部边界。

## 当前状态

| 范围 | 状态 | 结论 |
|---|---|---|
| Wave 0/1 | Completed / Historical | RunState、RunOrchestrator、SeedService、基础战斗不变式和契约 HUD 已验证 |
| Wave 2 | Completed / Historical | ContentRegistry、M1 房间计划、DraftService、PlayerActionState 和 ChoicePanel 已验证 |
| Wave 3A | Completed / Historical | 真实运行时 Facade、旧流程桥接、选择幂等与五房流程已验证 |
| Wave 3B | Completed / Historical | 敌人前摇、Boss 行为互斥、玩家单时钟、回溯取消、真实 HUD 与 640×360 画布已验证 |
| P0 Foundation Baseline | Completed | 本地化与 Godot 4.6 基线已提交，干净克隆可生成翻译产物并通过验证 |
| P1 Test/CI Foundation | Completed | 唯一验证入口、只读 CI、双阶段导入和日志分类已通过 |
| P2 Atomic SaveService | Completed / Certified | 原子写入、双备份、迁移、损坏恢复、前向拒绝、Profile/Mod 域隔离和一次性 legacy 导入已验证 |
| P3 ContentRegistry v2 | Completed / Certified | Base pack、依赖/完整性/本地化/效果校验、运行时唯一内容源和 SaveService 指纹已验证 |
| P4 Single RunState / RoomRuntime | Completed / Certified | RunOrchestrator/RoomRuntime 是唯一运行与房间写入权威；GameState 运行镜像、LegacyRunAdapter 和旧运行 UI 已退休 |
| P5 Single event publication | Completed / Certified | 14 个 typed gameplay facts exactly-once；generic EventBus 与所有运行域状态变更订阅已退休 |
| P6 Controller/focus/accessibility | Completed / Certified | 14 动作双设备合同、可恢复 remap、纯手柄焦点链、15 项设置 UI、字幕/音频/视觉替代和本局助攻快照已通过 focused、整库及 detached gate |
| P7/P9 Export and clean certification | Active / Externally blocked | 工具链、fail-closed 执行器、detached clone 认证已提交；真实覆盖率、导出模板和 packaged startup 尚未通过 |
| P8 Documentation governance | Completed / Certified | 离线验证、元数据/生命周期、零基线、ADR、Current 索引、证据状态和整库认证已完成 |
| Wave 4A | Completed | 试玩会话、去标识、导入、汇总、证据 Gate 和合同测试已完成 |
| Wave 4B | Completed | 回溯残影、Boss 全招前摇、精英主动机制和五房权威遭遇已实现并通过测试 |
| Wave 4C | Completed for M1 technical scope | Pixel Proxy、核心动画、合成音频、战斗反馈、可访问性开关和清理回归已验证 |
| Wave 4D | Repository automation completed | 30 Seed 权威矩阵已连续两轮匹配，仓库 Gate `PASS`；真实外部试玩为 `0 / 20` |
| Formal M1 | `M1 Candidate — External Validation Pending` | Candidate commit `79a20fd183fb57b8bdf62019ab80ff3f6e430635`；Matrix digest `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`；仓库 Gate 通过，真人 Gate 待外部执行 |
| Experience tuning | Not authorized by evidence | 真人体验数据为 `0 / 20`，不使用 synthetic 或 30 Seed 数据伪装手感调参依据 |
| Post-M1 Promotion | Not started / Evidence-gated | 弓、时间裂隙、时间加速三选一尚未启动，等待真实 M1 人类证据 |
| P10 Candidate Loadouts | Completed / Certified | 五角色、五武器、四能力目录、候选运行时、双槽 HUD、Candidate Lab 与六种时间组合已本地认证；Bow/Rift/Accelerate 未正式晋升 Current |
| Full Product Content | Active / Phased program | 五角色、五武器、四时间能力、五层五 Boss、八流派和完整内容池按依赖顺序持续实施 |
| Launch / Expansion Systems | Preserved / Later program | Hub、成长、叙事、多结局、Boss Rush、挑战、无尽、回放、排行、Mod、外观和 DLC 内容包保留，本轮不展开 |

当前权威 M1 Candidate 是干净提交 `79a20fd183fb57b8bdf62019ab80ff3f6e430635`。30 Seed 矩阵的两轮权威执行使用同一 digest `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`，仓库 Gate 为 `PASS`。真实外部玩家和匹配观察均为 `0 / 20`，因此状态不得升级为 `M1 Go`。

P0–P9、Wave 4A–4D、M1 放行、M1 后能力提升以及 Next/Launch/Expansion 是同一连续交付程序。M1 不是停工点；其中的外部真人试玩是诚信证据 Gate。仓库必须完成会话导入、匿名校验、报告生成、问卷/观察模板和修复跟踪，但自动化模拟不得冒充 20 局真实外部试玩。

## 权威顺序

规则冲突时按以下顺序执行：

1. 仓库根目录 `AGENTS.md` 的授权和安全边界。
2. 已批准 ADR。
3. [完整产品 Completion Spec](superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md)。
4. 当前阶段的 Implementation Plan 和 contracts。
5. `docs/dev/` 中已与 Godot 实现对齐的系统文档。
6. [深度收敛与系统职责设计](0_%E6%B7%B1%E5%BA%A6%E6%94%B6%E6%95%9B%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%81%8C%E8%B4%A3%E8%AE%BE%E8%AE%A1.md)。
7. 旧 GDD、运营设想、伪代码和 Historical 计划。

已完成 Wave 计划是验证记录，不是新工作的任务队列。其已验证契约在有等价或更强替代经过测试前仍然是回归 Gate。

## 文档地图

### 当前规格与计划

| 文档 | 用途 | 状态 |
|---|---|---|
| [完整产品 Completion Spec](superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md) | 全产品范围、体系结构、数量和完成 Gate | Approved / Current authority |
| [ADR Index](adrs/README.md) | 已接受/已取代架构决策、权威顺序与 supersession 链 | Approved / Current authority |
| [Document Governance v1](contracts/document-governance-v1.md) | 元数据、生命周期、Current 索引、ADR、相对链接和证据状态合同 | Approved / Current contract |
| [SaveService v1 Contract](contracts/save-service-v1.md) | 原子存档、迁移、恢复和内容兼容边界 | Approved / Current contract |
| [Content Pack v2 Contract](contracts/content-pack-v2.md) | Base/更新/Mod/DLC 内容包、完整性与声明式效果边界 | Frozen / Current contract |
| [M1 Playtest Protocol](current/2026-09-28-m1-playtest-protocol.md) | 真实外部试玩、匿名化、cohort、观察和证明合同 | Approved / Current protocol |
| [M1 Release Report](current/2026-09-28-m1-release-report.md) | 30 Seed 仓库证据、真实玩家门禁与正式 M1 结论 | External Validation Pending / Current |
| [Wave 4 与 M1 放行计划](superpowers/plans/2026-09-28-plane-walker-wave-4-m1-release.md) | Wave 4A–4D 仓库成果、M1 Candidate 和外部证据 Gate | External Validation Pending / Current |
| [Wave 4B Encounter Mechanics Plan](superpowers/plans/2026-09-28-plane-walker-wave-4b-encounter-mechanics.md) | 回溯残影、Boss 前摇、精英主动和五房遭遇 | Completed / Historical |
| [Wave 4C Pixel Feedback Plan](superpowers/plans/2026-09-28-plane-walker-wave-4c-pixel-feedback.md) | M1 Pixel Proxy、音频、战斗反馈与可访问性 | Completed / Historical |
| [Wave 4C Evidence](current/2026-09-28-wave-4c-pixel-feedback-evidence.md) | Wave 4C 焦点、全套与 Candidate 门禁证据 | Verified Locally / Current |
| [P0 Foundation Baseline Evidence](current/2026-09-28-foundation-baseline-evidence.md) | 本地化、验证入口和干净克隆认证证据 | Verified Locally / Current |
| [P2 Atomic SaveService Evidence](current/2026-09-29-p2-atomic-save-evidence.md) | 原子存档、迁移、恢复、隔离、GameState 兼容和 P3/P4 接力证据 | Verified Locally / Current |
| [P3 ContentRegistry v2 Evidence](current/2026-09-29-p3-content-registry-evidence.md) | 版本化内容包、声明式效果、运行时切换和 SaveService 指纹证据 | Verified Locally / Current |
| [P4/P5 Authority and Event Plan](superpowers/plans/2026-09-29-plane-walker-p4-p5-authority-events.md) | 单一 RunState、RoomRuntime、Host 切换、镜像退休和 exactly-once 事件实施记录 | Completed / Historical |
| [P4/P5 Authority and Event Evidence](current/2026-09-29-p4-p5-authority-events-evidence.md) | 运行权威、直接生命周期路由、typed facts、源码门禁和 59 场景整库认证 | Verified Locally / Current |
| [P6 Controller and Accessibility Plan](superpowers/plans/2026-09-29-plane-walker-p6-controller-accessibility.md) | 手柄、重映射、焦点恢复与无障碍持久化实施记录 | Completed / Historical |
| [P6 Controller and Accessibility Evidence](current/2026-09-29-p6-controller-accessibility-evidence.md) | 纯手柄流程、设置持久化、运行时替代、focused/整库/detached 认证和真人验证边界 | Verified Locally / Current |
| [P7/P9 Export Certification Plan](superpowers/plans/2026-09-29-plane-walker-p7-p9-exports-certification.md) | 三平台导出合同、离线预检和清洁认证基础 | Active / Current |
| [Export Executor and Evidence Plan](superpowers/plans/2026-09-29-plane-walker-export-executor-evidence.md) | 导出执行、artifact hash、detached checkout 和 fail-closed 证据 | External Validation Pending / Current |
| [P7/P9 Export Certification Evidence](current/2026-09-29-p7-p9-export-certification-evidence.md) | 导出预检、fail-closed 执行器、detached clone 与当前 blocker | External Validation Pending / Current |
| [P8 Documentation Governance Plan](superpowers/plans/2026-09-29-plane-walker-p8-document-governance.md) | 文档元数据、生命周期、链接、ADR、Current 索引和证据状态实施记录 | Completed / Historical |
| [P8 Documentation Governance Evidence](current/2026-09-29-p8-document-governance-evidence.md) | 零基线、Current 索引、ADR、证据状态和离线整库治理认证 | Verified Locally / Current |
| [P10 Candidate Loadouts Plan](superpowers/plans/2026-09-29-plane-walker-p10-candidate-loadouts.md) | 五角色/五武器/四能力目录、候选 Loadout、运行时隔离、双槽 HUD 和六组合验证 | Completed / Historical |
| [P10 Candidate Loadouts Evidence](current/2026-09-29-p10-candidate-loadouts-evidence.md) | 五角色/五武器/四能力、候选运行时、双槽 HUD、Candidate Lab、六组合与事实完整性认证 | Verified Locally / Current |
| [P11 Five Complete Weapons Design](superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md) | 五武器共享动作权威、完整节奏、输入、HUD、反馈、时间与 Boss 联动及 30 组合验证 | Approved / Current authority |
| [P11 Five Complete Weapons Plan](superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md) | P11A–P11H 共享权威、五武器迁移/实现、跨武器系统及认证执行计划 | Active / Current |
| [P11A Shared Weapon Authority Evidence](current/2026-09-29-p11a-shared-weapon-authority-evidence.md) | Profile、Coordinator、语义输入、Modifier、typed facts、完整性及 69 场景全量认证 | Verified Locally / Current |
| [P11B Sword Migration Evidence](current/2026-09-29-p11b-sword-migration-evidence.md) | Sword Coordinator 迁移、M1 帧表/伤害权威、Active cue、输入优先级及 73 场景全量认证 | Verified Locally / Current |
| [P0 Foundation Baseline Plan](superpowers/plans/2026-09-28-plane-walker-foundation-baseline.md) | 已执行的本地化基线与清洁重现计划 | Completed / Historical |
| [分阶段开发设计](superpowers/specs/2026-09-28-plane-walker-staged-development-design.md) | 保留 M1 设计理由和已验证契约 | Historical / Superseded for execution order |

P3 证据保留其认证时的历史 HEAD 与指纹。后续提交 `0eb9942` 在新增本地化键后刷新了当前 Base Pack 的本地化完整性哈希；它不追溯改写 P3 认证记录，任何“当前内容 digest”必须从当前 HEAD 重新生成。

### 核心产品设计

| 领域 | 主要入口 |
|---|---|
| 产品收敛、八流派与成长边界 | [0_深度收敛与系统职责设计](0_%E6%B7%B1%E5%BA%A6%E6%94%B6%E6%95%9B%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%81%8C%E8%B4%A3%E8%AE%BE%E8%AE%A1.md) |
| 世界观、剧情和结局 | [2_世界观与叙事进度设计](2_%E4%B8%96%E7%95%8C%E8%A7%82%E4%B8%8E%E5%8F%99%E4%BA%8B%E8%BF%9B%E5%BA%A6%E8%AE%BE%E8%AE%A1.md) |
| 战斗和时间系统 | [3.1 战斗](3.1combat-system-design.md) / [3.2 时间](3.2_%E6%97%B6%E9%97%B4%E6%93%8D%E6%8E%A7%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1.md) |
| 局内构筑 | [3.3 道具](3.3_%E9%81%93%E5%85%B7%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1.md) / [3.4 祝福与诅咒](3.4_%E7%A5%9D%E7%A6%8F%E4%B8%8E%E8%AF%85%E5%92%92%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1.md) |
| 地牢、敌人和 Boss | [3.5 地牢](3.5_%E5%9C%B0%E7%89%A2%E7%94%9F%E6%88%90%E4%B8%8E%E5%85%B3%E5%8D%A1%E8%AE%BE%E8%AE%A1.md) / [3.6 敌人](3.6_%E6%95%8C%E4%BA%BA%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1.md) / [3.7 Boss](3.7_Boss%E8%AE%BE%E8%AE%A1.md) |
| 角色和数值 | [4_角色与数值体系设计](4_%E8%A7%92%E8%89%B2%E4%B8%8E%E6%95%B0%E5%80%BC%E4%BD%93%E7%B3%BB%E8%AE%BE%E8%AE%A1.md) |
| UI、像素美术和音频 | [5_6_UI美术音效技术设计](5_6_UI%E7%BE%8E%E6%9C%AF%E9%9F%B3%E6%95%88%E6%8A%80%E6%9C%AF%E8%AE%BE%E8%AE%A1.md) |
| Hub、局外成长和教学 | [8.1 Hub](8.1_%E5%B1%80%E5%A4%96%E6%9E%A2%E7%BA%BD%E4%B8%8E%E6%AD%BB%E4%BA%A1%E7%BB%93%E7%AE%97%E8%AE%BE%E8%AE%A1.md) / [8.2 成长](8.2_%E8%B4%A7%E5%B8%81%E5%85%BB%E6%88%90%E4%B8%8E%E5%A4%A9%E8%B5%8B%E6%A0%91%E8%AE%BE%E8%AE%A1.md) / [8.4 教学](8.4_%E9%94%BB%E9%80%A0%E5%BC%BA%E5%8C%96%E4%B8%8E%E6%96%B0%E6%89%8B%E6%95%99%E5%AD%A6%E8%AE%BE%E8%AE%A1.md) |
| 外观、运营与外部系统 | [8.3 选择与外观](8.3_%E5%B1%80%E5%86%85%E9%80%89%E6%8B%A9%E4%B8%8E%E6%8A%BD%E5%8D%A1%E5%A4%96%E8%A7%82%E8%AE%BE%E8%AE%A1.md) / [8.5 系统与运营](8.5_%E7%B3%BB%E7%BB%9F%E5%8A%9F%E8%83%BD%E4%B8%8E%E8%BF%90%E8%90%A5%E8%A7%84%E5%88%92%E8%AE%BE%E8%AE%A1.md) |

### 工程文档

`docs/dev/00_Architecture.md` 是工程总入口。`docs/dev/01`–`09` 包含各系统的历史实现设计，其中仍有 Unity/C# 伪代码和旧 1920×1080 坐标；它们可作为意图参考，不得覆盖当前 Godot 契约、640×360 像素画布和已验证运行时实现。

## 外部执行边界与商业 Gate

仓库内必须实现可测试的离线 Provider、数据契约、导出路径和 UI 降级流程。以下操作不是“代码完成”的前置条件，也不得阻塞开发：

- Steam Cloud、Workshop、成就、好友、排行榜和 Activity Feed 的真实平台配置。
- 公开上架、远程推送、商店页、公告、社交媒体发布、证书和平台签名。
- 翻译、托管、分析、网络或商业服务的付费购买。

付费抽卡、真实货币销售、DLC 定价、限时销售和商业运营日历处于 **Commercial Decision Gate**：未获得单独产品决策时，只实现免费外观收集、中性商品接口和内容包基础设施，不激活现金交易、付费概率池或购买入口。

## 维护规则

- 新的当前计划必须在本页状态表中有一项，完成后改为 Completed / Historical。
- 每个实施阶段必须记录测试、日志扫描、已知限制和回滚点。
- 不得把外部凭据、公开发布或真实玩家反馈写成仓库内自动化已完成事项。
- 修改产品数量、核心角色、八流派、内容包格式或 Product Complete Gate 时，必须同步更新 Completion Spec。
