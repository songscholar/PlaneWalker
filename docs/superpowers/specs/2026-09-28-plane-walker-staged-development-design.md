# Plane Walker 全量愿景与分阶段并行开发设计

- Status: Approved
- Authority Level: Milestone design and cross-module contract
- Applies To: M0 文档治理与 M1 五房垂直切片
- Implementation Status: Wave 0/1 foundation verified; legacy runtime integration pending
- Owner: Project integration lead
- Depends On: docs/0_深度收敛与系统职责设计.md
- Supersedes: 现有文档中与 M1 范围、五房节奏、UI 契约、状态迁移相冲突的执行口径
- Last Verified: 2026-09-28

## 1. 决策摘要

Plane Walker 保留完整产品愿景，不永久删除现有角色、武器、时间能力、流派、五层地牢、敌人、Boss、事件、商店、局外成长、叙事、外观、排行、回放、Mod、DLC 或其他已设计内容。

范围控制采用“分阶段启用”，而不是“内容删减”：

- Current：当前必须实现和验收。
- Next：当前保留接口和数据兼容性，下一阶段启用。
- Launch：首发完整愿景。
- Expansion：EA、DLC 或长期扩展。
- Archive：旧规则或旧引擎方案，只作历史参考。

首个正式里程碑 M1 是一块生产级垂直切片：

- 一局 8–12 分钟。
- 固定五个房间。
- 一个角色、一个主武器、两个时间能力。
- 三条完整可成型流派。
- 三种普通敌人、一个精英、一个 Boss。
- 完整 HUD、选择、暂停、死亡、胜利和快速重开。
- 后端玩法、战斗、UI 和像素美术能够依据冻结契约并行开发。

M1 通过后，完整内容按依赖顺序逐步从 Next 或 Launch 提升为新的 Current。

## 2. 核心概念优化

完整产品的一句话体验定义为：

> 玩家在崩塌位面中观察威胁、承诺动作、扭曲时间，并把创造出的时间窗口转化为伤害、站位或风险收益。

时间能力不是四个独立的强力按钮，而是四种不同的战斗语法：

| 能力 | 战术职责 | 不应退化为 |
|---|---|---|
| 时间停止 | 改变敌人的时间，创造输出窗口和弹幕路径 | 普通全屏眩晕 |
| 时间回溯 | 改变玩家的时间，预设位置并承担风险后返回 | 免费治疗或撤销全部失败 |
| 时间加速 | 压缩自己的节奏，用更高操作压力换收益 | 普通攻速增益 |
| 时间裂隙 | 改造路径、区域和弹幕流向 | 普通范围减速 |

M1 只启用时间停止和时间回溯，但时间加速和时间裂隙的设计、数据和原型代码继续保留为 Next。

核心概念 Gate：

- 玩家能清楚说出停止与回溯的用途差异。
- 时间技能使用后存在可识别的“收益转化动作”。
- 两个技能不能都被玩家描述成“危险时按一下保命”。
- Boss 必须让两个技能都产生正向策略价值。

## 3. 产品范围分层

### 3.1 Current：M1 五房垂直切片

当前启用：

- 角色：行者。
- 武器：剑。
- 时间能力：停止、回溯。
- 普通敌人：追击者、坦克、射手。
- 精英：一个基础敌人的机制型变体。
- Boss：时序守卫。
- 流派：时停爆发、回溯残影、剑势节奏。
- 通用补短板：防御、能量、回复。
- 系统：固定房间、奖励草拟、祝福、天赋、风险契约、死亡与胜利结算。

### 3.2 Next

- 弓。
- 时间裂隙或时间加速；二者不在同一里程碑同时启用。
- 事件房。
- 第二个 Boss。
- 更完整的角色和武器选择。
- 小地图、重 Roll、Build 详情。
- 完整键位重映射和可访问性设置。

### 3.3 Launch

- 五角色、五武器、四种时间能力。
- 五层地牢与五个 Boss。
- 八条首发核心流派。
- 40–60 个首发道具。
- 25–30 个祝福。
- 15–18 个诅咒。
- 五路线核心天赋。
- 商店、事件、Hub、局外成长、完整叙事和多结局。

### 3.4 Expansion

- 扩展道具池和流派变体。
- Boss Rush、每日挑战、无尽模式。
- Mod、排行、回放和社交功能。
- 外观、长期运营和 DLC。
- 付费抽卡保留为商业模型 Decision Gate，不自动进入首发承诺；需在核心玩法、玩家定位、平台规则和商业研究完成后单独批准。

## 4. 文档治理

### 4.1 权威优先级

发生冲突时按以下顺序执行：

1. 已批准的 ADR。
2. 已批准的 Current 里程碑规格。
3. contracts 目录中的接口与数据契约。
4. 当前系统开发文档。
5. Full Vision GDD。
6. Reference 与 Archive。

上层愿景决定“为什么做”，Current 决定“现在做什么”，Contract 决定“模块如何互通”。

### 4.2 文档状态

每份有效文档必须标记：

- Status。
- Authority Level。
- Applies To。
- Implementation Status。
- Owner。
- Depends On。
- Supersedes。
- Last Verified。
- Contract References。

未标状态的文档不得作为智能体或开发者的实现依据。

### 4.3 推荐文档入口

第一轮采用原地治理，不立即搬动全部 47,000 多行旧文档：

- docs/README.md：唯一入口和状态表。
- docs/current/：当前里程碑、验收标准和 Known Gaps。
- docs/contracts/：玩法状态、UI ViewModel、奖励 Offer、事件目录。
- docs/adr/：已裁决的设计和架构决策。
- docs/dev/：与当前 Godot 工程一致的实现说明。
- docs/archive/：第二轮再迁移的旧规则和旧引擎内容。

### 4.4 M0 文档治理验收

- docs/README.md 能在五分钟内回答当前做什么、以后做什么、每个模块看哪份文档。
- 所有非 Archive 文档具有标准页头。
- 不存在两个 Current 文档对同一规则给出不同数值。
- Active Godot 文档中不存在 Unity API、Unity 组件或不可执行的伪 Godot C#。
- 所有 Markdown 相对链接有效。
- Current 文档没有 TBD、TODO 或不可测试的验收语句。
- 每个 Current 功能都有负责人、依赖和对应测试。
- GDD 中错误的 combat-system-design.md 链接被修正为实际文件。
- 1920×1080 绝对坐标表降级为视觉参考，不再作为布局契约。

## 5. M1 五房节奏

M1 的唯一权威顺序为：

| 阶段 | 目的 | 目标耗时 | 清房结果 |
|---|---|---:|---|
| 开始提示 | 进入战斗，不使用长教学 | 15–30 秒 | 无 |
| 房间 1：基础战斗 | 学习移动、剑、闪避、停止 | 45–70 秒 | 三条路线各一个启动件 |
| 房间 2：组合战斗 | 近战压力与远程站位 | 60–85 秒 | 当前路线补强、转向、通用补短板 |
| 房间 3：压力战斗 | 多种威胁与资源管理 | 70–100 秒 | 天赋三选一，确定本局方向 |
| 房间 4：精英 | 验证 Build 与风险承担 | 90–125 秒 | 两份风险契约加安全拒绝 |
| 房间 5：Boss | 验证时间能力和 Build | 120–170 秒 | 直接胜利结算 |

节奏指标：

- 完整通关中位数 9 分 30 秒至 10 分 30 秒。
- 至少 80% 的通关局落在 8–12 分钟。
- P90 不超过 13 分钟。
- Boss 占通关时间的 22%–30%。
- 奖励选择占总时长的 10%–18%。
- 死亡到重新进入房间不超过 8 秒，最多两次操作。
- Boss 击败后不再发放无后续战斗价值的局内奖励。

事件系统继续保留，但不进入 M1 权威五房序列。

## 6. M1 流派与奖励草拟

### 6.1 三条验证流派

| 路线 | 启动方式 | 补强方式 | Boss 转化 |
|---|---|---|---|
| 时停爆发 | 延长停止或降低成本 | 凝滞弱点 | 剑第三段或重击兑现暴露窗口 |
| 回溯残影 | 回溯路径留下残影 | 路径穿越伤害或诱导 | 回溯穿越弱点、处理裂纹危机 |
| 剑势节奏 | 连段、终结、闪避蓄能 | 剑势祝福或处决天赋 | 保持完整连段并换取时间收益 |

完整八流派继续保留在 Launch 内容注册表中。

### 6.2 奖励 Offer 规则

- 奖励 1：三条路线各一个启动件。
- 奖励 2：至少一个匹配当前路线的补强、一个转向启动件、一个通用补短板。
- 奖励 3：至少一个匹配当前路线的天赋、一个替代路线、一个通用生存方案。
- 未装备武器或未启用时间技能的专属内容不得进入 M1 默认池。
- 已选择内容不得重复出现。
- Payoff 不应在对应 Starter 尚未获得且没有通用意义时出现。

自动验收：

- 1,000 个种子中，100% 第一轮能够启动有效路线。
- 95% 以上种子在 Boss 前存在“同路线至少两件 + 一个通用补短板”的可选路径。
- 零个种子出现三个均不适用的选项。
- 零个重复奖励或无效依赖奖励。

试玩验收：

- 8/10 测试者在 Boss 前能用一句话描述自己的 Build。
- 奖励选择中位耗时 10–25 秒，P90 不超过 45 秒。
- 同一玩家连续三局至少形成两种可感知不同的打法。

### 6.3 风险契约

风险契约由不可拆分的收益与代价组成：

- 房间 4 后提供两个契约和一个拒绝选项。
- 拒绝后直接进入 Boss，不补发普通奖励。
- 契约收益目标为 20%–35% 峰值能力提升。
- 代价目标为 10%–25% 有效生存压力，或改变资源、站位和操作规则。
- 代价不能被契约自身动作自动撤销。
- 契约必须能在随后的 Boss 战中实际触发。

接受率目标为 35%–70%；单个契约选择率不得超过全部选项的 70%。

## 7. 目标架构

本文中的“后端”指本地玩法、状态、内容和数据逻辑，不引入联网服务器。前端指 Godot UI、表现和交互层。

依赖方向：

```text
Presentation/UI
→ Application/Orchestration
→ Domain Systems
→ Infrastructure/Scene Adapters
```

禁止反向依赖：

- 领域逻辑不得引用 UI 节点。
- UI 不得直接修改 GameState、玩家属性或房间阶段。
- 奖励面板不得调用 player.apply_reward 或 apply_curse。
- EventBus 不得承担需要返回成功或失败结果的 Command。
- 选择、死亡和房间推进由应用层统一提交。

### 7.1 模块职责

| 模块 | 唯一职责 |
|---|---|
| RunOrchestrator | 一局生命周期、阶段迁移、命令校验 |
| RunState | 本局唯一权威数据 |
| DungeonDirector | 房间顺序、房间定义、节奏配置 |
| RoomRuntime | 刷怪、存活计数、战场安全清理 |
| PlayerActionController | 输入缓冲、动作状态、取消窗口 |
| Combat | 伤害、暴击、防御、命中、生命状态 |
| TimeAbilityService | 能量、冷却、停止和回溯结算 |
| BuildState | 已持有内容、流派权重、历史 |
| DraftService | 生成和消费唯一奖励 Offer |
| EffectService | 应用已验证的 EffectSpec |
| ContentRegistry | 加载、索引和验证内容 |
| UI Shell | 渲染 ViewState、发送 Intent |
| SaveService | 版本、迁移、原子写入、恢复 |

### 7.2 渐进迁移

不推倒现有可玩闭环：

| 当前实现 | M1 目标 |
|---|---|
| 任意模块可 set_phase | 只有 RunOrchestrator 可迁移 RunPhase |
| RoomController 同时刷怪、结算和推进 | 收敛为 RoomRuntime |
| RewardSelection 抽取并直接施加效果 | 只渲染 SelectionOffer 并发送 Command |
| UI 每帧直接读取节点 | 只消费 RunViewState |
| signal 与 publish 双发 | 每个事实保留一条 typed signal |
| JSON 与代码常量双重数据源 | ContentRegistry 加载单一数据源 |
| 单个 863 行 smoke test | 拆成 unit、contract、integration、smoke |

兼容适配器可以临时存在，但新功能不得依赖适配器内部细节。

## 8. 状态机

### 8.1 RunPhase

- BOOT
- HUB
- RUN_PREPARING
- ROOM_ENTERING
- COMBAT_ACTIVE
- ROOM_RESOLVING
- SELECTION_ACTIVE
- ROOM_TRANSITION
- BOSS_ACTIVE
- VICTORY
- DEFEAT

PAUSED 不作为 RunPhase，而是独立 suspended 覆盖状态。

### 8.2 核心约束

- VICTORY 和 DEFEAT 是不可逆终止状态。
- 终止状态后，奖励、事件和延迟回调不能重新打开选择或修改结果。
- 进入 SELECTION_ACTIVE 前，敌人 AI、弹幕、地面危险和玩家受伤必须冻结或清理。
- 同一房间只能生成一次完成结果和一次 Offer。
- 同一 Offer 只能消费一次。
- 异步回调执行前重新校验 run_id、phase、revision 和对象有效性。

### 8.3 PlayerActionState

- FREE
- ATTACK_WINDUP
- ATTACK_ACTIVE
- ATTACK_RECOVERY
- DASH
- TIME_CAST
- HITSTUN
- DEAD

优先级：

DEAD > HITSTUN > DASH > TIME_CAST > ATTACK > FREE

手感契约：

- 输入缓冲 8 帧，60Hz 下约 0.133 秒。
- 连段续接窗口 12 帧，约 0.2 秒。
- 只有规格声明的恢复期允许闪避取消。
- Dash 期间默认不能启动普通攻击。
- 普通受击保护基线约 0.3 秒，最终值由试玩调整。
- 受击硬直、击退和无敌分别建模。
- 重叠无敌以最晚到期时间或 token 集合为准。

## 9. 时间能力规格

### 9.1 时间停止

基础目标：

- 消耗 35。
- 冷却 12 秒。
- 普通敌人停止 3 秒。
- 精英效果缩短。
- Boss 不完全冻结。

验收：

- 普通敌人 AI、移动和攻击计时均停止。
- 弹幕降低 90%–100%，恢复时无瞬移或叠帧命中。
- Boss 延后当前或下一招，并延长后摇至少 0.8 秒。
- 70% 以上正常使用在一秒内转化为命中、击杀、弱点攻击或弹幕穿越。
- Boss 战使用目标为 2–4 次。

### 9.2 时间回溯

回溯只恢复：

- 合法位置。
- 朝向和必要速度。
- HP。
- 可安全重置的玩家动作状态。

不恢复：

- 时之能量。
- 技能冷却。
- 道具、祝福、诅咒、天赋。
- 奖励、金币、房间状态。
- 敌人、弹幕、Boss 阶段和世界状态。

固定结算顺序：

1. 校验快照和施放条件。
2. 恢复允许回溯的玩家状态。
3. 扣除本次能量并进入冷却。
4. 结算诅咒自伤等代价。
5. 结算额外治疗、护盾或路径效果。
6. 发布一次完整结算事件。

关键不变量：

- 本次成本不能被快照覆盖。
- 诅咒代价不能被同一次回溯覆盖。
- 房间转换时清空快照。
- 无效位置回落到最近可站立点。
- 100 次边界测试中不得卡墙、越界或进入碰撞体。

## 10. 战斗手感 Gate

### 10.1 输入和动作

- 无阻塞输入到状态切换不超过一个物理帧。
- 合法缓冲输入执行率不低于 99%。
- 普攻 1→2→3 可稳定衔接。
- 五分钟训练后，至少 8/10 新玩家可连续完成三次完整连段。
- 普攻期间移动速度为基础的 45%–65%。
- 重击期间移动速度为 0%–30%。

### 10.2 命中和受击

- 命中视觉、音效、伤害数字和逻辑伤害在同一帧或下一帧出现。
- 普通命中停顿 2–3 帧。
- 终结击 4–5 帧。
- 重击 5–7 帧。
- 轻受击硬直 8–12 帧。
- 中受击 14–20 帧。
- 重受击 24–30 帧。
- 受击硬直结束后至少 15 帧保护。
- 无法解释的受伤或死亡低于 10%。
- 10 名外部测试者中，至少 80% 对响应性评分达到 4/5。

### 10.3 敌人辨识

| 敌人 | 行为 | 预警 |
|---|---|---:|
| 追击者 | 快速逼近、短蓄力、小范围 | 0.25–0.35 秒 |
| 坦克 | 停止移动、明显蓄力、大范围、长后摇 | 0.65–0.90 秒 |
| 射手 | 瞄准提示、发射后换位或保持距离 | 0.50–0.70 秒 |
| 精英 | 在基础角色上增加一种可学习机制 | 不得只增加数值 |

## 11. Boss Gate

Boss 中位时长 120–170 秒。

必须具备：

1. 重砸：停止延长后摇。
2. 径向或瞄准弹幕：停止形成安全通道。
3. 召唤碎片：停止可控场但不完全冻结 Boss。
4. 时间裂纹：回溯返回预设安全位置或触发路径 Build。

验收：

- 停止影响弹幕、召唤物、后摇中的至少两项。
- 回溯明确处理一种 Boss 危机，并存在进攻用法。
- 每招具有独立轮廓、颜色或声音提示。
- 不存在连续不可操作伤害超过最大 HP 40% 的组合。
- 80% 测试者能说出两项时间技能与 Boss 的正向交互。
- Boss 战低于 90 秒或高于 210 秒均视为节奏失败。

## 12. UI 与玩法契约

采用单向数据流：

```text
玩法领域状态
→ UI State Projector
→ 不可变 RunViewState
→ Godot UI View
→ 用户 Intent
→ Command Handler
→ 玩法领域状态
```

UI 只负责：

- 展示 ViewState。
- 播放视觉动画。
- 发送用户意图。
- 处理焦点、键鼠、手柄和可访问性。

UI 不负责：

- 抽取奖励。
- 修改玩家属性。
- 判断房间奖励类型。
- 设置 RunPhase。
- 查询 Player、HealthComponent、TimeManager、Weapon 或 Boss 节点。

### 12.1 冻结契约

RunViewState 至少包含：

- schema_version、revision、run_id、phase、suspended。
- run_time、room。
- player HP、能量、动作状态、技能冷却。
- build 内容和主流派。
- selection。
- boss。
- result。
- UI 可见性与输入 Flags。

SelectionOffer 至少包含：

- offer_id、revision、category。
- title_key、can_skip。
- options。
- 每个选项的 content_id、name_key、description_key、archetype、role、rarity、icon_id 和 effect summary。

Command：

- start_run。
- submit_selection。
- skip_selection。
- pause_run。
- resume_run。
- restart_run。
- return_to_hub。

CommandResult 标准错误码：

- INVALID_PHASE。
- STALE_REVISION。
- OFFER_CLOSED。
- OPTION_NOT_FOUND。
- ALREADY_CONSUMED。
- TERMINAL_STATE。
- CONTENT_NOT_AVAILABLE。
- SAVE_FAILED。

submit_selection 必须幂等；重复点击不能重复施加效果。

## 13. UI 与像素美术基准

### 13.1 技术基准

- 逻辑分辨率 640×360。
- 1280×720 使用整数 2 倍缩放。
- 1920×1080 使用整数 3 倍缩放。
- 基础瓦片 16×16。
- 常规角色 32×32 至 32×48。
- Boss 可使用 64×64 或组合 Sprite。
- 所有像素纹理默认 Nearest。
- 世界 Sprite、摄像机和关键特效对齐整数像素。
- 使用 Anchor、Container、Safe Area 和最小尺寸，不使用绝对 1080p 坐标作为布局真源。

### 13.2 像素基准房

独立基准房包含：

- 角色待机、移动、闪避、攻击、受击和死亡。
- 三种敌人剪影。
- 一套遗迹瓦片。
- 墙、障碍物、危险区和交互物。
- 时间停止和时间回溯。
- 攻击前摇、命中和受击反馈。
- HP、能量、技能图标、Boss 条。
- 一次三选一奖励。
- 中英文文本。
- 720p 与 1080p 截图基准。

资源成熟度：

- Greybox。
- Pixel Proxy。
- Final。

玩法只依赖资源 ID 和逻辑锚点，替换美术不得改变碰撞、攻击范围和动作时序。

## 14. 内容和数据契约

### 14.1 单一数据源

运行时内容只从 data 或未来统一 Resource 目录加载。禁止 JSON 与脚本常量维护两套完整内容。

开发启动时验证：

- ID 唯一。
- 必需字段齐全。
- name_key 和 description_key 在中英文存在。
- effect_id 有唯一处理器。
- 数值类型和范围有效。
- M1 条目只引用已启用武器、能力和机制。
- Starter、Amplifier、Risk、BossTool、Utility 角色合法。

M1 必需内容无效时阻止开始 Run；Next 或 Launch 内容无效时隔离条目并记录错误。

### 14.2 随机数

所有玩法随机数从 Run seed 派生，并区分 channel：

- room。
- spawn。
- draft。
- combat。
- event。

UI 动画和视觉粒子不得消耗玩法 RNG。

相同版本、seed 和选择历史必须产生相同房间与 SelectionOffer。

## 15. 错误处理与诊断

错误等级：

| 等级 | 示例 | 行为 |
|---|---|---|
| 启动阻塞 | M1 必需内容缺失 | 禁止开始 Run，显示可读错误 |
| 内容隔离 | 单个 Next 条目无效 | 禁用条目，其他内容继续 |
| Command 拒绝 | 重复点击、旧 Offer、非法状态 | 返回失败，不修改状态 |
| 不变量破坏 | 终止态重新进入战斗 | 开发版立即失败，发行版记录并回到安全状态 |

要求：

- 日志包含 run_id、phase、room、command 或 event、content_id。
- 不允许在可能损坏状态时只 push_warning 后继续。
- 选择、死亡和胜利使用 revision 或 token 防迟到回调。
- 存档使用临时文件写入后原子替换。
- 保留上一份有效备份。
- 存档具有 schema_version 和显式迁移。
- 损坏文件不得在没有诊断副本时被默认存档覆盖。

## 16. 多智能体并行所有权

最多四条同时活动的工作流：

### 16.1 集成与规格负责人

拥有：

- docs/current、docs/contracts、ADR。
- 跨模块状态机。
- project.godot。
- 主场景、autoload 和总装文件。
- 合并、回归和最终验收。

### 16.2 工程与 Run/Build 智能体

负责：

- ContentRegistry。
- RunState 和 RunOrchestrator。
- DungeonDirector、DraftService、EffectService。
- Seed、存档、数据校验和逻辑测试。

### 16.3 战斗与时间智能体

负责：

- PlayerActionController。
- Combat、Health、Damage。
- TimeAbilityService。
- 敌人和 Boss。
- 战斗、时间和场景集成测试。

### 16.4 UI 与像素表现智能体

负责：

- 独立 UI 场景、Theme、Presenter。
- ViewModel Fixture。
- HUD、统一选择、暂停、结算。
- Pixel Proxy、图标、基准房和视觉反馈。

共享 contracts、fixtures、main scene 和 autoload 只由集成负责人修改。

UI 必须先从 combat_room_01.tscn 中提取为独立场景，避免 UI 和地牢智能体同时编辑同一总装文件。

## 17. 实施波次

### Wave 0：文档与契约冻结

- 建立 docs/README.md。
- 标记 Current、Next、Launch、Expansion、Archive。
- 冻结五房节奏、两个时间技能和三条流派。
- 冻结 RunViewState、SelectionOffer、CommandResult。
- 建立普通战斗、低血、冷却、Boss、选择、死亡和胜利 Fixture。

### Wave 1：共享底座与 UI 空壳并行

工程：

- ContentRegistry、SeedService、RunState、RunOrchestrator。
- CommandResult 和 revision。
- 测试目录拆分。

UI：

- UI Shell、Theme、像素字体、布局。
- Fixture 驱动 HUD、选择、暂停和结算。

### Wave 2：两条玩法流并行

战斗流：

- 动作状态机、输入缓冲、取消窗口。
- 暴击、防御、无敌 token。
- 停止与回溯正确结算。
- 敌人前摇、后摇和反馈。

Run/Build 流：

- 五房 Director。
- 三条流派。
- 风险契约。
- 房间安全结算。
- Boss 结束和 RunResult。

### Wave 3：集成

- 真实 ViewState 替换 Fixture Provider。
- Intent 接入 Command Handler。
- 验证重复输入、死亡竞态、暂停和房间转换。
- 固定 seed 五房测试。

### Wave 4：像素基准与试玩

- 640×360 逻辑画布与整数缩放。
- Pixel Proxy 基准房。
- 调整房间时长、能量、奖励权重和 Boss 窗口。
- 10 名非开发测试者，每人至少两局。

## 18. 测试策略

测试分层：

- unit/combat。
- unit/time_system。
- unit/progression。
- unit/dungeon。
- unit/core。
- contract/content_schema。
- contract/localization。
- contract/ui_view_state。
- integration/run_state_machine。
- integration/reward_flow。
- integration/death_and_terminal。
- integration/combat_time_interactions。
- smoke/m1_full_run。
- smoke/scene_load。
- fixtures/ui。

核心要求：

- 可测试核心逻辑覆盖率不低于 80%。
- 同一个 Offer 连续提交两次只应用一次。
- 奖励期间伤害事件为零。
- 弹丸一次接触只造成一次伤害。
- 多个无敌效果按最晚到期结束。
- 回溯不恢复能量、冷却和世界状态。
- Boss 死亡直接进入 VICTORY。
- 玩家死亡后迟到回调不能离开 DEFEAT。
- Headless smoke 退出码为 0。
- 无未处理错误、孤儿节点或 ObjectDB leak。

自动测试不能替代手感测试。

## 19. M1 最终放行标准

工程：

- 30 个固定种子的完整流程中无崩溃、脚本错误、软锁或无法结算。
- DEFEAT、VICTORY 不可被迟到回调逆转。
- 选择期间不存在敌对伤害。
- 单一数据源、单一事件发布和合法状态迁移通过测试。

玩法：

- 至少 80% 通关局处于 8–12 分钟。
- 至少 80% 玩家使用过停止和回溯。
- 至少 80% 玩家能描述自己的 Build。
- 至少 80% 玩家能指出两项 Boss 时间交互。
- 无法解释的受伤或死亡低于 10%。
- 响应性评分达到 4/5 的测试者至少 80%。
- 至少 60% 测试者主动再次开始或明确愿意再玩一局。

UI 与像素表现：

- 720p 和 1080p 无模糊、非整数拉伸或关键文本截断。
- 中英文、键鼠和基础手柄焦点均可完成 Current 流程。
- 最终美术未完成时，Pixel Proxy 仍可完整试玩。
- 时间能力、敌方危险和治疗区域具有不同形状、动画与声音语言。

任一情况触发 No-Go：

- 存在回溯资源漏洞、阶段回退、奖励期间死亡或重复奖励应用。
- 超过 20% 的局在 Boss 前没有可描述 Build。
- 两个时间技能被认为用途相同。
- Boss 时间交互不可见，或时间停止可以跳过主要机制。
- 通关中位时长不在 8–12 分钟。
- 普通房主要难度仍来自无前摇碰撞伤害和纯数值堆叠。
- 玩家必须依赖开发者解释才能理解 HP、能量、技能、奖励和死亡原因。

## 20. 后续阶段提升规则

只有 M1 放行后才能将 Next 内容提升为新的 Current。

每次只提升一个主要复杂度变量：

- 第二把武器，或第三个时间能力。
- 事件房，或随机房间图。
- 第二个角色，或第二个 Boss。

不在同一里程碑同时增加多个会改变输入、Build 和内容池的主要变量。

这不是永久删减，而是保证完整愿景中的每一项内容都建立在已经验证的系统之上。
