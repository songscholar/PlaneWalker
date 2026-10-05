# Plane Walker 开发文档入口

- Status: Approved / Current
- Document Role: Current documentation index
- Authority Level: Documentation index and execution-status source
- Applies To: 全仓库设计、开发、测试、构建和发布准备
- Implementation Status: P11 five weapons, P12 five characters and P13 complete Launch pools are locally certified. P14 native dungeon panels and Save/Replay have focused verification. P15 production native encounters, five Boss foundations, Time Watch and live combat checkpoints are active; remaining species, affixes and Boss arena constructs continue. P16 native Hub/meta/training/tutorial, narrative/endings and trusted active-content migration have focused evidence. P17 actor/enemy raster assets and music, P18 local Mod/DLC management, P20A native build sharing and P20B durable local records have focused evidence. P21 native modes and P22 replay productization are active. Combined clean-checkout validation, line coverage, retained release exports and full-gameplay certification remain pending. Formal M1 remains `M1 Candidate — External Validation Pending`
- Owner: Project integration lead
- Depends On: `AGENTS.md`
- Supersedes: 以无状态旧文档或已完成 Wave 计划作为当前执行入口
- Last Verified: 2026-10-05
- Contract References: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## 当前执行结论

Main 已接入三个原生据点区域、成长/锻造/配装、真实教学和训练、剧情/结局/字幕，以及活跃战斗的物理冷恢复。P20A 配装分享和 P20B 本地排行已通过原生流程、持久保存及双语窗口专项验证。狂暴/坚固精英已接入真实生成与历史冷恢复，Ruin 掩体能阻挡激光。完整动态词缀、敌人效果、Boss 场地机制与挑战模式正在推进；回放产品化、外观及额外 Expansion 内容仍在后续队列。每项专项证据与最终整合认证分别记录。

Plane Walker 已进入“完整产品愿景全量完成”计划，不再把 Current、Next、Launch 和 Expansion 作为可被删减的产品选项。范围通过实施顺序和质量 Gate 控制，不通过删除角色、武器、楼层、Boss、Hub、剧情、回放、排行、Mod 或 DLC 能力来降低范围。

当前实施入口是：

1. [完整产品 Completion Spec](superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md)：定义最终范围、架构约束、内容数量和 Product Complete Gate。
2. [Wave 4 与 M1 放行计划](superpowers/plans/2026-09-28-plane-walker-wave-4-m1-release.md)：记录已完成的仓库 Gate、M1 Candidate 状态和外部证据边界。
3. `AGENTS.md`：定义持续授权、无需再确认的工作以及远程发布、真实付费和私密凭据等外部边界。

## 本地验证前置条件

统一验证入口依赖 Godot 4.6.1、Python 3 和固定版本的 `jsonschema`。新环境先在仓库根目录执行 `python3 -m pip install --requirement requirements-dev.txt`，再运行 `./tools/validate_project.sh`。验证脚本只检查依赖并在缺失时给出安装命令，不会自行联网安装；CI 也在调用统一验证入口前显式安装同一依赖清单。

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
| P7/P9 Export and clean certification | Active / Validation repair | 官方模板已在项目工具链提供；最新干净检出暴露内容契约与 CI 编排不一致，正修复并重跑。真实行覆盖率与最终发行包认证仍待完成 |
| P8 Documentation governance | Completed / Certified | 离线验证、元数据/生命周期、零基线、ADR、Current 索引、证据状态和整库认证已完成 |
| Wave 4A | Completed | 试玩会话、去标识、导入、汇总、证据 Gate 和合同测试已完成 |
| Wave 4B | Completed | 回溯残影、Boss 全招前摇、精英主动机制和五房权威遭遇已实现并通过测试 |
| Wave 4C | Completed for M1 technical scope | Pixel Proxy、核心动画、合成音频、战斗反馈、可访问性开关和清理回归已验证 |
| Wave 4D | Repository automation completed | 30 Seed 权威矩阵已连续两轮匹配，仓库 Gate `PASS`；真实外部试玩为 `0 / 20` |
| Formal M1 | `M1 Candidate — External Validation Pending` | Candidate commit `79a20fd183fb57b8bdf62019ab80ff3f6e430635`；Matrix digest `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`；仓库 Gate 通过，真人 Gate 待外部执行 |
| Experience tuning | Not authorized by evidence | 真人体验数据为 `0 / 20`，不使用 synthetic 或 30 Seed 数据伪装手感调参依据 |
| Post-M1 Promotion | Not started / Evidence-gated | 弓、时间裂隙、时间加速三选一尚未启动，等待真实 M1 人类证据 |
| P10 Candidate Loadouts | Completed / Certified | 五角色、五武器、四能力目录、候选运行时、双槽 HUD、Candidate Lab 与六种时间组合已本地认证；Bow/Rift/Accelerate 未正式晋升 Current |
| Full Product Content | Active / Phased program | P11、P12、P13 已认证；P14 六类原生面板、五层状态和 Save/Replay 专项通过；P15 正式原生遭遇、二十二敌人动作领域、五 Boss 基础及 Time Watch 专项通过，完整机制与场地构造物继续实施 |
| Launch / Expansion Systems | Active / Phased program | Hub、成长、训练、叙事、多结局、活跃存档、原创资源/音乐、离线 Mod/DLC 管理和配装分享已专项验证。本地排行在实施；Boss Rush、挑战、无尽、回放产品化、外观和追加内容尚待完成 |

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
| [Dungeon Probe Encounter Design](superpowers/specs/2026-10-05-dungeon-probe-native-encounter-design.md) | 合成模拟复用正式遭遇状态机、固定帧与生成及死亡回执 | Approved / Current authority |
| [Dungeon Probe Encounter Plan](superpowers/plans/2026-10-05-dungeon-probe-native-encounter.md) | 守卫事件回归、工具适配器和三十种子报告修复 | Active / Current |
| [Dungeon Probe Encounter Repair Evidence](current/2026-10-05-dungeon-probe-encounter-repair-evidence.md) | 正式状态机工具适配、守卫事件回归和整体验证修复 | Focused Verified / Combined certification pending |
| [P22A Player Replay Archive Design](superpowers/specs/2026-10-05-p22a-player-replay-archive-design.md) | 玩家录制封装、物理回放库、兼容拒绝与隔离播放边界 | Approved / Current authority |
| [P22A Player Replay Archive Plan](superpowers/plans/2026-10-05-p22a-player-replay-archive.md) | 实际 Player 录制、原子保存、导入导出和寻址播放实施 | Completed / Historical |
| [P22A Player Replay Archive Evidence](current/2026-10-05-p22a-player-replay-archive-evidence.md) | 物理回放库、故障与并发写保护、实际 Player 隔离寻址播放 | Focused Verified / Current |
| [Native Elite Regeneration Evidence](current/2026-10-05-native-elite-regeneration-evidence.md) | 精英真实回血、实际恢复预算、重击中断、Stop 和物理冷恢复 | Focused Verified / Current |
| [Native Player Weapon Collision Evidence](current/2026-10-05-native-player-weapon-collision-evidence.md) | 五武器真实敌人扣血、高速弹丸扫掠和自然地牢剑击 | Focused Verified / Current |
| [P21A Native Boss Rush Evidence](current/2026-10-05-p21a-native-boss-rush-evidence.md) | 五 Boss 原生流程、物理存档、失败重试和手柄暂停 | Focused Verified / Current |
| [P21B Native Daily Boss Design](superpowers/specs/2026-10-05-p21b-native-daily-boss-design.md) | 固定配装、UTC+8 日界、每天三次尝试和原生每日 Boss | Approved / Current authority |
| [P21B Native Daily Boss Plan](superpowers/plans/2026-10-05-p21b-native-daily-boss.md) | 独立挑战状态、真实道具效果与物理保存实施 | Active / Current |
| [ADR Index](adrs/README.md) | 已接受/已取代架构决策、权威顺序与 supersession 链 | Approved / Current authority |
| [Document Governance v1](contracts/document-governance-v1.md) | 元数据、生命周期、Current 索引、ADR、相对链接和证据状态合同 | Approved / Current contract |
| [SaveService v1 Contract](contracts/save-service-v1.md) | 原子存档、迁移、恢复和内容兼容边界 | Approved / Historical contract |
| [SaveService v2 Contract](contracts/save-service-v2.md) | Launch 奖励/主动道具运行时状态、v1→v2 迁移、JSON 规范化和生产回写边界 | Approved / Historical contract |
| [SaveService v3 Contract](contracts/save-service-v3.md) | FloorPlan、五层运行状态、v2→v3 fail-closed 迁移、Save/Replay 恢复边界 | Approved / Current contract |
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
| [P11 Five Complete Weapons Plan](superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md) | P11A–P11H 共享权威、五武器迁移/实现、跨武器系统及认证实施记录 | Completed / Historical |
| [P12 Five Complete Characters Design](superpowers/specs/2026-09-30-plane-walker-p12-five-characters-design.md) | 五角色 Profile、专属资源/技能、武器 mastery、双时间转换、15 天赋、角色 UI/Replay 与 150 组合认证权威 | Approved / Current authority |
| [P12 Five Complete Characters Plan](superpowers/plans/2026-09-30-plane-walker-p12-five-characters.md) | 五角色运行时、角色技能/天赋、UI/Replay、150 组合与 4500 synthetic samples 的执行记录 | Completed / Historical |
| [P12A Character Profile Authority Evidence](current/2026-09-30-p12a-character-profile-authority-evidence.md) | 六个里程碑角色 Profile、15 Talent 身份、Registry/Policy、150 canonical loadouts、Schema/CI 与 115 场景整库认证 | Verified Locally / Current |
| [P12B Input and Hostile Authority Evidence](current/2026-10-01-p12b-input-hostile-authority-evidence.md) | Input schema 3、角色技能优先级、Mastery exactly-once、Replay 迁移、稳定敌人身份与非缩放威胁权威 | Focused Verified / Current |
| [P12 Five Complete Characters Evidence](current/2026-09-30-p12-five-characters-evidence.md) | 五角色、15 Talents、角色 UI/反馈、Replay、150 组合、40 Talent 子集、30 pairwise、4500 synthetic samples 与 154 场景最终认证 | Verified Locally / Current |
| [P13A Launch Archetype Authority Plan](superpowers/plans/2026-10-01-plane-walker-p13a-launch-archetype-authority.md) | 八个顶层 Launch 流派、内容引用、Draft、BuildState 与 HUD 权威的执行记录 | Completed / Historical |
| [P13A Launch Archetype Authority Evidence](current/2026-10-01-p13a-launch-archetype-authority-evidence.md) | 八流派 Profile、跨引用、里程碑 Draft/Build/UI、哈希、确定性与 156 场景整库认证 | Verified Locally / Current |
| [P13B Complete Launch Pools Design](superpowers/specs/2026-10-01-plane-walker-p13b-launch-content-design.md) | 精确 `50 / 28 / 18 / 15` 内容目录、效果事务、8 主动道具、Talent 数据权威、UI/Replay 与认证 Gate | Approved / Current authority |
| [P13B Complete Launch Pools Plan](superpowers/plans/2026-10-01-plane-walker-p13b-launch-content.md) | 内容 Schema、原子效果事务、完整池、主动道具、Talent、UI/Replay、模拟与认证的执行记录 | Completed / Historical |
| [P13B Complete Launch Pools Evidence](current/2026-10-01-p13b-launch-content-evidence.md) | `50 / 28 / 18 / 15`、`42 / 8`、62 effects、8 主动、15 Talent、Replay/Save、240 samples、150 组合与 168 场景认证 | Verified Locally / Current |
| [P14 Five-Floor Dungeon Design](superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md) | 五层确定性路线图、30 房间场景、楼层规则、经济、商人、事件、地图/UI、Save/Replay 权威 | Approved / Current authority |
| [P14 Five-Floor Dungeon Plan](superpowers/plans/2026-10-01-plane-walker-p14-five-floor-dungeon.md) | P14A–P14H 内容权威、FloorPlan、生命周期、房间流式加载、经济事件、UI、模拟与认证计划 | Active / Current |
| [P14F Dungeon Events Plan](superpowers/plans/2026-10-02-plane-walker-p14f-dungeon-events.md) | 18 事件数据闭环、确定性选择、原子后果、延续事务、Save/Replay、全事件 smoke 与认证 | Active / Current |
| [P14F Dungeon Events Evidence](current/2026-10-02-p14f-dungeon-events-evidence.md) | 事件事务、存档和回放的实际执行与恢复证据 | Implemented / Current |
| [P14G Production Flow Plan](superpowers/plans/2026-10-04-plane-walker-p14g-production-flow.md) | 原生地牢面板与生产流程集成计划 | Active / Current |
| [P14G Production Flow Evidence](current/2026-10-04-p14g-production-flow-evidence.md) | 五层原生操作、手柄焦点、多分辨率与双语验证 | Verified Locally / Current |
| [P14 Event Lifetime and Player Replay Evidence](current/2026-10-04-p14-event-lifetime-replay-evidence.md) | 事件实际效果、跨层期限、商店存档延续与玩家 Replay 7 | Verified Locally / Current |
| [P14H Retention Review](current/2026-10-04-p14h-retention-review.md) | 确定性报告、奖励补偿、离线运行包与最终门禁边界 | Focused Verified / Current |
| [P15 Enemies and Bosses Design](superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md) | 22 敌人、五 Boss、攻击契约、遭遇与原生演员集成 | Approved / Current authority |
| [P15 Enemies and Bosses Plan](superpowers/plans/2026-10-04-plane-walker-p15-enemies-bosses.md) | 固定帧敌方行为、内容目录与真实场景实现计划 | Active / Current |
| [P15 Hostile Foundation Evidence](current/2026-10-04-p15-hostile-foundation-evidence.md) | 已验证的攻击状态、遭遇状态与目录基础 | Verified Locally / Current |
| [P15A Hostile Content Evidence](current/2026-10-04-p15a-hostile-content-evidence.md) | 22 敌人、五 Boss 48 主招、词缀/召唤物、闭合模式与双语预备目录 | Verified Locally / Inactive content |
| [P15 Hostile Frame Bridge Evidence](current/2026-10-04-p15-hostile-frame-bridge-evidence.md) | 原生敌人伤害、精通观察、完整帧回滚及死亡/波次生命周期 | Verified Locally / Current |
| [P16 Hub, Meta and Narrative Design](superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md) | 三个 Hub 区域、成长预算、剧情与五结局权威 | Approved / Current authority |
| [P16 Hub, Meta and Narrative Plan](superpowers/plans/2026-10-04-plane-walker-p16-hub-meta-narrative.md) | 档案、结算、锻造、剧情、教学与原生场景执行计划 | Active / Current |
| [P16A Profile Domain Evidence](current/2026-10-04-p16a-profile-domain-evidence.md) | 成长树、严格局外档案、不可变局内投影与 JSON 兼容 | Verified Locally / Current |
| [P16B Content Evidence](current/2026-10-04-p16b-authoritative-content-evidence.md) | 156 条主城、成长、剧情和教学目录与双语内容 | Verified Locally / Current |
| [P16C Settlement Evidence](current/2026-10-04-p16c-settlement-service-evidence.md) | 一次结算、开局收据、真实 JSON 写入与失败恢复 | Verified Locally / Current |
| [P16D Workshop Domain Evidence](current/2026-10-04-p16d-forge-build-proficiency-evidence.md) | 锻造、配装库候选和固定容量武器熟练度领域 | Verified Locally / Current |
| [P16E Save and Workshop Evidence](current/2026-10-05-p16e-save-v4-workshop-service-evidence.md) | 旧存档 v4 迁移、旧局冻结效果、锻造与配装库原子持久化 | Verified Locally / Current |
| [P16 Narrative Domain Evidence](current/2026-10-05-p16e-narrative-domain-evidence.md) | 叙事来源、NPC 对话候选与五结局精确资格 | Verified Locally / Native integration pending |
| [P16F Permanent Stats Evidence](current/2026-10-05-p16f-meta-stats-evidence.md) | 真实角色基础属性、永久成长与所选武器锻造的纯投影和 150 配装矩阵 | Verified Locally / Player integration pending |
| [P16 Native Permanent Player Evidence](current/2026-10-05-p16h-meta-player-replay-evidence.md) | 原生永久属性、虚空减伤、150 配装与 Replay 8 冻结身份 | Verified Locally / Main integration pending |
| [P16 Native Floor Entry Evidence](current/2026-10-05-p16-native-floor-entry-evidence.md) | 冻结永久成长、楼层回血、失败补偿、严格原生恢复和 JSON 存档 | Verified Locally / Main integration pending |
| [P16 Onboarding Domain Evidence](current/2026-10-05-p16f-onboarding-domain-evidence.md) | 教学动作计数、提示投影、跳过重放与指导局策略领域 | Verified Locally / Native integration pending |
| [P16 Native Tutorial Observation Evidence](current/2026-10-05-p16i-native-tutorial-evidence.md) | 真实动作与成功帧认证、击退排除、保存后发布和失败帧补偿 | Verified Locally / Profile service and UI integration pending |
| [P16 Native Tutorial UI Evidence](current/2026-10-05-p16l-tutorial-ui-evidence.md) | 真实 InputMap、课程和训练投影、原生焦点、双语及 17 张渲染证据 | Verified Locally / Main and training integration pending |
| [P16 Physical Tutorial Service Evidence](current/2026-10-05-p16l-physical-tutorial-service-evidence.md) | 真实动作进度、完整局与奖励状态原子保存、回调漂移拒绝和恢复 | Verified Locally / Main routing and guided policy separate |
| [P16 Compatible Content Rebinding Evidence](current/2026-10-05-p16k-content-rebinding-evidence.md) | 已认证旧内容指纹迁移、整档案保留、物理保存故障与并发回调拒绝 | Verified Locally / Current |
| [P16 Registry Activation Evidence](current/2026-10-05-p16m-registry-activation-evidence.md) | 正式激活 431 条目录、40 遭遇配方、领域整组校验与 76 个完整性摘要 | Verified Locally / Complete native certification pending |
| [P16 Player Frame Observer Evidence](current/2026-10-05-p16-player-frame-observer-evidence.md) | Player 成功帧通知、冻结输入读取、Replay 恢复失效与 11 场景回归 | Verified Locally / Tutorial UI integration pending |
| [P16 Native Narrative Retention Evidence](current/2026-10-05-p16j-native-narrative-retention-evidence.md) | 原生叙事来源、HP 支付、完整局/奖励参与者保存、冻结开局和终局恢复 | Verified Locally / Main integration pending |
| [P16 Durable Host Startup Evidence](current/2026-10-05-p16-durable-host-startup-evidence.md) | 保存后开局发布、冷启动重试、回调身份复检与下一层恢复等待 | Verified Locally / Main integration pending |
| [P16 Native Hub Scene Evidence](current/2026-10-05-p16-native-hub-shell-evidence.md) | 三个像素场景、原生移动与九目的地、48 张渲染截图 | Verified Locally / Business panels pending |
| [P16 Hub Business Evidence](current/2026-10-05-p16-hub-business-evidence.md) | 权威档案业务入口、闭合可用性与成本投影、配装和离线出发 | Verified Locally / Native panel certification separate |
| [P16 Production Profile Boot Evidence](current/2026-10-05-p16-production-profile-boot-evidence.md) | 真实内容指纹、已核验历史迁移、权威进度镜像与未知内容拒绝 | Verified Locally / Full resume pending |
| [P16 Actual Content Compatibility Evidence](current/2026-10-05-p16-actual-content-compatibility-evidence.md) | 原始与 Hub 历史内容版本、Git 来源审计与全部物理保存故障补偿 | Verified Locally / Pinned localization-only upgrades |
| [P16 Training Content Compatibility Evidence](current/2026-10-05-p16-training-content-compatibility-evidence.md) | 四训练翻译键、三个真实历史档案升级与完整指纹认证 | Verified Locally / Exact localization-only upgrades |
| [P16 Encounter Timer Evidence](current/2026-10-05-p16-encounter-timer-evidence.md) | 原生计时器、暂停继承、退出取消与零泄漏房间退役 | Verified Locally / Current |
| [P16 Main Profile Flow Evidence](current/2026-10-05-p16-main-profile-flow-evidence.md) | 正式耐久开局、真实死亡结算、保存重试和下一局身份 | Verified Locally / Victory and full resume pending |
| [P16 Native Hub Flow Evidence](current/2026-10-05-p16-native-hub-flow-evidence.md) | Main 首屏、九面板、真实购买和锻造、手柄入口与原生画面 | Verified Locally / Training and optional providers pending |
| [P16 Tutorial Flow Design](superpowers/specs/2026-10-05-plane-walker-p16n-tutorial-flow-design.md) | 真实观察器、课程回顾、原生提示与暂停身份设计 | Approved / Current |
| [P16 Tutorial Flow Plan](superpowers/plans/2026-10-05-plane-walker-p16n-tutorial-flow.md) | 原生教学协调器与保存失败验证实施计划 | Implemented / Current |
| [P16 Tutorial Flow Evidence](current/2026-10-05-p16n-tutorial-flow-evidence.md) | 真实成功帧、物理保存、课程回顾与原生提示生命周期 | Verified Locally / Training and guided runs pending |
| [P16 Native Narrative Flow Design](superpowers/specs/2026-10-05-plane-walker-p16o-native-narrative-flow-design.md) | 真实原生来源接触、胜利通行、结局保存和字幕身份 | Approved / Current |
| [P16 Native Narrative Flow Plan](superpowers/plans/2026-10-05-plane-walker-p16o-native-narrative-flow.md) | 原生剧情协调器、失败重试和终局流程实施 | Active / Current |
| [P16 Native Narrative Evidence](current/2026-10-05-p16o-native-narrative-evidence.md) | 真实接触、保存故障、过期回调、恢复与中英文原生渲染 | Verified Locally / Main handoff separate |
| [P16 Main Narrative Flow Evidence](current/2026-10-05-p16-main-narrative-flow-evidence.md) | 正式最终碎片、结局、物理结算重试、片尾重启恢复与房间正确呈现 | Verified Locally / Five-boss combat separate |
| [P16P Native Training Evidence](current/2026-10-05-p16p-native-training-evidence.md) | 150 个实际练习配置、五武器成功帧、一次性训练奖励与保存补偿 | Verified Locally / Arena and T05 separate |
| [P16Q Native Checkpoint Evidence](current/2026-10-05-p16q-native-checkpoint-evidence.md) | 原生入口、奖励待选、死亡、World payload 的物理冷恢复与失败补偿 | Verified Locally / Live combat separate |
| [P16 Main Native Resume Evidence](current/2026-10-05-p16-main-native-resume-evidence.md) | 据点实际继续按钮、同局物理恢复、安全点保存和完整玩家状态保持 | Verified Locally / Live combat separate |
| [P16R Training Arena Design](superpowers/specs/2026-10-05-plane-walker-p16r-training-arena-design.md) | 原生演练场、Boss 转化目标、配置与手柄流程设计 | Approved / Current authority |
| [P16R Training Arena Plan](superpowers/plans/2026-10-05-plane-walker-p16r-training-arena.md) | 可玩训练场及真实目标验证记录 | Completed / Historical |
| [P16R Training Arena Evidence](current/2026-10-05-p16r-training-arena-evidence.md) | 真实训练目标、Boss 前摇转化、一次性奖励和八种原生画面合同 | Verified Locally / Production Boss integration separate |
| [Content Pack Export Evidence](current/2026-10-05-content-pack-export-evidence.md) | 导出原始认证字节、PCK 实际大厅开局和角色原生导入资源 | Verified Locally / Formal template builds separate |
| [P15N Production Launch Encounters Design](superpowers/specs/2026-10-05-plane-walker-p15n-production-launch-encounters-design.md) | 正式遭遇生成、统一动作帧与原生敌人桥接合同 | Approved / Current authority |
| [P15N Production Launch Encounters Plan](superpowers/plans/2026-10-05-plane-walker-p15n-production-launch-encounters.md) | 正式战斗生成与角色生命周期接线计划 | Active / Current |
| [P15N Production Launch Encounters Evidence](current/2026-10-05-p15n-production-launch-encounter-evidence.md) | 真实 Main 生成、统一动作帧、最终死亡和奖励生命周期验证 | Verified Locally / Remaining combat gates active |
| [P15E Native Event Ambush Design](superpowers/specs/2026-10-05-plane-walker-p15e-native-event-ambush-design.md) | 事件伏击原生生成和精确完成身份约束 | Approved / Current authority |
| [P15E Native Event Ambush Plan](superpowers/plans/2026-10-05-plane-walker-p15e-native-event-ambush.md) | 事件选择、提交、敌人生成及回滚接线 | Active / Current |
| [P15E Native Event Ambush Evidence](current/2026-10-05-p15e-native-event-ambush-evidence.md) | 真实 Main 事件战斗和续行身份验证 | Verified Locally / Combined certification separate |
| [P15C Complete Enemy Domain Plan](superpowers/plans/2026-10-05-plane-walker-p15c-complete-enemy-domain.md) | 二十二敌人机制、动作时间轴和最终死亡实施 | Active / Current |
| [P15C Complete Enemy Domain Evidence](current/2026-10-05-p15c-complete-enemy-domain-evidence.md) | 二十二敌人领域时间轴、Guard/Hound 首次致死与原生事务验证 | Verified Locally / Complete native mechanisms separate |
| [P15D Native Semantic Effects Plan](superpowers/plans/2026-10-05-plane-walker-p15d-native-semantic-effects.md) | 原生治疗、区域、位移和增益的真实效果事务 | Active / Current |
| [P15D Native Semantic Effects Evidence](current/2026-10-05-p15d-native-semantic-effects-evidence.md) | 双演员真实治疗、原子区域预算和控制生命周期验证 | Verified Locally / Constructs and death effects active |
| [P15B Native Boss Runtime Plan](superpowers/plans/2026-10-05-plane-walker-p15b-native-boss-runtime.md) | 五首领固定帧、原生演员及完整动作效果实施 | Active / Current |
| [P15B Native Boss Foundation Evidence](current/2026-10-05-p15b-native-boss-foundation-evidence.md) | 五首领动作、实际玩家帧桥接、资源显示和回滚验证 | Verified Locally / Full effects pending |
| [P15B Native Boss Temporal Evidence](current/2026-10-05-p15b-native-boss-temporal-evidence.md) | 时之首领真实生命恢复、固定落点、阻挡和整帧失败补偿 | Verified Locally / Arena constructs active |
| [P15E Native Mixed Hazard Work Evidence](current/2026-10-05-p15e-native-mixed-hazard-work-evidence.md) | 语义危险区死亡后所有权、共享区域预算、完整预警与清场补偿 | Verified Locally / Constructs active |
| [P15B Native Time Watch Evidence](current/2026-10-05-p15b-native-watch-evidence.md) | 真实武器弱点代理、80 伤害打断、55 帧恢复、致死补偿与冷重建 | Verified Locally / Remaining arena mechanics active |
| [Native Boss Arena Constructs Plan](superpowers/plans/2026-10-05-native-boss-arena-constructs.md) | 可破坏原生掩体、场地构造物、接受帧补偿和版本化冷恢复 | Active / Current |
| [P15B Native Ruin Cover Evidence](current/2026-10-05-p15b-native-ruin-cover-evidence.md) | 四个物理掩体、五武器命中、冲锋碰撞和当前/历史冷恢复 | Verified Locally / Remaining arena mechanics active |
| [P15B Native Ruin Aftershock Evidence](current/2026-10-05-p15b-native-ruin-aftershock-evidence.md) | 延迟余震独立预警、真实伤害、区域预算、所有权退役和冷恢复 | Verified Locally / Dynamic geometry active |
| [Native Elite Affixes Plan](superpowers/plans/2026-10-05-native-elite-affixes.md) | 十词缀的真实 Health、控制、动态效果和生产冷恢复 | Active / Current |
| [Native Static Elite Affix Evidence](current/2026-10-05-native-static-elite-affix-evidence.md) | 狂暴和坚固真实伤害、Health、运动与生产历史冷恢复 | Verified Locally / Dynamic affixes active |
| [Runtime Line Coverage Provider Plan](superpowers/plans/2026-10-05-runtime-line-coverage-provider.md) | 语法树插桩、隔离原生运行和原始源码行命中证据 | Active / Current |
| [P17A Actor Atlases Design](superpowers/specs/2026-10-05-plane-walker-p17a-actor-atlases-design.md) | 五角色与五首领原始像素动画资源合同 | Approved / Current authority |
| [P17A Actor Atlases Plan](superpowers/plans/2026-10-05-plane-walker-p17a-actor-atlases.md) | 确定性图集生产、许可、逐帧和原生加载验证 | Active / Current |
| [P17A Actor Atlases Evidence](current/2026-10-05-p17a-actor-atlases-evidence.md) | 十套动画、240 帧、来源、哈希与真实 Godot 图集验证 | Verified Locally / Gameplay integration separate |
| [P17B Original Music Design](superpowers/specs/2026-10-05-plane-walker-p17b-original-music-design.md) | 十五首原创循环与游戏状态只读投影 | Approved / Current authority |
| [P17B Original Music Plan](superpowers/plans/2026-10-05-plane-walker-p17b-original-music.md) | 音频生成、双轨切换、暂停与真实 Main 验证 | Active / Current |
| [P17B Original Music Evidence](current/2026-10-05-p17b-original-music-evidence.md) | 十五首循环、字节复现、真实 Main 与 PCK 播放和暂停验证 | Verified Locally / Combined certification separate |
| [P17C Launch Enemy Presentation Plan](superpowers/plans/2026-10-05-plane-walker-p17c-launch-enemy-presentation.md) | 二十二敌人原创像素资源、缺失原生场景与实际渲染验证 | Active / Current |
| [P17C Launch Enemy Presentation Evidence](current/2026-10-05-p17c-launch-enemy-presentation-evidence.md) | 二十二敌人造型、十八场景、真实窗口和 PCK 资源验证 | Verified Locally / Combat certification separate |
| [P18A Local Content Management Design](superpowers/specs/2026-10-05-plane-walker-p18a-local-content-management-design.md) | 离线 Mod 和 DLC 发现、启停、权利接口与存档隔离 | Approved / Current authority |
| [P18A Local Content Management Plan](superpowers/plans/2026-10-05-plane-walker-p18a-local-content-management.md) | 安全内容安装、实际 Registry 激活与独立存档域实施 | Active / Current |
| [P18A Local Content Management Evidence](current/2026-10-05-p18a-local-content-management-evidence.md) | 离线安装、原子启停、权利边界和独立存档域验证 | Verified Locally / Main integration pending |
| [P18B Native Content Management Plan](superpowers/plans/2026-10-05-plane-walker-p18b-native-content-management.md) | Hub 内容包控制、真实启动程序集与独立冒险存档接线 | Active / Current |
| [P18B Native Content Management Evidence](current/2026-10-05-p18b-native-content-management-evidence.md) | 实际内容启停、冷恢复、独立结算、本体字节保护及原生界面与 PCK 验证 | Verified Locally / Combined certification active |
| [P19 Packaged Startup Plan](superpowers/plans/2026-10-05-plane-walker-p19-packaged-startup.md) | 实际三平台发行包和独立主场景启动认证 | Active / Current |
| [P19 Packaged Startup Evidence](current/2026-10-05-p19-packaged-startup-evidence.md) | 三个真实发行包、认证哈希与 macOS 原生十二项启动检查 | Verified Locally / Clean combined certification active |
| [P19 Corpse Content Compatibility Evidence](current/2026-10-05-p19-corpse-content-compatibility-evidence.md) | 泰坦尸体池数据绑定、保留原始描述及旧档案物理兼容验证 | Verified Locally / Current |
| [P20A Build Sharing Design](superpowers/specs/2026-10-05-plane-walker-p20a-build-sharing-design.md) | 离线配装码、严格解码、档案解锁和原生冥想室合同 | Approved / Current authority |
| [P20A Build Sharing Plan](superpowers/plans/2026-10-05-plane-walker-p20a-build-sharing.md) | 150 组合、原子导入导出和实际控制的实施记录 | Implemented / Current |
| [P20A Native Build Sharing Evidence](current/2026-10-05-p20a-native-build-sharing-evidence.md) | 150 配装往返、实际导入导出、保存补偿、剪贴板和八种原生画面 | Verified Locally / Current |
| [P20B Local Records Design](superpowers/specs/2026-10-05-plane-walker-p20b-local-records-design.md) | 可信终局收据、内容/存档域隔离和离线排行合同 | Approved / Current authority |
| [P20B Local Records Plan](superpowers/plans/2026-10-05-plane-walker-p20b-local-records.md) | 本地排行原子保存、去重、重启、Main 和原生 Hub 实施 | Active / Current |
| [P20B Local Records Evidence](current/2026-10-05-p20b-local-records-evidence.md) | 真实终局排行、持久队列、物理确认与原生战绩窗口 | Verified Locally / Modes and global providers pending |
| [P21A Native Boss Rush Design](superpowers/specs/2026-10-05-p21a-native-boss-rush-design.md) | 独立挑战状态、真实五 Boss 序列、阶段保存与普通成长隔离 | Approved / Current authority |
| [P21A Native Boss Rush Plan](superpowers/plans/2026-10-05-p21a-native-boss-rush.md) | 原生 Boss Rush、物理继续、失败重试和据点入口实施 | Active / Current |
| [P16 Native Training Design](superpowers/specs/2026-10-05-plane-walker-p16p-native-training-design.md) | 隔离练习、真实动作认证与一次性档案奖励 | Approved / Current |
| [P16 Native Training Plan](superpowers/plans/2026-10-05-plane-walker-p16p-native-training.md) | 实体训练、保存失败恢复与原生教学入口实施 | Active / Current |
| [P16 Native Checkpoint Design](superpowers/specs/2026-10-05-plane-walker-p16q-native-checkpoint-design.md) | 真实安全快照、关闭重建与严格冷恢复 | Approved / Current |
| [P16 Native Checkpoint Plan](superpowers/plans/2026-10-05-plane-walker-p16q-native-checkpoint.md) | 原生房间、玩家、档案与领域事务恢复 | Active / Current |
| [P16R Native Combat Checkpoint Design](superpowers/specs/2026-10-05-plane-walker-p16r-native-combat-checkpoint-design.md) | 活跃战斗的原生演员、效果和威胁冷恢复合同 | Approved / Current authority |
| [P16R Native Combat Checkpoint Plan](superpowers/plans/2026-10-05-plane-walker-p16r-native-combat-checkpoint.md) | 战斗快照、重建、失败补偿与教学保存回归实施 | Active / Current |
| [P16R Native Combat Checkpoint Evidence](current/2026-10-05-p16r-native-combat-checkpoint-evidence.md) | 十一种战斗冷续跑、篡改拒绝与旧版安全存档/教学回归 | Verified Locally / Current |
| [P16S Native Content Migration Design](superpowers/specs/2026-10-05-plane-walker-p16s-native-content-migration-design.md) | 已认证历史内容与活跃原生战斗的重建和原子迁移合同 | Approved / Current authority |
| [P16S Native Content Migration Plan](superpowers/plans/2026-10-05-plane-walker-p16s-native-content-migration.md) | 全档案迁移、物理保存故障和无发布探测的实施记录 | Active / Current |
| [P16S Native Content Migration Evidence](current/2026-10-05-p16s-native-content-migration-evidence.md) | 六历史来源、24次实际迁移、重签篡改拒绝及枪杖无发布验证 | Verified Locally / Current |
| [P16G Native Material Evidence](current/2026-10-05-p16g-native-material-evidence.md) | 原生敌人死亡认证、材料保留重试与真实结算金额 | Verified Locally / Main integration pending |
| [P14E Launch Economy and Merchants Evidence](current/2026-10-02-p14e-launch-economy-merchants-evidence.md) | 原子经济、五商人、八类服务、楼层结算、Save/Replay、真实商店链路与 197 场景整库认证 | Verified Locally / Current |
| [P11A Shared Weapon Authority Evidence](current/2026-09-29-p11a-shared-weapon-authority-evidence.md) | Profile、Coordinator、语义输入、Modifier、typed facts、完整性及 69 场景全量认证 | Verified Locally / Current |
| [P11B Sword Migration Evidence](current/2026-09-29-p11b-sword-migration-evidence.md) | Sword Coordinator 迁移、M1 帧表/伤害权威、Active cue、输入优先级及 73 场景全量认证 | Verified Locally / Current |
| [P11C Bow Candidate Migration Evidence](current/2026-09-29-p11c-bow-candidate-evidence.md) | Bow Candidate 同 token HOLD/release、道具能力迁移、反馈、legacy 时钟退休及 75 场景全量认证 | Verified Locally / Current |
| [P11C Launch Bow L2 Evidence](current/2026-09-29-p11c-bow-launch-evidence.md) | Launch 四档蓄力、五动作、四时间联动、Chrono Warden 转换、确定性 payload、清理边界与 82 场景全量认证 | Verified Locally / Current |
| [P11D Launch Gun Evidence](current/2026-09-29-p11d-gun-launch-evidence.md) | 枪械弹药/换弹、三种射击、Time Load、Void Penetration、四时间联动、HUD/反馈、生命周期与 88 场景全量认证 | Verified Locally / Current |
| [P11E Launch Staff Evidence](current/2026-09-29-p11e-staff-launch-evidence.md) | 法杖 Mana/三元素/六组合、真实效果、四时间联动、Boss 转换、HUD/反馈、有界生命周期与 97 场景整库认证 | Verified Locally / Current |
| [P11F Launch Gauntlets Evidence](current/2026-09-30-p11f-gauntlets-launch-evidence.md) | 拳套五连段/Combo、四时间联动、Boss 韧性转换、真实命中/区域、HUD/Pixel Proxy/反馈、原子恢复与 103 场景整库认证 | Verified Locally / Current |
| [P11 Five Complete Weapons Evidence](current/2026-09-30-p11-five-weapons-evidence.md) | 五武器统一 HUD、Launch Loadout UI、capability 道具、确定性 Replay、30 组合矩阵、900 synthetic samples 与 113 场景最终认证 | Verified Locally / Current |
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
