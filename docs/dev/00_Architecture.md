# Plane Walker: Chronicles of Collapse — 开发文档总纲

**版本**: 1.0  
**日期**: 2026-04-22  
**引擎**: Godot 4.x  
**语言**: GDScript 2.0（性能瓶颈可用GDExtension/C++）  
**目标平台**: Steam (Windows PC)  

---

> **v1.1设计基线**：开发实现默认服从 `docs/0_深度收敛与系统职责设计.md`。首发版本以5层地牢、8个核心流派、40-60道具、25-30祝福、15-18诅咒、低数值局外成长为基线；旧版大内容池和10层曲线只作为储备/扩展内容。

## 1. 整体架构

### 1.1 架构风格

采用**模块化单体架构** (Modular Monolith)，按功能域拆分为独立模块。运行时以 Godot 节点树承载实体和场景，跨模块通信通过 Autoload 服务、EventBus 和 signal 完成，降低耦合度。不采用 Unity ECS/DOTS 式架构；如后续出现战斗判定、回放压缩或寻路性能瓶颈，局部使用 GDExtension/C++。

```
┌─────────────────────────────────────────────────────────┐
│                    Game Application                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ Bootstrap │  │  Scene   │  │  Config  │              │
│  │ Autoload  │  │  Loader  │  │  System  │              │
│  └──────────┘  └──────────┘  └──────────┘              │
├─────────────────────────────────────────────────────────┤
│                    Core Framework                        │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐           │
│  │ Event  │ │Autoload │ │  Data  │ │  State │           │
│  │  Bus   │ │Services │ │Manager │ │Machine │           │
│  └────────┘ └────────┘ └────────┘ └────────┘           │
├─────────────────────────────────────────────────────────┤
│                    Game Modules                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │ Combat  │ │  Time   │ │  Enemy  │ │  Item   │      │
│  │ System  │ │ System  │ │ System  │ │ System  │      │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├─────────┤      │
│  │ Dungeon │ │  Char   │ │   UI    │ │  Meta   │      │
│  │ System  │ │ System  │ │ System  │ │ System  │      │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├─────────┤      │
│  │  Hub    │ │  Gacha  │ │  Save   │ │ Social  │      │
│  │ System  │ │ System  │ │ System  │ │ System  │      │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘      │
├─────────────────────────────────────────────────────────┤
│                    Infrastructure                        │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐           │
│  │ Audio  │ │VFX/Pool│ │ Input  │ │  Net   │           │
│  │Manager │ │Manager │ │Manager │ │Manager │           │
│  └────────┘ └────────┘ └────────┘ └────────┘           │
└─────────────────────────────────────────────────────────┘
```

### 1.2 核心设计原则

1. **数据驱动**: 所有游戏内容（道具、敌人、祝福、诅咒、天赋、房间模板等）均为Godot Resource(`.tres`)或JSON配置，代码只实现机制
2. **事件解耦**: 模块间通过EventBus Autoload和signal通信，禁止直接引用其他模块的具体实现类
3. **接口隔离**: 模块对外暴露稳定脚本API，内部实现细节对外不可见
4. **状态显式**: 所有游戏状态通过GameState单例管理，状态变更必须经过状态机
5. **可测试性**: 核心逻辑优先写成RefCounted/Resource脚本，避免依赖场景树，便于单元测试

---

## 2. 项目目录结构

```
project.godot
addons/                             # Godot插件：测试、Steamworks、导入工具等
autoload/                           # 全局单例服务，Project Settings中注册
├── event_bus.gd
├── game_state.gd
├── service_registry.gd
├── scene_loader.gd
├── save_manager.gd
├── audio_manager.gd
├── input_manager.gd
└── pool_manager.gd

scripts/
├── core/                           # 核心框架
│   ├── fsm/
│   │   ├── state_machine.gd
│   │   ├── state_logic.gd
│   │   └── transition.gd
│   ├── data/
│   │   ├── registry.gd
│   │   ├── data_loader.gd
│   │   └── rng.gd
│   ├── pool/
│   │   └── object_pool.gd
│   └── utils/
│       ├── math_utils.gd
│       └── random_utils.gd
│
├── combat/
│   ├── action_system/
│   │   ├── action_player.gd
│   │   ├── action_state.gd
│   │   ├── action_data.gd
│   │   └── cancel_window.gd
│   ├── weapon/
│   │   ├── weapon_base.gd
│   │   ├── sword_weapon.gd
│   │   ├── bow_weapon.gd
│   │   ├── gun_weapon.gd
│   │   ├── staff_weapon.gd
│   │   └── fist_weapon.gd
│   ├── damage/
│   │   ├── damage_calculator.gd
│   │   ├── damage_info.gd
│   │   └── damage_type.gd
│   ├── hitbox/
│   │   ├── hitbox_manager.gd
│   │   ├── hitbox_data.gd
│   │   └── hurtbox.gd
│   └── combo/
│       ├── combo_tree.gd
│       └── combo_node.gd
│
├── time_system/
│   ├── time_controller.gd
│   ├── time_energy_system.gd
│   ├── time_stop.gd
│   ├── time_rewind.gd
│   ├── time_accelerate.gd
│   ├── time_rift.gd
│   └── time_scale_manager.gd
│
├── enemy/
├── boss/
├── item/
├── blessing/
├── curse/
├── talent/
├── dungeon/
├── character/
├── meta/
├── hub/
├── gacha/
├── cosmetics/
├── ui/
├── save/
├── social/
├── input/
└── audio/

resources/                          # Godot Resource和配置
├── items/                           # ItemData .tres
├── enemies/
├── bosses/
├── blessings/
├── curses/
├── talents/
├── rooms/
├── events/
├── characters/
├── weapons/
├── localization/
│   ├── en.csv
│   ├── zh_CN.csv
│   └── ...
└── balance/
    ├── damage_table.json
    ├── economy_table.json
    └── progression_table.json

scenes/
├── boot/boot.tscn
├── hub/hub.tscn
├── dungeon/dungeon_root.tscn
├── boss/boss_arena.tscn
├── player/
├── enemies/
├── bosses/
├── items/
├── rooms/
├── vfx/
└── ui/

art/
├── sprites/
├── tilesets/
├── animations/
└── vfx/

audio/
├── bgm/
├── sfx/
└── voice/

tests/
├── unit/
├── integration/
└── smoke/
```

---

## 3. 核心框架接口定义

### 3.1 事件总线 (EventBus)

```gdscript
# autoload/event_bus.gd
# 全局事件总线，模块间通信的核心。事件统一用Dictionary承载，便于存档/回放/日志。
extends Node

var _handlers: Dictionary[StringName, Array] = {}
var _deferred_events: Array[Dictionary] = []

func subscribe(event_name: StringName, target: Object, method_name: StringName) -> void:
    var entry := {"target": target, "method": method_name}
    _handlers.get_or_add(event_name, []).append(entry)

func unsubscribe(event_name: StringName, target: Object, method_name: StringName) -> void:
    if not _handlers.has(event_name):
        return
    _handlers[event_name] = _handlers[event_name].filter(
        func(entry): return entry.target != target or entry.method != method_name
    )

func publish(event_name: StringName, payload: Dictionary = {}) -> void:
    for entry in _handlers.get(event_name, []):
        if is_instance_valid(entry.target):
            entry.target.call(entry.method, payload)

func publish_deferred(event_name: StringName, payload: Dictionary = {}) -> void:
    _deferred_events.append({"name": event_name, "payload": payload})

func _process(_delta: float) -> void:
    var events := _deferred_events
    _deferred_events = []
    for event in events:
        publish(event.name, event.payload)
```

**核心事件列表**（按模块）：

```gdscript
# 事件名统一放在 scripts/core/events.gd 或 autoload/event_bus.gd 常量区
const DAMAGE_DEALT := &"damage_dealt"            # {target_id, damage_info}
const DAMAGE_RECEIVED := &"damage_received"      # {source_id, damage_info}
const ENTITY_DEATH := &"entity_death"            # {entity_id, is_boss}
const PERFECT_PARRY := &"perfect_parry"          # {player_id}
const PERFECT_RELOAD := &"perfect_reload"        # {}
const COMBO_HIT := &"combo_hit"                  # {combo_count, weapon_type}

const TIME_STOP_START := &"time_stop_start"      # {duration}
const TIME_STOP_END := &"time_stop_end"          # {}
const TIME_REWIND := &"time_rewind"              # {rewind_seconds}
const TIME_ACCELERATE_START := &"time_accelerate_start"
const TIME_RIFT_CREATED := &"time_rift_created"  # {position, radius}
const TIME_ENERGY_CHANGED := &"time_energy_changed"

const ITEM_ACQUIRED := &"item_acquired"          # {item_id, slot}
const BLESSING_ACQUIRED := &"blessing_acquired"
const CURSE_ACCEPTED := &"curse_accepted"
const TALENT_SELECTED := &"talent_selected"

const ROOM_CLEARED := &"room_cleared"
const FLOOR_CLEARED := &"floor_cleared"
const BOSS_DEFEATED := &"boss_defeated"
const DUNGEON_RUN_END := &"dungeon_run_end"

const CURRENCY_CHANGED := &"currency_changed"
const META_UNLOCK := &"meta_unlock"
const ACHIEVEMENT_UNLOCKED := &"achievement_unlocked"
```

### 3.2 服务注册表 (ServiceRegistry)

```gdscript
# autoload/service_registry.gd
extends Node

var _services: Dictionary[StringName, Object] = {}

func register(service_name: StringName, service: Object) -> void:
    _services[service_name] = service

func get_service(service_name: StringName) -> Object:
    assert(_services.has(service_name), "Missing service: %s" % service_name)
    return _services[service_name]

func try_get_service(service_name: StringName) -> Object:
    return _services.get(service_name)

func reset() -> void:
    _services.clear()
```

### 3.3 状态机 (FSM)

```gdscript
# scripts/core/fsm/state_machine.gd
class_name StateMachine
extends RefCounted

var current_state: StringName
var _states: Dictionary[StringName, Object] = {}
var _transitions: Array[Dictionary] = []

func register_state(state: StringName, logic: Object) -> void:
    _states[state] = logic

func transition_to(new_state: StringName, payload: Dictionary = {}) -> void:
    if current_state != &"" and _states.has(current_state):
        _states[current_state].exit()
    current_state = new_state
    _states[current_state].enter(payload)

func tick(delta: float) -> void:
    if _states.has(current_state):
        _states[current_state].tick(delta)

func physics_tick(delta: float) -> void:
    if _states.has(current_state):
        _states[current_state].physics_tick(delta)
```

### 3.4 数据管理

```gdscript
# scripts/core/data/registry.gd
class_name Registry
extends RefCounted

var _entries: Dictionary[StringName, Resource] = {}

func register(entry: Resource) -> void:
    _entries[StringName(entry.id)] = entry

func get_entry(id: StringName) -> Resource:
    return _entries[id]

func get_all() -> Array[Resource]:
    return _entries.values()

func filter(predicate: Callable) -> Array[Resource]:
    return get_all().filter(predicate)

func random(rng: RandomNumberGenerator, predicate: Callable = Callable()) -> Resource:
    var candidates := get_all() if predicate.is_null() else filter(predicate)
    return candidates[rng.randi_range(0, candidates.size() - 1)]
```

---

## 4. 游戏状态管理

### 4.1 全局游戏状态

```gdscript
# autoload/game_state.gd
extends Node

enum GamePhase {
    BOOT,
    HUB,
    RUN_START,
    DUNGEON,
    ROOM_CLEAR,
    SELECTION,
    BOSS_FIGHT,
    DEATH,
    RUN_END,
    PAUSED,
}

var phase: GamePhase = GamePhase.BOOT
var current_floor: int = 1
var current_room: int = 0
var run_seed: int = 0
var run_timer: float = 0.0
var death_count: int = 0

# 局内数据：Run开始时初始化，死亡/通关时结算。
var current_run: Dictionary = {
    "character_id": "",
    "weapon_id": "",
    "difficulty": "normal",
    "inventory": [],
    "active_blessings": [],
    "active_curses": [],
    "talent_tree": {},
    "currencies": {},
    "stats": {},
}

# 局外数据：永久保存，SaveManager负责序列化。
var persistent: Dictionary = {
    "chronos_shards": 0,
    "existential_imprints": 0,
    "unlocked_nodes": [],
    "discovered_items": [],
    "unlocked_characters": [],
    "unlocked_weapons": [],
    "weapon_proficiency": {},
    "npc_affinity": {},
    "unlocked_achievements": [],
    "cosmetics": {},
    "settings": {},
}
```

### 4.2 场景流转

```
Boot → Hub → (选角色/武器/难度) → Dungeon.Floor1 → ... → Floor5 → Boss → RunEnd → Hub
                ↑                                                                    │
                └────────────────────── 死亡/通关 ←──────────────────────────────────┘
```

---

## 5. 通用接口规范

### 5.1 伤害接口

```gdscript
# scripts/combat/damage/damage_info.gd
class_name DamageInfo
extends RefCounted

enum Type { PHYSICAL, TIME, VOID, FIRE, ICE, LIGHTNING }

var base_damage: float
var type: Type
var crit_multiplier: float = 1.0
var source_id: int = -1
var knockback_force: Vector2 = Vector2.ZERO
var is_proc: bool = false

# 约定：可受击节点实现以下脚本API：
# - get_entity_id() -> int
# - get_current_hp() -> float
# - get_max_hp() -> float
# - is_alive() -> bool
# - take_damage(damage_info: DamageInfo) -> void
# - heal(amount: float) -> void
# - kill() -> void
```

### 5.2 武器接口

```gdscript
# scripts/combat/weapon/weapon_base.gd
class_name WeaponBase
extends Node2D

var weapon_id: StringName
var weapon_type: StringName
var data: Resource
var owner_player: Node

func initialize(weapon_data: Resource) -> void:
    data = weapon_data
    weapon_id = StringName(data.id)

func on_equip(player: Node) -> void:
    owner_player = player

func on_unequip() -> void:
    owner_player = null

func on_attack_start() -> void: pass
func on_attack_end() -> void: pass
func on_special_start() -> void: pass
func on_special_end() -> void: pass

func on_time_stop_start() -> void: pass
func on_time_stop_end() -> void: pass
func on_time_accelerate(multiplier: float) -> void: pass
```

### 5.3 道具效果接口

```gdscript
# scripts/item/item_effect.gd
class_name ItemEffect
extends Resource

@export var effect_id: StringName
@export var triggers: Array[StringName] = []

func on_acquired(player: Node, item_instance: Resource) -> void: pass
func on_removed(player: Node, item_instance: Resource) -> void: pass
func on_event(event_name: StringName, payload: Dictionary, player: Node, item_instance: Resource) -> void: pass

# 道具触发器命名示例：
# &"on_kill", &"on_hit", &"on_damaged", &"on_room_clear", &"on_boss_hit",
# &"on_time_stop_use", &"on_dodge", &"on_crit", &"on_heal", &"on_curse_accept"
```

### 5.4 RNG接口（确定性随机）

```gdscript
# scripts/core/data/rng.gd
class_name RunRNG
extends RefCounted

var seed_value: int
var _rng := RandomNumberGenerator.new()

func _init(run_seed: int) -> void:
    seed_value = run_seed
    _rng.seed = run_seed

func next_int(min_value: int, max_value: int) -> int:
    return _rng.randi_range(min_value, max_value)

func next_float(min_value: float, max_value: float) -> float:
    return _rng.randf_range(min_value, max_value)

func next_bool(probability: float) -> bool:
    return _rng.randf() <= probability

func next_item(items: Array) -> Variant:
    return items[next_int(0, items.size() - 1)]

func shuffle(items: Array) -> void:
    items.shuffle()
```

---

## 6. 开发文档索引

| 编号 | 文档 | 内容 |
|------|------|------|
| 00 | [架构总纲](dev/00_Architecture.md) | 本文档 — 架构、目录、核心框架、接口 |
| 01 | [战斗系统](dev/01_CombatSystem.md) | 动作系统、伤害公式、五武器实现 |
| 02 | [时间操控系统](dev/02_TimeSystem.md) | 时之能量、四大技能、时间缩放架构 |
| 03 | [敌人与Boss系统](dev/03_EnemyBossSystem.md) | AI状态机、Boss多阶段、精英词缀 |
| 04 | [道具与Build系统](dev/04_ItemBuildSystem.md) | 道具注册、联动引擎、祝福/诅咒、天赋树 |
| 05 | [地牢生成系统](dev/05_DungeonGeneration.md) | 程序化生成、房间模板、波次、事件 |
| 06 | [角色与进度系统](dev/06_CharacterProgression.md) | 角色差异化、Meta进度、货币、锻造 |
| 07 | [UI与交互系统](dev/07_UIInteractionSystem.md) | HUD、选择界面、菜单、手柄、教学 |
| 08 | [局外系统](dev/08_HubExternalSystem.md) | Hub、死亡结算、抽卡、外观、存档、社交 |
| 09 | [基础设施](dev/09_Infrastructure.md) | 项目配置、构建、本地化、Mod SDK、测试 |
| 10 | [MVP垂直切片路线图](dev/10_MVP_VerticalSlice_Roadmap.md) | 首个可玩版本范围、任务卡、数据契约、验收清单 |

---

## 7. 编码规范

### 7.1 命名规范
- 类名/class_name: PascalCase (`PlayerController`, `DamageCalculator`)
- 节点场景名: PascalCase (`PlayerController.tscn`, `DamageNumber.tscn`)
- 文件/变量/方法: snake_case (`player_controller.gd`, `take_damage`, `current_hp`)
- 私有变量: `_snake_case` (`_current_hp`, `_weapon_data`)
- 常量: UPPER_SNAKE_CASE (`MAX_INVENTORY_SIZE`)
- 事件名: lower_snake_case StringName (`&"damage_dealt"`)
- Resource类: PascalCase + Data后缀 (`WeaponData`, `ItemData`)

### 7.2 注释规范
- 公共脚本API必须有简短注释说明用途和调用时机
- 复杂算法必须有行内注释说明逻辑
- TODO标记: `# TODO(模块): 描述` — 如 `# TODO(Combat): 完善暴击公式`

### 7.3 性能规范
- 禁止在`_process`/`_physics_process`热路径中频繁`get_node`、`find_child`或字符串路径查找；节点引用在`_ready`缓存
- 频繁创建/销毁的对象必须使用对象池
- 热路径中避免临时Array/Dictionary分配，复用查询结果数组和对象池
- 大量同类视觉对象优先使用MultiMeshInstance2D、GPUParticles2D或批量TileMap

### 7.4 Git规范
- 分支: `main` → `dev` → `feature/模块名-描述` → PR → merge
- 提交格式: `[模块] 描述` — 如 `[Combat] 实现剑武器4段连击`
- PR必须通过CI检查（编译+单元测试+代码规范检查）
