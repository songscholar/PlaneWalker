# 06 — 角色与进度系统开发文档

**版本**: 1.0  
**日期**: 2026-04-22  
**引擎**: Godot 4.x  
**语言**: GDScript 2.0（性能瓶颈可用GDExtension/C++）  
**关联架构**: [00_Architecture.md](00_Architecture.md)  
**关联设计**: 4_角色与数值体系 / 2_世界观与叙事进度 / 8.2_货币养成与天赋树 / 8.4_锻造强化与新手教学

---

> **Godot迁移约束**：角色静态数据使用 Resource(`.tres`)，角色运行时实体使用 `CharacterBody2D` + 组合式能力脚本。无场景依赖的逻辑写成 `RefCounted`，需要挂载的行为写成节点脚本。

> **v1.1实现约束**：若本文档中的Meta、锻造、虚空淬炼、熟练度或角色等级数值与 `docs/0_深度收敛与系统职责设计.md` / `docs/8.2_货币养成与天赋树设计.md` 冲突，以v1.1低数值局外成长为准。局外成长优先实现解锁、便利性、信息、训练和流派入口；直接战斗数值常规控制在15-25%，极限满收集不超过30%。

## 1. 角色系统架构

### 1.1 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                    角色系统架构                            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  CharacterData (Resource)                   │ │
│  │  · 角色基础数值配置                                   │ │
│  │  · 专属技能配置                                       │ │
│  │  · 解锁条件                                          │ │
│  └──────────────────────┬─────────────────────────────┘ │
│                         │ 数据注入                        │
│                         ▼                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │  CharacterBase (抽象类)                              │ │
│  │  · 共用生命周期: Initialize / UpdateMechanics        │ │
│  │  · 共用接口: UseActiveSkill / OnRoomEnter          │ │
│  │  · 属性持有: CharacterStats                          │ │
│  └──────────────────────┬─────────────────────────────┘ │
│                         │ 继承                           │
│      ┌──────┬───────┬───────┬───────┬────────┐         │
│      ▼      ▼       ▼       ▼       ▼        ▼         │
│  Walker  TimeG   VoidW  OriginK  TimeLord              │
│  行者    守卫    行者    骑士    领主                    │
│  均衡型  格挡型  高风险  双武器  时间专精                 │
└─────────────────────────────────────────────────────────┘
```

### 1.2 CharacterData Resource

```text
using Godot;

/// <summary>
/// 角色配置数据，每种角色一份SO实例
/// 路径: resources/characters/
/// </summary>
[CreateAssetMenu(fileName = "CharacterData_", menuName = "Plane Walker/Character Data")]
public class CharacterData : Resource
{
    [Header("基础信息")]
    public string CharacterId;              // 唯一ID: "walker", "time_guardian" 等
    public string DisplayName;              // 显示名: "行者", "时之守卫" 等
    public string Description;              // 角色描述
    public Sprite Portrait;                 // 角色肖像
    public int OperationDifficulty;         // 操作复杂度: 1~5星

    [Header("基础属性")]
    public float BaseHP = 200f;             // 基础生命值
    public float BaseATK = 30f;             // 基础攻击力
    public float BaseDEF = 15f;             // 基础防御力
    public float BaseSPD = 5.0f;            // 基础移动速度(格/秒)
    public float BaseMaxTimeEnergy = 100f;  // 时之能量上限
    public float BaseTimeEnergyRegen = 5f;  // 时之能量回复/秒
    public int BaseDodgeCount = 3;          // 闪避次数上限
    public float BaseDodgeIframes = 0.25f;  // 闪避无敌帧(秒)
    public float BaseParryWindow = 0f;      // 格挡判定窗(秒，时之守卫专属)

    [Header("伤害系数")]
    public float TimeDamageMultiplier = 1.0f; // 时间伤害系数(时间领主1.5x)
    public float VoidDamageMultiplier = 1.0f; // 虚无伤害系数

    [Header("武器适配")]
    public WeaponAffinity[] WeaponAffinities; // 5种武器的适配评分(1~5星)

    [Header("解锁条件")]
    public UnlockCondition UnlockCondition;   // 角色解锁条件

    [Header("技能配置")]
    public string PassiveSkillId;           // 专属被动技能ID
    public string ActiveSkillId;            // 专属主动技能ID
    public float ActiveSkillCooldown = 12f; // 主动技能冷却(秒)
    public float ActiveSkillEnergyCost = 30f;// 主动技能时之能量消耗
}

/// <summary>武器适配条目</summary>
[System.Serializable]
public struct WeaponAffinity
{
    public WeaponType Type;     // 武器类型
    public int Rating;          // 适配评分: 1~5
}

/// <summary>武器类型枚举</summary>
public enum WeaponType
{
    Sword,   // 剑
    Bow,     // 弓
    Gun,     // 枪
    Staff,   // 杖
    Fist     // 拳套
}

/// <summary>角色解锁条件</summary>
[System.Serializable]
public class UnlockCondition
{
    public UnlockConditionType Type;
    public string RequiredCharacterId;   // 需要使用的角色ID
    public int RequiredValue;            // 数值阈值
    public string RequiredMetaNodeId;    // 替代条件: Meta节点ID
    public string Description;           // 解锁描述

    public bool IsUnlocked(PersistentData persistent)
    {
        switch (Type)
        {
            case UnlockConditionType.Default:
                return true;
            case UnlockConditionType.ClearFloor:
                return persistent.UnlockedCharacters.Contains(RequiredCharacterId)
                    && persistent.MaxFloorCleared >= RequiredValue;
            case UnlockConditionType.TotalDamageTaken:
                return persistent.MaxDamageTakenInFloor >= RequiredValue;
            case UnlockConditionType.WeaponSwitchCount:
                return persistent.MaxWeaponSwitchesInRun >= RequiredValue;
            case UnlockConditionType.TotalTimeEnergySpent:
                return persistent.MaxTimeEnergySpentInRun >= RequiredValue;
            case UnlockConditionType.OrMetaNode:
                return persistent.UnlockedNodes.Contains(RequiredMetaNodeId)
                    || persistent.UnlockedCharacters.Contains(RequiredCharacterId);
            default:
                return false;
        }
    }
}

public enum UnlockConditionType
{
    Default,                // 默认解锁
    ClearFloor,             // 通关指定层数
    TotalDamageTaken,       // 单层受伤总量
    WeaponSwitchCount,      // 单局武器切换次数
    TotalTimeEnergySpent,   // 单局时之能量消耗
    OrMetaNode              // 或: Meta节点解锁
}
```

### 1.3 CharacterBase 抽象类

```text
using Godot;
using System;
using System.Collections.Generic;

/// <summary>
/// 角色抽象基类，所有角色共享的生命周期和接口
/// 不继承Node，RefCounted类，便于测试
/// 由PlayerController持有和调用
/// </summary>
public abstract class CharacterBase
{
    // ── 核心引用 ──
    public CharacterData Data { get; protected set; }
    public CharacterStats Stats { get; protected set; }

    // ── 运行时状态 ──
    public float CurrentHP { get; protected set; }
    public float CurrentTimeEnergy { get; protected set; }
    public bool IsAlive { get; protected set; }
    public float ActiveSkillCooldownTimer { get; protected set; }

    // ── 事件 ──
    public event Action<float, float> OnHPChanged;          // (current, max)
    public event Action<float, float> OnTimeEnergyChanged;   // (current, max)
    public event Action OnDeath;

    // ── 初始化 ──

    /// <summary>
    /// 使用CharacterData初始化角色，创建属性系统并设置初始值
    /// </summary>
    public virtual void Initialize(CharacterData data)
    {
        Data = data;
        Stats = new CharacterStats(data);
        CurrentHP = Stats.GetStat(StatType.MHP).Value;
        CurrentTimeEnergy = Stats.GetStat(StatType.ME).Value;
        IsAlive = true;
        ActiveSkillCooldownTimer = 0f;
    }

    // ── 生命周期 ──

    /// <summary>
    /// 每帧调用，处理角色专属机制更新
    /// </summary>
    /// <param name="deltaTime">帧间隔时间</param>
    public virtual void UpdateMechanics(float deltaTime)
    {
        // 时之能量自然回复
        RegenTimeEnergy(deltaTime);

        // 主动技能冷却递减
        if (ActiveSkillCooldownTimer > 0f)
            ActiveSkillCooldownTimer = math.Max(0f, ActiveSkillCooldownTimer - deltaTime);
    }

    /// <summary>
    /// 固定时间步更新，处理物理相关的角色机制
    /// </summary>
    public virtual void FixedUpdateMechanics(float fixedDeltaTime) { }

    // ── 共用接口 ──

    /// <summary>
    /// 使用角色专属主动技能
    /// </summary>
    /// <returns>是否成功施放</returns>
    public abstract bool UseActiveSkill();

    /// <summary>
    /// 房间进入时触发(角色被动机制入口)
    /// </summary>
    public abstract void OnRoomEnter(string roomId);

    /// <summary>
    /// 房间清除时触发
    /// </summary>
    public virtual void OnRoomCleared(string roomId) { }

    /// <summary>
    /// 武器命中敌人时触发
    /// </summary>
    public virtual void OnWeaponHit(WeaponType weaponType, int targetEntityId) { }

    /// <summary>
    /// 武器切换时触发
    /// </summary>
    public virtual void OnWeaponSwitch(WeaponType fromType, WeaponType toType) { }

    /// <summary>
    /// 受到伤害时触发(在伤害结算之后)
    /// </summary>
    public virtual void OnDamageReceived(DamageInfo damage) { }

    /// <summary>
    /// 击杀敌人时触发
    /// </summary>
    public virtual void OnKill(int entityId, bool isBoss) { }

    /// <summary>
    /// 格挡/闪避成功时触发
    /// </summary>
    public virtual void OnDodgeSuccess() { }
    public virtual void OnParrySuccess(bool isPerfect) { }

    // ── 通用逻辑 ──

    /// <summary>
    /// 受到伤害
    /// </summary>
    public virtual void TakeDamage(float amount)
    {
        if (!IsAlive) return;

        CurrentHP -= amount;
        OnHPChanged?.Invoke(CurrentHP, Stats.GetStat(StatType.MHP).Value);

        if (CurrentHP <= 0f)
        {
            CurrentHP = 0f;
            OnDeath?.Invoke();
        }
    }

    /// <summary>
    /// 治疗生命值
    /// </summary>
    public virtual void Heal(float amount)
    {
        float maxHP = Stats.GetStat(StatType.MHP).Value;
        CurrentHP = math.Min(maxHP, CurrentHP + amount);
        OnHPChanged?.Invoke(CurrentHP, maxHP);
    }

    /// <summary>
    /// 消耗时之能量
    /// </summary>
    /// <returns>是否消耗成功</returns>
    public bool TryConsumeTimeEnergy(float amount)
    {
        if (CurrentTimeEnergy < amount) return false;
        CurrentTimeEnergy -= amount;
        OnTimeEnergyChanged?.Invoke(CurrentTimeEnergy, Stats.GetStat(StatType.ME).Value);
        return true;
    }

    /// <summary>
    /// 时之能量自然回复
    /// </summary>
    protected void RegenTimeEnergy(float deltaTime)
    {
        float maxEnergy = Stats.GetStat(StatType.ME).Value;
        if (CurrentTimeEnergy >= maxEnergy) return;

        float regenRate = Stats.GetStat(StatType.MER).Value;
        CurrentTimeEnergy = math.Min(maxEnergy, CurrentTimeEnergy + regenRate * deltaTime);
        OnTimeEnergyChanged?.Invoke(CurrentTimeEnergy, maxEnergy);
    }

    /// <summary>
    /// 主动技能是否可用
    /// </summary>
    public virtual bool CanUseActiveSkill()
    {
        return ActiveSkillCooldownTimer <= 0f
            && CurrentTimeEnergy >= Data.ActiveSkillEnergyCost;
    }

    /// <summary>
    /// 进入死亡状态(角色专属死亡处理)
    /// </summary>
    public virtual void OnRunDeath() { }
}
```

### 1.4 五个角色子类

#### 1.4.1 Walker — 行者

```text
/// <summary>
/// 行者 — 均衡型，旅途印记被动 + 时间回溯主动
/// 操作复杂度: ★☆☆☆☆
/// </summary>
public class Walker : CharacterBase
{
    // ── 旅途印记 (被动) ──
    private int _pathMarkStacks;
    private const int PATH_MARK_MAX = 10;
    private const float PATH_MARK_DAMAGE_BONUS = 0.03f;   // 每层3%
    private const float PATH_MARK_HEAL_PER_STACK = 2f;    // 每层回复2HP
    private const int MEMORY_SHARD_PER_MARK = 5;          // 记忆碎片转化

    public int PathMarkStacks => _pathMarkStacks;

    // ── 时间回溯 (主动) ──
    private TimeAnchor _activeAnchor;
    private const float ANCHOR_DURATION = 8f;
    private float _anchorTimer;
    private const float RECALL_HEAL_PERCENT = 0.25f;      // 回溯回复25%
    private float _damageSinceAnchor;                      // 锚点后受到的伤害

    // ── 记忆碎片(局外成长资源) ──
    public int MemoryShards { get; private set; }

    public override void Initialize(CharacterData data)
    {
        base.Initialize(data);
        _pathMarkStacks = 0;
        _activeAnchor = null;
        _anchorTimer = 0f;
        _damageSinceAnchor = 0f;
    }

    public override void UpdateMechanics(float deltaTime)
    {
        base.UpdateMechanics(deltaTime);

        // 锚点持续时间递减
        if (_activeAnchor != null)
        {
            _anchorTimer -= deltaTime;
            if (_anchorTimer <= 0f)
            {
                _activeAnchor = null; // 锚点消失
            }
        }
    }

    // ── 被动: 旅途印记 ──

    public override void OnRoomEnter(string roomId)
    {
        // 每次切换房间获得1层旅途印记
        _pathMarkStacks = math.Min(PATH_MARK_MAX, _pathMarkStacks + 1);

        // 应用伤害加成修饰符
        var markModifier = new StatModifier(
            StatType.ATK_PERCENT,
            PATH_MARK_DAMAGE_BONUS * _pathMarkStacks,
            StatModType.Additive,
            "PathMark"
        );
        Stats.RemoveModifiersBySource("PathMark");
        Stats.AddModifier(markModifier);

        EventBus.Publish(new PathMarkChangedEvent
        {
            Stacks = _pathMarkStacks,
            MaxStacks = PATH_MARK_MAX
        });
    }

    public override void OnRoomCleared(string roomId)
    {
        // 房间结束时每层印记回复2HP
        float healAmount = PATH_MARK_HEAL_PER_STACK * _pathMarkStacks;
        Heal(healAmount);
    }

    public override void OnDamageReceived(DamageInfo damage)
    {
        base.OnDamageReceived(damage);
        // 记录锚点后的伤害
        if (_activeAnchor != null)
        {
            _damageSinceAnchor += damage.BaseDamage;
        }
    }

    // ── 主动: 时间回溯 ──

    public override bool UseActiveSkill()
    {
        if (!CanUseActiveSkill()) return false;

        if (_activeAnchor == null)
        {
            // 放置锚点
            if (!TryConsumeTimeEnergy(Data.ActiveSkillEnergyCost)) return false;

            _activeAnchor = new TimeAnchor(
                position: GetCurrentPosition(),
                hp: CurrentHP,
                timeEnergy: CurrentTimeEnergy
            );
            _anchorTimer = ANCHOR_DURATION;
            _damageSinceAnchor = 0f;

            EventBus.Publish(new TimeAnchorPlacedEvent
            {
                Position = _activeAnchor.Position,
                Duration = ANCHOR_DURATION
            });
            return true;
        }
        else
        {
            // 回溯到锚点
            if (!TryConsumeTimeEnergy(Data.ActiveSkillEnergyCost)) return false;

            // 回复锚点后所受伤害的25%
            float healAmount = _damageSinceAnchor * RECALL_HEAL_PERCENT;
            Heal(healAmount);

            // 瞬移到锚点位置
            SetPosition(_activeAnchor.Position);

            EventBus.Publish(new TimeRecallEvent
            {
                FromPosition = GetCurrentPosition(),
                ToPosition = _activeAnchor.Position,
                HealAmount = healAmount
            });

            // 清理并进入冷却
            _activeAnchor = null;
            ActiveSkillCooldownTimer = Data.ActiveSkillCooldown;
            return true;
        }
    }

    // ── 死亡处理 ──

    public override void OnRunDeath()
    {
        // 印记50%转化为记忆碎片
        int shards = math.FloorToInt(_pathMarkStacks * 0.5f) * MEMORY_SHARD_PER_MARK;
        MemoryShards += shards;
    }

    // 辅助方法 (由PlayerController桥接)
    protected virtual Vector2 GetCurrentPosition() => Vector2.zero;
    protected virtual void SetPosition(Vector2 pos) { }
}

/// <summary>时间锚点数据</summary>
public class TimeAnchor
{
    public Vector2 Position;
    public float HP;
    public float TimeEnergy;
    public float Timestamp;

    public TimeAnchor(Vector2 position, float hp, float timeEnergy)
    {
        Position = position;
        HP = hp;
        TimeEnergy = timeEnergy;
        Timestamp = runtime_time;
    }
}
```

#### 1.4.2 TimeGuardian — 时之守卫

```text
/// <summary>
/// 时之守卫 — 格挡/防御型，时间壁垒被动 + 时之堡垒主动
/// 操作复杂度: ★★☆☆☆
/// 闪避替换为格挡操作
/// </summary>
public class TimeGuardian : CharacterBase
{
    // ── 时间壁垒 (被动) ──
    private float _bulwarkCharge;                    // 壁垒充能(0~5层，半层精度)
    private const float BULWARK_MAX = 5f;
    private const float BULWARK_DAMAGE_BONUS = 0.15f; // 每层15%
    private const float SLOW_RADIUS = 6f;             // 减速场半径(格)
    private const float SLOW_DURATION = 3f;           // 减速持续时间
    private const float SLOW_PERCENT = 0.70f;         // 减速70%

    public float BulwarkCharge => _bulwarkCharge;

    // ── 时之堡垒 (主动) ──
    private bool _isInFortress;
    private float _fortressTimer;
    private const float FORTRESS_DURATION = 4f;
    private const float FORTRESS_ATK_SPEED_BONUS = 0.40f;
    private const float FORTRESS_SLOW_RADIUS = 8f;
    private const float SEISMIC_WAVE_MULTIPLIER = 3.0f;

    public bool IsInFortress => _isInFortress;

    public override void UpdateMechanics(float deltaTime)
    {
        base.UpdateMechanics(deltaTime);

        if (_isInFortress)
        {
            _fortressTimer -= deltaTime;
            if (_fortressTimer <= 0f)
            {
                ExitFortress();
            }
        }
    }

    // ── 格挡逻辑 (替代闪避) ──

    /// <summary>
    /// 尝试格挡，在格挡窗口内触发完美格挡
    /// </summary>
    /// <param name="parryTiming">按下格挡到敌人命中的时间差(秒)</param>
    public void TryParry(float parryTiming)
    {
        float parryWindow = Stats.GetStat(StatType.PW).Value;

        if (parryTiming <= parryWindow)
        {
            // 完美格挡: 100%减伤 + 时间凝滞 + 1层充能
            ApplyPerfectParry();
        }
        else if (parryTiming <= parryWindow + 0.25f)
        {
            // 普通格挡: 50%减伤 + 0.5层充能
            ApplyNormalParry();
        }
        // 超出窗口: 正常受伤
    }

    private void ApplyPerfectParry()
    {
        _bulwarkCharge = math.Min(BULWARK_MAX, _bulwarkCharge + 1f);

        // 触发时间凝滞: 周围敌人减速70%/3秒
        EventBus.Publish(new ChronoStasisEvent
        {
            Radius = SLOW_RADIUS,
            Duration = SLOW_DURATION,
            SlowPercent = SLOW_PERCENT
        });

        EventBus.Publish(new PerfectParryEvent { PlayerId = 0 });
    }

    private void ApplyNormalParry()
    {
        _bulwarkCharge = math.Min(BULWARK_MAX, _bulwarkCharge + 0.5f);
    }

    // ── 消耗充能 ──

    /// <summary>
    /// 攻击时消耗壁垒充能增加伤害
    /// </summary>
    /// <returns>充能增伤倍率</returns>
    public float ConsumeBulwarkCharge()
    {
        if (_bulwarkCharge <= 0f) return 0f;
        float bonus = BULWARK_DAMAGE_BONUS * _bulwarkCharge;
        _bulwarkCharge = 0f;
        return bonus;
    }

    // ── 主动: 时之堡垒 ──

    public override bool UseActiveSkill()
    {
        if (!CanUseActiveSkill() || _isInFortress) return false;
        if (!TryConsumeTimeEnergy(Data.ActiveSkillEnergyCost)) return false;

        _isInFortress = true;
        _fortressTimer = FORTRESS_DURATION;

        // 堡垒期间攻速+40%
        Stats.AddModifier(new StatModifier(
            StatType.AS, FORTRESS_ATK_SPEED_BONUS,
            StatModType.Multiplicative, "ChronoFortress"
        ));

        // 无法移动 (由PlayerController检查IsInFortress来限制)
        EventBus.Publish(new ChronoFortressStartEvent { Duration = FORTRESS_DURATION });
        return true;
    }

    private void ExitFortress()
    {
        _isInFortress = false;
        Stats.RemoveModifiersBySource("ChronoFortress");

        // 满充能释放时间震荡波
        if (_bulwarkCharge >= BULWARK_MAX)
        {
            ReleaseSeismicWave();
        }

        ActiveSkillCooldownTimer = Data.ActiveSkillCooldown;
        EventBus.Publish(new ChronoFortressEndEvent());
    }

    private void ReleaseSeismicWave()
    {
        float atk = Stats.GetStat(StatType.FATK).Value;
        float damage = atk * SEISMIC_WAVE_MULTIPLIER;

        EventBus.Publish(new SeismicWaveEvent
        {
            Radius = FORTRESS_SLOW_RADIUS,
            Damage = damage,
            DamageType = DamageType.Time
        });

        _bulwarkCharge = 0f;
    }

    // 堡垒期间每次格挡自动叠加充能
    public override void OnParrySuccess(bool isPerfect)
    {
        if (_isInFortress)
        {
            if (isPerfect) ApplyPerfectParry();
            else ApplyNormalParry();
        }
    }

    public override void OnRoomEnter(string roomId) { }
}
```

#### 1.4.3 VoidWalker — 虚空行者

```text
/// <summary>
/// 虚空行者 — 高风险高回报，虚无共鸣被动 + 虚空吞噬主动
/// 操作复杂度: ★★★★☆
/// HP越低伤害越高，但低HP时持续掉血
/// </summary>
public class VoidWalker : CharacterBase
{
    // ── 虚无共鸣 (被动) ──
    // HP区间增伤表
    private static readonly (float hpPercent, float atkBonus)[] RESONANCE_TIERS = {
        (1.00f, 0.10f),   // 100%~76%: +10%
        (0.75f, 0.30f),   // 75%~51%:  +30%
        (0.50f, 0.60f),   // 50%~26%:  +60%
        (0.25f, 1.00f),   // 25%~1%:   +100%
    };

    private const float EROSION_HP_THRESHOLD = 0.30f;  // HP<30%触发侵蚀
    private const float EROSION_DPS = 2f;               // 侵蚀伤害/秒
    private const float CRITICAL_DURATION = 5f;          // 虚空临界持续
    private const float CRITICAL_DPS = 5f;               // 临界掉血/秒
    private const float CRITICAL_DAMAGE_MULT = 2.0f;     // 临界伤害翻倍

    // ── 虚空临界状态 ──
    private bool _isInCritical;
    private float _criticalTimer;
    private int _criticalHealThreshold = 1;              // 需回复至1HP以上

    public bool IsInCritical => _isInCritical;

    // ── 虚空吞噬 (主动) ──
    private const float DEVOUR_HP_COST_PERCENT = 0.20f;  // 消耗20%最大HP
    private const float DEVOUR_MIN_HP_COST = 10f;        // 最低消耗10HP
    private const float DEVOUR_ATK_MULTIPLIER = 4.0f;    // 4.0x ATK
    private const float DEVOUR_HEAL_PERCENT = 0.15f;     // 回复造成伤害15%
    private const float DEVOUR_KILL_HEAL = 10f;          // 击杀额外回复10HP
    private const float DEVOUR_RANGE = 8f;               // 锥形长度(格)
    private const float DEVOUR_ANGLE = 60f;              // 锥形角度

    public override void UpdateMechanics(float deltaTime)
    {
        base.UpdateMechanics(deltaTime);

        float hpPercent = CurrentHP / Stats.GetStat(StatType.MHP).Value;

        // 虚空侵蚀: HP<30%时持续掉血(真实伤害)
        if (hpPercent < EROSION_HP_THRESHOLD && hpPercent > 0f)
        {
            CurrentHP -= EROSION_DPS * deltaTime;
            OnHPChanged?.Invoke(CurrentHP, Stats.GetStat(StatType.MHP).Value);
        }

        // 虚空临界: HP=0时不立即死亡
        if (_isInCritical)
        {
            _criticalTimer -= deltaTime;
            CurrentHP -= CRITICAL_DPS * deltaTime;
            OnHPChanged?.Invoke(CurrentHP, Stats.GetStat(StatType.MHP).Value);

            // 临界期间回复至1HP以上则脱离
            if (CurrentHP >= 1f)
            {
                _isInCritical = false;
            }

            // 5秒后或HP降到-10则真正死亡
            if (_criticalTimer <= 0f || CurrentHP < -10f)
            {
                IsAlive = false;
                OnDeath?.Invoke();
            }
        }
        else if (CurrentHP <= 0f)
        {
            // 进入虚空临界
            CurrentHP = 0f;
            _isInCritical = true;
            _criticalTimer = CRITICAL_DURATION;
            EventBus.Publish(new VoidCriticalStartEvent { Duration = CRITICAL_DURATION });
        }

        // 更新虚无共鸣增伤修饰符
        UpdateResonanceModifier();
    }

    /// <summary>
    /// 获取当前虚无共鸣增伤百分比
    /// </summary>
    public float GetCurrentResonanceBonus()
    {
        float hpPercent = CurrentHP / Stats.GetStat(StatType.MHP).Value;
        float bonus = 0f;
        foreach (var tier in RESONANCE_TIERS)
        {
            if (hpPercent <= tier.hpPercent)
                bonus = tier.atkBonus;
            else
                break;
        }
        // 临界期间伤害再翻倍
        if (_isInCritical) bonus *= CRITICAL_DAMAGE_MULT;
        return bonus;
    }

    private void UpdateResonanceModifier()
    {
        float bonus = GetCurrentResonanceBonus();
        Stats.RemoveModifiersBySource("VoidResonance");
        if (bonus > 0f)
        {
            Stats.AddModifier(new StatModifier(
                StatType.VDM, bonus,
                StatModType.Additive, "VoidResonance"
            ));
        }
    }

    // ── 主动: 虚空吞噬 ──

    public override bool UseActiveSkill()
    {
        if (!CanUseActiveSkill()) return false;

        float maxHP = Stats.GetStat(StatType.MHP).Value;
        float hpCost = math.Max(DEVOUR_MIN_HP_COST, maxHP * DEVOUR_HP_COST_PERCENT);

        // 消耗HP
        CurrentHP -= hpCost;
        OnHPChanged?.Invoke(CurrentHP, maxHP);

        // 消耗时之能量
        if (!TryConsumeTimeEnergy(Data.ActiveSkillEnergyCost)) return false;

        // 造成伤害 (由战斗系统处理锥形判定)
        float atk = Stats.GetStat(StatType.FATK).Value;
        float totalDamage = atk * DEVOUR_ATK_MULTIPLIER;

        EventBus.Publish(new VoidDevourEvent
        {
            Range = DEVOUR_RANGE,
            Angle = DEVOUR_ANGLE,
            Damage = totalDamage,
            DamageType = DamageType.Void,
            SourceEntityId = 0
        });

        return true;
    }

    /// <summary>
    /// 虚空吞噬命中敌人后回调，计算回复
    /// </summary>
    public void OnDevourHit(float totalDamageDealt)
    {
        Heal(totalDamageDealt * DEVOUR_HEAL_PERCENT);
    }

    /// <summary>
    /// 虚空吞噬击杀敌人回调，额外回复+重置冷却
    /// </summary>
    public void OnDevourKill()
    {
        Heal(DEVOUR_KILL_HEAL);
        ActiveSkillCooldownTimer = 0f; // 击杀重置冷却
    }

    public override void OnRoomEnter(string roomId) { }
}
```

#### 1.4.4 OriginKnight — 原界骑士

```text
/// <summary>
/// 原界骑士 — 双武器切换型，位面共振被动 + 裂界斩主动
/// 操作复杂度: ★★★☆☆
/// 同时装备主副武器，命中蓄积共振层数
/// </summary>
public class OriginKnight : CharacterBase
{
    // ── 位面共振 (被动) ──
    private int _resonanceStacks;
    private const int RESONANCE_MAX = 6;
    private const float RESONANCE_DAMAGE_BONUS = 0.12f;   // 每层12%
    private const float RESONANCE_RANGE_BONUS = 0.05f;     // 每层5%范围
    private const int RESONANCE_CONSUME_HITS = 3;          // 副武器前3次攻击消耗共振
    private const float RESONANCE_BURST_WINDOW = 0.5f;     // 切换后0.5秒共振爆发
    private const float RESONANCE_BURST_TIME_DMG = 0.3f;   // 爆发窗口0.3x ATK时间伤害

    private int _resonanceConsumeHits;  // 当前剩余消耗次数
    private float _resonanceBurstTimer; // 共振爆发窗口计时
    private WeaponType _currentWeapon;
    private WeaponType _otherWeapon;

    public int ResonanceStacks => _resonanceStacks;
    public bool IsInResonanceBurst => _resonanceBurstTimer > 0f;

    // ── 裂界斩 (主动) ──
    private const float REALM_CLEAVE_RANGE = 5f;          // 360度范围5格
    private const float REALM_CLEAVE_MULTIPLIER = 1.5f;   // 1.5x (主+副)ATK
    private const float RESONANCE_PER_STACK_DMG = 0.5f;   // 每层额外0.5x ATK
    private const int UNSTABLE_THRESHOLD = 6;              // 满共振触发位面不稳
    private const float UNSTABLE_DURATION = 8f;            // 位面不稳持续8秒
    private const float UNSTABLE_DAMAGE_BONUS = 0.25f;     // 受到伤害+25%

    public override void OnWeaponHit(WeaponType weaponType, int targetEntityId)
    {
        // 使用当前武器命中，为另一把武器蓄积共振
        if (_resonanceConsumeHits <= 0)
        {
            // 正常蓄积
            _resonanceStacks = math.Min(RESONANCE_MAX, _resonanceStacks + 1);
        }

        // 共振爆发窗口内攻击附带时间伤害
        if (_resonanceBurstTimer > 0f)
        {
            float atk = Stats.GetStat(StatType.FATK).Value;
            EventBus.Publish(new ResonanceBurstHitEvent
            {
                Damage = atk * RESONANCE_BURST_TIME_DMG,
                DamageType = DamageType.Time
            });
        }
    }

    public override void OnWeaponSwitch(WeaponType fromType, WeaponType toType)
    {
        // 切换武器时消耗共振，为副武器增伤
        if (_resonanceStacks > 0)
        {
            _resonanceConsumeHits = RESONANCE_CONSUME_HITS;
            float damageBonus = RESONANCE_DAMAGE_BONUS * _resonanceStacks;
            float rangeBonus = RESONANCE_RANGE_BONUS * _resonanceStacks;

            Stats.AddModifier(new StatModifier(
                StatType.ATK_PERCENT, damageBonus,
                StatModType.Additive, "ResonanceConsume"
            ));
            Stats.AddModifier(new StatModifier(
                StatType.ATK_RANGE, rangeBonus,
                StatModType.Additive, "ResonanceConsume"
            ));
        }

        _resonanceStacks = 0;
        _resonanceBurstTimer = RESONANCE_BURST_WINDOW;

        _currentWeapon = toType;
        _otherWeapon = fromType;
    }

    public override void UpdateMechanics(float deltaTime)
    {
        base.UpdateMechanics(deltaTime);

        if (_resonanceBurstTimer > 0f)
        {
            _resonanceBurstTimer -= deltaTime;
            if (_resonanceBurstTimer <= 0f)
            {
                Stats.RemoveModifiersBySource("ResonanceConsume");
            }
        }

        // 消耗次数用完后清除增伤
        if (_resonanceConsumeHits > 0)
        {
            // 每次副武器攻击递减(由外部调用DecrementResonanceHits)
        }
    }

    /// <summary>
    /// 副武器攻击时调用，递减共振消耗次数
    /// </summary>
    public void DecrementResonanceHits()
    {
        if (_resonanceConsumeHits > 0)
        {
            _resonanceConsumeHits--;
            if (_resonanceConsumeHits <= 0)
            {
                Stats.RemoveModifiersBySource("ResonanceConsume");
            }
        }
    }

    // ── 主动: 裂界斩 ──

    public override bool UseActiveSkill()
    {
        if (!CanUseActiveSkill()) return false;
        if (!TryConsumeTimeEnergy(Data.ActiveSkillEnergyCost)) return false;

        float atk = Stats.GetStat(StatType.FATK).Value;
        float mainAtk = GetWeaponATK(_currentWeapon);
        float subAtk = GetWeaponATK(_otherWeapon);

        // 伤害 = (主ATK + 副ATK) × 1.5 + 共振层数 × 0.5 × ATK
        float totalDamage = (mainAtk + subAtk) * REALM_CLEAVE_MULTIPLIER
                          + _resonanceStacks * RESONANCE_PER_STACK_DMG * atk;

        EventBus.Publish(new RealmCleaveEvent
        {
            Radius = REALM_CLEAVE_RANGE,
            Damage = totalDamage,
            ResonanceStacks = _resonanceStacks
        });

        // 满共振: 标记位面不稳
        if (_resonanceStacks >= UNSTABLE_THRESHOLD)
        {
            EventBus.Publish(new PlanarUnstableEvent
            {
                Duration = UNSTABLE_DURATION,
                DamageBonus = UNSTABLE_DAMAGE_BONUS
            });
        }

        _resonanceStacks = 0;
        ActiveSkillCooldownTimer = Data.ActiveSkillCooldown;
        return true;
    }

    protected virtual float GetWeaponATK(WeaponType type) => Stats.GetStat(StatType.FATK).Value;

    public override void OnRoomEnter(string roomId) { }
}
```

#### 1.4.5 TimeLord — 时间领主

```text
/// <summary>
/// 时间领主 — 时间操控专精，时间法典被动 + 时间支配主动
/// 操作复杂度: ★★★★★
/// 闪避消耗时之能量替代次数，留下时间残影
/// </summary>
public class TimeLord : CharacterBase
{
    // ── 时间法典 (被动) ──
    private const float TIME_ATTACH_DAMAGE_MULT = 1.5f;    // 普攻时间附伤1.5x
    private const float EMPOWERED_DAMAGE_MULT = 2.5f;      // 强化攻击2.5x
    private const float EMPOWERED_ENERGY_COST = 10f;        // 强化攻击能量消耗
    private const float DODGE_ENERGY_COST = 15f;            // 闪避能量消耗
    private const float AFTERIMAGE_DURATION = 4f;           // 残影持续时间
    private const float AFTERIMAGE_EXPLOSION_MULT = 0.8f;   // 残影爆炸0.8x ATK
    private const float AFTERIMAGE_RADIUS = 3f;             // 残影爆炸范围3格
    private const int MAX_AFTERIMAGES = 5;                  // 最大同存残影数

    private readonly List<TimeAfterimage> _afterimages = new List<TimeAfterimage>();

    // ── 时间支配 (主动) ──
    // 短按: 时间冻结
    private const float FREEZE_ENERGY_COST = 60f;
    private const float FREEZE_RADIUS = 10f;
    private const float FREEZE_DURATION = 2.5f;
    private const float FREEZE_DAMAGE_BONUS = 0.30f;       // 冻结期间+30%受伤
    private const float FREEZE_COOLDOWN = 8f;

    // 长按: 时间倒流
    private const float REWIND_ENERGY_COST = 100f;
    private const float REWIND_SECONDS = 4f;
    private const float REWIND_EXPLOSION_MULT = 3.0f;
    private const float REWIND_RADIUS = 6f;
    private const float REWIND_COOLDOWN = 20f;
    private const float LONG_PRESS_THRESHOLD = 1f;

    private float _skillPressTimer;
    private bool _isSkillPressed;
    private bool _isEmpoweredAttack;  // 下一次攻击是否为强化攻击

    public bool IsEmpoweredAttack => _isEmpoweredAttack;

    public override void Initialize(CharacterData data)
    {
        base.Initialize(data);
        // 时间领主闪避改为消耗能量，无次数限制
        // 由PlayerController检查DODGE_ENERGY_COST替代闪避次数
    }

    // ── 被动机制 ──

    /// <summary>
    /// 普攻时自动附加时间伤害(ATK × 1.5)
    /// </summary>
    public float GetTimeAttachDamage()
    {
        float atk = Stats.GetStat(StatType.FATK).Value;
        float tdm = Stats.GetStat(StatType.TDM).Value;
        return atk * TIME_ATTACH_DAMAGE_MULT * tdm;
    }

    /// <summary>
    /// 按住强化键+攻击: 消耗时之能量，完全转化为时间伤害(ATK × 2.5)
    /// </summary>
    public bool TryEmpowerAttack()
    {
        if (TryConsumeTimeEnergy(EMPOWERED_ENERGY_COST))
        {
            _isEmpoweredAttack = true;
            return true;
        }
        return false;
    }

    /// <summary>
    /// 强化攻击伤害计算
    /// </summary>
    public float GetEmpoweredDamage()
    {
        float atk = Stats.GetStat(StatType.FATK).Value;
        float tdm = Stats.GetStat(StatType.TDM).Value;
        _isEmpoweredAttack = false;
        return atk * EMPOWERED_DAMAGE_MULT * tdm;
    }

    /// <summary>
    /// 闪避时产生时间残影
    /// </summary>
    public void OnDodgeCreateAfterimage(Vector2 position)
    {
        if (_afterimages.Count >= MAX_AFTERIMAGES)
        {
            _afterimages[0].Explode(Stats.GetStat(StatType.FATK).Value
                * AFTERIMAGE_EXPLOSION_MULT);
            _afterimages.RemoveAt(0);
        }

        _afterimages.Add(new TimeAfterimage(position, AFTERIMAGE_DURATION));
    }

    public override void UpdateMechanics(float deltaTime)
    {
        base.UpdateMechanics(deltaTime);

        // 更新残影计时
        for (int i = _afterimages.Count - 1; i >= 0; i--)
        {
            _afterimages[i].Timer -= deltaTime;
            if (_afterimages[i].Timer <= 0f)
            {
                _afterimages[i].Explode(Stats.GetStat(StatType.FATK).Value
                    * AFTERIMAGE_EXPLOSION_MULT);
                _afterimages.RemoveAt(i);
            }
        }

        // 长按技能键计时
        if (_isSkillPressed)
        {
            _skillPressTimer += deltaTime;
        }
    }

    // ── 主动: 时间支配 (双模式) ──

    /// <summary>
    /// 按下技能键
    /// </summary>
    public void OnSkillPressStart()
    {
        _isSkillPressed = true;
        _skillPressTimer = 0f;
    }

    /// <summary>
    /// 松开技能键，判断短按/长按
    /// </summary>
    public override bool UseActiveSkill()
    {
        _isSkillPressed = false;

        if (_skillPressTimer < LONG_PRESS_THRESHOLD)
        {
            return UseTimeFreeze();
        }
        else
        {
            return UseTimeRewind();
        }
    }

    private bool UseTimeFreeze()
    {
        if (CurrentTimeEnergy < FREEZE_ENERGY_COST) return false;
        if (ActiveSkillCooldownTimer > 0f) return false;

        TryConsumeTimeEnergy(FREEZE_ENERGY_COST);

        EventBus.Publish(new TimeFreezeEvent
        {
            Radius = FREEZE_RADIUS,
            Duration = FREEZE_DURATION,
            DamageBonus = FREEZE_DAMAGE_BONUS
        });

        ActiveSkillCooldownTimer = FREEZE_COOLDOWN;
        return true;
    }

    private bool UseTimeRewind()
    {
        if (CurrentTimeEnergy < REWIND_ENERGY_COST) return false;
        if (ActiveSkillCooldownTimer > 0f) return false;

        TryConsumeTimeEnergy(REWIND_ENERGY_COST);

        // 状态回溯(由SaveSystem/TimeSystem处理4秒前的状态快照)
        EventBus.Publish(new TimeRewindSkillEvent
        {
            RewindSeconds = REWIND_SECONDS,
            ExplosionDamage = Stats.GetStat(StatType.FATK).Value * REWIND_EXPLOSION_MULT,
            ExplosionRadius = REWIND_RADIUS
        });

        ActiveSkillCooldownTimer = REWIND_COOLDOWN;
        return true;
    }

    public override void OnRoomEnter(string roomId) { }

    // 时间领主闪避: 消耗时之能量
    public bool CanDodgeWithEnergy()
    {
        return CurrentTimeEnergy >= DODGE_ENERGY_COST;
    }

    public void ConsumeDodgeEnergy()
    {
        TryConsumeTimeEnergy(DODGE_ENERGY_COST);
    }
}

/// <summary>时间残影</summary>
public class TimeAfterimage
{
    public Vector2 Position;
    public float Timer;

    public TimeAfterimage(Vector2 position, float duration)
    {
        Position = position;
        Timer = duration;
    }

    public void Explode(float damage)
    {
        EventBus.Publish(new AfterimageExplodeEvent
        {
            Position = Position,
            Damage = damage,
            DamageType = DamageType.Time,
            Radius = 3f
        });
    }
}
```

---

## 2. CharacterStats 属性系统

### 2.1 20项属性定义

```text
/// <summary>
/// 属性类型枚举，20项核心属性
/// 编号对应计算优先级
/// </summary>
public enum StatType
{
    // === 攻击属性(优先级1~3) ===
    BATK = 1,   // 基础攻击力 (Base ATK)
    ATK_PERCENT, // 攻击力加成% (ATK%)
    FATK,        // 最终攻击力 (Final ATK, 计算值)

    // === 防御属性(优先级4~6) ===
    BDEF,        // 基础防御力 (Base DEF)
    DEF_PERCENT, // 防御力加成% (DEF%)
    FDEF,        // 最终防御力 (Final DEF, 计算值)

    // === 生存属性(优先级7~8) ===
    MHP,         // 最大生命值 (Max HP)
    SPD,         // 移动速度 (Speed, 格/秒)

    // === 暴击属性(优先级9~10) ===
    CR,          // 暴击率 (Crit Rate, 0~75%)
    CD,          // 暴击伤害 (Crit Damage, 1.5x~3.5x)

    // === 攻速(优先级11) ===
    AS,          // 攻击速度 (Attack Speed, 1.0x~2.5x)

    // === 时间属性(优先级12~13) ===
    ME,          // 时之能量上限 (Max Energy)
    MER,         // 时之能量回复 (Max Energy Regen, /秒)

    // === 伤害系数(优先级14~15) ===
    TDM,         // 时间伤害系数 (Time Damage Multiplier)
    VDM,         // 虚无伤害系数 (Void Damage Multiplier)

    // === 动作属性(优先级16~17) ===
    IF,          // 闪避无敌帧 (I-frames, 秒)
    PW,          // 格挡判定窗 (Parry Window, 秒)

    // === 减伤属性(优先级18~19) ===
    DR,          // 伤害减免% (Damage Reduction, 0~80%)
    RES,         // 元素抗性 (Resistance, 时间/虚无独立)

    // === 幸运(优先级20) ===
    LCK,         // 幸运值 (Luck, 影响掉落和触发)

    // === 扩展(非核心20项，角色机制用) ===
    ATK_RANGE,   // 攻击范围加成%
}
```

### 2.2 StatModifier 修饰符

```text
/// <summary>
/// 属性修饰符，表示对一个属性的增量修改
/// 支持加法/乘法两种堆叠方式
/// </summary>
public struct StatModifier
{
    public StatType TargetStat;       // 修饰的目标属性
    public float Value;               // 修饰值
    public StatModType ModType;       // 修饰类型: 加法/乘法
    public string Source;             // 来源标识(用于批量移除)
    public int Priority;              // 同类型内的计算优先级(值小先算)

    public StatModifier(StatType targetStat, float value, StatModType modType, string source, int priority = 0)
    {
        TargetStat = targetStat;
        Value = value;
        ModType = modType;
        Source = source;
        Priority = priority;
    }
}

/// <summary>修饰符类型</summary>
public enum StatModType
{
    Additive,       // 加法叠加: 先求和再乘基础值 (如ATK%, DEF%, CR)
    Multiplicative  // 乘法叠加: 各自独立相乘 (如AS, TDM, VDM)
}
```

### 2.3 StatEntry 单属性容器

```text
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// 单个属性的完整计算容器
/// 管理基础值、修饰符列表、软硬上限
/// </summary>
public class StatEntry
{
    public StatType Type { get; }
    public float BaseValue { get; set; }

    // ── 软硬上限 ──
    public bool HasSoftCap { get; set; }
    public float SoftCapValue { get; set; }
    public float SoftCapEfficiency { get; set; }  // 超出部分的效率(0~1)
    public bool HasHardCap { get; set; }
    public float HardCapValue { get; set; }

    // ── 修饰符列表 ──
    private readonly List<StatModifier> _additiveMods = new List<StatModifier>();
    private readonly List<StatModifier> _multiplicativeMods = new List<StatModifier>();
    private bool _isDirty = true;
    private float _cachedValue;

    public StatEntry(StatType type, float baseValue)
    {
        Type = type;
        BaseValue = baseValue;
    }

    /// <summary>最终计算值(带缓存)</summary>
    public float Value
    {
        get
        {
            if (_isDirty)
            {
                _cachedValue = CalculateFinalValue();
                _isDirty = false;
            }
            return _cachedValue;
        }
    }

    /// <summary>添加修饰符</summary>
    public void AddModifier(StatModifier mod)
    {
        if (mod.ModType == StatModType.Additive)
            _additiveMods.Add(mod);
        else
            _multiplicativeMods.Add(mod);

        _isDirty = true;
    }

    /// <summary>移除指定来源的所有修饰符</summary>
    public void RemoveModifiersBySource(string source)
    {
        _additiveMods.RemoveAll(m => m.Source == source);
        _multiplicativeMods.RemoveAll(m => m.Source == source);
        _isDirty = true;
    }

    /// <summary>移除所有修饰符</summary>
    public void ClearAllModifiers()
    {
        _additiveMods.Clear();
        _multiplicativeMods.Clear();
        _isDirty = true;
    }

    /// <summary>
    /// 计算最终值:
    /// 1. 加法修饰符按Priority排序后求和
    /// 2. 乘法修饰符按Priority排序后连乘
    /// 3. 应用软上限
    /// 4. 应用硬上限
    /// </summary>
    private float CalculateFinalValue()
    {
        // Step 1: 加法堆叠求和
        float additiveSum = 0f;
        foreach (var mod in _additiveMods.OrderBy(m => m.Priority))
        {
            additiveSum += mod.Value;
        }

        // Step 2: 基础值 × (1 + 加法总和)
        float result = BaseValue * (1f + additiveSum);

        // Step 3: 乘法堆叠连乘
        foreach (var mod in _multiplicativeMods.OrderBy(m => m.Priority))
        {
            result *= (1f + mod.Value);
        }

        // Step 4: 软上限处理
        if (HasSoftCap)
        {
            // 对于百分比的软上限，需要计算"加成部分"
            float additiveValue = additiveSum;
            if (additiveValue > SoftCapValue)
            {
                float excess = additiveValue - SoftCapValue;
                float effectiveExcess = excess * SoftCapEfficiency;
                float effectiveAdditive = SoftCapValue + effectiveExcess;
                result = BaseValue * (1f + effectiveAdditive);

                // 重新应用乘法
                foreach (var mod in _multiplicativeMods.OrderBy(m => m.Priority))
                {
                    result *= (1f + mod.Value);
                }
            }
        }

        // Step 5: 硬上限
        if (HasHardCap)
        {
            result = math.Min(result, HardCapValue);
        }

        return result;
    }
}
```

### 2.4 CharacterStats 完整实现

```text
using System.Collections.Generic;
using Godot;

/// <summary>
/// 角色属性系统，管理20项核心属性
/// 提供属性查询、修饰符管理、软硬上限配置
/// </summary>
public class CharacterStats
{
    private readonly Dictionary<StatType, StatEntry> _stats = new Dictionary<StatType, StatEntry>();

    public CharacterStats(CharacterData data)
    {
        InitializeBaseStats(data);
        ConfigureCaps();
    }

    /// <summary>初始化基础属性值</summary>
    private void InitializeBaseStats(CharacterData data)
    {
        // 攻击属性
        _stats[StatType.BATK] = new StatEntry(StatType.BATK, data.BaseATK);
        _stats[StatType.ATK_PERCENT] = new StatEntry(StatType.ATK_PERCENT, 0f);
        _stats[StatType.FATK] = new StatEntry(StatType.FATK, data.BaseATK); // 计算值

        // 防御属性
        _stats[StatType.BDEF] = new StatEntry(StatType.BDEF, data.BaseDEF);
        _stats[StatType.DEF_PERCENT] = new StatEntry(StatType.DEF_PERCENT, 0f);
        _stats[StatType.FDEF] = new StatEntry(StatType.FDEF, data.BaseDEF);

        // 生存属性
        _stats[StatType.MHP] = new StatEntry(StatType.MHP, data.BaseHP);
        _stats[StatType.SPD] = new StatEntry(StatType.SPD, data.BaseSPD);

        // 暴击属性
        _stats[StatType.CR] = new StatEntry(StatType.CR, 0.05f);    // 基础5%
        _stats[StatType.CD] = new StatEntry(StatType.CD, 1.5f);     // 基础1.5x

        // 攻速
        _stats[StatType.AS] = new StatEntry(StatType.AS, 1.0f);     // 基础1.0x

        // 时间属性
        _stats[StatType.ME] = new StatEntry(StatType.ME, data.BaseMaxTimeEnergy);
        _stats[StatType.MER] = new StatEntry(StatType.MER, data.BaseTimeEnergyRegen);

        // 伤害系数
        _stats[StatType.TDM] = new StatEntry(StatType.TDM, data.TimeDamageMultiplier);
        _stats[StatType.VDM] = new StatEntry(StatType.VDM, data.VoidDamageMultiplier);

        // 动作属性
        _stats[StatType.IF] = new StatEntry(StatType.IF, data.BaseDodgeIframes);
        _stats[StatType.PW] = new StatEntry(StatType.PW, data.BaseParryWindow);

        // 减伤属性
        _stats[StatType.DR] = new StatEntry(StatType.DR, 0f);
        _stats[StatType.RES] = new StatEntry(StatType.RES, 0f);

        // 幸运
        _stats[StatType.LCK] = new StatEntry(StatType.LCK, 0f);

        // 扩展
        _stats[StatType.ATK_RANGE] = new StatEntry(StatType.ATK_RANGE, 0f);
    }

    /// <summary>配置软硬上限</summary>
    private void ConfigureCaps()
    {
        // ATK%: 软上限+150% (效率50%), 硬上限+300%
        SetSoftCap(StatType.ATK_PERCENT, 1.50f, 0.50f);
        SetHardCap(StatType.ATK_PERCENT, 3.00f);

        // DEF%: 软上限+120% (效率30%), 硬上限+200%
        SetSoftCap(StatType.DEF_PERCENT, 1.20f, 0.30f);
        SetHardCap(StatType.DEF_PERCENT, 2.00f);

        // CR: 软上限50% (效率50%), 硬上限75%
        SetSoftCap(StatType.CR, 0.50f, 0.50f);
        SetHardCap(StatType.CR, 0.75f);

        // CD: 软上限2.5x (效率40%), 硬上限3.5x
        SetSoftCap(StatType.CD, 2.5f, 0.40f);
        SetHardCap(StatType.CD, 3.5f);

        // AS: 软上限1.8x (效率30%), 硬上限2.5x
        SetSoftCap(StatType.AS, 1.8f, 0.30f);
        SetHardCap(StatType.AS, 2.5f);

        // DR: 软上限60% (效率25%), 硬上限80%
        SetSoftCap(StatType.DR, 0.60f, 0.25f);
        SetHardCap(StatType.DR, 0.80f);

        // SPD: 软上限8.0格/秒 (效率40%), 硬上限10.0格/秒
        SetSoftCap(StatType.SPD, 8.0f, 0.40f);
        SetHardCap(StatType.SPD, 10.0f);

        // MER: 软上限20/秒 (效率30%), 硬上限30/秒
        SetSoftCap(StatType.MER, 20f, 0.30f);
        SetHardCap(StatType.MER, 30f);
    }

    // ── 公开API ──

    /// <summary>获取属性条目</summary>
    public StatEntry GetStat(StatType type)
    {
        return _stats.TryGetValue(type, out var entry) ? entry : null;
    }

    /// <summary>添加修饰符</summary>
    public void AddModifier(StatModifier mod)
    {
        if (_stats.TryGetValue(mod.TargetStat, out var entry))
        {
            entry.AddModifier(mod);
        }
    }

    /// <summary>移除指定来源的所有修饰符</summary>
    public void RemoveModifiersBySource(string source)
    {
        foreach (var entry in _stats.Values)
        {
            entry.RemoveModifiersBySource(source);
        }
    }

    /// <summary>设置属性基础值</summary>
    public void SetBaseValue(StatType type, float value)
    {
        if (_stats.TryGetValue(type, out var entry))
        {
            entry.BaseValue = value;
        }
    }

    /// <summary>设置软上限</summary>
    public void SetSoftCap(StatType type, float softCapValue, float efficiency)
    {
        if (_stats.TryGetValue(type, out var entry))
        {
            entry.HasSoftCap = true;
            entry.SoftCapValue = softCapValue;
            entry.SoftCapEfficiency = efficiency;
        }
    }

    /// <summary>设置硬上限</summary>
    public void SetHardCap(StatType type, float hardCapValue)
    {
        if (_stats.TryGetValue(type, out var entry))
        {
            entry.HasHardCap = true;
            entry.HardCapValue = hardCapValue;
        }
    }

    /// <summary>
    /// 计算最终攻击力(FATK)
    /// FATK = BATK × (1 + ATK%有效值)
    /// </summary>
    public float CalculateFATK()
    {
        float batk = _stats[StatType.BATK].Value;
        float atkPercent = _stats[StatType.ATK_PERCENT].Value;
        float fatk = batk * (1f + atkPercent);
        _stats[StatType.FATK].BaseValue = fatk;
        return fatk;
    }

    /// <summary>
    /// 计算最终防御力(FDEF)
    /// FDEF = BDEF × (1 + DEF%有效值)
    /// </summary>
    public float CalculateFDEF()
    {
        float bdef = _stats[StatType.BDEF].Value;
        float defPercent = _stats[StatType.DEF_PERCENT].Value;
        float fdef = bdef * (1f + defPercent);
        _stats[StatType.FDEF].BaseValue = fdef;
        return fdef;
    }

    /// <summary>
    /// 计算防御减伤率
    /// DR_def = FDEF / (FDEF + K), K = 50 + attackerLevel × 5
    /// </summary>
    public float CalculateDefenseReduction(int attackerLevel)
    {
        float fdef = CalculateFDEF();
        float k = 50f + attackerLevel * 5f;
        return fdef / (fdef + k);
    }

    /// <summary>
    /// 清除所有修饰符(新Run开始时)
    /// </summary>
    public void ClearAllModifiers()
    {
        foreach (var entry in _stats.Values)
        {
            entry.ClearAllModifiers();
        }
    }
}
```

---

## 3. 五个角色专属机制实现要点

### 3.1 机制总览表

| 角色 | 被动机制 | 主动技能 | 核心资源 | 实现难点 |
|------|---------|---------|---------|---------|
| 行者 | 旅途印记(房间切换叠层) | 时间回溯(锚点+回溯) | 印记层数 | 锚点状态快照/回溯位置同步 |
| 时之守卫 | 时间壁垒(格挡→充能→增伤) | 时之堡垒(定点输出) | 壁垒充能 | 格挡判定窗口精确计时 |
| 虚空行者 | 虚无共鸣(低HP增伤+侵蚀) | 虚空吞噬(自伤→伤害→回复) | HP百分比 | 临界状态的特殊死亡处理 |
| 原界骑士 | 位面共振(双武器蓄能) | 裂界斩(双武器+共振爆发) | 共振层数 | 双武器ATK分别计算 |
| 时间领主 | 时间法典(附伤+残影+能量闪避) | 时间支配(冻结/倒流双模式) | 时之能量 | 能量管理的全局资源竞争 |

### 3.2 关键实现要点

**行者 — 时间回溯状态快照**

```text
/// <summary>
/// 行者时间回溯所需的状态快照
/// 每帧记录，最多保存8秒历史(480帧@60fps)
/// </summary>
public class TimeAnchorSnapshot
{
    public Vector2 Position;
    public float HP;
    public float TimeEnergy;
    public List<ActiveBuffSnapshot> ActiveBuffs;

    public TimeAnchorSnapshot(Vector2 pos, float hp, float energy, List<ActiveBuffSnapshot> buffs)
    {
        Position = pos;
        HP = hp;
        TimeEnergy = energy;
        ActiveBuffs = buffs;
    }
}

// PlayerController中循环缓冲区实现
private readonly CircularBuffer<TimeAnchorSnapshot> _snapshotBuffer = 
    new CircularBuffer<TimeAnchorSnapshot>(480);

void Update()
{
    // 每帧记录快照
    _snapshotBuffer.PushFront(new TimeAnchorSnapshot(
        transform.position, CurrentHP, CurrentTimeEnergy, GetActiveBuffSnapshots()
    ));
}
```

**时之守卫 — 格挡判定窗口**

```text
/// <summary>
/// 格挡判定由PlayerController的输入时序驱动
/// 格挡键按下时记录时间戳，敌人伤害到达时计算时间差
/// </summary>
private float _parryPressTimestamp;
private const float PERFECT_PARRY_WINDOW = 0.15f;   // 完美格挡窗口
private const float NORMAL_PARRY_WINDOW = 0.40f;     // 普通格挡窗口

public void OnParryPressed()
{
    _parryPressTimestamp = runtime_time;
    // 播放格挡动画(护手举起)
}

// 在DamageCalculator判定伤害时调用
public float GetParryDamageReduction(float attackArrivalTime)
{
    float timeSinceParry = attackArrivalTime - _parryPressTimestamp;
    
    if (timeSinceParry <= PERFECT_PARRY_WINDOW)
    {
        _character.OnParrySuccess(isPerfect: true);
        return 1.0f; // 100%减伤
    }
    else if (timeSinceParry <= NORMAL_PARRY_WINDOW)
    {
        _character.OnParrySuccess(isPerfect: false);
        return 0.5f; // 50%减伤
    }
    
    return 0f; // 不减伤
}
```

**虚空行者 — 虚空临界状态机**

```text
/// <summary>
/// 虚空行者的特殊死亡状态机
/// HP=0 → 虚空临界(5秒) → 回复则生 / 超时则死
/// </summary>
public enum VoidWalkerState
{
    Normal,         // 正常状态
    Erosion,        // 虚空侵蚀(HP<30%, 持续掉血)
    Critical,       // 虚空临界(HP=0, 5秒倒计时)
    Dead            // 真正死亡
}

// 在VoidWalker.UpdateMechanics中:
// 1. Normal → Erosion: HP百分比 < 30%
// 2. Erosion → Critical: HP降至0
// 3. Critical → Normal: 回复至1HP以上
// 4. Critical → Dead: 5秒倒计时结束
// 关键: TakeDamage不应在Critical状态直接触发OnDeath
```

**原界骑士 — 双武器ATK独立计算**

```text
/// <summary>
/// 原界骑士同时持有主副两把武器
/// 武器ATK独立计算，裂界斩使用双武器ATK之和
/// </summary>
public class DualWeaponManager
{
    private WeaponInstance _mainWeapon;
    private WeaponInstance _subWeapon;
    private bool _isMainActive = true;

    public WeaponInstance ActiveWeapon => _isMainActive ? _mainWeapon : _subWeapon;
    public WeaponInstance InactiveWeapon => _isMainActive ? _subWeapon : _mainWeapon;

    public float GetMainATK() => _mainWeapon?.GetFinalATK() ?? 0f;
    public float GetSubATK() => _subWeapon?.GetFinalATK() ?? 0f;

    public void Switch()
    {
        _isMainActive = !_isMainActive;
        // 0.2秒切换动画
    }
}
```

**时间领主 — 能量全局竞争管理**

```text
/// <summary>
/// 时间领主所有行为都消耗时之能量，需要统一能量管理
/// 闪避: 15点/次
/// 强化攻击: 10点/次
/// 时间冻结: 60点
/// 时间倒流: 100点
/// 
/// 能量回复8/秒(基础), 需要在进攻/防御/技能间做策略分配
/// </summary>
// 在TimeLord中，重写闪避逻辑
public override bool CanDodgeWithEnergy() => CurrentTimeEnergy >= 15f;
public override void OnDodgeCreateAfterimage(Vector2 pos) { /* 见1.4.5 */ }

// PlayerController中时间领主分支:
// if (character is TimeLord tl)
// {
//     if (!tl.CanDodgeWithEnergy()) return; // 能量不足无法闪避
//     tl.ConsumeDodgeEnergy();
//     tl.OnDodgeCreateAfterimage(transform.position);
// }
```

---

## 4. MetaProgression 解锁树

### 4.1 解锁树结构

```
Meta解锁树(5分支, 42节点)
├── W-行者之路 (10节点, 148碎片) — 生存与基础
│   W-01: HP+10%        W-02: HP+10%       W-03: HP+10%
│   W-04: DEF+8%        W-05: DEF+8%       W-06: 复活1次/局
│   W-07: 魂保留50%     W-08: 魂保留70%    W-09: 新手金+20%
│   W-10: 死亡保障碎片+3
│
├── C-确信之术 (8节点, 150碎片) — 战斗强化
│   C-01: ATK+5%        C-02: ATK+5%       C-03: CR+3%
│   C-04: CR+3%         C-05: CD+0.2x      C-06: 击杀回复2HP
│   C-07: 完美格挡窗+0.03s  C-08: 完美装弹窗+0.05s
│
├── L-碎片知识 (10节点, 155碎片) — 信息与探索
│   L-01: 图鉴20%       L-02: 图鉴40%      L-03: 图鉴60%
│   L-04: 时间裂隙房+15%  L-05: 隐藏房+10% L-06: 商店折扣10%
│   L-07: 商店折扣15%   L-08: 道具预览      L-09: 道具重选1次
│   L-10: 全知之眼(需5存在印记)
│
├── F-位面熔铸 (8节点, 122碎片) — 锻造与强化
│   F-01: 解锁强化台     F-02: 解锁附魔位1  F-03: 解锁附魔位2
│   F-04: 解锁虚空淬炼   F-05: 强化不降级   F-06: 强化成功率+5%
│   F-07: 附魔折扣10%   F-08: 存在确认药水配方
│
└── P-存在之约 (6节点, 103碎片) — 叙事与收集
    P-01: NPC对话+1       P-02: NPC好感+15%  P-03: 消逝者对话HP消耗-2
    P-04: 虚无歌者深层对话 P-05: 隐藏剧情线提示 P-06: 存在印记获取+1/局
```

### 4.2 UnlockTree 实现

```text
using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Meta解锁树，管理局外永久进度的节点依赖与解锁逻辑
/// </summary>
public class UnlockTree
{
    private readonly Dictionary<string, UnlockNode> _nodes = new Dictionary<string, UnlockNode>();
    private readonly HashSet<string> _unlockedNodeIds = new HashSet<string>();

    public IReadOnlyList<UnlockNode> AllNodes => _nodes.Values.ToList();
    public IReadOnlyCollection<string> UnlockedNodeIds => _unlockedNodeIds;

    // ── 事件 ──
    public event Action<string> OnNodeUnlocked;  // nodeId

    // ── 初始化 ──

    /// <summary>
    /// 注册一个解锁节点
    /// </summary>
    public void RegisterNode(UnlockNode node)
    {
        _nodes[node.Id] = node;
    }

    /// <summary>
    /// 批量注册节点
    /// </summary>
    public void RegisterNodes(IEnumerable<UnlockNode> nodes)
    {
        foreach (var node in nodes)
            _nodes[node.Id] = node;
    }

    /// <summary>
    /// 从存档恢复已解锁节点
    /// </summary>
    public void RestoreUnlocked(IEnumerable<string> unlockedIds)
    {
        _unlockedNodeIds.Clear();
        foreach (var id in unlockedIds)
        {
            if (_nodes.ContainsKey(id))
                _unlockedNodeIds.Add(id);
        }
    }

    // ── 解锁逻辑 ──

    /// <summary>
    /// 尝试解锁指定节点
    /// </summary>
    /// <param name="nodeId">节点ID</param>
    /// <param name="currencyManager">货币管理器(扣除碎片)</param>
    /// <returns>解锁结果</returns>
    public UnlockResult TryUnlock(string nodeId, CurrencyManager currencyManager)
    {
        if (!_nodes.TryGetValue(nodeId, out var node))
            return UnlockResult.Fail("节点不存在");

        if (_unlockedNodeIds.Contains(nodeId))
            return UnlockResult.Fail("节点已解锁");

        if (!CheckPrerequisites(node))
            return UnlockResult.Fail("前置节点未解锁");

        if (node.RequiredExistentialImprint > 0
            && currencyManager.ExistentialImprint < node.RequiredExistentialImprint)
            return UnlockResult.Fail("存在印记不足");

        if (currencyManager.ChronosShards < node.Cost)
            return UnlockResult.Fail("时之碎片不足");

        // 扣除货币
        currencyManager.SpendChronosShards(node.Cost);
        if (node.RequiredExistentialImprint > 0)
            currencyManager.SpendExistentialImprint(node.RequiredExistentialImprint);

        // 解锁
        _unlockedNodeIds.Add(nodeId);
        OnNodeUnlocked?.Invoke(nodeId);

        EventBus.Publish(new MetaUnlockEvent { NodeId = nodeId });
        return UnlockResult.Success();
    }

    /// <summary>
    /// 检查前置节点依赖
    /// </summary>
    public bool CheckPrerequisites(UnlockNode node)
    {
        if (node.PrerequisiteIds == null || node.PrerequisiteIds.Length == 0)
            return true;

        return node.PrerequisiteIds.All(preId => _unlockedNodeIds.Contains(preId));
    }

    /// <summary>
    /// 判断节点是否已解锁
    /// </summary>
    public bool IsUnlocked(string nodeId) => _unlockedNodeIds.Contains(nodeId);

    /// <summary>
    /// 判断节点是否可解锁(前置满足 + 未解锁)
    /// </summary>
    public bool CanUnlock(string nodeId)
    {
        if (!_nodes.TryGetValue(nodeId, out var node)) return false;
        return !_unlockedNodeIds.Contains(nodeId) && CheckPrerequisites(node);
    }

    /// <summary>
    /// 获取指定分支的解锁进度
    /// </summary>
    public float GetBranchProgress(string branchPrefix)
    {
        var branchNodes = _nodes.Values.Where(n => n.Id.StartsWith(branchPrefix)).ToList();
        if (branchNodes.Count == 0) return 0f;
        int unlocked = branchNodes.Count(n => _unlockedNodeIds.Contains(n.Id));
        return (float)unlocked / branchNodes.Count;
    }

    /// <summary>
    /// 获取全树解锁进度(0~1)
    /// </summary>
    public float GetTotalProgress()
    {
        if (_nodes.Count == 0) return 0f;
        return (float)_unlockedNodeIds.Count / _nodes.Count;
    }
}

/// <summary>解锁结果</summary>
public struct UnlockResult
{
    public bool Success;
    public string FailReason;

    public static UnlockResult Success() => new UnlockResult { Success = true };
    public static UnlockResult Fail(string reason) => new UnlockResult { Success = false, FailReason = reason };
}

/// <summary>解锁节点数据</summary>
public class UnlockNode
{
    public string Id;                           // 节点ID: "W-01", "C-03" 等
    public string DisplayName;                  // 显示名称
    public string Description;                  // 效果描述
    public string Branch;                       // 所属分支: "W", "C", "L", "F", "P"
    public int Cost;                            // 时之碎片消耗
    public string[] PrerequisiteIds;            // 前置节点ID列表
    public int RequiredExistentialImprint;      // 额外需要的存在印记(0=不需要)
    public string EffectId;                     // 解锁后激活的效果ID

    public UnlockNode(string id, string displayName, string description,
        string branch, int cost, string[] prerequisites = null,
        int existentialImprint = 0, string effectId = null)
    {
        Id = id;
        DisplayName = displayName;
        Description = description;
        Branch = branch;
        Cost = cost;
        PrerequisiteIds = prerequisites ?? Array.Empty<string>();
        RequiredExistentialImprint = existentialImprint;
        EffectId = effectId;
    }
}
```

---

## 5. CurrencyManager 货币系统

### 5.1 四货币体系

```text
using System;
using Godot;

/// <summary>
/// 四货币管理器: Gold(金币), Soul(魂), ChronosShard(时之碎片), ExistentialImprint(存在印记)
/// Gold/Soul为局内临时货币, ChronosShard/ExistentialImprint为局外永久货币
/// </summary>
public class CurrencyManager
{
    // ── 货币余额 ──
    public int Gold { get; private set; }
    public int Soul { get; private set; }
    public int ChronosShards { get; private set; }
    public int ExistentialImprint { get; private set; }

    // ── 配置 ──
    private float _soulRetainRatio = 0.30f;  // 魂死亡保留基础比例

    // ── 事件 ──
    public event Action<CurrencyType, int, int> OnCurrencyChanged; // (type, oldValue, newValue)

    // ── 局内货币: 金币 ──

    /// <summary>获取金币</summary>
    public void AddGold(int amount)
    {
        if (amount <= 0) return;
        int old = Gold;
        Gold += amount;
        OnCurrencyChanged?.Invoke(CurrencyType.Gold, old, Gold);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.Gold, OldValue = old, NewValue = Gold
        });
    }

    /// <summary>消费金币</summary>
    /// <returns>是否消费成功</returns>
    public bool SpendGold(int amount)
    {
        if (amount <= 0 || Gold < amount) return false;
        int old = Gold;
        Gold -= amount;
        OnCurrencyChanged?.Invoke(CurrencyType.Gold, old, Gold);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.Gold, OldValue = old, NewValue = Gold
        });
        return true;
    }

    // ── 局内货币: 魂 ──

    /// <summary>获取魂</summary>
    public void AddSoul(int amount)
    {
        if (amount <= 0) return;
        int old = Soul;
        Soul += amount;
        OnCurrencyChanged?.Invoke(CurrencyType.Soul, old, Soul);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.Soul, OldValue = old, NewValue = Soul
        });
    }

    /// <summary>消费魂(魂之祭坛升级)</summary>
    public bool SpendSoul(int amount)
    {
        if (amount <= 0 || Soul < amount) return false;
        int old = Soul;
        Soul -= amount;
        OnCurrencyChanged?.Invoke(CurrencyType.Soul, old, Soul);
        return true;
    }

    // ── 局外永久货币: 时之碎片 ──

    /// <summary>获取时之碎片</summary>
    public void AddChronosShards(int amount)
    {
        if (amount <= 0) return;
        int old = ChronosShards;
        ChronosShards += amount;
        OnCurrencyChanged?.Invoke(CurrencyType.ChronosShard, old, ChronosShards);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.ChronosShard, OldValue = old, NewValue = ChronosShards
        });
    }

    /// <summary>消费时之碎片</summary>
    public bool SpendChronosShards(int amount)
    {
        if (amount <= 0 || ChronosShards < amount) return false;
        int old = ChronosShards;
        ChronosShards -= amount;
        OnCurrencyChanged?.Invoke(CurrencyType.ChronosShard, old, ChronosShards);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.ChronosShard, OldValue = old, NewValue = ChronosShards
        });
        return true;
    }

    // ── 局外稀有货币: 存在印记 ──

    /// <summary>获取存在印记</summary>
    public void AddExistentialImprint(int amount)
    {
        if (amount <= 0) return;
        int old = ExistentialImprint;
        ExistentialImprint += amount;
        OnCurrencyChanged?.Invoke(CurrencyType.ExistentialImprint, old, ExistentialImprint);
        EventBus.Publish(new CurrencyChangedEvent
        {
            Type = CurrencyType.ExistentialImprint, OldValue = old, NewValue = ExistentialImprint
        });
    }

    /// <summary>消费存在印记</summary>
    public bool SpendExistentialImprint(int amount)
    {
        if (amount <= 0 || ExistentialImprint < amount) return false;
        int old = ExistentialImprint;
        ExistentialImprint -= amount;
        OnCurrencyChanged?.Invoke(CurrencyType.ExistentialImprint, old, ExistentialImprint);
        return true;
    }

    // ── 死亡结算 ──

    /// <summary>
    /// 死亡结算: 金币清零, 魂按保留比例保留, 碎片/印记全保留
    /// </summary>
    /// <param name="metaRetainBonus">Meta节点额外保留加成(如W-07/W-08)</param>
    /// <param name="difficultyBonus">难度额外保留加成</param>
    public void ProcessDeath(float metaRetainBonus = 0f, float difficultyBonus = 0f)
    {
        // 金币清零
        int oldGold = Gold;
        Gold = 0;
        OnCurrencyChanged?.Invoke(CurrencyType.Gold, oldGold, 0);

        // 魂按比例保留
        float totalRetainRatio = math.Min(0.90f, _soulRetainRatio + metaRetainBonus + difficultyBonus);
        int retainedSoul = math.FloorToInt(Soul * totalRetainRatio);
        int oldSoul = Soul;
        Soul = retainedSoul;
        OnCurrencyChanged?.Invoke(CurrencyType.Soul, oldSoul, Soul);

        // 碎片和印记全保留(无需处理)
    }

    /// <summary>
    /// 通关结算: 金币清零, 魂按比例保留, 碎片/印记全保留
    /// </summary>
    public void ProcessRunEnd(float metaRetainBonus = 0f, float difficultyBonus = 0f)
    {
        ProcessDeath(metaRetainBonus, difficultyBonus);
    }

    /// <summary>
    /// 设置魂保留基础比例(由新手保护修改)
    /// </summary>
    public void SetSoulRetainRatio(float ratio)
    {
        _soulRetainRatio = ratio;
    }

    // ── 存在印记兑换 ──

    /// <summary>
    /// 将存在印记兑换为时之碎片(1:3，不可逆)
    /// </summary>
    public bool ExchangeImprintToShards(int imprintAmount)
    {
        if (!SpendExistentialImprint(imprintAmount)) return false;
        AddChronosShards(imprintAmount * 3);
        return true;
    }

    // ── 新Run初始化 ──

    /// <summary>
    /// 新Run开始: 魂从保留值开始, 金币从0开始
    /// </summary>
    public void StartNewRun()
    {
        int oldGold = Gold;
        Gold = 0;
        OnCurrencyChanged?.Invoke(CurrencyType.Gold, oldGold, 0);
    }
}

/// <summary>货币类型枚举</summary>
public enum CurrencyType
{
    Gold,
    Soul,
    ChronosShard,
    ExistentialImprint
}
```

---

## 6. ForgeSystem 锻造系统

### 6.1 五级强化系统

```text
using System;
using Godot;

/// <summary>
/// 锻造系统: 基础强化(+1~+5) + 附魔(15种) + 虚空淬炼
/// 永久强化，消耗时之碎片
/// </summary>
public class ForgeSystem
{
    // ── 强化成功率表 ──
    private static readonly float[] BASE_SUCCESS_RATES = { 1.0f, 0.90f, 0.75f, 0.55f, 0.35f };

    // ── 强化碎片消耗表 ──
    private static readonly int[] SHARD_COSTS = { 5, 10, 20, 35, 50 };

    // ── 强化ATK加成表 ──
    private static readonly float[] ATK_BONUSES = { 0.05f, 0.10f, 0.15f, 0.22f, 0.30f };

    // ── 失败碎片返还表(按目标等级索引) ──
    private static readonly int[] FAILURE_SHARD_REFUNDS = { 0, 0, 5, 10, 15 };

    // ── 连续失败保护 ──
    private const int CONSECUTIVE_FAIL_THRESHOLD = 2;
    private const float CONSECUTIVE_FAIL_BONUS = 0.15f;

    private readonly CurrencyManager _currencyManager;
    private readonly UnlockTree _unlockTree;

    // 每武器连续失败计数
    private readonly Dictionary<WeaponType, int> _consecutiveFailures = new Dictionary<WeaponType, int>();

    public ForgeSystem(CurrencyManager currencyManager, UnlockTree unlockTree)
    {
        _currencyManager = currencyManager;
        _unlockTree = unlockTree;
    }

    // ── 基础强化 ──

    /// <summary>
    /// 尝试强化武器
    /// </summary>
    /// <param name="weapon">武器强化数据</param>
    /// <returns>强化结果</returns>
    public ForgeResult TryEnhance(WeaponEnhancement weapon)
    {
        int currentLevel = weapon.EnhanceLevel;

        // 前置条件检查
        if (currentLevel >= 5)
            return ForgeResult.Fail("已达最大强化等级");

        if (currentLevel >= 3 && !_unlockTree.IsUnlocked("F-01"))
            return ForgeResult.Fail("未解锁强化台");

        if (currentLevel >= 4 && !_unlockTree.IsUnlocked("F-05"))
            return ForgeResult.Fail("未解锁高等级强化");

        // 碎片消耗检查
        int cost = SHARD_COSTS[currentLevel];
        if (_currencyManager.ChronosShards < cost)
            return ForgeResult.Fail("时之碎片不足");

        // 扣除碎片
        _currencyManager.SpendChronosShards(cost);

        // 计算成功率
        float successRate = CalculateSuccessRate(currentLevel);

        // 判定成功/失败
        bool success = Godot.Random.value <= successRate;

        if (success)
        {
            weapon.EnhanceLevel = currentLevel + 1;
            weapon.ATKBonusPercent = ATK_BONUSES[weapon.EnhanceLevel - 1];

            // 应用武器特定副效果
            ApplyWeaponBonusEffect(weapon);

            // 清零连续失败
            _consecutiveFailures[weapon.WeaponType] = 0;

            return ForgeResult.Success(
                newLevel: weapon.EnhanceLevel,
                atkBonus: weapon.ATKBonusPercent,
                shardCost: cost
            );
        }
        else
        {
            // 失败处理
            int refund = FAILURE_SHARD_REFUNDS[currentLevel];
            if (refund > 0)
                _currencyManager.AddChronosShards(refund);

            // 降级判定
            bool degraded = false;
            if (currentLevel >= 3 && !_unlockTree.IsUnlocked("F-05"))
            {
                weapon.EnhanceLevel = currentLevel - 1;
                weapon.ATKBonusPercent = currentLevel > 1 ? ATK_BONUSES[weapon.EnhanceLevel - 1] : 0f;
                degraded = true;
            }
            // Meta F-05后: 不降级，碎片仍消耗

            // 累计连续失败
            if (!_consecutiveFailures.ContainsKey(weapon.WeaponType))
                _consecutiveFailures[weapon.WeaponType] = 0;
            _consecutiveFailures[weapon.WeaponType]++;

            return ForgeResult.Failure(
                currentLevel: weapon.EnhanceLevel,
                degraded: degraded,
                shardRefund: refund,
                consecutiveFailures: _consecutiveFailures[weapon.WeaponType]
            );
        }
    }

    /// <summary>
    /// 计算实际成功率(含连续失败保护)
    /// </summary>
    private float CalculateSuccessRate(int currentLevel)
    {
        float rate = BASE_SUCCESS_RATES[currentLevel];

        // 连续失败保护
        WeaponType wt = WeaponType.Sword; // 由调用方传入
        if (_consecutiveFailures.TryGetValue(wt, out int fails) && fails >= CONSECUTIVE_FAIL_THRESHOLD)
        {
            rate = math.Min(1.0f, rate + CONSECUTIVE_FAIL_BONUS);
        }

        // Meta F-06: 强化成功率+5%
        if (_unlockTree.IsUnlocked("F-06"))
        {
            rate = math.Min(1.0f, rate + 0.05f);
        }

        return rate;
    }

    /// <summary>
    /// 应用武器特定副效果
    /// </summary>
    private void ApplyWeaponBonusEffect(WeaponEnhancement weapon)
    {
        switch (weapon.WeaponType)
        {
            case WeaponType.Sword:
                weapon.BonusDEF = weapon.EnhanceLevel * 0.01f;  // 每级+1%DEF
                break;
            case WeaponType.Bow:
                weapon.BonusCR = weapon.EnhanceLevel * 0.02f;  // 每级+2%CR
                break;
            case WeaponType.Gun:
                if (weapon.EnhanceLevel >= 3)
                    weapon.BonusRange = (weapon.EnhanceLevel - 2) * 0.03f; // +3起+3%攻击距离/级
                break;
            case WeaponType.Staff:
                weapon.BonusMaxEnergy = weapon.EnhanceLevel * 2; // 每级+2时之能量上限
                break;
            case WeaponType.Fist:
                if (weapon.EnhanceLevel >= 3)
                    weapon.BonusAS = (weapon.EnhanceLevel - 2) * 0.02f; // +3起+2%攻速/级
                break;
        }
    }

    // ── 附魔系统 ──

    /// <summary>
    /// 为武器添加附魔
    /// </summary>
    /// <param name="weapon">武器强化数据</param>
    /// <param name="enchantId">附魔ID: EN-01~EN-15</param>
    /// <param name="slotIndex">附魔位索引: 0或1</param>
    /// <returns>附魔结果</returns>
    public EnchantResult ApplyEnchant(WeaponEnhancement weapon, string enchantId, int slotIndex)
    {
        // 前置条件
        if (slotIndex == 0 && !_unlockTree.IsUnlocked("F-02"))
            return EnchantResult.Fail("附魔位1未解锁");
        if (slotIndex == 1 && !_unlockTree.IsUnlocked("F-03"))
            return EnchantResult.Fail("附魔位2未解锁");

        // 元素互斥检查
        if (!CheckEnchantCompatibility(weapon, enchantId, slotIndex))
            return EnchantResult.Fail("附魔互斥，不可共存");

        // 获取附魔数据
        EnchantData enchant = EnchantRegistry.Get(enchantId);
        if (enchant == null)
            return EnchantResult.Fail("附魔不存在");

        // 碎片消耗
        if (_currencyManager.ChronosShards < enchant.Cost)
            return EnchantResult.Fail("时之碎片不足");
        _currencyManager.SpendChronosShards(enchant.Cost);

        // 应用附魔
        if (weapon.Enchants[slotIndex] != null && weapon.Enchants[slotIndex].EnchantId != "")
        {
            // 已有附魔，先移除(不返还消耗)
            weapon.Enchants[slotIndex] = new EnchantSlot { EnchantId = "", Locked = false };
        }

        weapon.Enchants[slotIndex] = new EnchantSlot
        {
            EnchantId = enchantId,
            Locked = false
        };

        return EnchantResult.Success(enchantId, slotIndex);
    }

    /// <summary>
    /// 移除附魔(消耗5碎片)
    /// </summary>
    public bool RemoveEnchant(WeaponEnhancement weapon, int slotIndex)
    {
        if (weapon.Enchants[slotIndex] == null) return false;
        if (_currencyManager.ChronosShards < 5) return false;

        _currencyManager.SpendChronosShards(5);
        weapon.Enchants[slotIndex] = new EnchantSlot { EnchantId = "", Locked = false };
        return true;
    }

    /// <summary>
    /// 检查附魔兼容性(元素互斥规则)
    /// EN-01/02/03三选一, EN-04/05二选一
    /// </summary>
    private bool CheckEnchantCompatibility(WeaponEnhancement weapon, string newEnchantId, int targetSlot)
    {
        int otherSlot = 1 - targetSlot;
        if (weapon.Enchants[otherSlot] == null) return true;

        string existingId = weapon.Enchants[otherSlot].EnchantId;
        if (string.IsNullOrEmpty(existingId)) return true;

        // 火焰/冰霜/雷电互斥
        string[] elementGroup1 = { "EN-01", "EN-02", "EN-03" };
        if (Array.IndexOf(elementGroup1, newEnchantId) >= 0
            && Array.IndexOf(elementGroup1, existingId) >= 0)
            return false;

        // 时间/虚无互斥
        string[] elementGroup2 = { "EN-04", "EN-05" };
        if (Array.IndexOf(elementGroup2, newEnchantId) >= 0
            && Array.IndexOf(elementGroup2, existingId) >= 0)
            return false;

        return true;
    }

    // ── 虚空淬炼 ──

    /// <summary>
    /// 虚空淬炼(前置: 装备+3以上, Meta F-04)
    /// </summary>
    /// <param name="weapon">武器强化数据</param>
    /// <param name="useImprintGuarantee">是否使用存在印记保底(3个)</param>
    /// <returns>淬炼结果</returns>
    public VoidQuenchResult TryVoidQuench(WeaponEnhancement weapon, bool useImprintGuarantee = false)
    {
        // 前置检查
        if (!_unlockTree.IsUnlocked("F-04"))
            return VoidQuenchResult.Fail("未解锁虚空淬炼");

        if (weapon.EnhanceLevel < 3)
            return VoidQuenchResult.Fail("装备需+3以上");

        if (weapon.VoidAwakened)
            return VoidQuenchResult.Fail("已虚空觉醒，不可重复淬炼");

        // 消耗检查
        if (useImprintGuarantee)
        {
            if (_currencyManager.ExistentialImprint < 3)
                return VoidQuenchResult.Fail("存在印记不足(需3个)");
            _currencyManager.SpendExistentialImprint(3);
        }
        else
        {
            if (_currencyManager.ChronosShards < 30)
                return VoidQuenchResult.Fail("时之碎片不足(需30)");
            _currencyManager.SpendChronosShards(30);
        }

        // 判定结果
        float awakenChance = _unlockTree.IsUnlocked("F-05") ? 0.75f : 0.70f;
        float shatterChance = _unlockTree.IsUnlocked("F-05") ? 0f : 0.05f;
        float noChangeChance = 0.25f;

        if (useImprintGuarantee)
        {
            awakenChance = 1.0f;
            shatterChance = 0f;
            noChangeChance = 0f;
        }

        float roll = Godot.Random.value;

        if (roll < shatterChance)
        {
            // 装备碎裂
            return VoidQuenchResult.Shattered();
        }
        else if (roll < shatterChance + noChangeChance)
        {
            // 无变化
            return VoidQuenchResult.NoChange();
        }
        else
        {
            // 虚空觉醒
            weapon.VoidAwakened = true;
            return VoidQuenchResult.Awakened();
        }
    }
}

// ── 数据结构 ──

/// <summary>武器强化数据</summary>
public class WeaponEnhancement
{
    public WeaponType WeaponType;
    public int EnhanceLevel;               // 0~5
    public float ATKBonusPercent;           // ATK加成%
    public EnchantSlot[] Enchants = new EnchantSlot[2];
    public bool VoidAwakened;
    public int ProficiencyLevel;           // 熟练度等级 0~10
    public int ProficiencyExp;             // 熟练度经验

    // 武器特定副效果
    public float BonusDEF;
    public float BonusCR;
    public float BonusRange;
    public int BonusMaxEnergy;
    public float BonusAS;
}

/// <summary>附魔位</summary>
[System.Serializable]
public struct EnchantSlot
{
    public string EnchantId;    // EN-01~EN-15 或 ""
    public bool Locked;         // 锁定防误操作
}

/// <summary>附魔数据(SO配置)</summary>
public class EnchantData
{
    public string Id;
    public string DisplayName;
    public EnchantRarity Rarity;
    public int Cost;            // 碎片消耗
    public string EffectDescription;
}

public enum EnchantRarity { Normal, Rare, Epic, Legendary }

/// <summary>强化结果</summary>
public struct ForgeResult
{
    public bool IsSuccess;
    public string FailReason;
    public int NewLevel;
    public float ATKBonus;
    public int ShardCost;
    public bool Degraded;
    public int ShardRefund;
    public int ConsecutiveFailures;

    public static ForgeResult Success(int newLevel, float atkBonus, int shardCost)
        => new ForgeResult { IsSuccess = true, NewLevel = newLevel, ATKBonus = atkBonus, ShardCost = shardCost };

    public static ForgeResult Fail(string reason) => new ForgeResult { FailReason = reason };

    public static ForgeResult Failure(int currentLevel, bool degraded, int shardRefund, int consecutiveFailures)
        => new ForgeResult
        {
            IsSuccess = false, NewLevel = currentLevel, Degraded = degraded,
            ShardRefund = shardRefund, ConsecutiveFailures = consecutiveFailures
        };
}

/// <summary>附魔结果</summary>
public struct EnchantResult
{
    public bool IsSuccess;
    public string FailReason;
    public string EnchantId;
    public int SlotIndex;

    public static EnchantResult Success(string id, int slot) => new EnchantResult { IsSuccess = true, EnchantId = id, SlotIndex = slot };
    public static EnchantResult Fail(string reason) => new EnchantResult { FailReason = reason };
}

/// <summary>虚空淬炼结果</summary>
public struct VoidQuenchResult
{
    public VoidQuenchOutcome Outcome;
    public string FailReason;

    public static VoidQuenchResult Awakened() => new VoidQuenchResult { Outcome = VoidQuenchOutcome.Awakened };
    public static VoidQuenchResult NoChange() => new VoidQuenchResult { Outcome = VoidQuenchOutcome.NoChange };
    public static VoidQuenchResult Shattered() => new VoidQuenchResult { Outcome = VoidQuenchOutcome.Shattered };
    public static VoidQuenchResult Fail(string reason) => new VoidQuenchResult { Outcome = VoidQuenchOutcome.Fail, FailReason = reason };
}

public enum VoidQuenchOutcome { Fail, Awakened, NoChange, Shattered }

/// <summary>附魔注册表(占位，实际从SO加载)</summary>
public static class EnchantRegistry
{
    private static readonly Dictionary<string, EnchantData> _enchants = new Dictionary<string, EnchantData>();

    public static void Register(EnchantData data) => _enchants[data.Id] = data;
    public static EnchantData Get(string id) => _enchants.TryGetValue(id, out var d) ? d : null;
}
```

---

## 7. WeaponProficiency 武器熟练度

### 7.1 完整实现

```text
using System;
using Godot;

/// <summary>
/// 武器熟练度系统: 5种武器独立熟练度(0~10级)
/// 纯粹通过使用积累，不消耗货币
/// 永久保留，跨Run累积
/// </summary>
public class WeaponProficiency
{
    // ── 等级经验表(累计) ──
    private static readonly int[] LEVEL_THRESHOLDS = {
        0,      // Lv.0
        100,    // Lv.1
        300,    // Lv.2
        600,    // Lv.3
        1000,   // Lv.4
        1600,   // Lv.5
        2500,   // Lv.6
        3800,   // Lv.7
        5500,   // Lv.8
        8000,   // Lv.9
        12000   // Lv.10
    };

    // ── 经验获取常量 ──
    private const int EXP_PER_HIT = 1;
    private const int EXP_PER_KILL = 5;
    private const int EXP_PER_ELITE_KILL = 15;
    private const int EXP_PER_BOSS_KILL = 50;
    private const int EXP_PER_FLOOR_CLEAR = 30;
    private const int EXP_PER_RUN_CLEAR = 100;
    private const float FLOOR_CLEAR_DAMAGE_RATIO = 0.60f; // 需60%伤害来自该武器

    // ── 状态 ──
    private readonly WeaponType _weaponType;
    private int _currentExp;
    private int _currentLevel;

    // ── 事件 ──
    public event Action<WeaponType, int, int> OnLevelUp; // (type, oldLevel, newLevel)
    public event Action<WeaponType, int> OnExpGained;    // (type, newExp)

    public WeaponType Type => _weaponType;
    public int Level => _currentLevel;
    public int CurrentExp => _currentExp;
    public int ExpToNextLevel => _currentLevel < 10 ? LEVEL_THRESHOLDS[_currentLevel + 1] - _currentExp : 0;

    public WeaponProficiency(WeaponType type)
    {
        _weaponType = type;
        _currentExp = 0;
        _currentLevel = 0;
    }

    // ── 经验获取 ──

    /// <summary>命中敌人</summary>
    public void AddHitExp() => AddExp(EXP_PER_HIT);

    /// <summary>击杀普通敌人</summary>
    public void AddKillExp() => AddExp(EXP_PER_KILL);

    /// <summary>击杀精英</summary>
    public void AddEliteKillExp() => AddExp(EXP_PER_ELITE_KILL);

    /// <summary>击杀Boss</summary>
    public void AddBossKillExp() => AddExp(EXP_PER_BOSS_KILL);

    /// <summary>完成一层(需满足伤害占比)</summary>
    public void AddFloorClearExp(float damageRatio)
    {
        if (damageRatio >= FLOOR_CLEAR_DAMAGE_RATIO)
            AddExp(EXP_PER_FLOOR_CLEAR);
    }

    /// <summary>通关额外奖励</summary>
    public void AddRunClearExp() => AddExp(EXP_PER_RUN_CLEAR);

    private void AddExp(int amount)
    {
        if (_currentLevel >= 10) return; // 已满级

        _currentExp += amount;
        OnExpGained?.Invoke(_weaponType, _currentExp);

        // 检查升级
        while (_currentLevel < 10 && _currentExp >= LEVEL_THRESHOLDS[_currentLevel + 1])
        {
            int oldLevel = _currentLevel;
            _currentLevel++;
            OnLevelUp?.Invoke(_weaponType, oldLevel, _currentLevel);
        }
    }

    // ── 等级效果 ──

    /// <summary>当前等级ATK加成%</summary>
    public float GetATKBonus() => _currentLevel * 0.01f;  // 每级+1%

    /// <summary>当前等级攻速加成%</summary>
    public float GetASBonus()
    {
        // Lv.1~2: 无; Lv.3起: 每级+1%(3级+2%, 4级+3%, ...)
        if (_currentLevel < 3) return 0f;
        return (_currentLevel - 1) * 0.01f;
    }

    /// <summary>当前等级暴击率加成%</summary>
    public float GetCRBonus()
    {
        // Lv.1~4: 无; Lv.5起: 每级+1%(5级+2%, 6级+3%, ...)
        if (_currentLevel < 5) return 0f;
        return (_currentLevel - 3) * 0.01f;
    }

    /// <summary>当前等级攻击范围加成%</summary>
    public float GetRangeBonus()
    {
        // Lv.1~7: 无; Lv.8起: 每级递增
        if (_currentLevel < 8) return 0f;
        return (_currentLevel - 7) switch
        {
            1 => 0.03f,   // Lv.8: +3%
            2 => 0.05f,   // Lv.9: +5%
            3 => 0.07f,   // Lv.10: +7%
            _ => 0f
        };
    }

    /// <summary>虚空洞炼成功率加成(Lv.10专属)</summary>
    public float GetVoidQuenchBonus()
    {
        return _currentLevel >= 10 ? 0.05f : 0f;
    }

    /// <summary>强化碎片消耗折扣(Lv.7+)</summary>
    public float GetForgeDiscount()
    {
        return _currentLevel >= 7 ? 0.10f : 0f;
    }

    /// <summary>获取所有被动增益汇总</summary>
    public ProficiencyBonuses GetAllBonuses()
    {
        return new ProficiencyBonuses
        {
            ATKBonus = GetATKBonus(),
            ASBonus = GetASBonus(),
            CRBonus = GetCRBonus(),
            RangeBonus = GetRangeBonus(),
            VoidQuenchBonus = GetVoidQuenchBonus(),
            ForgeDiscount = GetForgeDiscount()
        };
    }

    /// <summary>从存档恢复</summary>
    public void Restore(int exp)
    {
        _currentExp = exp;
        _currentLevel = 0;
        for (int i = 0; i < LEVEL_THRESHOLDS.Length - 1; i++)
        {
            if (_currentExp >= LEVEL_THRESHOLDS[i + 1])
                _currentLevel = i + 1;
            else
                break;
        }
    }
}

/// <summary>熟练度增益汇总</summary>
public struct ProficiencyBonuses
{
    public float ATKBonus;
    public float ASBonus;
    public float CRBonus;
    public float RangeBonus;
    public float VoidQuenchBonus;
    public float ForgeDiscount;
}

/// <summary>
/// 武器熟练度管理器: 管理5种武器的独立熟练度
/// </summary>
public class WeaponProficiencyManager
{
    private readonly Dictionary<WeaponType, WeaponProficiency> _proficiencies
        = new Dictionary<WeaponType, WeaponProficiency>();

    public event Action<WeaponType, int, int> OnAnyLevelUp;

    public WeaponProficiencyManager()
    {
        foreach (WeaponType type in Enum.GetValues(typeof(WeaponType)))
        {
            var prof = new WeaponProficiency(type);
            prof.OnLevelUp += (wt, oldLv, newLv) => OnAnyLevelUp?.Invoke(wt, oldLv, newLv);
            _proficiencies[type] = prof;
        }
    }

    /// <summary>获取指定武器的熟练度</summary>
    public WeaponProficiency Get(WeaponType type) => _proficiencies[type];

    /// <summary>从存档恢复</summary>
    public void Restore(Dictionary<string, int> savedExp)
    {
        foreach (var kv in savedExp)
        {
            if (Enum.TryParse<WeaponType>(kv.Key, out var type))
            {
                _proficiencies[type].Restore(kv.Value);
            }
        }
    }

    /// <summary>导出存档数据</summary>
    public Dictionary<string, int> ExportSaveData()
    {
        var data = new Dictionary<string, int>();
        foreach (var kv in _proficiencies)
        {
            data[kv.Key.ToString()] = kv.Value.CurrentExp;
        }
        return data;
    }
}
```

---

## 8. 测试计划

### 8.1 单元测试

| 测试类 | 测试项 | 预期结果 | 优先级 |
|--------|--------|---------|:---:|
| **CharacterStatsTest** | 软上限ATK%=150%时值正确 | 加成150%以内全量生效 | P0 |
| | 软上限ATK%=200%时值折算 | 150% + (200%-150%)×50% = 175% | P0 |
| | 硬上限CR=75%不可超越 | CR叠加至80%时截断为75% | P0 |
| | 乘法修饰符独立相乘 | AS=1.8×1.2=2.16 | P0 |
| | 加法+乘法混合计算正确 | FATK=30×1.5×1.2=54 | P0 |
| | RemoveModifiersBySource批量清除 | 清除后ATK%回到基础值 | P1 |
| **WalkerTest** | 旅途印记每房间+1层 | 连续进入3个房间→3层 | P0 |
| | 旅途印记上限10层 | 进入11个房间→10层 | P1 |
| | 印记增伤3%/层 | 5层→ATK%+15% | P0 |
| | 房间清除每层回复2HP | 5层+清除→回复10HP | P1 |
| | 时间回溯放置锚点 | 锚点位置=当前坐标 | P0 |
| | 时间回溯回溯成功 | 回到锚点位置+回复25%伤害 | P0 |
| | 死亡后记忆碎片转化 | 10层×50%×5=25碎片 | P1 |
| **TimeGuardianTest** | 完美格挡0.15s窗口内 | 100%减伤+1层充能 | P0 |
| | 普通格挡0.15~0.40s | 50%减伤+0.5层充能 | P0 |
| | 壁垒充能上限5层 | 6次完美格挡→5层 | P1 |
| | 充能消耗增伤15%/层 | 5层→下次攻击+75% | P0 |
| | 时之堡垒期间不可移动 | IsInFortress=true限制移动 | P1 |
| | 满充能释放震荡波 | 5层+堡垒结束→3.0×ATK范围伤害 | P0 |
| **VoidWalkerTest** | HP 80%增伤+10% | RESONANCE_TIERS[0] | P0 |
| | HP 40%增伤+60% | RESONANCE_TIERS[2] | P0 |
| | HP 20%增伤+100% | RESONANCE_TIERS[3] | P0 |
| | HP<30%虚空侵蚀2HP/秒 | 每秒扣2HP(真实伤害) | P0 |
| | HP=0进入虚空临界 | 5秒倒计时,伤害×2 | P0 |
| | 临界期间回复脱离 | 回复至1HP→恢复正常 | P1 |
| | 临界超时真正死亡 | 5秒后IsAlive=false | P0 |
| | 虚空吞噬自伤20%最大HP | HP 150→扣除30 | P0 |
| | 虚空吞噬击杀重置冷却 | 击杀→ActiveSkillCooldownTimer=0 | P0 |
| **OriginKnightTest** | 命中叠共振+1/次 | 6次命中→6层 | P0 |
| | 共振上限6层 | 7次命中→6层 | P1 |
| | 切换武器消耗共振 | 6层→切换→副武器前3次+72%+30%范围 | P0 |
| | 共振爆发窗口0.5秒 | 切换后0.5秒内攻击附带时间伤害 | P1 |
| | 裂界斩伤害公式 | (主+副)×1.5 + 层数×0.5×ATK | P0 |
| | 满共振位面不稳 | 6层→标记8秒+25%受伤 | P0 |
| **TimeLordTest** | 普攻时间附伤1.5×ATK | 附伤独立于物理伤害 | P0 |
| | 强化攻击2.5×ATK | 消耗10能量→纯时间伤害 | P0 |
| | 闪避消耗15能量 | 能量不足时无法闪避 | P0 |
| | 闪避产生时间残影 | 4秒后爆炸0.8×ATK范围3格 | P1 |
| | 残影上限5个 | 第6次闪避→最旧残影提前爆炸 | P1 |
| | 短按时间冻结 | 消耗60能量,10格范围冻结2.5秒 | P0 |
| | 长按时间倒流 | 消耗100能量,回溯4秒 | P0 |
| **CurrencyManagerTest** | 金币正常增减 | AddGold(100)→Gold=100 | P0 |
| | 金币不足消费失败 | Gold=50,SpendGold(100)→false | P0 |
| | 死亡金币清零 | ProcessDeath→Gold=0 | P0 |
| | 死亡魂保留30% | Soul=1000→保留300 | P0 |
| | 死亡魂保留70%(满Meta) | metaRetainBonus=0.40→保留700 | P0 |
| | 保留上限90% | 0.70+0.10+0.10=0.90 | P1 |
| | 印记兑换碎片(1:3) | 1印记→3碎片 | P0 |
| | 碎片不可兑换印记 | 无此接口 | P0 |
| **ForgeSystemTest** | +1强化100%成功 | 必定成功 | P0 |
| | +3强化75%成功 | 概率判定 | P0 |
| | +3失败降级(无F-05) | +3→+2 | P0 |
| | +3失败不降级(有F-05) | +3→+3 | P0 |
| | 连续失败2次+15%成功率 | 2次失败后第3次90%→100%(封顶) | P1 |
| | 附魔互斥EN-01+EN-02 | 不允许共存 | P0 |
| | 附魔兼容EN-01+EN-06 | 允许共存(跨类) | P1 |
| | 虚空淬炼觉醒70% | 概率判定 | P0 |
| | 虚空淬炼碎裂5%(无F-05) | 概率判定 | P0 |
| | 虚空淬炼碎裂0%(有F-05) | 必不碎裂 | P0 |
| | 保底淬炼100%觉醒 | 3印记→必定觉醒 | P0 |
| **UnlockTreeTest** | 前置节点检查 | W-08需W-07先解锁 | P0 |
| | 重复解锁失败 | 已解锁→Fail | P0 |
| | 碎片不足解锁失败 | 不足→Fail | P0 |
| | 全树进度计算 | 10/42→23.8% | P1 |
| | 存在印记节点额外检查 | L-10需5印记 | P0 |
| **WeaponProficiencyTest** | 命中+1经验 | AddHitExp→+1 | P0 |
| | 击杀+5经验 | AddKillExp→+5 | P0 |
| | Lv.1→Lv.2升级 | 累计300exp→Lv.2 | P0 |
| | Lv.10满级 | 12000exp→Lv.10 | P1 |
| | 满级ATK+10%/攻速+10%/CR+8% | GetAllBonuses验证 | P0 |
| | 存档恢复 | Restore(600)→Lv.3 | P1 |

### 8.2 集成测试

| 测试场景 | 测试内容 | 验证目标 |
|---------|---------|---------|
| 完整行者Run | 选择行者→通关5层→结算 | 旅途印记全程生效,死亡碎片转化 |
| 时之守卫Boss战 | 选择守卫→击败Boss | 格挡-充能-堡垒循环完整 |
| 虚空行者极限Build | HP压至10%→输出 | 共鸣100%增伤+侵蚀伤害平衡 |
| 原界骑士双武器 | 主副切换5次→裂界斩 | 共振蓄积-消耗-爆发完整循环 |
| 时间领主能量管理 | 全程只靠时之能量 | 闪避/强化/技能间能量竞争决策 |
| Meta解锁全流程 | 赚碎片→解锁→生效 | 42节点全部可达+效果生效 |
| 锻造全流程 | +0→+5+2附魔+淬炼 | 完整强化路径+成功/失败处理 |
| 死亡-重生循环 | 死亡→结算→枢纽→新Run | 货币保留/清零正确,Meta效果持续 |

### 8.3 性能测试

| 指标 | 目标 | 测试方法 |
|------|------|---------|
| CharacterStats计算耗时 | <0.1ms/次 | 1000次连续CalculateFATK |
| 修饰符增删 | <0.01ms/次 | 100个修饰符Add/Remove |
| UnlockTree依赖检查 | <0.05ms/次 | 42节点全量前置遍历 |
| 时间残影更新(5个) | <0.02ms/帧 | 5个残影同时倒计时+爆炸 |
| 死亡结算 | <5ms | ProcessDeath完整流程 |

### 8.4 平衡测试

| 指标 | 健康范围 | 警告阈值 | 数据来源 |
|------|---------|---------|---------|
| 行者平均通关率 | 40~50% | <30% 或 >60% | 1000局模拟 |
| 虚空行者平均通关率 | 20~30% | <15% 或 >40% | 1000局模拟 |
| 各角色DPS偏差(同装备) | <15% | >20% | 30秒输出测试 |
| +5武器玩家占比 | <15% | >30% | 全局统计 |
| 满级熟练度玩家占比 | <5% | >15% | 全局统计 |
| 虚空淬炼使用率 | >30% | <15% | 全局统计 |
| Meta全解锁所需局数 | 40~60局 | <25 或 >80 | 新号进度追踪 |

---

> **文档结束**  
> 本文档定义了《Plane Walker: Chronicles of Collapse》的角色系统架构(5角色子类)、20项属性系统、角色专属机制、Meta解锁树(42节点)、四货币管理、锻造系统(5级强化+15附魔+虚空淬炼)、武器熟练度(10级)及完整测试计划。所有GDScript实现包含完整方法签名和参数，可直接作为开发基准。
