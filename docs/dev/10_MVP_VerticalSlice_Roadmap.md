# 10 MVP垂直切片开发路线图

> **文档版本**：v1.0  
> **最后更新**：2026-05-25  
> **适用项目**：《Plane Walker: Chronicles of Collapse》  
> **定位**：给 coding agent / 开发者直接执行的首个可玩版本开发规格  
> **上层约束**：默认服从 `docs/0_深度收敛与系统职责设计.md` 的v1.1收敛口径

---

## 10.1 结论：现在能不能开始代码开发？

可以开始，但不建议直接开发完整首发版本。当前设计文档已经足够支撑**MVP垂直切片**开发；完整首发版本仍需要在MVP验证后再扩展。

MVP的目标不是证明"内容足够多"，而是证明这四件事成立：

1. 玩家移动、闪避、攻击、受击和死亡手感成立。
2. 时间技能能改变打法，而不是只是一个强力按钮。
3. 房间清理、奖励选择、进入下一房间能形成闭环。
4. 少量道具/祝福/诅咒已经能让玩家识别Build方向。

只要这四件事成立，后续扩展道具、Boss、层数、Meta才有意义。

---

## 10.2 MVP范围定义

### 10.2.1 MVP必须包含

| 模块 | MVP范围 | 不做内容 |
|------|---------|----------|
| 引擎工程 | Godot 4.x项目、基础目录、Autoload | Steam、云存档、Mod、成就 |
| 玩家 | 1个角色：行者 | 其他4个角色 |
| 武器 | 1把武器：剑 | 弓/枪/杖/拳套 |
| 时间技能 | 2个技能：时间停止、时间回溯 | 时间加速、时间裂隙可延后 |
| 敌人 | 3种普通敌人 + 1种精英 | 完整27种敌人 |
| 地牢 | 1层，5个房间：战斗×3、精英×1、Boss×1 | 完整5层、复杂分支 |
| Boss | 1个原型Boss | 完整5 Boss、Boss Rush |
| 道具 | 8个道具 | 40-60首发池 |
| 祝福 | 4个祝福 | 25-30首发池 |
| 诅咒 | 2个诅咒 | 15-18首发池 |
| 天赋 | 3个天赋节点，1次选择 | 完整5路线×3层 |
| UI | HP、时之能量、房间进度、奖励选择 | 完整HUD、图鉴、结算统计 |
| 存档 | 可选：本地设置和简单Run结果 | Meta长期成长 |

### 10.2.2 MVP体验目标

MVP的一局长度控制在8-12分钟：

```
主菜单/快速开始
  → 房间1：基础战斗
  → 奖励：道具3选1
  → 房间2：敌人组合
  → 奖励：祝福2选1
  → 房间3：压力战斗
  → 奖励：天赋3选1
  → 房间4：精英 + 诅咒选择
  → 房间5：Boss
  → 胜利/死亡结算
```

MVP不需要程序化生成复杂地图。可以用固定房间序列验证核心循环；生成器在第二阶段再替换。

---

## 10.3 推荐技术基线

### 10.3.1 项目技术选择

| 项目 | 选择 |
|------|------|
| 引擎 | Godot 4.3+ |
| 语言 | GDScript 2.0 |
| 视角 | 2D俯视/2.5D表现，MVP先按2D实现 |
| 资源方式 | `.tscn` 场景 + `.tres` Resource + 少量JSON配置 |
| 测试 | Godot GUT 或轻量脚本测试，MVP至少保留手动验收清单 |
| 输入 | 键鼠优先，手柄映射预留 |

### 10.3.2 MVP工程目录

MVP阶段先建立能运行的最小目录，不需要一次创建完整架构总纲中的所有目录。

```text
project.godot
autoload/
├── event_bus.gd
├── game_state.gd
└── scene_loader.gd

scenes/
├── main.tscn
├── rooms/
│   ├── room_base.tscn
│   ├── room_combat_01.tscn
│   ├── room_combat_02.tscn
│   ├── room_combat_03.tscn
│   ├── room_elite_01.tscn
│   └── room_boss_01.tscn
├── player/
│   └── player.tscn
├── enemies/
│   ├── enemy_chaser.tscn
│   ├── enemy_shooter.tscn
│   ├── enemy_tank.tscn
│   ├── enemy_elite_chaser.tscn
│   └── boss_time_golem.tscn
└── ui/
    ├── hud.tscn
    ├── reward_choice.tscn
    └── run_result.tscn

scripts/
├── core/
│   ├── damage_info.gd
│   ├── stats.gd
│   └── rng.gd
├── player/
│   ├── player_controller.gd
│   ├── player_combat.gd
│   └── player_time_skills.gd
├── combat/
│   ├── health_component.gd
│   ├── hitbox.gd
│   ├── hurtbox.gd
│   ├── damage_calculator.gd
│   └── sword_weapon.gd
├── time_system/
│   ├── time_manager.gd
│   ├── time_stop_effect.gd
│   └── rewind_recorder.gd
├── enemies/
│   ├── enemy_base.gd
│   ├── enemy_chaser.gd
│   ├── enemy_shooter.gd
│   ├── enemy_tank.gd
│   └── boss_time_golem.gd
├── dungeon/
│   ├── run_director.gd
│   ├── room_controller.gd
│   └── spawn_point.gd
├── items/
│   ├── item_data.gd
│   ├── item_instance.gd
│   ├── effect_context.gd
│   ├── item_effect.gd
│   └── item_manager.gd
├── progression/
│   ├── blessing_data.gd
│   ├── curse_data.gd
│   ├── talent_data.gd
│   └── run_build_state.gd
└── ui/
    ├── hud.gd
    ├── reward_choice_ui.gd
    └── run_result_ui.gd

data/
├── items/
│   └── mvp_items.json
├── blessings/
│   └── mvp_blessings.json
├── curses/
│   └── mvp_curses.json
├── talents/
│   └── mvp_talents.json
└── enemies/
    └── mvp_enemies.json
```

MVP可以先用JSON提高迭代速度；稳定后再转为`.tres`。

---

## 10.4 核心数据契约

### 10.4.1 DamageInfo

所有伤害都通过同一个结构传递，避免武器、道具、时间技能各算一套。

```gdscript
class_name DamageInfo
extends RefCounted

enum DamageType { PHYSICAL, TIME, VOID, FIRE, ICE, LIGHTNING }

var amount: float
var damage_type: DamageType
var source: Node
var attacker: Node
var can_crit: bool = true
var crit_chance: float = 0.0
var crit_multiplier: float = 1.5
var knockback: Vector2 = Vector2.ZERO
var tags: Array[String] = []
```

MVP必需标签：

| Tag | 用途 |
|-----|------|
| `weapon:sword` | 剑类效果判断 |
| `time:stop` | 时间停止相关效果 |
| `time:rewind` | 回溯相关效果 |
| `hit:perfect_guard` | 后续完美格挡流派预留 |
| `item_triggered` | 避免道具触发道具死循环 |

### 10.4.2 Stats

MVP只实现必要属性。

```gdscript
class_name Stats
extends Resource

@export var max_hp: float = 200.0
@export var attack: float = 30.0
@export var defense: float = 0.0
@export var move_speed: float = 220.0
@export var attack_speed: float = 1.0
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5
@export var time_energy_max: float = 100.0
@export var time_energy_regen: float = 2.0
```

暂不实现复杂软上限。MVP只需要在`DamageCalculator`里预留入口。

### 10.4.3 EventBus事件

MVP必须统一事件名。所有道具、祝福、诅咒都通过这些事件接入。

```gdscript
signal damage_about_to_apply(damage_info, target)
signal damage_applied(damage_info, target, final_amount)
signal entity_died(entity, killer)
signal room_started(room_id)
signal room_cleared(room_id)
signal reward_selected(reward_data)
signal time_skill_started(skill_id)
signal time_skill_ended(skill_id)
signal player_dashed()
signal player_attacked(weapon_id)
signal enemy_spawned(enemy)
signal run_started()
signal run_ended(result)
```

MVP禁止系统之间为了赶进度直接互相硬引用，除非是父子节点的明确控制关系。

---

## 10.5 MVP内容清单

### 10.5.1 玩家：行者

| 项目 | 数值 |
|------|------|
| HP | 200 |
| ATK | 30 |
| 移速 | 220 px/s |
| 闪避距离 | 120 px |
| 闪避时间 | 0.28s |
| 闪避无敌 | 前0.20s |
| 时之能量 | 100 |
| 能量恢复 | 2/s |

MVP行者专属机制先不做完整"旅途印记"。可做简化版：

```text
每清理1个房间，下一房间开始时恢复10HP和10时之能量。
```

这能验证角色差异入口，但不会压过核心战斗。

### 10.5.2 武器：剑

MVP剑只做3段普攻 + 重击。

| 动作 | 伤害 | 前摇 | 活动 | 后摇 | 备注 |
|------|------|------|------|------|------|
| 普攻1 | ATK×0.8 | 0.10s | 0.08s | 0.18s | 小范围扇形 |
| 普攻2 | ATK×1.0 | 0.12s | 0.08s | 0.20s | 稍大范围 |
| 普攻3 | ATK×1.3 | 0.16s | 0.10s | 0.28s | 击退 |
| 重击 | ATK×2.0 | 0.35s | 0.12s | 0.45s | 打断普通敌人 |

验收：

- 连续点击能打出1→2→3段。
- 0.8秒不攻击后连段重置。
- 每段命中都发出`player_attacked`和`damage_applied`事件。
- 重击可以明显击退普通敌人。

### 10.5.3 时间技能

#### 时间停止

| 参数 | MVP数值 |
|------|---------|
| 消耗 | 35时之能量 |
| 冷却 | 12秒 |
| 普通敌人停止 | 3秒 |
| 精英停止 | 1.5秒 |
| Boss效果 | 不停止本体，减速弹幕/召唤物并延长Boss后摇 |

MVP实现方式：

- 普通敌人暂停AI、移动、攻击计时器。
- 已飞行弹幕速度降为0或10%。
- Boss进入`time_resisted`状态：动作速度×0.6，下一次攻击后摇+0.8秒。

验收：

- 时间停止不是纯保命按钮，玩家能在停止窗口内打出明显爆发。
- Boss不会被完全冻结，但玩家能感知到弱点窗口变长。

#### 时间回溯

| 参数 | MVP数值 |
|------|---------|
| 消耗 | 45时之能量 |
| 冷却 | 15秒 |
| 记录长度 | 5秒 |
| 记录频率 | 10次/秒 |
| 回溯内容 | 玩家位置、HP、时之能量 |

MVP简化：

- 回溯不还原敌人状态。
- 回溯不撤销已造成伤害。
- 回溯路径可触发部分道具效果。

验收：

- 玩家能回到5秒内的位置。
- HP能回到记录值，但不能超过当前最大HP。
- 回溯后有0.5秒无敌，避免回到伤害区域立刻死亡。

---

## 10.6 MVP道具/祝福/诅咒/天赋

### 10.6.1 8个道具

| ID | 名称 | 类型 | 流派 | 效果 |
|----|------|------|------|------|
| TIM_REWIND_ECHO | 回声透镜 | 时间 | 回溯残影 | 回溯路径留下2秒残影，每0.5秒对附近敌人造成ATK×0.25时间伤害 |
| TIM_STOP_BURST | 静止棱镜 | 时间 | 冻结爆发 | 时间停止期间首次命中敌人时追加ATK×0.8时间伤害，每敌人1次 |
| WEP_SWORD_RIPOSTE | 断刃护符 | 武器 | 完美格挡 | 闪避后0.4秒内剑攻击伤害+40% |
| ATK_PIERCING_WAVE | 裂波核心 | 攻击 | 弹幕穿透 | 剑第三段发出短程剑气，造成ATK×0.6物理伤害 |
| DEF_TIME_SHIELD | 时砂护盾 | 防御 | 通用补短板 | 进入新房间获得30护盾，持续到破裂 |
| UTI_ENERGY_CELL | 时能电池 | 功能 | 通用补短板 | 时之能量上限+20，击杀恢复额外+2 |
| SPC_LOW_HP_VOID | 虚无血滴 | 特殊 | 低血虚无 | HP低于35%时，攻击附带ATK×0.3虚无伤害 |
| SPC_ECHO_CLONE | 残像核心 | 特殊 | 分身召唤 | 使用时间技能后生成1个残像，2秒后模仿一次最近的剑攻击 |

### 10.6.2 4个祝福

| ID | 名称 | 强化对象 | 效果 |
|----|------|----------|------|
| BLS_STOP_WEAKPOINT | 凝滞弱点 | 时间停止 | 时间停止影响过的敌人获得3秒弱点，受到剑第三段/重击伤害+35% |
| BLS_REWIND_PATH | 逆旅刻痕 | 时间回溯 | 回溯路径穿过敌人时造成ATK×0.5时间伤害，每敌人1次 |
| BLS_SWORD_TEMPO | 剑势回环 | 剑 | 完成3段连击后，下一次时间技能消耗-10 |
| BLS_SURVIVE_THREAD | 命线余辉 | 通用补短板 | 每房间第一次低于30%HP时，获得1秒无敌和20时之能量 |

### 10.6.3 2个诅咒

诅咒必须改变打法，不做单纯倍率交易。

| ID | 名称 | 增益 | 代价 | 设计意图 |
|----|------|------|------|----------|
| CUR_NARROW_VISION | 狭窄未来 | 对屏幕内近距离敌人伤害+25% | 远距离敌人预警范围降低，远程弹幕提示延迟0.3秒 | 鼓励贴近与主动压制 |
| CUR_REWIND_DEBT | 回溯债务 | 回溯冷却-5秒 | 每次回溯后5秒内受到治疗-50%，且敌人移速+10% | 回溯从保命药变成带债务的节奏选择 |

### 10.6.4 3个天赋

MVP只做一次天赋3选1，验证UI和Build方向。

| ID | 名称 | 路线 | 效果 |
|----|------|------|------|
| TAL_RUIN_EXECUTE | 裂伤处决 | 毁灭 | 敌人低于30%HP时，剑重击伤害+50% |
| TAL_STEEL_RECOVER | 余势回复 | 钢铁 | 每清理房间，若HP低于50%，额外恢复20HP |
| TAL_ETERNITY_RESERVE | 时能蓄池 | 永恒 | 时之能量低于30时，恢复速度+100% |

---

## 10.7 开发阶段拆分

### Phase 0：工程启动

目标：项目能打开、能运行空场景、基础Autoload可用。

任务：

1. 创建Godot 4.x项目。
2. 建立MVP目录结构。
3. 创建`main.tscn`，运行后进入测试房间。
4. 注册`event_bus.gd`、`game_state.gd`、`scene_loader.gd`为Autoload。
5. 建立基础输入映射：
   - `move_up/down/left/right`
   - `attack`
   - `heavy_attack`
   - `dash`
   - `time_stop`
   - `time_rewind`
   - `interact`
   - `pause`

验收：

- 项目无报错启动。
- 按键映射能在调试面板打印。
- `EventBus.run_started.emit()`可被HUD或测试节点接收。

### Phase 1：玩家移动与基础战斗

目标：玩家手感和剑攻击成立。

任务：

1. 实现`player_controller.gd`：
   - WASD移动
   - 鼠标朝向或移动方向朝向
   - 闪避
   - 受击短暂无敌
2. 实现`health_component.gd`：
   - HP增减
   - 死亡事件
   - 无敌帧
3. 实现`hitbox.gd` / `hurtbox.gd`。
4. 实现`sword_weapon.gd`三段普攻和重击。
5. 实现`damage_calculator.gd`最小版本。

验收：

- 玩家可移动、闪避、攻击。
- 剑攻击能命中测试木桩。
- 木桩HP归零后触发`entity_died`。
- 闪避期间不会受伤。

### Phase 2：敌人与房间闭环

目标：一间房能开始、刷怪、清怪、开门。

任务：

1. 实现`enemy_base.gd`。
2. 实现3种敌人：
   - 追击者：靠近近战攻击
   - 射手：保持距离发射慢速弹幕
   - 坦克：慢速高HP，攻击前摇明显
3. 实现`room_controller.gd`：
   - 房间开始刷怪
   - 统计存活敌人
   - 全部死亡后触发清理
4. 实现`run_director.gd`固定房间序列。

验收：

- 进入房间后敌人生成。
- 清完敌人后房间进入cleared状态。
- 清理后出现奖励或进入下一房间入口。

### Phase 3：时间技能

目标：时间停止和回溯成为核心玩法。

任务：

1. 实现`time_manager.gd`：
   - 时之能量
   - 冷却
   - 技能状态
2. 实现时间停止：
   - 普通敌人停止
   - 精英减半
   - Boss抗性接口
3. 实现`rewind_recorder.gd`：
   - 环形缓冲记录玩家状态
   - 回溯到最近5秒内状态
4. HUD显示能量和冷却。

验收：

- 时间停止能冻结普通敌人3秒。
- 回溯能回到旧位置和HP。
- 能量不足或冷却中不能施放。
- 时间技能发出`time_skill_started/ended`事件。

### Phase 4：道具/祝福/诅咒/天赋框架

目标：少量Build选择能改变打法。

任务：

1. 实现数据加载：
   - `mvp_items.json`
   - `mvp_blessings.json`
   - `mvp_curses.json`
   - `mvp_talents.json`
2. 实现`run_build_state.gd`：
   - 当前道具列表
   - 当前祝福列表
   - 当前诅咒列表
   - 当前天赋列表
3. 实现`item_effect.gd`基础效果接口。
4. 让8个道具、4个祝福、2个诅咒、3个天赋生效。
5. 实现奖励选择UI：
   - 道具3选1
   - 祝福2选1
   - 诅咒接受/拒绝
   - 天赋3选1

验收：

- 选择道具后立即在HUD或调试面板显示。
- 至少4个效果可通过战斗明显验证。
- 诅咒有明确代价，不是只改面板数值。
- 同一奖励不会重复出现。

### Phase 5：Boss原型

目标：Boss验证"时间技能正向用法"。

Boss：时岩傀儡 `boss_time_golem`

招式：

| 招式 | 描述 | 时间技能正向用法 |
|------|------|------------------|
| 重砸 | 长前摇圆形AOE | 时间停止延长后摇，给重击窗口 |
| 追踪弹 | 发射3枚慢速弹幕 | 时间停止冻结弹幕，创造安全通道 |
| 召唤碎片 | 召唤2个小怪 | 时间停止冻结小怪，回溯拉开距离 |
| 时间裂纹 | 地面延迟爆炸 | 回溯可离开危险区域 |

验收：

- Boss不被时间停止硬控到失去威胁。
- 时间停止至少能影响弹幕/召唤物/后摇中的两项。
- 回溯能处理至少一种Boss危机。
- 击败Boss进入胜利结算。

### Phase 6：UI、结算与可玩打包

目标：MVP可给人试玩。

任务：

1. HUD：
   - HP
   - 时之能量
   - 当前房间
   - 当前道具/祝福/诅咒图标占位
2. 暂停菜单：
   - 继续
   - 重新开始
   - 退出
3. 结算：
   - 胜利/死亡
   - 击杀数
   - 获得的Build列表
   - 用时
4. 打包桌面可运行版本。

验收：

- 新玩家不用看控制台也知道自己HP、能量、奖励选择和胜负状态。
- 死亡后可以一键重开。
- 胜利后能看到本局拿了什么Build。

---

## 10.8 Agent任务卡模板

后续给agent开发时，建议每次只给一个任务卡，避免一次读完整GDD后失焦。

```text
任务：实现时间停止MVP

背景：
- 项目使用Godot 4.x + GDScript。
- 服从 docs/dev/10_MVP_VerticalSlice_Roadmap.md。
- 当前已有 Player、EnemyBase、TimeManager。

范围：
- 实现 time_stop 技能。
- 普通敌人停止3秒。
- 精英停止1.5秒。
- Boss只走 time_resisted 接口，不完全停止。
- HUD显示冷却和能量消耗。

禁止：
- 不实现时间回溯。
- 不重构敌人AI架构。
- 不添加新技能。

验收：
- 能量>=35时按键可施放。
- 普通敌人AI、移动、攻击计时器暂停3秒。
- 冷却12秒内不能再次施放。
- 发出 time_skill_started('time_stop') 和 time_skill_ended('time_stop')。
- 手动测试房间中无报错。
```

---

## 10.9 推荐给agent的开发顺序

### 第一轮：只做可移动可攻击

1. Phase 0 工程启动
2. Phase 1 玩家移动、闪避、剑攻击
3. 测试木桩受击死亡

这轮结束标准：能打开项目，操控玩家打死木桩。

### 第二轮：做1个房间闭环

1. 追击者敌人
2. 房间刷怪
3. 清怪后开门或弹奖励

这轮结束标准：能玩完一间房。

### 第三轮：加入时间技能

1. 时间停止
2. 时间回溯
3. HUD能量显示

这轮结束标准：时间技能确实改变战斗方式。

### 第四轮：加入Build

1. 道具数据加载
2. 8个MVP道具
3. 祝福/诅咒/天赋最小框架
4. 奖励选择UI

这轮结束标准：同一房间重复玩三次，Build体验明显不同。

### 第五轮：Boss与完整Run

1. 固定5房间序列
2. 精英房
3. Boss房
4. 胜利/死亡结算

这轮结束标准：完整8-12分钟MVP可试玩。

---

## 10.10 开发前还需要用户确认的决策

如果要让agent马上开始写代码，建议先确认以下决策：

| 决策 | 推荐选择 | 原因 |
|------|----------|------|
| 是否现在创建Godot项目 | 是 | 当前目录只有docs，没有工程 |
| Godot版本 | 4.3或4.4稳定版 | 避免API差异过大 |
| MVP视角 | 2D俯视 | 最快验证战斗与时间机制 |
| MVP美术 | 占位图形/基础Sprite | 先验证手感 |
| MVP数据格式 | JSON | 比`.tres`更适合agent批量编辑 |
| 是否做自动测试 | 做核心逻辑轻量测试 | 伤害、时间能量、数据加载值得测 |
| 是否做完整Meta | 不做 | MVP先验证局内体验 |

---

## 10.11 开发验收总清单

MVP完成必须满足：

- [ ] 项目可从`main.tscn`启动，无启动报错。
- [ ] 玩家可移动、闪避、普攻、重击。
- [ ] 至少3种普通敌人行为清晰可区分。
- [ ] 房间可以开始、刷怪、清理、进入下一房间。
- [ ] 时间停止和时间回溯均可用，且有能量/冷却限制。
- [ ] 至少8个道具可选择并生效。
- [ ] 至少4个祝福可选择并生效。
- [ ] 至少2个诅咒可选择并生效，且改变打法。
- [ ] 至少1次天赋3选1可完成。
- [ ] Boss有至少2种可被时间技能正向应对的机制。
- [ ] 玩家死亡可重开。
- [ ] 击败Boss可进入胜利结算。
- [ ] 一局时长8-12分钟。
- [ ] 不依赖控制台才能理解基本状态。

---

## 10.12 MVP之后的扩展顺序

MVP验证通过后，再按以下顺序扩展：

1. 把1层固定序列扩成5层固定序列。
2. 把固定序列替换成轻量随机房间图。
3. 剑以外新增第2把武器，优先弓或枪。
4. 补齐时间加速和时间裂隙。
5. 道具池扩到20个。
6. 祝福扩到10个、诅咒扩到6个。
7. 增加第2个Boss。
8. 再考虑局外Meta、锻造、熟练度。

不要在MVP前开发完整Meta系统。否则很容易先做出成长框架，却没有验证局内战斗是否好玩。

