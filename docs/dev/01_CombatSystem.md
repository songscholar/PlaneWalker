# Plane Walker: Chronicles of Collapse — 战斗系统开发文档

**版本**: 1.0  
**日期**: 2026-04-22  
**引擎**: Godot 4.x  
**语言**: GDScript 2.0（性能瓶颈可用GDExtension/C++）  
**目标帧率**: 60 fps (Fixed Timestep)  
**前置文档**: [00_Architecture.md](00_Architecture.md)

---

> **Godot迁移约束**：本文档中的类名和系统边界保留为设计语义；实际实现使用 `Node2D` / `Area2D` / `CharacterBody2D`、`Resource(.tres)`、Autoload服务和signal。历史伪代码中的实体、配置和PackedScene概念，分别映射为 Godot节点脚本、Resource数据、PackedScene/Node实例。

## 1. 战斗系统概述与架构类图

### 1.1 系统定位

战斗系统是《Plane Walker》的核心模块，负责：动作播放、伤害计算、判定检测、武器行为、受击反馈。系统遵循架构总纲的数据驱动、事件解耦、接口隔离、状态显式、可测试性五大原则。

### 1.2 战斗模块架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                       Combat System                               │
│                                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ ActionSystem │  │   Damage    │  │   Hitbox    │              │
│  │ ┌───────────┐│  │  ┌────────┐ │  │ ┌────────┐  │              │
│  │ │ActionPlayer││  │  │Damage  │ │  │ │Hitbox  │  │              │
│  │ │ActionData ││  │  │Calculator│ │  │ │Manager │  │              │
│  │ │CancelWindow││  │  │DamageInfo│ │  │ │HitboxData│ │              │
│  │ │InputBuffer ││  │  │DOTSystem│ │  │ │Hurtbox │  │              │
│  │ └───────────┘│  │  └────────┘ │  │ └────────┘  │              │
│  └──────┬───────┘  └──────┬─────┘  └──────┬─────┘              │
│         │                 │                │                      │
│  ┌──────┴─────────────────┴────────────────┴──────┐              │
│  │                  Weapon Layer                    │              │
│  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐           │              │
│  │  │Sword│ │Bow │ │Gun │ │Staff│ │Fist│           │              │
│  │  └────┘ └────┘ └────┘ └────┘ └────┘           │              │
│  └─────────────────────────────────────────────────┘              │
│                                                                    │
│  ┌─────────────────────────────────────────────────┐              │
│  │              Hit Feedback Layer                   │              │
│  │  Knockback │ Invincibility │ Hitstun │ DOT      │              │
│  └─────────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────────┘
         │                │                │
    ┌────┴────┐    ┌──────┴──────┐   ┌────┴────┐
    │ EventBus│    │ServiceRegistry│   │Registry │
    │(事件通信)│    │(服务访问)    │   │(数据查询)│
    └─────────┘    └─────────────┘   └─────────┘
```

### 1.3 核心类依赖关系

```
PlayerController
  ├── ActionPlayer (动作播放器，驱动状态机)
  │     └── ActionData (SO帧数据)
  │           └── CancelWindow[]
  ├── IWeapon (武器接口)
  │     └── WeaponBase (基类)
  │           ├── SwordWeapon
  │           ├── BowWeapon
  │           ├── GunWeapon
  │           ├── StaffWeapon
  │           └── FistWeapon
  ├── DamageCalculator (伤害计算器，RefCounted可测试)
  │     └── DamageInfo / DamageResult
  ├── HitboxManager (判定管理器)
  │     └── HitboxData / Hurtbox
  └── HitFeedbackController (受击反馈)
        ├── KnockbackController
        ├── InvincibilityController
        └── HitstunController
```

### 1.4 战斗事件定义

```text
// === 战斗核心事件 ===
public struct DamageDealtEvent : IEvent
{
    public int SourceId;
    public int TargetId;
    public DamageInfo Damage;
    public float FinalDamage;
}

public struct DamageReceivedEvent : IEvent
{
    public int SourceId;
    public DamageInfo Damage;
    public float FinalDamage;
}

public struct EntityDeathEvent : IEvent
{
    public int EntityId;
    public bool IsBoss;
    public int KillerId;
}

public struct PerfectParryEvent : IEvent
{
    public int PlayerId;
    public int ParryCount; // 连续完美格挡次数
}

public struct PerfectReloadEvent : IEvent
{
    public int PlayerId;
}

public struct ComboHitEvent : IEvent
{
    public int ComboCount;
    public WeaponType Weapon;
}

public struct HitstunEvent : IEvent
{
    public int TargetId;
    public HitstunLevel Level;
    public int DurationFrames;
}

public struct DOTAppliedEvent : IEvent
{
    public int TargetId;
    public DOTType DotType;
    public float DamagePerTick;
    public float Duration;
}

public struct DamageTypeInteractionEvent : IEvent
{
    public int TargetId;
    public DamageTypeInteractionType InteractionType;
    public float BonusDamage;
}

public struct ActionCancelEvent : IEvent
{
    public string ActionId;
    public int CancelFrame;
    public ActionCancelReason Reason;
}

public enum HitstunLevel { Light, Medium, Heavy, Knockdown }
public enum ActionCancelReason { Dodge, Parry, Special, ComboNext, Hit }
public enum DamageTypeInteractionType
{
    PhysTime,      // 时断打击
    PhysVoid,      // 虚空裂伤
    TimeVoid,      // 熵增
    PhysElement,   // 元素共鸣
    TimeElement,   // 时空风暴
    VoidElement    // 虚化焰
}
```

---

## 2. ActionData Resource 结构（帧数据定义）

### 2.1 设计原则

- 所有动作帧数据均为Resource配置，策划可直接在Inspector中调整
- 帧数基于60fps基准，运行时由攻速系数换算实际帧数
- 每个动作包含完整的三阶段（前摇/活动帧/后摇）+ 取消窗口 + 连招窗口

### 2.2 核心数据结构

```text
/// <summary>
/// 动作帧数据，Resource配置
/// 定义每个攻击动作的完整帧级参数
/// </summary>
[CreateAssetMenu(fileName = "ActionData_", menuName = "PlaneWalker/Combat/ActionData")]
public class ActionData : Resource, IRegistryEntry
{
    [Header("基础信息")]
    public string actionId;          // 唯一ID，如 "sword_attack_1"
    public string displayName;       // 显示名称，如 "横斩"
    public WeaponType weaponType;    // 所属武器类型
    public ActionType actionType;    // 动作类型
    public int priority;             // 动作优先级 (1~5)

    [Header("帧数据 (60fps基准)")]
    public int startupFrames = 5;    // 前摇帧数
    public int activeFrames = 4;     // 活动帧数
    public int recoveryFrames = 8;   // 后摇帧数
    
    [Header("伤害参数")]
    public float damageMultiplier = 1.0f;       // 伤害倍率
    public DamageType damageType = DamageType.Physical; // 主伤害类型
    public DamageType secondaryDamageType = DamageType.Physical; // 副伤害类型(混合伤害)
    public float primaryTypeRatio = 1.0f;       // 主类型占比(0~1)，剩余为副类型
    public float secondaryMultiplier = 0f;      // 副类型额外倍率(如回旋斩第2命中)
    public bool canHitMultiple = false;         // 是否可多次命中
    public int maxHitCount = 1;                 // 最大命中次数
    public float hitIntervalFrames = 0;         // 多次命中间隔帧数

    [Header("判定区域")]
    public HitboxShape hitboxShape;             // 判定形状
    public float hitboxRadius = 2.0f;           // 扇形/圆形半径(格)
    public float hitboxArc = 120f;              // 扇形弧度(度)
    public Vector2 hitboxOffset = Vector2.zero; // 判定中心偏移
    public float hitboxWidth = 1.0f;            // 矩形宽(格)
    public float hitboxLength = 1.5f;           // 矩形长(格)
    public float projectileSpeed = 0f;          // 弹道速度(0=非弹道)
    public float maxRange = 0f;                 // 最大射程(格)
    public int pierceCount = 0;                 // 穿透数量(0=命中消失, -1=无限)
    public float pierceDamageDecay = 0.1f;      // 每次穿透伤害衰减率
    public float pierceDamageFloor = 0.5f;      // 穿透衰减下限

    [Header("击退与硬直")]
    public float knockbackForce = 1.0f;         // 基础击退力(格)
    public float knockbackDurationFrames = 8;   // 击退持续帧数
    public bool forceLaunch = false;            // 强制浮空
    public float launchDuration = 0f;           // 浮空持续时间(秒)
    public bool breakGuard = false;             // 可破防

    [Header("取消窗口")]
    public CancelWindow[] cancelWindows;        // 取消窗口定义
    public int comboWindowStartFrame = 9;       // 连招输入起始帧
    public int comboWindowEndFrame = 21;        // 连招输入截止帧
    public string[] comboNextActions;           // 可连招转入的动作ID

    [Header("特殊效果")]
    public StatusEffectData[] applyOnHit;       // 命中时附加的状态效果
    public bool isImmortal = false;             // 动作期间无敌
    public int immortalFrames = 0;              // 无敌帧数
    public float moveSpeedModifier = 1.0f;      // 动作期间移速修正
    public float lungeDistance = 0f;            // 前冲距离(格)
    public float lungeSpeed = 0f;               // 前冲速度

    [Header("资源消耗")]
    public int timeEnergyCost = 0;              // 时之能量消耗
    public int manaCost = 0;                    // 法力消耗(杖)
    public int ammoCost = 0;                    // 弹药消耗(枪)
    public float cooldownFrames = 0;            // 冷却帧数

    [Header("动画与特效")]
    public string animationStateName;           // AnimationPlayer或AnimationTree状态名
    public string vfxId;                        // 特效ID
    public string sfxId;                        // 音效ID
    public float hitstopFrames = 0;             // 命中停顿帧数(打击感)

    // --- IRegistryEntry ---
    public string Id => actionId;

    /// <summary>
    /// 获取经过攻速修正的实际帧数
    /// </summary>
    public int GetAdjustedStartupFrames(float attackSpeed)
    {
        return math.Max(math.RoundToInt(startupFrames / attackSpeed),
                         math.RoundToInt(startupFrames * 0.4f)); // 下限40%
    }

    public int GetAdjustedActiveFrames(float attackSpeed)
    {
        return math.Max(math.RoundToInt(activeFrames / attackSpeed),
                         math.RoundToInt(activeFrames * 0.4f));
    }

    public int GetAdjustedRecoveryFrames(float attackSpeed)
    {
        return math.Max(math.RoundToInt(recoveryFrames / attackSpeed),
                         math.RoundToInt(recoveryFrames * 0.4f));
    }

    public int TotalFrames => startupFrames + activeFrames + recoveryFrames;
}

/// <summary>动作类型枚举</summary>
public enum ActionType
{
    Attack,         // 普攻
    ChargeAttack,   // 蓄力攻击
    Special,        // 特殊技
    Ultimate,       // 终极技
    Parry,          // 格挡
    Dodge,          // 闪避
    Reload,         // 换弹(枪)
    CounterAttack   // 反击
}

/// <summary>判定形状</summary>
public enum HitboxShape
{
    Sector,     // 扇形(剑/拳套)
    Circle,     // 圆形(回旋斩/终极技)
    Rectangle,  // 矩形(拳套直拳)
    Projectile, // 弹道型(弓/枪/杖)
    Area        // 区域型(法术领域/裂隙)
}

/// <summary>武器类型</summary>
public enum WeaponType
{
    Sword, Bow, Gun, Staff, Fist
}

/// <summary>伤害类型</summary>
public enum DamageType
{
    Physical,   // 物理
    Time,       // 时间
    Void,       // 虚无
    Fire,       // 火
    Ice,        // 冰
    Lightning   // 雷
}

/// <summary>取消窗口定义</summary>
[System.Serializable]
public struct CancelWindow
{
    public ActionCancelType cancelType;     // 可取消动作类型
    public int startFrame;                  // 取消窗口起始帧(从动作开始计)
    public int endFrame;                    // 取消窗口截止帧
    public float staminaMultiplier = 1.0f;  // 消耗倍率(紧急闪避=2.0)
}

public enum ActionCancelType
{
    Dodge,      // 闪避取消
    Parry,      // 格挡取消
    Special,    // 特殊技取消
    ComboNext,  // 连招下一击取消
    Charge,     // 蓄力取消
    Reload      // 换弹取消
}

/// <summary>状态效果数据</summary>
[System.Serializable]
public struct StatusEffectData
{
    public StatusEffectType effectType;
    public float duration;          // 持续时间(秒)
    public float value;             // 效果值(百分比/倍率等)
    public float probability = 1.0f; // 触发概率
}

public enum StatusEffectType
{
    TimeMark,        // 时间标记
    VoidErosion,     // 虚化
    TimeFreeze,      // 时间冻结
    TimeSlow,        // 时间减速
    Stun,            // 眩晕
    Float,           // 浮空
    Burn_DOT,        // 灼烧
    Bleed_DOT,       // 流血
    VoidErosion_DOT, // 虚无侵蚀DOT
    TimeDecay_DOT,   // 时间衰减DOT
    SwordIntent,     // 剑意(剑特有)
    TimeRift,        // 时间裂隙(区域)
    Electrified      // 感电
}
```

### 2.3 ActionData配置示例（剑第1段横斩）

```
actionId: "sword_attack_1"
displayName: "横斩"
weaponType: Sword
actionType: Attack
priority: 2

startupFrames: 5
activeFrames: 4
recoveryFrames: 8

damageMultiplier: 1.0
damageType: Physical
primaryTypeRatio: 1.0

hitboxShape: Sector
hitboxRadius: 2.0
hitboxArc: 120
hitboxOffset: (0, 0)

knockbackForce: 1.5
knockbackDurationFrames: 8

cancelWindows:
  - cancelType: Dodge, startFrame: 11, endFrame: 17
  - cancelType: Parry, startFrame: 11, endFrame: 17
  - cancelType: Special, startFrame: 11, endFrame: 17
  - cancelType: ComboNext, startFrame: 9, endFrame: 21

comboWindowStartFrame: 9
comboWindowEndFrame: 21
comboNextActions: ["sword_attack_2"]

applyOnHit: []
isImmortal: false
```

---

## 3. ActionPlayer 动作播放器

### 3.1 设计说明

ActionPlayer是战斗系统的核心驱动器，负责：
- 按帧驱动当前动作的三阶段状态机
- 管理取消窗口判定和输入缓冲
- 与Weapon层协作，在活动帧触发判定
- 在正确帧触发特效/音效/伤害事件

### 3.2 动作状态机定义

```text
/// <summary>
/// 动作播放器状态枚举
/// </summary>
public enum ActionState
{
    Idle,           // 空闲
    Startup,        // 前摇
    Active,         // 活动帧
    Recovery,       // 后摇
    Hitstun,        // 受击硬直
    Charge,         // 蓄力中
    Dodge,          // 闪避中
    Parry,          // 格挡中
    Ultimate,       // 终极技演出
    Reload          // 换弹中
}
```

### 3.3 InputBuffer 输入缓冲

```text
/// <summary>
/// 输入缓冲器 - 在可取消窗口前的输入会被缓存
/// 缓冲窗口: 8帧(通用), 12帧(连招)
/// 闪避输入优先级最高
/// </summary>
public class InputBuffer
{
    private struct BufferedInput
    {
        public InputType type;
        public int bufferedFrame;   // 输入被缓冲的帧号
        public int expireFrame;     // 过期帧号
        public int priority;        // 优先级
    }

    private readonly List<BufferedInput> _buffer = new List<BufferedInput>(4);
    private int _currentFrame;
    private const int GENERAL_BUFFER_FRAMES = 8;
    private const int COMBO_BUFFER_FRAMES = 12;

    /// <summary>缓冲输入</summary>
    public void BufferInput(InputType type, int currentFrame, int priority = 0)
    {
        int bufferFrames = type == InputType.ComboNext ? COMBO_BUFFER_FRAMES : GENERAL_BUFFER_FRAMES;
        
        // 闪避输入优先：清除低优先级缓冲
        if (type == InputType.Dodge)
        {
            _buffer.Clear();
        }
        
        _buffer.Add(new BufferedInput
        {
            type = type,
            bufferedFrame = currentFrame,
            expireFrame = currentFrame + bufferFrames,
            priority = priority
        });
    }

    /// <summary>消费最高优先级的有效缓冲输入</summary>
    public bool TryConsume(InputType expectedType, int currentFrame, out InputType consumedType)
    {
        consumedType = default;
        
        // 移除过期输入
        _buffer.RemoveAll(b => b.expireFrame < currentFrame);
        
        // 按优先级排序(闪避>格挡>特殊>连招)
        BufferedInput? best = null;
        int bestPriority = -1;
        
        for (int i = 0; i < _buffer.Count; i++)
        {
            if (_buffer[i].type == expectedType || expectedType == InputType.Any)
            {
                if (_buffer[i].priority > bestPriority)
                {
                    best = _buffer[i];
                    bestPriority = _buffer[i].priority;
                }
            }
        }
        
        if (best.HasValue)
        {
            consumedType = best.Value.type;
            _buffer.Remove(best.Value);
            return true;
        }
        
        return false;
    }

    /// <summary>检查是否有特定类型的缓冲输入</summary>
    public bool HasInput(InputType type, int currentFrame)
    {
        _buffer.RemoveAll(b => b.expireFrame < currentFrame);
        return _buffer.Exists(b => b.type == type);
    }

    /// <summary>清除所有缓冲</summary>
    public void Clear() => _buffer.Clear();
}

public enum InputType
{
    Any = -1,
    Attack = 0,
    ComboNext = 1,
    Dodge = 5,       // 最高优先级
    Parry = 4,
    Special = 3,
    Charge = 2,
    Reload = 1
}
```

### 3.4 ActionPlayer 完整代码骨架

```text
/// <summary>
/// 动作播放器 - 战斗核心驱动器
/// 按帧驱动动作三阶段状态机，管理取消窗口和输入缓冲
/// 依赖: StateMachine, EventBus, IWeapon
/// </summary>
public class ActionPlayer
{
    // === 状态 ===
    private readonly StateMachine<ActionState> _fsm;
    private ActionData _currentAction;
    private int _currentFrame;              // 当前动作内帧计数
    private int _globalFrame;               // 全局帧计数
    private float _attackSpeed = 1.0f;      // 当前攻速
    private bool _isCharging;
    private int _chargeFrames;
    private ChargeLevel _chargeLevel;
    
    // === 输入缓冲 ===
    private readonly InputBuffer _inputBuffer = new InputBuffer();
    
    // === 连招状态 ===
    private int _comboIndex;                // 当前连招段数
    private string _comboChainId;           // 当前连招链ID
    private float _comboTimeout;            // 连招超时计时器
    
    // === 冷却管理 ===
    private readonly Dictionary<string, int> _cooldowns = new Dictionary<string, int>();
    
    // === 外部依赖 ===
    private readonly IWeapon _weapon;
    private readonly PlayerController _owner;
    
    // === 事件 ===
    public event System.Action<ActionData, int> OnActionStart;
    public event System.Action<ActionData, int> OnActionFrame;     // 每帧回调
    public event System.Action<ActionData> OnActionEnd;
    public event System.Action<HitboxData> OnActiveFrameTrigger;   // 活动帧触发判定
    public event System.Action<ActionState, ActionState> OnStateChanged;

    // === 公开属性 ===
    public ActionState CurrentState => _fsm.CurrentState;
    public ActionData CurrentAction => _currentAction;
    public int CurrentFrame => _currentFrame;
    public bool IsInAction => _fsm.CurrentState != ActionState.Idle;
    public bool CanCancel => IsInCancelWindow();
    public float AttackSpeed => _attackSpeed;

    public ActionPlayer(PlayerController owner, IWeapon weapon)
    {
        _owner = owner;
        _weapon = weapon;
        _fsm = new StateMachine<ActionState>();
        
        RegisterStates();
        RegisterTransitions();
    }

    // ===== 状态注册 =====
    
    private void RegisterStates()
    {
        _fsm.RegisterState(ActionState.Idle, new IdleStateLogic(this));
        _fsm.RegisterState(ActionState.Startup, new StartupStateLogic(this));
        _fsm.RegisterState(ActionState.Active, new ActiveStateLogic(this));
        _fsm.RegisterState(ActionState.Recovery, new RecoveryStateLogic(this));
        _fsm.RegisterState(ActionState.Hitstun, new HitstunStateLogic(this));
        _fsm.RegisterState(ActionState.Charge, new ChargeStateLogic(this));
        _fsm.RegisterState(ActionState.Dodge, new DodgeStateLogic(this));
        _fsm.RegisterState(ActionState.Parry, new ParryStateLogic(this));
        _fsm.RegisterState(ActionState.Ultimate, new UltimateStateLogic(this));
        _fsm.RegisterState(ActionState.Reload, new ReloadStateLogic(this));
    }

    private void RegisterTransitions()
    {
        // 闪避可中断大部分动作
        _fsm.AddTransition(ActionState.Startup, ActionState.Dodge, () => CheckBufferedDodge());
        _fsm.AddTransition(ActionState.Active, ActionState.Dodge, () => CheckBufferedDodge());
        _fsm.AddTransition(ActionState.Recovery, ActionState.Dodge, () => CheckBufferedDodge());
        _fsm.AddTransition(ActionState.Charge, ActionState.Dodge, () => CheckBufferedDodge());
        
        // 后摇可被多种动作取消
        _fsm.AddTransition(ActionState.Recovery, ActionState.Startup, () => CheckBufferedAttack());
        _fsm.AddTransition(ActionState.Recovery, ActionState.Parry, () => CheckBufferedParry());
        _fsm.AddTransition(ActionState.Recovery, ActionState.Charge, () => CheckBufferedCharge());
        
        // 硬直恢复
        _fsm.AddTransition(ActionState.Hitstun, ActionState.Idle, () => _currentFrame >= GetHitstunDuration());
        _fsm.AddTransition(ActionState.Hitstun, ActionState.Dodge, () => CheckEmergencyDodge());
        
        // 动作完成回归Idle
        _fsm.AddTransition(ActionState.Startup, ActionState.Active, () => _currentFrame >= GetAdjustedStartup());
        _fsm.AddTransition(ActionState.Active, ActionState.Recovery, () => _currentFrame >= GetAdjustedActive());
        _fsm.AddTransition(ActionState.Recovery, ActionState.Idle, () => _currentFrame >= GetAdjustedRecovery());
    }

    // ===== 主循环更新 =====
    
    /// <summary>
    /// 每固定帧调用(FixedUpdate, 60Hz)
    /// </summary>
    public void Update()
    {
        _globalFrame++;
        _fsm.Update();
        UpdateCooldowns();
        UpdateComboTimeout();
    }

    /// <summary>
    /// 物理帧更新(FixedUpdate)
    /// </summary>
    public void FixedUpdate()
    {
        _fsm.FixedUpdate();
    }

    // ===== 动作触发接口 =====
    
    /// <summary>请求播放动作</summary>
    public bool RequestAction(ActionData action)
    {
        if (!CanStartAction(action)) return false;
        
        StartAction(action);
        return true;
    }
    
    /// <summary>请求攻击(普攻/连招)</summary>
    public bool RequestAttack()
    {
        if (_weapon == null) return false;
        
        // 如果在连招窗口内，请求下一击
        if (IsInComboWindow() && _inputBuffer.HasInput(InputType.ComboNext, _globalFrame))
        {
            string nextActionId = _weapon.GetNextComboAction(_comboIndex);
            if (!string.IsNullOrEmpty(nextActionId))
            {
                ActionData nextAction = Registry<ActionData>.Instance.Get(nextActionId);
                if (nextAction != null)
                {
                    _comboIndex++;
                    return RequestAction(nextAction);
                }
            }
        }
        
        // 否则从第1段开始
        _comboIndex = 0;
        ActionData firstAction = _weapon.GetFirstComboAction();
        return RequestAction(firstAction);
    }
    
    /// <summary>请求闪避</summary>
    public bool RequestDodge()
    {
        _inputBuffer.BufferInput(InputType.Dodge, _globalFrame, (int)InputType.Dodge);
        
        if (_fsm.CurrentState == ActionState.Idle || IsInCancelWindowFor(ActionCancelType.Dodge))
        {
            ActionData dodgeAction = _weapon.GetDodgeActionData();
            if (dodgeAction != null)
            {
                return RequestAction(dodgeAction);
            }
        }
        return false;
    }
    
    /// <summary>请求格挡</summary>
    public bool RequestParry()
    {
        _inputBuffer.BufferInput(InputType.Parry, _globalFrame, (int)InputType.Parry);
        
        if (_fsm.CurrentState == ActionState.Idle || IsInCancelWindowFor(ActionCancelType.Parry))
        {
            ActionData parryAction = _weapon.GetParryActionData();
            if (parryAction != null)
            {
                return RequestAction(parryAction);
            }
        }
        return false;
    }
    
    /// <summary>请求特殊技</summary>
    public bool RequestSpecial()
    {
        _inputBuffer.BufferInput(InputType.Special, _globalFrame, (int)InputType.Special);
        
        if (IsInCancelWindowFor(ActionCancelType.Special))
        {
            ActionData specialAction = _weapon.GetSpecialActionData();
            if (specialAction != null && IsCooldownReady(specialAction.actionId) &&
                _owner.TimeEnergy >= specialAction.timeEnergyCost)
            {
                _owner.ConsumeTimeEnergy(specialAction.timeEnergyCost);
                return RequestAction(specialAction);
            }
        }
        return false;
    }
    
    /// <summary>请求终极技</summary>
    public bool RequestUltimate()
    {
        ActionData ultimateAction = _weapon.GetUltimateActionData();
        if (ultimateAction != null && IsCooldownReady(ultimateAction.actionId) &&
            _owner.TimeEnergy >= ultimateAction.timeEnergyCost &&
            _fsm.CurrentState == ActionState.Idle)
        {
            _owner.ConsumeTimeEnergy(ultimateAction.timeEnergyCost);
            return RequestAction(ultimateAction);
        }
        return false;
    }
    
    /// <summary>请求蓄力</summary>
    public bool RequestCharge()
    {
        if (_fsm.CurrentState == ActionState.Idle || IsInCancelWindowFor(ActionCancelType.Charge))
        {
            _fsm.TransitionTo(ActionState.Charge);
            _isCharging = true;
            _chargeFrames = 0;
            _chargeLevel = ChargeLevel.None;
            return true;
        }
        return false;
    }
    
    /// <summary>释放蓄力</summary>
    public bool ReleaseCharge()
    {
        if (!_isCharging) return false;
        
        ActionData chargeAction = _weapon.GetChargeAction(_chargeLevel);
        _isCharging = false;
        
        if (chargeAction != null)
        {
            return RequestAction(chargeAction);
        }
        return false;
    }

    /// <summary>强制进入受击硬直</summary>
    public void ForceHitstun(int durationFrames, HitstunLevel level)
    {
        CancelCurrentAction();
        _currentFrame = 0;
        _fsm.TransitionTo(ActionState.Hitstun);
        EventBus.Publish(new HitstunEvent
        {
            TargetId = _owner.EntityId,
            Level = level,
            DurationFrames = durationFrames
        });
    }

    // ===== 内部方法 =====
    
    private void StartAction(ActionData action)
    {
        _currentAction = action;
        _currentFrame = 0;
        
        // 设置冷却
        if (action.cooldownFrames > 0)
        {
            _cooldowns[action.actionId] = _globalFrame + math.RoundToInt(action.cooldownFrames / _attackSpeed);
        }
        
        // 切换状态
        ActionState targetState = action.actionType switch
        {
            ActionType.Dodge => ActionState.Dodge,
            ActionType.Parry => ActionState.Parry,
            ActionType.Ultimate => ActionState.Ultimate,
            ActionType.Reload => ActionState.Reload,
            _ => ActionState.Startup
        };
        
        _fsm.TransitionTo(targetState);
        OnActionStart?.Invoke(action, _globalFrame);
        
        // 播放动画
        _owner.PlayAnimation(action.animationStateName);
        
        // 播放音效
        if (!string.IsNullOrEmpty(action.sfxId))
        {
            ServiceRegistry.Get<IAudioManager>().PlaySFX(action.sfxId, _owner.Position);
        }
    }
    
    private void CancelCurrentAction()
    {
        if (_currentAction != null)
        {
            EventBus.Publish(new ActionCancelEvent
            {
                ActionId = _currentAction.actionId,
                CancelFrame = _currentFrame,
                Reason = ActionCancelReason.Hit
            });
            OnActionEnd?.Invoke(_currentAction);
            _currentAction = null;
        }
    }
    
    private bool CanStartAction(ActionData action)
    {
        // 冷却检查
        if (!IsCooldownReady(action.actionId)) return false;
        
        // 资源检查
        if (action.timeEnergyCost > 0 && _owner.TimeEnergy < action.timeEnergyCost) return false;
        if (action.manaCost > 0 && _owner.Mana < action.manaCost) return false;
        if (action.ammoCost > 0 && _owner.Ammo < action.ammoCost) return false;
        
        // 状态检查: 空闲/后摇/可取消窗口
        if (_fsm.CurrentState == ActionState.Idle) return true;
        if (_fsm.CurrentState == ActionState.Recovery && IsInCancelWindow()) return true;
        
        return false;
    }
    
    private bool IsInCancelWindow()
    {
        if (_currentAction == null) return false;
        
        int adjustedStartup = _currentAction.GetAdjustedStartupFrames(_attackSpeed);
        int adjustedActive = _currentAction.GetAdjustedActiveFrames(_attackSpeed);
        int currentPhaseStart = adjustedStartup + adjustedActive;
        
        for (int i = 0; i < _currentAction.cancelWindows.Length; i++)
        {
            var window = _currentAction.cancelWindows[i];
            int startFrame = currentPhaseStart + (window.startFrame - (adjustedStartup + adjustedActive));
            if (_currentFrame >= window.startFrame && _currentFrame <= window.endFrame)
            {
                return true;
            }
        }
        
        return false;
    }
    
    private bool IsInCancelWindowFor(ActionCancelType cancelType)
    {
        if (_currentAction == null || _fsm.CurrentState == ActionState.Idle) return true;
        
        for (int i = 0; i < _currentAction.cancelWindows.Length; i++)
        {
            var window = _currentAction.cancelWindows[i];
            if (window.cancelType == cancelType && 
                _currentFrame >= window.startFrame && _currentFrame <= window.endFrame)
            {
                return true;
            }
        }
        return false;
    }
    
    private bool IsInComboWindow()
    {
        if (_currentAction == null) return false;
        return _currentFrame >= _currentAction.comboWindowStartFrame &&
               _currentFrame <= _currentAction.comboWindowEndFrame;
    }
    
    private bool CheckBufferedDodge()
    {
        return _inputBuffer.TryConsume(InputType.Dodge, _globalFrame, out _);
    }
    
    private bool CheckBufferedAttack()
    {
        return _inputBuffer.TryConsume(InputType.ComboNext, _globalFrame, out _) ||
               _inputBuffer.TryConsume(InputType.Attack, _globalFrame, out _);
    }
    
    private bool CheckBufferedParry()
    {
        return _inputBuffer.TryConsume(InputType.Parry, _globalFrame, out _);
    }
    
    private bool CheckBufferedCharge()
    {
        return _inputBuffer.TryConsume(InputType.Charge, _globalFrame, out _);
    }
    
    /// <summary>紧急闪避: 受击硬直第4帧起可闪避，消耗2倍闪避耐力</summary>
    private bool CheckEmergencyDodge()
    {
        int hitstunDuration = GetHitstunDuration();
        if (_currentFrame >= 3 && _currentFrame < hitstunDuration) // 第4帧起
        {
            if (_inputBuffer.HasInput(InputType.Dodge, _globalFrame))
            {
                // TODO: 检查2倍闪避耐力
                return true;
            }
        }
        return false;
    }
    
    private int GetHitstunDuration() => _currentAction?.recoveryFrames ?? 20;
    private int GetAdjustedStartup() => _currentAction?.GetAdjustedStartupFrames(_attackSpeed) ?? 0;
    private int GetAdjustedActive() => _currentAction?.GetAdjustedActiveFrames(_attackSpeed) ?? 0;
    private int GetAdjustedRecovery() => _currentAction?.GetAdjustedRecoveryFrames(_attackSpeed) ?? 0;
    
    private bool IsCooldownReady(string actionId)
    {
        return !_cooldowns.TryGetValue(actionId, out int readyFrame) || _globalFrame >= readyFrame;
    }
    
    private void UpdateCooldowns()
    {
        // 冷却自然过期由IsCooldownReady检查，无需主动清理
    }
    
    private void UpdateComboTimeout()
    {
        if (_comboIndex > 0)
        {
            _comboTimeout -= Time.fixedDeltaTime;
            if (_comboTimeout <= 0)
            {
                _comboIndex = 0; // 超时重置连招
            }
        }
    }
    
    /// <summary>设置攻速(外部调用，属性变更时)</summary>
    public void SetAttackSpeed(float speed)
    {
        _attackSpeed = math.Clamp(speed, 0.4f, 2.5f);
    }
}

// ===== 各状态逻辑实现 =====

/// <summary>空闲状态</summary>
public class IdleStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public IdleStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { }
    public void Update() { }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>前摇状态</summary>
public class StartupStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public StartupStateLogic(ActionPlayer player) => _player = player;
    
    public void Enter()
    {
        _player._currentFrame = 0;
    }
    
    public void Update()
    {
        _player._currentFrame++;
        _player.OnActionFrame?.Invoke(_player._currentAction, _player._currentFrame);
    }
    
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>活动帧状态 - 触发判定</summary>
public class ActiveStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    private bool _hasTriggered;
    
    public ActiveStateLogic(ActionPlayer player) => _player = player;
    
    public void Enter()
    {
        _player._currentFrame = 0;
        _hasTriggered = false;
    }
    
    public void Update()
    {
        _player._currentFrame++;
        
        // 在活动帧第1帧触发判定
        if (!_hasTriggered && _player._currentFrame == 1)
        {
            _hasTriggered = true;
            HitboxData hitbox = CreateHitboxFromAction(_player._currentAction);
            _player.OnActiveFrameTrigger?.Invoke(hitbox);
        }
        
        _player.OnActionFrame?.Invoke(_player._currentAction, _player._currentFrame);
    }
    
    public void FixedUpdate() { }
    public void Exit() { }
    
    private HitboxData CreateHitboxFromAction(ActionData action)
    {
        // 将ActionData的判定参数转为HitboxData
        return new HitboxData
        {
            shape = action.hitboxShape,
            radius = action.hitboxRadius,
            arc = action.hitboxArc,
            offset = action.hitboxOffset,
            width = action.hitboxWidth,
            length = action.hitboxLength,
            damageMultiplier = action.damageMultiplier,
            damageType = action.damageType,
            knockbackForce = action.knockbackForce,
            knockbackDurationFrames = action.knockbackDurationFrames,
            ownerEntityId = _player._owner.EntityId
        };
    }
}

/// <summary>后摇状态</summary>
public class RecoveryStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public RecoveryStateLogic(ActionPlayer player) => _player = player;
    
    public void Enter()
    {
        _player._currentFrame = 0;
    }
    
    public void Update()
    {
        _player._currentFrame++;
        _player.OnActionFrame?.Invoke(_player._currentAction, _player._currentFrame);
    }
    
    public void FixedUpdate() { }
    public void Exit()
    {
        if (_player._currentAction != null)
        {
            _player.OnActionEnd?.Invoke(_player._currentAction);
        }
    }
}

/// <summary>受击硬直状态</summary>
public class HitstunStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public HitstunStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._currentFrame = 0; }
    public void Update() { _player._currentFrame++; }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>蓄力状态</summary>
public class ChargeStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public ChargeStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._chargeFrames = 0; _player._chargeLevel = ChargeLevel.None; }
    public void Update()
    {
        _player._chargeFrames++;
        // 根据蓄力帧数更新阶段
        if (_player._chargeFrames >= 36) _player._chargeLevel = ChargeLevel.Level2;
        else if (_player._chargeFrames >= 18) _player._chargeLevel = ChargeLevel.Level1;
        else _player._chargeLevel = ChargeLevel.Level0;
    }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>闪避状态</summary>
public class DodgeStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public DodgeStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._currentFrame = 0; }
    public void Update() { _player._currentFrame++; }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>格挡状态</summary>
public class ParryStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public ParryStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._currentFrame = 0; }
    public void Update() { _player._currentFrame++; }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>终极技状态(不可取消)</summary>
public class UltimateStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public UltimateStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._currentFrame = 0; }
    public void Update() { _player._currentFrame++; }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>换弹状态</summary>
public class ReloadStateLogic : IStateLogic
{
    private readonly ActionPlayer _player;
    public ReloadStateLogic(ActionPlayer player) => _player = player;
    public void Enter() { _player._currentFrame = 0; }
    public void Update() { _player._currentFrame++; }
    public void FixedUpdate() { }
    public void Exit() { }
}

/// <summary>蓄力阶段</summary>
public enum ChargeLevel
{
    None = -1,
    Level0 = 0,  // 0~18帧
    Level1 = 1,  // 18~36帧
    Level2 = 2   // 36帧+
}
```

---

## 4. DamageCalculator 伤害计算器

### 4.1 设计说明

DamageCalculator为RefCounted/静态工具脚本，无Node依赖，100%可单元测试。实现四种伤害公式（物理/时间/虚无/元素），暴击系统、防御减伤、DOT计算、伤害类型交互。

### 4.2 伤害公式汇总

| 伤害类型 | 公式 | 特性 |
|---------|------|------|
| 物理 | `FATK × 倍率 × (1 - DEF/(DEF+K)) × 暴击 × 波动` | 受DEF全额减免 |
| 时间 | `FATK × TDM × 时间倍率 × (1 - 时间抗性) × 时间易伤 × 暴击 × 波动` | 无视50%DEF |
| 虚无 | `FATK × VDM × 虚无倍率 × (1+虚无共鸣) × (1 - 虚无抗性) × 虚无易伤 × 波动` | 无视100%DEF，不可暴击 |
| 元素 | `FATK × 倍率 × (1 - DEF/(DEF+K)×0.5) × 元素抗性修正 × 暴击 × 波动` | 受DEF半额减免 |

### 4.3 完整GDScript实现

```text
/// <summary>
/// 伤害计算器 - RefCounted/静态工具脚本，无Node依赖
/// 实现四种伤害公式、暴击、防御减伤、DOT、伤害类型交互
/// 所有公式基于设计文档3.1.2和4.2.2节
/// </summary>
public static class DamageCalculator
{
    // ===== 常量 =====
    private const float VARIANCE_MIN = 0.95f;       // 随机波动下限
    private const float VARIANCE_MAX = 1.05f;        // 随机波动上限
    private const float CRIT_RATE_CAP = 0.75f;       // 暴击率硬上限
    private const float CRIT_DAMAGE_MIN = 1.0f;      // 暴击伤害下限
    private const float DAMAGE_REDUCTION_CAP = 0.90f; // 总减伤上限(至少受10%)
    private const int PITY_CRIT_THRESHOLD = 5;       // 保底暴击：连续5次非暴击后必暴
    private const float DEF_CONST_BASE = 50f;        // 减伤常数K基础值
    private const float DEF_CONST_PER_LEVEL = 5f;    // 每级减伤常数增量
    private const float TIME_DEF_IGNORE = 0.5f;      // 时间伤害无视50%DEF
    private const float VOID_ABNORMAL_BONUS = 0.25f;  // 虚无对异常状态目标+25%
    
    // ===== 主计算入口 =====
    
    /// <summary>
    /// 计算最终伤害 - 主入口
    /// </summary>
    /// <param name="context">攻击方上下文(属性、等级等)</param>
    /// <param name="target">防御方上下文(属性、抗性等)</param>
    /// <param name="action">动作数据(倍率、伤害类型等)</param>
    /// <param name="rng">确定性随机数生成器</param>
    /// <returns>伤害计算结果</returns>
    public static DamageResult CalculateDamage(
        AttackerContext context,
        DefenderContext target,
        ActionData action,
        RNG rng)
    {
        var result = new DamageResult();
        
        float fatk = CalculateFinalATK(context);
        
        // 计算主伤害类型伤害
        float primaryRatio = action.primaryTypeRatio;
        float secondaryRatio = 1.0f - primaryRatio;
        
        // 主类型伤害
        if (primaryRatio > 0f)
        {
            result.PrimaryDamage = CalculateTypedDamage(
                fatk, action.damageType, action.damageMultiplier,
                primaryRatio, context, target, rng);
        }
        
        // 副类型伤害(混合伤害)
        if (secondaryRatio > 0f && action.secondaryDamageType != action.damageType)
        {
            result.SecondaryDamage = CalculateTypedDamage(
                fatk, action.secondaryDamageType, 
                action.secondaryMultiplier > 0 ? action.secondaryMultiplier : action.damageMultiplier,
                secondaryRatio, context, target, rng);
        }
        
        // 伤害类型交互
        DamageTypeInteractionResult interaction = CheckDamageTypeInteraction(
            action.damageType, action.secondaryDamageType, primaryRatio, secondaryRatio,
            fatk, context, target);
        
        if (interaction.Triggered)
        {
            result.InteractionBonus = interaction.BonusDamage;
            result.InteractionType = interaction.Type;
            result.AppliedStatusEffect = interaction.StatusEffect;
        }
        
        // 最终乘区(诅咒、特殊Buff等)
        float finalMultiplier = CalculateFinalMultiplier(context);
        
        // 汇总
        result.TotalDamage = math.Floor(
            (result.PrimaryDamage + result.SecondaryDamage + result.InteractionBonus)
            * finalMultiplier);
        
        result.TotalDamage = math.Max(1, result.TotalDamage); // 最低1点伤害
        
        // 发布事件
        EventBus.Publish(new DamageDealtEvent
        {
            SourceId = context.EntityId,
            TargetId = target.EntityId,
            Damage = new DamageInfo
            {
                BaseDamage = result.TotalDamage,
                Type = action.damageType,
                SourceId = context.EntityId
            },
            FinalDamage = result.TotalDamage
        });
        
        return result;
    }
    
    // ===== 按类型计算 =====
    
    /// <summary>
    /// 按伤害类型计算伤害
    /// </summary>
    private static float CalculateTypedDamage(
        float fatk,
        DamageType type,
        float multiplier,
        float typeRatio,
        AttackerContext context,
        DefenderContext target,
        RNG rng)
    {
        float baseDamage = fatk * multiplier * typeRatio;
        float finalDamage;
        
        switch (type)
        {
            case DamageType.Physical:
                finalDamage = CalculatePhysicalDamage(baseDamage, context, target, rng);
                break;
                
            case DamageType.Time:
                finalDamage = CalculateTimeDamage(baseDamage, context, target, rng);
                break;
                
            case DamageType.Void:
                finalDamage = CalculateVoidDamage(baseDamage, context, target, rng);
                break;
                
            case DamageType.Fire:
            case DamageType.Ice:
            case DamageType.Lightning:
                finalDamage = CalculateElementalDamage(baseDamage, type, context, target, rng);
                break;
                
            default:
                finalDamage = baseDamage;
                break;
        }
        
        return finalDamage;
    }
    
    /// <summary>
    /// 物理伤害公式
    /// 最终伤害 = (FATK × 倍率 × 类型占比 - 防御减伤值) × 暴击修正 × 随机波动
    /// 防御减伤率 = DEF / (DEF + K), K = 50 + 攻击者等级 × 5
    /// </summary>
    private static float CalculatePhysicalDamage(
        float baseDamage,
        AttackerContext context,
        DefenderContext target,
        RNG rng)
    {
        // 防御减伤
        float effectiveDef = math.Max(0f, target.FinalDEF - context.ArmorPenetration);
        float k = DEF_CONST_BASE + context.Level * DEF_CONST_PER_LEVEL;
        float defReduction = effectiveDef / (effectiveDef + k);
        
        float afterDef = baseDamage * (1f - defReduction);
        
        // 独立减伤(祝福/道具)
        float afterIndependentReduction = ApplyIndependentReduction(afterDef, target);
        
        // 暴击
        float critMultiplier = RollCrit(context.CritRate, context.CritDamage, rng);
        
        // 随机波动
        float variance = rng.NextFloat(VARIANCE_MIN, VARIANCE_MAX);
        
        return afterIndependentReduction * critMultiplier * variance;
    }
    
    /// <summary>
    /// 时间伤害公式
    /// 最终伤害 = FATK × TDM × 时间倍率 × (1 - 目标时间抗性) × 时间易伤乘区 × 暴击 × 波动
    /// 关键特性：无视50%DEF（实际DEF减半计算）
    /// </summary>
    private static float CalculateTimeDamage(
        float baseDamage,
        AttackerContext context,
        DefenderContext target,
        RNG rng)
    {
        // 时间伤害无视50%DEF
        float effectiveDef = math.Max(0f, (target.FinalDEF * TIME_DEF_IGNORE) - context.ArmorPenetration);
        float k = DEF_CONST_BASE + context.Level * DEF_CONST_PER_LEVEL;
        float defReduction = effectiveDef / (effectiveDef + k);
        
        float afterDef = baseDamage * (1f - defReduction);
        
        // 时间抗性
        float afterResist = afterDef * (1f - target.TimeResistance);
        
        // 时间易伤乘区(冻结+30%等)
        float timeVulnerability = 1f;
        foreach (var vul in target.TimeVulnerabilities)
        {
            timeVulnerability *= (1f + vul);
        }
        float afterVuln = afterResist * timeVulnerability;
        
        // 时间伤害系数(TDM)
        float afterTDM = afterVuln * context.TimeDamageMultiplier;
        
        // 独立减伤
        float afterReduction = ApplyIndependentReduction(afterTDM, target);
        
        // 暴击(时间暴击独立计算)
        float timeCritRate = context.CritRate + context.TimeCritBonus; // 时间领主额外+15%
        float critMultiplier = RollCrit(timeCritRate, context.CritDamage, rng);
        
        // 随机波动
        float variance = rng.NextFloat(VARIANCE_MIN, VARIANCE_MAX);
        
        return afterReduction * critMultiplier * variance;
    }
    
    /// <summary>
    /// 虚无伤害公式
    /// 最终伤害 = FATK × VDM × 虚无倍率 × (1+虚无共鸣) × (1 - 虚无抗性) × 虚无易伤 × 波动
    /// 关键特性：无视100%DEF；不可暴击；对异常状态目标+25%
    /// </summary>
    private static float CalculateVoidDamage(
        float baseDamage,
        AttackerContext context,
        DefenderContext target,
        RNG rng)
    {
        // 虚无伤害完全无视DEF，无防御减伤计算
        
        // VDM虚无伤害系数
        float afterVDM = baseDamage * context.VoidDamageMultiplier;
        
        // 虚无共鸣加成(虚空行者被动，HP越低越高)
        float afterResonance = afterVDM * (1f + context.VoidResonanceBonus);
        
        // 异常状态目标+25%
        if (target.HasAbnormalStatus)
        {
            afterResonance *= (1f + VOID_ABNORMAL_BONUS);
        }
        
        // 虚无抗性
        float afterResist = afterResonance * (1f - target.VoidResistance);
        
        // 虚无易伤乘区(虚化+15%等)
        float voidVulnerability = 1f;
        foreach (var vul in target.VoidVulnerabilities)
        {
            voidVulnerability *= (1f + vul);
        }
        float afterVuln = afterResist * voidVulnerability;
        
        // 独立减伤
        float afterReduction = ApplyIndependentReduction(afterVuln, target);
        
        // 虚无伤害不可暴击
        
        // 随机波动
        float variance = rng.NextFloat(VARIANCE_MIN, VARIANCE_MAX);
        
        return afterReduction * variance;
    }
    
    /// <summary>
    /// 元素伤害公式
    /// 最终伤害 = FATK × 倍率 × (1 - DEF/(DEF+K)×0.5) × 元素抗性修正 × 暴击 × 波动
    /// 受DEF半额减免
    /// </summary>
    private static float CalculateElementalDamage(
        float baseDamage,
        DamageType elementType,
        AttackerContext context,
        DefenderContext target,
        RNG rng)
    {
        // 元素伤害受DEF半额减免
        float effectiveDef = math.Max(0f, (target.FinalDEF * 0.5f) - context.ArmorPenetration);
        float k = DEF_CONST_BASE + context.Level * DEF_CONST_PER_LEVEL;
        float defReduction = effectiveDef / (effectiveDef + k);
        
        float afterDef = baseDamage * (1f - defReduction);
        
        // 元素抗性
        float elementResist = elementType switch
        {
            DamageType.Fire => target.FireResistance,
            DamageType.Ice => target.IceResistance,
            DamageType.Lightning => target.LightningResistance,
            _ => 0f
        };
        float afterResist = afterDef * (1f - elementResist);
        
        // 独立减伤
        float afterReduction = ApplyIndependentReduction(afterResist, target);
        
        // 暴击
        float critMultiplier = RollCrit(context.CritRate, context.CritDamage, rng);
        
        // 随机波动
        float variance = rng.NextFloat(VARIANCE_MIN, VARIANCE_MAX);
        
        return afterReduction * critMultiplier * variance;
    }
    
    // ===== 暴击系统 =====
    
    /// <summary>
    /// 暴击判定与伤害计算
    /// 保底暴击：连续5次非暴击后第6次必定暴击
    /// </summary>
    private static float RollCrit(float critRate, float critDamage, RNG rng)
    {
        // 硬上限75%
        float effectiveCritRate = math.Min(critRate, CRIT_RATE_CAP);
        
        bool isCrit;
        if (_nonCritCount >= PITY_CRIT_THRESHOLD)
        {
            isCrit = true;
            _nonCritCount = 0;
        }
        else
        {
            isCrit = rng.NextFloat(0f, 1f) < effectiveCritRate;
            if (isCrit)
            {
                _nonCritCount = 0;
            }
            else
            {
                _nonCritCount++;
            }
        }
        
        if (!isCrit) return 1.0f;
        
        // 暴击伤害下限100%
        float effectiveCritDamage = math.Max(critDamage, CRIT_DAMAGE_MIN);
        return effectiveCritDamage;
    }
    
    // 保底暴击计数器(静态，按攻击者实例化时应改为实例变量)
    // TODO(Combat): 改为AttackerContext内字段，避免多攻击者共享状态
    private static int _nonCritCount = 0;
    
    // ===== 防御与减伤 =====
    
    /// <summary>
    /// 独立减伤叠加(每种减伤来源独立乘算)
    /// 最终受伤 = 原始伤害 × (1-A) × (1-B) × (1-C) ...
    /// 总减伤上限90%(至少受10%伤害)
    /// </summary>
    private static float ApplyIndependentReduction(float damage, DefenderContext target)
    {
        float remaining = damage;
        
        foreach (float reduction in target.IndependentReductions)
        {
            remaining *= (1f - reduction);
        }
        
        // 总减伤上限
        float maxReduction = damage * DAMAGE_REDUCTION_CAP;
        return math.Max(remaining, damage - maxReduction);
    }
    
    /// <summary>
    /// 软上限计算
    /// 有效加成 = 软上限值 + (实际值 - 软上限值) × 效率系数
    /// </summary>
    public static float ApplySoftCap(float value, float softCap, float efficiency)
    {
        if (value <= softCap) return value;
        return softCap + (value - softCap) * efficiency;
    }
    
    // ===== 最终攻击力计算 =====
    
    /// <summary>
    /// FATK = (BATK + Σ固定加成) × (1 + ATK%有效值) 
    /// ATK%有软上限：+150%，超出×50%效率
    /// </summary>
    public static float CalculateFinalATK(AttackerContext context)
    {
        float atkPercentEffective = ApplySoftCap(context.ATKPercent, 1.5f, 0.5f);
        // 硬上限+300%
        atkPercentEffective = math.Min(atkPercentEffective, 3.0f);
        
        return (context.BaseATK + context.FlatATKBonus) * (1f + atkPercentEffective);
    }
    
    /// <summary>
    /// 最终防御力计算
    /// FDEF = (BDEF + Σ固定加成) × (1 + DEF%有效值)
    /// DEF%软上限：+120%，超出×30%效率
    /// </summary>
    public static float CalculateFinalDEF(DefenderContext context)
    {
        float defPercentEffective = ApplySoftCap(context.DEFPercent, 1.2f, 0.3f);
        defPercentEffective = math.Min(defPercentEffective, 2.0f);
        
        return (context.BaseDEF + context.FlatDEFBonus) * (1f + defPercentEffective);
    }
    
    // ===== 最终乘区 =====
    
    /// <summary>
    /// 最终乘区(诅咒效果、特殊Buff等)
    /// </summary>
    private static float CalculateFinalMultiplier(AttackerContext context)
    {
        float multiplier = 1f;
        foreach (float m in context.FinalMultipliers)
        {
            multiplier *= m;
        }
        return multiplier;
    }
    
    // ===== 伤害类型交互 =====
    
    /// <summary>
    /// 伤害类型交互判定
    /// 同一击中同时存在两种伤害类型时触发
    /// </summary>
    private static DamageTypeInteractionResult CheckDamageTypeInteraction(
        DamageType primary, DamageType secondary,
        float primaryRatio, float secondaryRatio,
        float fatk, AttackerContext context, DefenderContext target)
    {
        var result = new DamageTypeInteractionResult();
        
        // 只有混合伤害(两种类型占比均>0)才触发交互
        if (primaryRatio <= 0f || secondaryRatio <= 0f) return result;
        
        // 归一化类型对(确保排序一致)
        (DamageType a, DamageType b) = NormalizeTypePair(primary, secondary);
        
        float bonusDamage = 0f;
        StatusEffectData? statusEffect = null;
        
        if (a == DamageType.Physical && b == DamageType.Time)
        {
            // 物理+时间 → 时断打击：+15%伤害，硬直+8帧
            bonusDamage = fatk * 0.15f;
            statusEffect = new StatusEffectData
            {
                effectType = StatusEffectType.Stun,
                duration = 8f / 60f, // 8帧换算秒
                value = 8 // 额外硬直帧数
            };
            result.Type = DamageTypeInteractionType.PhysTime;
        }
        else if (a == DamageType.Physical && b == DamageType.Void)
        {
            // 物理+虚无 → 虚空裂伤：+20%伤害，流血DOT 3秒
            bonusDamage = fatk * 0.20f;
            statusEffect = new StatusEffectData
            {
                effectType = StatusEffectType.Bleed_DOT,
                duration = 6f, // 6秒12刻
                value = 0.08f  // 每刻8%攻击力
            };
            result.Type = DamageTypeInteractionType.PhysVoid;
        }
        else if (a == DamageType.Time && b == DamageType.Void)
        {
            // 时间+虚无 → 熵增：+30%伤害，时间标记5秒
            bonusDamage = fatk * 0.30f;
            statusEffect = new StatusEffectData
            {
                effectType = StatusEffectType.TimeMark,
                duration = 5f,
                value = 0.5f // 受到时间伤害+50%
            };
            result.Type = DamageTypeInteractionType.TimeVoid;
        }
        else if (a == DamageType.Physical && IsElemental(b))
        {
            // 物理+元素 → 元素共鸣：+10%伤害，50%攻击力同类型元素二次伤害
            bonusDamage = fatk * 0.10f + fatk * 0.5f; // +10% + 额外50%元素伤害
            result.Type = DamageTypeInteractionType.PhysElement;
        }
        else if (a == DamageType.Time && IsElemental(b))
        {
            // 时间+元素 → 时空风暴：+20%伤害，半径2格时空力场3秒
            bonusDamage = fatk * 0.20f;
            statusEffect = new StatusEffectData
            {
                effectType = StatusEffectType.TimeRift,
                duration = 3f,
                value = 0.3f // 减速30%
            };
            result.Type = DamageTypeInteractionType.TimeElement;
        }
        else if (a == DamageType.Void && IsElemental(b))
        {
            // 虚无+元素 → 虚化焰：+25%伤害，虚化3秒
            bonusDamage = fatk * 0.25f;
            statusEffect = new StatusEffectData
            {
                effectType = StatusEffectType.VoidErosion,
                duration = 3f,
                value = 0.15f // 受伤+15%
            };
            result.Type = DamageTypeInteractionType.VoidElement;
        }
        
        if (bonusDamage > 0f)
        {
            result.Triggered = true;
            result.BonusDamage = bonusDamage;
            result.StatusEffect = statusEffect;
        }
        
        return result;
    }
    
    private static (DamageType, DamageType) NormalizeTypePair(DamageType a, DamageType b)
    {
        // 将元素类型统一为排序比较
        int ia = IsElemental(a) ? (int)DamageType.Fire : (int)a; // 元素统一排最后
        int ib = IsElemental(b) ? (int)DamageType.Fire : (int)b;
        return ia <= ib ? (a, b) : (b, a);
    }
    
    private static bool IsElemental(DamageType type) =>
        type == DamageType.Fire || type == DamageType.Ice || type == DamageType.Lightning;
    
    // ===== DOT伤害计算 =====
    
    /// <summary>
    /// DOT每刻伤害计算
    /// 刻间隔: 30帧(0.5秒/次)
    /// DOT不暴击(来源暴击时初始DOT值+20%)
    /// 同类型取最高不叠加；不同类型各自独立
    /// </summary>
    public static float CalculateDOTDamage(
        DOTType dotType,
        float attackerATK,
        float dotMultiplier,
        float dotAmplifier,
        bool sourceWasCrit,
        RNG rng)
    {
        float baseDOT = attackerATK * dotMultiplier;
        
        // 来源暴击时初始DOT值+20%
        if (sourceWasCrit)
        {
            baseDOT *= 1.2f;
        }
        
        // DOT增幅(道具/Buff)
        float afterAmplifier = baseDOT * dotAmplifier;
        
        // 随机波动
        float variance = rng.NextFloat(VARIANCE_MIN, VARIANCE_MAX);
        
        return math.Floor(afterAmplifier * variance);
    }
    
    /// <summary>
    /// 标准DOT配置表
    /// </summary>
    public static readonly Dictionary<DOTType, DOTConfig> DOTConfigs = new()
    {
        { DOTType.Bleed,        new DOTConfig { DamagePerTick = 0.08f, DurationSec = 6f, TickCount = 12 } },
        { DOTType.Burn,         new DOTConfig { DamagePerTick = 0.10f, DurationSec = 4f, TickCount = 8 } },
        { DOTType.VoidErosion,  new DOTConfig { DamagePerTick = 0.06f, DurationSec = 8f, TickCount = 16 } },
        { DOTType.TimeDecay,    new DOTConfig { DamagePerTick = 0.05f, DurationSec = 10f, TickCount = 20 } }
    };
}

// ===== 数据结构定义 =====

/// <summary>攻击方上下文</summary>
public struct AttackerContext
{
    public int EntityId;
    public int Level;
    public float BaseATK;           // BATK
    public float FlatATKBonus;      // 固定攻击力加成
    public float ATKPercent;        // ATK%加成(1.5 = +150%)
    public float ArmorPenetration;  // 穿甲值
    public float CritRate;          // 暴击率(0~1)
    public float CritDamage;        // 暴击伤害(1.5 = 150%)
    public float TimeCritBonus;     // 时间暴击额外加成
    public float TimeDamageMultiplier;  // TDM时间伤害系数
    public float VoidDamageMultiplier;  // VDM虚无伤害系数
    public float VoidResonanceBonus;    // 虚无共鸣加成(0~1)
    public float[] FinalMultipliers;    // 最终乘区
}

/// <summary>防御方上下文</summary>
public struct DefenderContext
{
    public int EntityId;
    public float BaseDEF;           // BDEF
    public float FlatDEFBonus;      // 固定防御加成
    public float DEFPercent;        // DEF%加成
    public float FinalDEF;          // FDEF(预计算)
    public float TimeResistance;    // 时间抗性(0~0.5)
    public float VoidResistance;    // 虚无抗性(0~0.5)
    public float FireResistance;    // 火抗(0~1)
    public float IceResistance;     // 冰抗(0~1)
    public float LightningResistance; // 雷抗(0~1)
    public bool HasAbnormalStatus;  // 是否处于异常状态
    public float[] IndependentReductions; // 独立减伤列表
    public float[] TimeVulnerabilities;   // 时间易伤列表
    public float[] VoidVulnerabilities;   // 虚无易伤列表
}

/// <summary>伤害计算结果</summary>
public struct DamageResult
{
    public float PrimaryDamage;          // 主类型伤害
    public float SecondaryDamage;        // 副类型伤害
    public float InteractionBonus;       // 类型交互额外伤害
    public DamageTypeInteractionType InteractionType;
    public StatusEffectData? AppliedStatusEffect;
    public float TotalDamage;            // 最终总伤害
    
    public bool IsCrit;                  // 是否暴击(主类型)
    public float CritMultiplier;         // 暴击倍率
}

/// <summary>伤害类型交互结果</summary>
public struct DamageTypeInteractionResult
{
    public bool Triggered;
    public float BonusDamage;
    public DamageTypeInteractionType Type;
    public StatusEffectData? StatusEffect;
}

/// <summary>DOT类型</summary>
public enum DOTType
{
    Bleed,          // 流血
    Burn,           // 灼烧
    VoidErosion,    // 虚无侵蚀
    TimeDecay       // 时间衰减
}

/// <summary>DOT配置</summary>
public struct DOTConfig
{
    public float DamagePerTick;  // 每刻伤害占ATK百分比
    public float DurationSec;    // 持续秒数
    public int TickCount;        // 总刻数
}

/// <summary>DOT运行时实例</summary>
public class DOTInstance
{
    public DOTType Type;
    public int TargetEntityId;
    public int SourceEntityId;
    public float DamagePerTick;
    public int RemainingTicks;
    public float TickInterval;       // 刻间隔(秒), 固定0.5
    public float TickTimer;          // 刻计时器
    public float TotalDamageDealt;   // 已造成总伤害
    public bool SourceWasCrit;       // 来源是否暴击
    
    /// <summary>同类型DOT取最高值不叠加; 重新施加刷新持续时间</summary>
    public void Refresh(float newDamagePerTick, int newTickCount)
    {
        // 取最高值
        DamagePerTick = math.Max(DamagePerTick, newDamagePerTick);
        // 刷新持续时间，不重置伤害
        RemainingTicks = newTickCount;
    }
    
    /// <summary>每帧更新</summary>
    public bool Update(float deltaTime)
    {
        // DOT刻间隔不受时间减速影响(按真实时间)
        TickTimer += deltaTime;
        
        if (TickTimer >= TickInterval)
        {
            TickTimer -= TickInterval;
            RemainingTicks--;
            // 此处应调用IDamageable.TakeDamage
            return true; // 表示本帧造成了伤害
        }
        
        return RemainingTicks > 0;
    }
    
    public bool IsExpired => RemainingTicks <= 0;
}
```

---

## 5. HitboxManager 判定系统

### 5.1 设计说明

HitboxManager管理攻击判定(Hitbox)与受击区域(Hurtbox)的碰撞检测。每帧在活动帧期间查询Hitbox与所有Hurtbox的碰撞。使用Godot Physics2D进行实际检测，通过Layer区分Hitbox/Hurtbox。

### 5.2 核心数据结构

```text
/// <summary>
/// 判定区域数据 - 运行时结构，由ActionData转换而来
/// </summary>
public struct HitboxData
{
    public int OwnerEntityId;          // 攻击者实体ID
    public HitboxShape shape;          // 判定形状
    public Vector2 center;             // 判定中心(世界坐标)
    public Vector2 offset;             // 偏移(相对于角色)
    public float radius;               // 半径(扇形/圆形)
    public float arc;                  // 弧度(扇形)
    public float width;                // 宽(矩形/弹道)
    public float length;               // 长(矩形/弹道)
    public float direction;            // 朝向角度(度)
    
    public float damageMultiplier;     // 伤害倍率
    public DamageType damageType;      // 主伤害类型
    public DamageType secondaryDamageType; // 副伤害类型
    public float primaryTypeRatio;     // 主类型占比
    
    public float knockbackForce;       // 击退力
    public int knockbackDurationFrames; // 击退帧数
    
    // 弹道参数
    public bool isProjectile;          // 是否弹道型
    public float projectileSpeed;      // 弹道速度
    public float maxRange;             // 最大射程
    public int pierceCount;            // 穿透数
    public float pierceDamageDecay;    // 穿透衰减
    public float pierceDamageFloor;    // 穿透衰减下限
    public int hitCount;               // 已命中数(穿透计数)
    
    // 多次命中
    public bool canHitMultiple;        // 可多次命中
    public int maxHitCount;            // 最大命中数
    public HashSet<int> hitEntities;   // 已命中实体ID集合(防重复命中)
    
    // 特殊效果
    public StatusEffectData[] applyOnHit; // 命中附加效果
    public bool breakGuard;            // 可破防
    public bool forceLaunch;           // 强制浮空
    public float launchDuration;       // 浮空时间
}

/// <summary>
/// 受击区域 - 挂载在每个可受伤实体上
/// </summary>
public class Hurtbox : Node
{
     private int _entityId;
     private CollisionShape2D _collider;
     private HurtboxType _hurtboxType;
    
    public int EntityId => _entityId;
    public CollisionShape2D Collider => _collider;
    public HurtboxType Type => _hurtboxType;
    public bool IsActive => _collider.enabled;
    
    /// <summary>设置受击区域激活状态(无敌帧期间禁用)</summary>
    public void SetActive(bool active) => _collider.enabled = active;
}

public enum HurtboxType
{
    Normal,     // 普通受击区域(身体)
    WeakPoint,  // 弱点(暴击加成)
    Guard,      // 格挡区域(正面180度)
    Back        // 背后(弱点射击加成)
}
```

### 5.3 HitboxManager 实现

```text
/// <summary>
/// 判定管理器 - 管理Hitbox/Hurtbox碰撞检测
/// 每帧在活动帧期间执行判定查询
/// 使用Physics2D.Overlap进行形状检测，Layer区分
/// </summary>
public class HitboxManager : Node
{
    private const int MAX_HITBOXES_PER_FRAME = 32;
    private const int MAX_HURTBOXES_PER_QUERY = 64;
    
    [Header("Layer设置")]
     private collision_mask _hitboxLayer;    // Hitbox所在Layer
     private collision_mask _hurtboxLayer;   // Hurtbox所在Layer
     private collision_mask _projectileLayer; // 弹道Hitbox Layer
    
    // 缓存(避免GC)
    private static readonly CollisionShape2D[] _colliderCache = new CollisionShape2D[MAX_HURTBOXES_PER_QUERY];
    private readonly List<ActiveHitbox> _activeHitboxes = new List<ActiveHitbox>(MAX_HITBOXES_PER_FRAME);
    
    // 对象池
    private readonly Dictionary<string, Queue<Node>> _projectilePool = new();
    
    /// <summary>
    /// 注册一个活动Hitbox(在ActionPlayer活动帧触发时调用)
    /// </summary>
    public void RegisterHitbox(HitboxData data, Vector2 ownerPosition, float ownerDirection)
    {
        // 计算世界坐标
        HitboxData worldData = data;
        worldData.center = ownerPosition + data.offset;
        worldData.direction = ownerDirection;
        worldData.hitEntities = new HashSet<int>();
        
        _activeHitboxes.Add(new ActiveHitbox
        {
            data = worldData,
            remainingFrames = data.isProjectile ? -1 : 1, // 弹道型持续存在
            processed = false
        });
    }
    
    /// <summary>
    /// 注册弹道型Hitbox(箭矢/子弹/法术弹)
    /// </summary>
    public void RegisterProjectile(HitboxData data, Vector2 spawnPos, Vector2 direction, Node scene)
    {
        // 从对象池获取弹道实例
        Node projectile = GetFromPool(scene);
        projectile.transform.position = spawnPos;
        
        ProjectileController ctrl = projectile.GetComponent<ProjectileController>();
        if (ctrl != null)
        {
            ctrl.Initialize(data, direction, data.projectileSpeed, data.maxRange, data.pierceCount);
        }
        
        projectile.SetActive(true);
    }
    
    /// <summary>
    /// 每固定帧更新(60Hz)
    /// </summary>
    public void FixedUpdate()
    {
        ProcessActiveHitboxes();
    }
    
    /// <summary>
    /// 处理所有活动Hitbox的碰撞检测
    /// </summary>
    private void ProcessActiveHitboxes()
    {
        for (int i = _activeHitboxes.Count - 1; i >= 0; i--)
        {
            var hitbox = _activeHitboxes[i];
            
            // 检测碰撞
            int hitCount = QueryHurtboxes(hitbox.data);
            
            // 处理命中
            for (int j = 0; j < hitCount; j++)
            {
                CollisionShape2D col = _colliderCache[j];
                Hurtbox hurtbox = col.GetComponent<Hurtbox>();
                
                if (hurtbox == null || !hurtbox.IsActive) continue;
                
                // 防止重复命中同一实体
                if (hitbox.data.hitEntities.Contains(hurtbox.EntityId)) continue;
                
                // 执行命中
                ProcessHit(hitbox.data, hurtbox);
                hitbox.data.hitEntities.Add(hurtbox.EntityId);
                
                // 穿透计数
                if (hitbox.data.pierceCount >= 0)
                {
                    hitbox.data.hitCount++;
                    if (hitbox.data.hitCount >= hitbox.data.pierceCount && hitbox.data.pierceCount != -1)
                    {
                        break; // 达到穿透上限
                    }
                }
                
                // 非穿透型命中即消失
                if (hitbox.data.pierceCount == 0)
                {
                    break;
                }
            }
            
            // 清理过期Hitbox
            if (!hitbox.data.isProjectile)
            {
                _activeHitboxes.RemoveAt(i);
            }
        }
    }
    
    /// <summary>
    /// 查询Hitbox范围内的Hurtbox
    /// </summary>
    private int QueryHurtboxes(HitboxData data)
    {
        Vector2 center = data.center;
        
        switch (data.shape)
        {
            case HitboxShape.Sector:
                return QuerySector(center, data.direction, data.radius, data.arc);
                
            case HitboxShape.Circle:
                return Physics2D.OverlapCircleNonAlloc(center, data.radius, _colliderCache, _hurtboxLayer);
                
            case HitboxShape.Rectangle:
                return QueryRectangle(center, data.direction, data.width, data.length);
                
            case HitboxShape.Projectile:
                // 弹道型由ProjectileController自身处理
                return 0;
                
            case HitboxShape.Area:
                return Physics2D.OverlapCircleNonAlloc(center, data.radius, _colliderCache, _hurtboxLayer);
                
            default:
                return 0;
        }
    }
    
    /// <summary>扇形范围查询</summary>
    private int QuerySector(Vector2 center, float direction, float radius, float arc)
    {
        int count = Physics2D.OverlapCircleNonAlloc(center, radius, _colliderCache, _hurtboxLayer);
        
        // 过滤不在扇形角度范围内的
        float halfArc = arc * 0.5f * math.Deg2Rad;
        float dirRad = direction * math.Deg2Rad;
        
        int validCount = 0;
        for (int i = 0; i < count; i++)
        {
            Vector2 toTarget = (Vector2)_colliderCache[i].bounds.center - center;
            float angle = math.Atan2(toTarget.y, toTarget.x);
            float angleDiff = math.DeltaAngle(dirRad * math.Rad2Deg, angle * math.Rad2Deg);
            
            if (math.Abs(angleDiff) <= arc * 0.5f)
            {
                _colliderCache[validCount] = _colliderCache[i];
                validCount++;
            }
        }
        
        return validCount;
    }
    
    /// <summary>矩形范围查询</summary>
    private int QueryRectangle(Vector2 center, float direction, float width, float length)
    {
        // 使用BoxCast近似矩形检测
        Vector2 dir = new Vector2(math.Cos(direction * math.Deg2Rad), math.Sin(direction * math.Deg2Rad));
        Vector2 size = new Vector2(width, length);
        float angle = direction;
        
        return Physics2D.OverlapBoxNonAlloc(center, size, angle, _colliderCache, _hurtboxLayer);
    }
    
    /// <summary>
    /// 处理单次命中
    /// </summary>
    private void ProcessHit(HitboxData hitbox, Hurtbox hurtbox)
    {
        // 获取攻击方和防御方上下文
        var attacker = GetAttackerContext(hitbox.OwnerEntityId);
        var defender = GetDefenderContext(hurtbox.EntityId);
        
        // 构造ActionData(简化：从HitboxData恢复)
        ActionData action = CreateActionFromHitbox(hitbox);
        
        // 计算伤害
        RNG rng = ServiceRegistry.Get<IGameManager>().State.CurrentRun.RNG;
        DamageResult result = DamageCalculator.CalculateDamage(attacker, defender, action, rng);
        
        // 应用伤害
        IDamageable target = GetDamageable(hurtbox.EntityId);
        if (target != null)
        {
            target.TakeDamage(new DamageInfo
            {
                BaseDamage = result.TotalDamage,
                Type = hitbox.damageType,
                SourceId = hitbox.OwnerEntityId,
                KnockbackForce = CalculateKnockbackDirection(hitbox, hurtbox) * hitbox.knockbackForce,
                IsProc = false
            });
        }
        
        // 应用状态效果
        if (hitbox.applyOnHit != null)
        {
            foreach (var effect in hitbox.applyOnHit)
            {
                ApplyStatusEffect(hurtbox.EntityId, effect);
            }
        }
        
        // 应用交互效果
        if (result.AppliedStatusEffect.HasValue)
        {
            ApplyStatusEffect(hurtbox.EntityId, result.AppliedStatusEffect.Value);
        }
        
        // 命中停顿(打击感)
        if (action.hitstopFrames > 0)
        {
            ApplyHitstop(action.hitstopFrames);
        }
        
        // 发布命中事件
        EventBus.Publish(new ComboHitEvent
        {
            ComboCount = 0, // 由武器系统更新
            Weapon = WeaponType.Sword // 由武器系统更新
        });
    }
    
    /// <summary>
    /// 击退方向计算
    /// </summary>
    private Vector2 CalculateKnockbackDirection(HitboxData hitbox, Hurtbox hurtbox)
    {
        Vector2 dir = (Vector2)hurtbox.transform.position - hitbox.center;
        if (dir.sqrMagnitude < 0.01f)
        {
            // 重叠时使用面朝方向
            float rad = hitbox.direction * math.Deg2Rad;
            dir = new Vector2(math.Cos(rad), math.Sin(rad));
        }
        return dir.normalized;
    }
    
    // --- 辅助方法(简化，实际从EntityManager获取) ---
    private AttackerContext GetAttackerContext(int entityId) => default;
    private DefenderContext GetDefenderContext(int entityId) => default;
    private ActionData CreateActionFromHitbox(HitboxData data) => null;
    private IDamageable GetDamageable(int entityId) => null;
    private void ApplyStatusEffect(int targetId, StatusEffectData effect) { }
    private void ApplyHitstop(float frames) { }
    private Node GetFromPool(Node scene) => null;
    
    private struct ActiveHitbox
    {
        public HitboxData data;
        public int remainingFrames;
        public bool processed;
    }
}

/// <summary>
/// 弹道控制器 - 挂在弹道型HitboxPackedScene上
/// 管理弹道飞行、穿透、碰撞
/// </summary>
public class ProjectileController : Node
{
    private HitboxData _data;
    private Vector2 _direction;
    private float _speed;
    private float _maxRange;
    private int _pierceRemaining;
    private float _distanceTraveled;
    private float _damageDecayAccum;
    private readonly HashSet<int> _hitEntities = new HashSet<int>();
    
     private CollisionShape2D _collider;
     private CharacterBody2D _rb;
     private collision_mask _hurtboxLayer;
    
    /// <summary>初始化弹道</summary>
    public void Initialize(HitboxData data, Vector2 direction, float speed, float maxRange, int pierceCount)
    {
        _data = data;
        _direction = direction.normalized;
        _speed = speed;
        _maxRange = maxRange;
        _pierceRemaining = pierceCount;
        _distanceTraveled = 0f;
        _damageDecayAccum = 0f;
        _hitEntities.Clear();
        
        // 设置速度
        _rb.velocity = _direction * speed;
        
        // 设置朝向
        float angle = math.Atan2(direction.y, direction.x) * math.Rad2Deg;
        transform.rotation = Quaternion.Euler(0, 0, angle);
    }
    
    private void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        _distanceTraveled += _speed * dt;
        
        // 超出射程
        if (_distanceTraveled >= _maxRange)
        {
            Despawn();
            return;
        }
        
        // 检测碰撞
        int count = Physics2D.OverlapColliderNonAlloc(_collider, _hitboxFilter, _overlapCache);
        for (int i = 0; i < count; i++)
        {
            Hurtbox hurtbox = _overlapCache[i].GetComponent<Hurtbox>();
            if (hurtbox == null || !hurtbox.IsActive) continue;
            if (_hitEntities.Contains(hurtbox.EntityId)) continue;
            
            // 命中处理
            _hitEntities.Add(hurtbox.EntityId);
            ProcessProjectileHit(hurtbox);
            
            // 非穿透
            if (_pierceRemaining == 0)
            {
                Despawn();
                return;
            }
            
            // 穿透计数
            if (_pierceRemaining > 0)
            {
                _pierceRemaining--;
                // 伤害衰减
                _damageDecayAccum += _data.pierceDamageDecay;
                float decay = math.Min(_damageDecayAccum, _data.pierceDamageFloor);
                _data.damageMultiplier *= (1f - decay);
            }
        }
    }
    
    private void ProcessProjectileHit(Hurtbox hurtbox)
    {
        // 委托给HitboxManager处理
        var manager = ServiceRegistry.Get<HitboxManager>();
        // ... 伤害计算与效果应用
    }
    
    private void Despawn()
    {
        gameObject.SetActive(false);
        // 归还对象池
    }
    
    private static readonly CollisionShape2D[] _overlapCache = new CollisionShape2D[16];
    private static ContactFilter2D _hitboxFilter = new ContactFilter2D();
}
```

---

## 6. IWeapon 接口 + WeaponBase 基类

### 6.1 IWeapon 接口

```text
/// <summary>
/// 武器接口 - 所有武器的行为契约
/// 扩展自架构总纲5.2节
/// </summary>
public interface IWeapon
{
    // === 基础属性 ===
    string WeaponId { get; }
    WeaponType Type { get; }
    WeaponData Data { get; }
    
    // === 生命周期 ===
    void Initialize(WeaponData data);
    void OnEquip(PlayerController player);
    void OnUnequip();
    
    // === 攻击相关 ===
    void OnAttackStart();
    void OnAttackEnd();
    void OnSpecialStart();
    void OnSpecialEnd();
    
    // === 连招系统 ===
    string GetNextComboAction(int currentIndex);
    string GetFirstComboAction();
    int ComboCount { get; }
    void ResetCombo();
    
    // === 蓄力系统 ===
    ActionData GetChargeAction(ChargeLevel level);
    bool HasChargeSystem { get; }
    
    // === 格挡系统 ===
    ActionData GetParryActionData();
    bool HasParrySystem { get; }
    
    // === 特殊技/终极技 ===
    ActionData GetSpecialActionData();
    ActionData GetUltimateActionData();
    ActionData GetDodgeActionData();
    
    // === 时间联动 ===
    void OnTimeStopStart();
    void OnTimeStopEnd();
    void OnTimeAccelerate(float multiplier);
    void OnTimeRewindEnd(); // 回溯结束后2秒内
}
```

### 6.2 WeaponData Resource

```text
/// <summary>
/// 武器配置数据 Resource
/// </summary>
[CreateAssetMenu(fileName = "WeaponData_", menuName = "PlaneWalker/Combat/WeaponData")]
public class WeaponData : Resource, IRegistryEntry
{
    [Header("基础属性")]
    public string weaponId;
    public string displayName;
    public WeaponType weaponType;
    public string description;
    
    [Header("数值")]
    public float baseAttackPower;        // 基础攻击力
    public float attackSpeedCoefficient; // 攻速系数
    public float attackRange;            // 攻击范围(格)
    public float chargeTime;             // 蓄力时间(秒)
    
    [Header("动作列表")]
    public string[] comboActionIds;      // 普攻连招动作ID列表
    public string[] chargeActionIds;     // 蓄力动作ID列表(按蓄力等级)
    public string specialActionId;       // 特殊技动作ID
    public string ultimateActionId;      // 终极技动作ID
    public string dodgeActionId;         // 闪避动作ID
    public string parryActionId;         // 格挡动作ID(剑专用)
    
    [Header("武器特有")]
    public bool hasChargeSystem;
    public bool hasParrySystem;
    public bool hasManaSystem;           // 法力系统(杖)
    public bool hasAmmoSystem;           // 弹药系统(枪)
    public int maxAmmo;                  // 弹夹容量(枪)
    public int maxMana;                  // 法力上限(杖)
    public float manaRegenRate;          // 法力回复速率(杖)
    
    [Header("时间联动")]
    public TimeInteractionData[] timeInteractions; // 时间联动技配置
    
    public string Id => weaponId;
}

[System.Serializable]
public struct TimeInteractionData
{
    public TimeInteractionTrigger trigger;
    public string effectName;
    public float effectValue;
    public string description;
}

public enum TimeInteractionTrigger
{
    TimeStop,       // 时间停止期间
    TimeAccelerate, // 时间加速期间
    TimeRewindEnd,  // 时间回溯结束后2秒内
    TimeRiftHit     // 时间裂隙内命中
}
```

### 6.3 WeaponBase 基类

```text
/// <summary>
/// 武器基类 - 提供通用武器逻辑
/// 子类通过override实现武器差异化行为
/// </summary>
public abstract class WeaponBase : IWeapon
{
    // === 基础属性 ===
    public string WeaponId => _data.weaponId;
    public WeaponType Type => _data.weaponType;
    public WeaponData Data => _data;
    
    // === 连招状态 ===
    public int ComboCount => _comboCount;
    public bool HasChargeSystem => _data.hasChargeSystem;
    public bool HasParrySystem => _data.hasParrySystem;
    
    // === 运行时状态 ===
    protected WeaponData _data;
    protected PlayerController _owner;
    protected int _comboCount;
    protected float _comboTimer;
    protected const float COMBO_TIMEOUT = 2.0f; // 2秒未命中重置
    
    // === 动作数据缓存(从Registry加载) ===
    protected Dictionary<string, ActionData> _actionCache = new();
    
    // ===== 生命周期 =====
    
    public virtual void Initialize(WeaponData data)
    {
        _data = data;
        _comboCount = 0;
        
        // 预加载所有动作数据
        var registry = Registry<ActionData>.Instance;
        CacheAction(ref _actionCache, data.comboActionIds, registry);
        CacheAction(ref _actionCache, data.chargeActionIds, registry);
        if (!string.IsNullOrEmpty(data.specialActionId))
            _actionCache[data.specialActionId] = registry.Get(data.specialActionId);
        if (!string.IsNullOrEmpty(data.ultimateActionId))
            _actionCache[data.ultimateActionId] = registry.Get(data.ultimateActionId);
        if (!string.IsNullOrEmpty(data.dodgeActionId))
            _actionCache[data.dodgeActionId] = registry.Get(data.dodgeActionId);
        if (!string.IsNullOrEmpty(data.parryActionId))
            _actionCache[data.parryActionId] = registry.Get(data.parryActionId);
    }
    
    public virtual void OnEquip(PlayerController player)
    {
        _owner = player;
    }
    
    public virtual void OnUnequip()
    {
        _owner = null;
        ResetCombo();
    }
    
    // ===== 攻击 =====
    
    public virtual void OnAttackStart() { }
    public virtual void OnAttackEnd() { }
    public virtual void OnSpecialStart() { }
    public virtual void OnSpecialEnd() { }
    
    // ===== 连招 =====
    
    public virtual string GetNextComboAction(int currentIndex)
    {
        if (_data.comboActionIds == null || _data.comboActionIds.Length == 0)
            return null;
        
        int nextIndex = currentIndex + 1;
        if (nextIndex >= _data.comboActionIds.Length)
        {
            nextIndex = 0; // 循环回第1段
        }
        
        return _data.comboActionIds[nextIndex];
    }
    
    public virtual string GetFirstComboAction()
    {
        if (_data.comboActionIds == null || _data.comboActionIds.Length == 0)
            return null;
        return _data.comboActionIds[0];
    }
    
    public virtual void ResetCombo()
    {
        _comboCount = 0;
        _comboTimer = 0f;
    }
    
    /// <summary>命中时增加连击数</summary>
    public virtual void OnHitConfirmed()
    {
        _comboCount++;
        _comboTimer = COMBO_TIMEOUT;
    }
    
    /// <summary>每帧更新连击超时</summary>
    public virtual void UpdateCombo(float deltaTime)
    {
        if (_comboCount > 0)
        {
            _comboTimer -= deltaTime;
            if (_comboTimer <= 0f)
            {
                ResetCombo();
            }
        }
    }
    
    // ===== 蓄力 =====
    
    public virtual ActionData GetChargeAction(ChargeLevel level)
    {
        if (_data.chargeActionIds == null) return null;
        int index = (int)level;
        if (index < 0 || index >= _data.chargeActionIds.Length) return null;
        
        string id = _data.chargeActionIds[index];
        return _actionCache.GetValueOrDefault(id);
    }
    
    // ===== 格挡/特殊/终极/闪避 =====
    
    public virtual ActionData GetParryActionData()
    {
        if (!_data.hasParrySystem) return null;
        return _actionCache.GetValueOrDefault(_data.parryActionId);
    }
    
    public virtual ActionData GetSpecialActionData()
    {
        return _actionCache.GetValueOrDefault(_data.specialActionId);
    }
    
    public virtual ActionData GetUltimateActionData()
    {
        return _actionCache.GetValueOrDefault(_data.ultimateActionId);
    }
    
    public virtual ActionData GetDodgeActionData()
    {
        return _actionCache.GetValueOrDefault(_data.dodgeActionId);
    }
    
    // ===== 时间联动(默认空实现) =====
    
    public virtual void OnTimeStopStart() { }
    public virtual void OnTimeStopEnd() { }
    public virtual void OnTimeAccelerate(float multiplier) { }
    public virtual void OnTimeRewindEnd() { }
    
    // ===== 辅助 =====
    
    protected void CacheAction(ref Dictionary<string, ActionData> cache, string[] ids, Registry<ActionData> registry)
    {
        if (ids == null) return;
        foreach (string id in ids)
        {
            if (!string.IsNullOrEmpty(id))
                cache[id] = registry.Get(id);
        }
    }
}
```

---

## 7. 五武器实现要点

### 7.1 剑(SwordWeapon)

**状态机定义**：
```
Idle → Startup(横斩) → Active → Recovery → Startup(上挑斩) → ... → Startup(下劈终结) → Recovery → Idle
                                                                                          ↓
                                                                                      可回到第1段
Idle → Charge(Level0/1/2) → Release → Startup → Active → Recovery → Idle
Idle → ParryStartup → ParryActive → [Perfect/Normal Parry] → CounterAttack → Idle
Idle → SpecialStartup → SpecialActive → SpecialRecovery → Idle
Idle → UltimateStartup → UltimateActive(不可取消) → UltimateRecovery → Idle
```

**关键方法签名**：

```text
/// <summary>
/// 剑武器 - 均衡近战，4段连击+蓄力+格挡
/// 特有机制：剑意系统、格挡反击链
/// </summary>
public class SwordWeapon : WeaponBase
{
    private bool _hasSwordIntent;           // 剑意Buff
    private float _swordIntentTimer;        // 剑意剩余时间
    private int _parryChainCount;           // 连续完美格挡次数
    private const int MAX_COMBO = 4;        // 4段连击
    private const float SWORD_INTENT_DURATION = 5f;
    private const float SWORD_INTENT_BONUS = 0.2f; // +20%伤害
    private const float PARRY_COUNTER_BONUS_PER_CHAIN = 0.5f; // 每次连击+0.5倍率
    private const float PARRY_COUNTER_MAX_MULT = 5.0f; // 反击倍率上限
    
    /// <summary>剑意Buff：蓄力1段命中获得，下次攻击+20%伤害</summary>
    public bool HasSwordIntent => _hasSwordIntent;
    public float SwordIntentDamageBonus => _hasSwordIntent ? SWORD_INTENT_BONUS : 0f;
    
    /// <summary>消耗剑意(攻击时调用)</summary>
    public void ConsumeSwordIntent()
    {
        _hasSwordIntent = false;
        _swordIntentTimer = 0f;
    }
    
    /// <summary>刷新剑意(蓄力1段命中时调用)</summary>
    public void RefreshSwordIntent()
    {
        _hasSwordIntent = true;
        _swordIntentTimer = SWORD_INTENT_DURATION;
    }
    
    /// <summary>完美格挡成功回调</summary>
    public void OnPerfectParry()
    {
        _parryChainCount++;
        EventBus.Publish(new PerfectParryEvent
        {
            PlayerId = _owner.EntityId,
            ParryCount = _parryChainCount
        });
    }
    
    /// <summary>获取反击斩倍率(随连续完美格挡递增)</summary>
    public float GetCounterAttackMultiplier()
    {
        float baseMult = 2.0f;
        if (_parryChainCount >= 3)
        {
            float bonus = (_parryChainCount - 2) * PARRY_COUNTER_BONUS_PER_CHAIN;
            return math.Min(baseMult + bonus, PARRY_COUNTER_MAX_MULT);
        }
        return baseMult;
    }
    
    /// <summary>重置格挡链(任意非完美格挡或超时)</summary>
    public void ResetParryChain() => _parryChainCount = 0;
    
    // === Override ===
    
    public override void OnAttackEnd()
    {
        // 终结击后重置连击段数
    }
    
    public override void OnTimeStopStart()
    {
        // 时之刃：攻速额外+30%，命中额外15%时间伤害
    }
    
    public override void OnTimeRewindEnd()
    {
        // 倒流斩：下一击+50%伤害，附加3格击退
    }
    
    public override void UpdateCombo(float deltaTime)
    {
        base.UpdateCombo(deltaTime);
        
        // 剑意计时
        if (_hasSwordIntent)
        {
            _swordIntentTimer -= deltaTime;
            if (_swordIntentTimer <= 0f)
                _hasSwordIntent = false;
        }
    }
}
```

### 7.2 弓(BowWeapon)

**状态机定义**：
```
Idle → Charge(Level0/1/2/Full) → Release → Startup → Active → Recovery → Idle
Idle → ScatterStartup → ScatterActive → ScatterRecovery → Idle
Idle → SpecialStartup → SpecialActive → SpecialRecovery → Idle
Idle → UltimateStartup → UltimateActive(不可取消) → UltimateRecovery → Idle
Charge中任意时刻 → DodgeCancel(蓄力作废)
```

**关键方法签名**：

```text
/// <summary>
/// 弓武器 - 蓄力射击，距离衰减，弱点射击
/// 特有机制：蓄力保持、弱点射击、距离衰减
/// </summary>
public class BowWeapon : WeaponBase
{
    private float _holdTimer;                // 满蓄保持计时
    private const float AUTO_RELEASE_TIME = 3f; // 满蓄3秒自动释放
    private const float MAX_CHARGE_TIME = 0.8f; // 满蓄时间(48帧/60fps)
    
    /// <summary>距离伤害修正</summary>
    public float GetDistanceModifier(float distance)
    {
        return distance switch
        {
            < 2f => 0.7f,         // 过近衰减
            >= 2f and < 6f => 1.0f,  // 最佳射程
            >= 6f and < 10f => 0.9f,
            >= 10f and < 15f => 0.8f,
            _ => 0.6f              // 超远衰减
        };
    }
    
    /// <summary>弱点射击判定(目标背后180度)</summary>
    public bool IsWeakpointShot(Vector2 attackerPos, Vector2 targetPos, Vector2 targetFacing)
    {
        Vector2 toAttacker = (attackerPos - targetPos).normalized;
        float dot = Vector2.Dot(targetFacing, toAttacker);
        return dot < 0f; // 攻击者在目标背后
    }
    
    /// <summary>弱点射击暴击加成: 暴击率+30%, 暴击伤害+50%</summary>
    public (float critRateBonus, float critDamageBonus) GetWeakpointBonus(bool isWeakpoint)
    {
        if (!isWeakpoint) return (0f, 0f);
        return (0.3f, 0.5f);
    }
    
    /// <summary>满蓄保持超时自动释放</summary>
    public bool ShouldAutoRelease(float holdTime)
    {
        return holdTime >= AUTO_RELEASE_TIME;
    }
    
    public override void OnTimeStopStart()
    {
        // 时停狙击：满蓄箭命中产生时间爆炸(半径2.5格, 200%ATK时间伤害)
    }
    
    public override void OnTimeAccelerate(float multiplier)
    {
        // 急速连射：蓄力速度×2，快速射击后摇-6帧
    }
}
```

### 7.3 枪(GunWeapon)

**状态机定义**：
```
Idle → Startup(普通射击) → Active → Recovery → Idle(循环射击)
Idle → AimStartup → AimActive → AimRecovery → Idle
Idle → ScatterStartup → ScatterActive → ScatterRecovery → Idle
Idle → Reload(不可取消8帧→可取消32帧→不可取消8帧) → Idle
Reload中 → PerfectReloadWindow → [成功/失败] → Idle
Idle → SpecialStartup → SpecialActive → SpecialRecovery → Idle
Idle → UltimateStartup(不可取消) → UltimateActive → UltimateRecovery → Idle
```

**关键方法签名**：

```text
/// <summary>
/// 枪武器 - 弹药系统，完美换弹，中距离射击
/// 特有机制：弹药管理、完美换弹、距离修正
/// </summary>
public class GunWeapon : WeaponBase
{
    private int _currentAmmo;
    private bool _isReloading;
    private bool _isPerfectReloadWindow;
    private int _reloadFrame;
    private bool _hasTimeLoadingBuff;       // 时间装填Buff
    private float _timeLoadingTimer;
    
    private const int MAX_AMMO = 6;
    private const int RELOAD_DURATION_FRAMES = 48;
    private const int PERFECT_WINDOW_START = 28; // 第28帧
    private const int PERFECT_WINDOW_END = 36;   // 第36帧
    private const float TIME_LOADING_DURATION = 5f;
    
    public int CurrentAmmo => _currentAmmo;
    public bool IsReloading => _isReloading;
    public bool HasTimeLoadingBuff => _hasTimeLoadingBuff;
    public bool IsMagazineEmpty => _currentAmmo <= 0;
    
    /// <summary>消耗弹药</summary>
    public bool ConsumeAmmo(int amount)
    {
        if (_hasTimeLoadingBuff) return true; // 时间装填期间不消耗
        
        if (_currentAmmo < amount) return false;
        _currentAmmo -= amount;
        
        if (_currentAmmo <= 0)
        {
            StartReload(); // 弹夹空自动换弹
        }
        return true;
    }
    
    /// <summary>开始换弹</summary>
    public void StartReload()
    {
        if (_isReloading) return;
        _isReloading = true;
        _reloadFrame = 0;
    }
    
    /// <summary>换弹帧更新(每FixedUpdate调用)</summary>
    public ReloadState UpdateReload()
    {
        if (!_isReloading) return ReloadState.None;
        
        _reloadFrame++;
        
        // 完美窗口判定
        if (_reloadFrame >= PERFECT_WINDOW_START && _reloadFrame <= PERFECT_WINDOW_END)
        {
            return ReloadState.PerfectWindow;
        }
        
        // 换弹完成
        if (_reloadFrame >= RELOAD_DURATION_FRAMES)
        {
            CompleteReload(false);
            return ReloadState.Completed;
        }
        
        // 前8帧不可取消
        if (_reloadFrame <= 8)
        {
            return ReloadState.Unbreakable;
        }
        
        return ReloadState.Cancelable;
    }
    
    /// <summary>尝试完美换弹</summary>
    public bool TryPerfectReload()
    {
        if (!_isReloading) return false;
        if (_reloadFrame >= PERFECT_WINDOW_START && _reloadFrame <= PERFECT_WINDOW_END)
        {
            CompleteReload(true);
            EventBus.Publish(new PerfectReloadEvent { PlayerId = _owner.EntityId });
            // 完美换弹自动触发时间装填
            ActivateTimeLoading();
            return true;
        }
        return false;
    }
    
    /// <summary>完成换弹</summary>
    private void CompleteReload(bool isPerfect)
    {
        _currentAmmo = isPerfect ? MAX_AMMO + 1 : MAX_AMMO;
        _isReloading = false;
        _reloadFrame = 0;
    }
    
    /// <summary>激活时间装填Buff</summary>
    public void ActivateTimeLoading()
    {
        _hasTimeLoadingBuff = true;
        _timeLoadingTimer = TIME_LOADING_DURATION;
    }
    
    /// <summary>距离修正(枪最佳射程2~8格)</summary>
    public float GetDistanceModifier(float distance)
    {
        return distance switch
        {
            < 2f => 1.0f,
            >= 2f and < 8f => 1.2f,   // 最佳射程+20%
            >= 8f and < 12f => 1.0f,
            >= 12f and < 15f => 0.8f,
            _ => 0.6f
        };
    }
    
    public override void OnTimeAccelerate(float multiplier)
    {
        // 弹雨时轮：射击间隔-4帧，弹药消耗减半
    }
}

public enum ReloadState
{
    None,           // 未在换弹
    Unbreakable,    // 不可取消阶段(前8帧)
    Cancelable,     // 可取消阶段
    PerfectWindow,  // 完美窗口
    Completed       // 换弹完成
}
```

### 7.4 杖(StaffWeapon)

**状态机定义**：
```
Idle → Startup(基础法术弹) → Active → Recovery → Idle(循环射击)
Idle → ElementSwitch(瞬切, 0帧) → Idle
Idle → ChargeStartup → ChargeActive → ChargeRecovery → Idle
ChargeRecovery → ComboWindow → 另一属性ChargeStartup(法术组合)
Idle → SpecialStartup → SpecialActive → SpecialRecovery → Idle
Idle → UltimateStartup(不可取消) → UltimateActive → UltimateRecovery → Idle
```

**关键方法签名**：

```text
/// <summary>
/// 杖武器 - 法力系统，三属性法术，法术组合
/// 特有机制：属性切换、法术组合、法力管理
/// </summary>
public class StaffWeapon : WeaponBase
{
    private ElementType _currentElement;      // 当前法术属性
    private float _currentMana;               // 当前法力值
    private ElementType _lastCastElement;     // 上次释放的蓄力法术属性
    private float _lastCastTime;              // 上次蓄力法术释放时间
    private const float COMBO_WINDOW = 5f;    // 法术组合窗口(5秒/300帧)
    private const float MANA_ON_DAMAGE = 0.02f; // 造成伤害回复2%法力
    
    public ElementType CurrentElement => _currentElement;
    public float CurrentMana => _currentMana;
    public float MaxMana => _data.maxMana;
    
    /// <summary>切换法术属性(火→冰→雷→火)</summary>
    public void SwitchElement()
    {
        _currentElement = _currentElement switch
        {
            ElementType.Fire => ElementType.Ice,
            ElementType.Ice => ElementType.Lightning,
            ElementType.Lightning => ElementType.Fire,
            _ => ElementType.Fire
        };
    }
    
    /// <summary>消耗法力</summary>
    public bool ConsumeMana(float amount)
    {
        if (_currentMana < amount) return false;
        _currentMana -= amount;
        return true;
    }
    
    /// <summary>法力回复(每帧调用)</summary>
    public void RegenerateMana(float deltaTime)
    {
        _currentMana = math.Min(_currentMana + _data.manaRegenRate * deltaTime, _data.maxMana);
    }
    
    /// <summary>造成伤害时回复法力</summary>
    public void OnDamageDealt(float damageAmount)
    {
        _currentMana = math.Min(_currentMana + damageAmount * MANA_ON_DAMAGE, _data.maxMana);
    }
    
    /// <summary>检查法术组合条件</summary>
    public bool CanComboSpell(ElementType newElement)
    {
        if (_lastCastElement == ElementType.None || newElement == _lastCastElement)
            return false;
        
        float elapsed = runtime_time - _lastCastTime;
        return elapsed <= COMBO_WINDOW;
    }
    
    /// <summary>获取法术组合结果</summary>
    public SpellComboResult GetComboResult(ElementType first, ElementType second)
    {
        // (火→冰), (冰→火)等不同组合有不同效果
        return first switch
        {
            ElementType.Fire when second == ElementType.Ice => new SpellComboResult
            {
                comboName = "蒸汽爆发",
                radius = 3.5f,
                damageMultiplier = 3.0f,
                manaCost = 15
            },
            ElementType.Fire when second == ElementType.Lightning => new SpellComboResult
            {
                comboName = "烈雷风暴",
                radius = 3.0f,
                damageMultiplier = 0f, // 持续伤害型
                duration = 6f,
                manaCost = 20
            },
            ElementType.Ice when second == ElementType.Lightning => new SpellComboResult
            {
                comboName = "冰晶雷爆",
                radius = 3.0f,
                damageMultiplier = 4.5f, // 冰2.5+雷2.0
                manaCost = 18
            },
            _ => null
        };
    }
    
    /// <summary>记录蓄力法术释放</summary>
    public void RecordChargeSpellCast(ElementType element)
    {
        _lastCastElement = element;
        _lastCastTime = runtime_time;
    }
    
    public override void OnTimeAccelerate(float multiplier)
    {
        // 急速吟唱：蓄力时间-50%，法力消耗-30%
    }
    
    public override void OnTimeRewindEnd()
    {
        // 回溯施法：法术不消耗法力，伤害+30%
    }
}

public enum ElementType { Fire, Ice, Lightning }

public class SpellComboResult
{
    public string comboName;
    public float radius;
    public float damageMultiplier;
    public float duration;
    public int manaCost;
}
```

### 7.5 拳套(FistWeapon)

**状态机定义**：
```
Idle → Startup(左直拳) → Active → Recovery → Startup(右直拳) → ... → Startup(升龙拳) → Recovery → Idle
                                                                                                  ↓
                                                                                              回到第1段
Idle → ChargeStartup → ChargeActive → ChargeRecovery → Idle
DodgeEnd → CounterWindow(8帧) → CounterStartup → CounterActive → CounterRecovery → Idle
Idle → SpecialStartup → SpecialActive → SpecialRecovery → Idle
Idle → UltimateStartup(不可取消) → UltimateActive → UltimateRecovery → Idle
```

**关键方法签名**：

```text
/// <summary>
/// 拳套武器 - 5段连击，连击数增益，闪避反击
/// 特有机制：连击阶梯增益、前冲系统、闪避反击
/// </summary>
public class FistWeapon : WeaponBase
{
    private int _comboHitCount;              // 连击命中数(不同于combo段数)
    private float _comboHitTimer;            // 连击超时
    private bool _dodgeCounterWindow;        // 闪避反击窗口
    private float _dodgeCounterTimer;        // 反击窗口剩余时间
    
    private const int MAX_COMBO = 5;         // 5段连击
    private const float COMBO_HIT_TIMEOUT = 2f; // 2秒未命中重置
    private const float COUNTER_WINDOW = 8f / 60f; // 8帧反击窗口
    
    public int ComboHitCount => _comboHitCount;
    public bool IsCounterWindow => _dodgeCounterWindow;
    
    /// <summary>
    /// 连击阶梯增益
    /// 0~4:无  5~9:疾风(攻速+10%)  10~14:烈风(攻速+10%,暴击+8%)
    /// 15~19:狂风(攻速+15%,暴击+12%,命中+1时能)  20~29:风暴(攻速+20%,暴击+15%,命中+2时能,附10%时间伤)
    /// 30+:时之风暴(攻速+25%,暴击+20%,命中+3时能,附20%时间伤,周围减速15%)
    /// </summary>
    public ComboTier GetCurrentTier()
    {
        return _comboHitCount switch
        {
            < 5 => ComboTier.None,
            < 10 => ComboTier.Gale,
            < 15 => ComboTier.FierceWind,
            < 20 => ComboTier.Storm,
            < 30 => ComboTier.Hurricane,
            _ => ComboTier.TimeStorm
        };
    }
    
    /// <summary>获取当前连击阶梯的攻速加成</summary>
    public float GetAttackSpeedBonus()
    {
        return GetCurrentTier() switch
        {
            ComboTier.Gale => 0.10f,
            ComboTier.FierceWind => 0.10f,
            ComboTier.Storm => 0.15f,
            ComboTier.Hurricane => 0.20f,
            ComboTier.TimeStorm => 0.25f,
            _ => 0f
        };
    }
    
    /// <summary>获取当前连击阶梯的暴击率加成</summary>
    public float GetCritRateBonus()
    {
        return GetCurrentTier() switch
        {
            ComboTier.FierceWind => 0.08f,
            ComboTier.Storm => 0.12f,
            ComboTier.Hurricane => 0.15f,
            ComboTier.TimeStorm => 0.20f,
            _ => 0f
        };
    }
    
    /// <summary>获取每命中回复时之能量</summary>
    public int GetTimeEnergyPerHit()
    {
        return GetCurrentTier() switch
        {
            ComboTier.Storm => 1,
            ComboTier.Hurricane => 2,
            ComboTier.TimeStorm => 3,
            _ => 0
        };
    }
    
    /// <summary>获取普攻附加时间伤害百分比</summary>
    public float GetTimeDamageBonus()
    {
        return GetCurrentTier() switch
        {
            ComboTier.Hurricane => 0.10f,
            ComboTier.TimeStorm => 0.20f,
            _ => 0f
        };
    }
    
    /// <summary>命中时增加连击数</summary>
    public override void OnHitConfirmed()
    {
        base.OnHitConfirmed();
        _comboHitCount++;
        _comboHitTimer = COMBO_HIT_TIMEOUT;
    }
    
    /// <summary>蓄力重拳命中+3连击</summary>
    public void OnChargeHitConfirmed()
    {
        _comboHitCount += 3;
        _comboHitTimer = COMBO_HIT_TIMEOUT;
    }
    
    /// <summary>闪避反击命中+5连击</summary>
    public void OnCounterHitConfirmed()
    {
        _comboHitCount += 5;
        _comboHitTimer = COMBO_HIT_TIMEOUT;
    }
    
    /// <summary>闪避结束，开启反击窗口</summary>
    public void OnDodgeEnd()
    {
        _dodgeCounterWindow = true;
        _dodgeCounterTimer = COUNTER_WINDOW;
    }
    
    /// <summary>每帧更新</summary>
    public override void UpdateCombo(float deltaTime)
    {
        base.UpdateCombo(deltaTime);
        
        // 连击超时
        if (_comboHitCount > 0)
        {
            _comboHitTimer -= deltaTime;
            if (_comboHitTimer <= 0f)
            {
                _comboHitCount = 0;
            }
        }
        
        // 反击窗口超时
        if (_dodgeCounterWindow)
        {
            _dodgeCounterTimer -= deltaTime;
            if (_dodgeCounterTimer <= 0f)
            {
                _dodgeCounterWindow = false;
            }
        }
    }
    
    public override void OnTimeStopStart()
    {
        // 时停连打：每次命中延长时间停止5帧，最多30帧
    }
    
    public override void OnTimeRewindEnd()
    {
        // 回溯反击：闪避反击伤害×2.0，产生时间冲击波
    }
}

public enum ComboTier
{
    None,           // 0~4
    Gale,           // 5~9 疾风
    FierceWind,     // 10~14 烈风
    Storm,          // 15~19 狂风
    Hurricane,      // 20~29 风暴
    TimeStorm       // 30+ 时之风暴
}
```

---

## 8. 受击反馈系统

### 8.1 HitFeedbackController

```text
/// <summary>
/// 受击反馈控制器 - 管理击退、无敌帧、硬直
/// 挂载在所有可受伤实体上
/// </summary>
public class HitFeedbackController : Node, IDamageable
{
    [Header("组件引用")]
     private CharacterBody2D _rb;
     private AnimationPlayer或AnimationTree _animator;
     private Hurtbox _hurtbox;
    
    [Header("属性")]
     private int _entityId;
     private float _maxHP;
     private float _currentHP;
     private float _baseDEF;
     private float _knockbackResistance; // 击退抵抗(0~0.8)
    
    // === 运行时状态 ===
    private bool _isInvincible;
    private int _invincibleFramesRemaining;
    private Vector2 _knockbackVelocity;
    private int _knockbackFramesRemaining;
    private bool _isInHitstun;
    private int _hitstunFramesRemaining;
    private HitstunLevel _currentHitstunLevel;
    
    // === 事件 ===
    public event System.Action<float, float> OnHPChanged;
    public event System.Action OnDeath;
    
    // === IDamageable实现 ===
    public int EntityId => _entityId;
    public float CurrentHP => _currentHP;
    public float MaxHP => _maxHP;
    public bool IsAlive => _currentHP > 0;
    
    // ===== 受伤处理 =====
    
    /// <summary>
    /// 受伤处理 - 完整流程
    /// </summary>
    public void TakeDamage(DamageInfo damage)
    {
        if (!IsAlive || _isInvincible) return;
        
        // 应用伤害
        _currentHP = math.Max(0, _currentHP - damage.BaseDamage);
        OnHPChanged?.Invoke(_currentHP, _maxHP);
        
        // 发布受伤事件
        EventBus.Publish(new DamageReceivedEvent
        {
            SourceId = damage.SourceId,
            Damage = damage,
            FinalDamage = damage.BaseDamage
        });
        
        // 计算受击类型(根据伤害占最大HP百分比)
        HitstunLevel level = CalculateHitstunLevel(damage.BaseDamage);
        
        // 应用击退
        ApplyKnockback(damage.KnockbackForce, level);
        
        // 应用受击硬直
        ApplyHitstun(level);
        
        // 受击后无敌帧
        ActivateInvincibility(15); // 基础15帧
        
        // 死亡判定
        if (_currentHP <= 0)
        {
            Kill();
        }
    }
    
    public void Heal(float amount)
    {
        _currentHP = math.Min(_maxHP, _currentHP + amount);
        OnHPChanged?.Invoke(_currentHP, _maxHP);
    }
    
    public void Kill()
    {
        _currentHP = 0;
        OnDeath?.Invoke();
        EventBus.Publish(new EntityDeathEvent
        {
            EntityId = _entityId,
            IsBoss = false // 由外部设置
        });
    }
    
    // ===== 受击硬直 =====
    
    /// <summary>
    /// 根据伤害比例确定硬直等级
    /// 轻(≤5%MaxHP): 12帧  中(5~15%): 20帧  重(15~25%): 30帧  击倒(>25%): 45帧(含起身20帧)
    /// </summary>
    private HitstunLevel CalculateHitstunLevel(float damage)
    {
        float ratio = damage / _maxHP;
        
        if (ratio > 0.25f) return HitstunLevel.Knockdown;
        if (ratio > 0.15f) return HitstunLevel.Heavy;
        if (ratio > 0.05f) return HitstunLevel.Medium;
        return HitstunLevel.Light;
    }
    
    private int GetHitstunFrames(HitstunLevel level)
    {
        return level switch
        {
            HitstunLevel.Light => 12,
            HitstunLevel.Medium => 20,
            HitstunLevel.Heavy => 30,
            HitstunLevel.Knockdown => 45,
            _ => 12
        };
    }
    
    private void ApplyHitstun(HitstunLevel level)
    {
        _isInHitstun = true;
        _currentHitstunLevel = level;
        _hitstunFramesRemaining = GetHitstunFrames(level);
        
        // 播放受击动画
        string animState = level switch
        {
            HitstunLevel.Light => "Hit_Light",
            HitstunLevel.Medium => "Hit_Medium",
            HitstunLevel.Heavy => "Hit_Heavy",
            HitstunLevel.Knockdown => "Hit_Knockdown",
            _ => "Hit_Light"
        };
        _animator.Play(animState);
        
        // 通知ActionPlayer进入硬直
        EventBus.Publish(new HitstunEvent
        {
            TargetId = _entityId,
            Level = level,
            DurationFrames = _hitstunFramesRemaining
        });
    }
    
    // ===== 击退 =====
    
    /// <summary>
    /// 应用击退
    /// 击退距离(base) = 攻击击退力 × (1 + 攻击者击退加成%) × (1 - 目标击退抵抗%)
    /// 击退持续帧数 = MAX(6, FLOOR(击退距离 / 3))
    /// </summary>
    private void ApplyKnockback(Vector2 knockbackForce, HitstunLevel level)
    {
        // 击退距离计算(考虑击退抵抗)
        float distance = knockbackForce.magnitude * (1f - _knockbackResistance);
        int duration = math.Max(6, math.FloorToInt(distance / 3f));
        
        // 击退速度
        _knockbackVelocity = knockbackForce.normalized * (distance / (duration / 60f));
        _knockbackFramesRemaining = duration;
    }
    
    // ===== 无敌帧 =====
    
    /// <summary>
    /// 激活无敌帧
    /// 触发条件: 闪避12帧, 受击后15帧, 完美格挡8帧, 起身20帧
    /// </summary>
    public void ActivateInvincibility(int frames)
    {
        _isInvincible = true;
        _invincibleFramesRemaining = frames;
        _hurtbox.SetActive(false); // 禁用受击区域
    }
    
    /// <summary>闪避无敌帧(12帧)</summary>
    public void ActivateDodgeInvincibility()
    {
        ActivateInvincibility(12 + GetBonusInvincibilityFrames());
    }
    
    /// <summary>起身无敌帧(20帧)</summary>
    public void ActivateGetUpInvincibility()
    {
        ActivateInvincibility(20 + GetBonusInvincibilityFrames());
    }
    
    /// <summary>获取额外无敌帧(来自属性INV_TIME)</summary>
    private int GetBonusInvincibilityFrames() => 0; // TODO: 从角色属性获取
    
    // ===== 每帧更新 =====
    
    private void FixedUpdate()
    {
        // 无敌帧倒计时
        if (_isInvincible)
        {
            _invincibleFramesRemaining--;
            if (_invincibleFramesRemaining <= 0)
            {
                _isInvincible = false;
                _hurtbox.SetActive(true);
            }
        }
        
        // 击退执行
        if (_knockbackFramesRemaining > 0)
        {
            _rb.MovePosition(_rb.position + _knockbackVelocity * Time.fixedDeltaTime);
            _knockbackFramesRemaining--;
            
            // 击退减速
            float t = (float)_knockbackFramesRemaining / GetHitstunFrames(_currentHitstunLevel);
            _knockbackVelocity *= t;
        }
        
        // 硬直倒计时
        if (_isInHitstun)
        {
            _hitstunFramesRemaining--;
            if (_hitstunFramesRemaining <= 0)
            {
                _isInHitstun = false;
                
                // 击倒状态结束后起身
                if (_currentHitstunLevel == HitstunLevel.Knockdown)
                {
                    ActivateGetUpInvincibility();
                    _animator.Play("GetUp");
                }
            }
        }
    }
}
```

---

## 9. 战斗性能优化

### 9.1 关键性能指标

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 战斗帧率 | 稳定60fps | 不允许战斗中掉帧 |
| 单帧Hitbox检测耗时 | <0.5ms | 场景内最多32个活动Hitbox |
| 伤害计算耗时 | <0.1ms/次 | 纯数学运算，无GC |
| 弹道实体数量 | ≤50同时在线 | 对象池管理 |
| DOT实例数量 | ≤100同时在线 | 时间减速不影响DOT |

### 9.2 优化策略

#### 9.2.1 零GC热路径

```text
/// <summary>
/// 战斗热路径零GC策略
/// </summary>
public static class CombatOptimization
{
    // 1. 预分配数组/列表，禁止运行时扩容
    private static readonly CollisionShape2D[] _colliderCache = new CollisionShape2D[64];
    private static readonly List<ActiveHitbox> _hitboxList = new List<ActiveHitbox>(32);
    
    // 2. 使用struct替代class( DamageInfo, HitboxData, DamageResult等)
    // 3. 缓存GetComponent结果，禁止Update中调用
    // 4. 使用ObjectPool管理弹道和VFX
    
    /// <summary>对象池接口(弹道/VFX共用)</summary>
    public static Node SpawnPooled(Node scene, Vector3 position, Quaternion rotation)
    {
        var pool = ServiceRegistry.Get<IPoolManager>();
        Node obj = pool.Spawn(scene.name);
        if (obj == null)
        {
            obj = Instantiate(scene, position, rotation);
        }
        else
        {
            obj.transform.SetPositionAndRotation(position, rotation);
            obj.SetActive(true);
        }
        return obj;
    }
    
    public static void DespawnPooled(Node obj)
    {
        var pool = ServiceRegistry.Get<IPoolManager>();
        pool.Despawn(obj);
    }
}
```

#### 9.2.2 空间分区优化

```text
/// <summary>
/// 战斗空间分区 - 减少碰撞检测范围
/// 仅检测玩家周围N格内的敌人Hitbox
/// </summary>
public class CombatSpatialGrid
{
    private const float CELL_SIZE = 5f; // 5格为一个网格单元
    private readonly Dictionary<Vector2Int, List<int>> _grid = new();
    
    /// <summary>注册实体到网格</summary>
    public void RegisterEntity(int entityId, Vector2 position)
    {
        Vector2Int cell = WorldToCell(position);
        if (!_grid.ContainsKey(cell))
            _grid[cell] = new List<int>();
        _grid[cell].Add(entityId);
    }
    
    /// <summary>查询半径内的实体</summary>
    public List<int> QueryRadius(Vector2 center, float radius)
    {
        var result = new List<int>();
        Vector2Int minCell = WorldToCell(center - Vector2.one * radius);
        Vector2Int maxCell = WorldToCell(center + Vector2.one * radius);
        
        for (int x = minCell.x; x <= maxCell.x; x++)
        {
            for (int y = minCell.y; y <= maxCell.y; y++)
            {
                if (_grid.TryGetValue(new Vector2Int(x, y), out var entities))
                {
                    result.AddRange(entities);
                }
            }
        }
        
        return result;
    }
    
    private Vector2Int WorldToCell(Vector2 pos)
    {
        return new Vector2Int(
            math.FloorToInt(pos.x / CELL_SIZE),
            math.FloorToInt(pos.y / CELL_SIZE));
    }
}
```

#### 9.2.3 其他优化清单

| 优化项 | 实现方式 | 预期收益 |
|--------|---------|---------|
| Physics2D Layer矩阵 | 仅Hitbox-Hurtbox层交互 | 减少50%碰撞检测量 |
| Hitbox形状简化 | 扇形→圆形近似(误差<5%) | 避免角度计算 |
| 弹道对象池 | 预创建50个弹道实例 | 消除Instantiate/Destroy GC |
| VFX对象池 | 预创建常用特效 | 消除粒子系统实例化开销 |
| 伤害数字合并 | 同目标30帧内数字叠加 | 减少80%浮动数字实例 |
| DOT批量更新 | HitFeedbackController统一遍历 | 避免每个DOT独立Update |
| 动画缓存 | AnimationPlayer library lookup预计算 | 避免每帧字符串查找 |
| 距离剔除 | 超过屏幕2倍距离的敌人暂停AI | 降低非可见敌人CPU开销 |
| Burst编译(可选) | DamageCalculator数学密集部分 | 伤害计算加速2~5倍 |

### 9.3 性能监控

```text
/// <summary>
/// 战斗性能监控 - 开发期使用，发布时移除
/// </summary>
public class CombatProfiler : Node
{
    private float _hitboxTime;
    private float _damageTime;
    private int _activeProjectiles;
    private int _activeDOTs;
    
    private void Update()
    {
        // 显示性能HUD
        if (Debug.isDebugBuild)
        {
            // 使用Godot debug overlay或Label显示
            // Hitbox: {_hitboxTime:F2}ms
            // Damage: {_damageTime:F2}ms
            // Projectiles: {_activeProjectiles}
            // DOTs: {_activeDOTs}
        }
    }
}
```

---

## 10. 测试计划

### 10.1 单元测试

| 测试类 | 测试项 | 验证内容 |
|--------|--------|---------|
| DamageCalculatorTests | PhysicalDamage_Basic | 物理伤害基础计算正确性 |
| DamageCalculatorTests | PhysicalDamage_WithDef | 防御减伤公式 DEF/(DEF+K) |
| DamageCalculatorTests | PhysicalDamage_ArmorPen | 穿甲值减少有效DEF |
| DamageCalculatorTests | TimeDamage_IgnoresHalfDef | 时间伤害无视50%DEF |
| DamageCalculatorTests | TimeDamage_WithResistance | 时间抗性正确应用 |
| DamageCalculatorTests | VoidDamage_IgnoresFullDef | 虚无伤害无视100%DEF |
| DamageCalculatorTests | VoidDamage_NoCrit | 虚无伤害不可暴击 |
| DamageCalculatorTests | VoidDamage_AbnormalBonus | 异常状态+25%伤害 |
| DamageCalculatorTests | ElementalDamage_HalfDef | 元素受DEF半额减免 |
| DamageCalculatorTests | Crit_RateAndDamage | 暴击率/暴击伤害正确 |
| DamageCalculatorTests | Crit_Cap75 | 暴击率硬上限75% |
| DamageCalculatorTests | Crit_Pity | 连续5次非暴击后必暴 |
| DamageCalculatorTests | IndependentReduction_Multi | 独立减伤乘算叠加 |
| DamageCalculatorTests | IndependentReduction_Cap90 | 总减伤上限90% |
| DamageCalculatorTests | SoftCap_ATKPercent | ATK%软上限计算 |
| DamageCalculatorTests | SoftCap_CR | 暴击率软上限 |
| DamageCalculatorTests | DamageInteraction_PhysTime | 物理+时间=时断打击 |
| DamageCalculatorTests | DamageInteraction_TimeVoid | 时间+虚无=熵增 |
| DamageCalculatorTests | DOT_CalculatePerTick | DOT每刻伤害计算 |
| DamageCalculatorTests | DOT_CritBonus | 来源暴击DOT+20% |
| DamageCalculatorTests | Variance_Range | 随机波动[0.95, 1.05] |
| DamageCalculatorTests | MinimumDamage1 | 最低1点伤害 |
| InputBufferTests | Buffer_WithinWindow | 缓冲窗口内输入有效 |
| InputBufferTests | Buffer_Expired | 过期输入被清除 |
| InputBufferTests | Buffer_DodgePriority | 闪避输入优先级最高 |
| ActionPlayerTests | StateTransition_StartupToActive | 前摇→活动帧正确切换 |
| ActionPlayerTests | CancelWindow_Dodge | 闪避取消正确触发 |
| ActionPlayerTests | ComboChain_4Hit | 剑4段连招完整流程 |
| ActionPlayerTests | AttackSpeed_FrameAdjust | 攻速修正帧数下限40% |
| FistWeaponTests | ComboTier_Gale | 连击阶梯5~9攻速+10% |
| FistWeaponTests | ComboTier_TimeStorm | 30+连击全增益生效 |
| FistWeaponTests | CounterWindow_8Frames | 闪避反击8帧窗口 |
| GunWeaponTests | Ammo_ConsumeAndReload | 弹药消耗与自动换弹 |
| GunWeaponTests | PerfectReload_Window | 完美换弹窗口28~36帧 |
| GunWeaponTests | PerfectReload_Bonus | 完美换弹+1弹药+时间装填 |
| BowWeaponTests | DistanceModifier_Ranges | 距离衰减各区间正确 |
| BowWeaponTests | WeakpointShot_Behind | 背后命中弱点判定 |
| StaffWeaponTests | ElementSwitch_Cycle | 属性切换循环 |
| StaffWeaponTests | SpellCombo_Window | 5秒组合窗口 |
| StaffWeaponTests | Mana_ConsumeAndRegen | 法力消耗与回复 |

### 10.2 集成测试

| 测试场景 | 测试内容 | 验证标准 |
|----------|---------|---------|
| SwordFullCombo | 剑4段连击完整流程 | 每段伤害/帧数/判定区域正确 |
| SwordParryChain | 连续完美格挡3次+反击 | 反击倍率2.0→2.5→3.0递增 |
| BowChargeRelease | 弓3段蓄力+满蓄 | 各段伤害/穿透/特效正确 |
| GunFullCycle | 射击6发→换弹→完美换弹 | 弹药管理正确，完美换弹触发 |
| StaffComboSpell | 火→冰法术组合 | 蒸汽爆发正确触发 |
| FistHighCombo | 拳套30+连击 | 时之风暴增益全部生效 |
| DamageInteraction | 物理+时间命中 | 时断打击+15%伤害+8帧硬直 |
| KnockbackPhysics | 重击击退 | 击退距离/速度/帧数符合公式 |
| InvincibilityFrames | 受击后无敌帧 | 15帧内不再受伤 |
| EmergencyDodge | 硬直中闪避 | 第4帧起可闪避，2倍消耗 |

### 10.3 性能测试

| 测试项 | 测试方法 | 通过标准 |
|--------|---------|---------|
| 60fps稳定 | 8敌人+玩家同时战斗 | 帧时间<16.67ms, 无GC Spike |
| 弹道压力 | 50弹道同时飞行 | 帧时间增量<2ms |
| DOT压力 | 100个DOT同时生效 | 帧时间增量<1ms |
| Hitbox批量 | 32个活动Hitbox | 单帧检测<0.5ms |
| 对象池验证 | 连续生成/回收1000次 | 零GC分配 |

### 10.4 回归测试清单

每次战斗系统修改后必跑：

- [ ] 五武器基础连招/蓄力/特殊技/终极技正常
- [ ] 四种伤害类型公式结果正确
- [ ] 暴击系统(含保底)正常
- [ ] 防御减伤公式正确
- [ ] 伤害类型交互6种组合正常
- [ ] DOT计算与刷新规则正确
- [ ] 取消窗口/输入缓冲正常
- [ ] 击退/无敌帧/硬直正常
- [ ] 各角色被动技能正常
- [ ] 时间联动技正常
- [ ] 无GC Spike(战斗场景Profile 5分钟)

---

> **文档结束**
>
> 本文档为战斗系统开发文档v1.0，所有代码骨架基于架构总纲(00_Architecture.md)、战斗设计(3.1combat-system-design.md)、数值体系(4_角色与数值体系设计.md)编写。
> 
> 下一步：02_TimeSystem.md → 时间操控系统开发文档
