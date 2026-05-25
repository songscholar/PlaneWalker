# 02 时间操控系统开发文档

> **引擎**: Godot 4.x  
> **架构依赖**: EventBus Autoload, ServiceRegistry, StateMachine, Registry  
> **基准帧率**: 60FPS, 所有帧数以秒存储，运行时换算  
> **版本**: v1.0  

> **Godot迁移约束**：时间系统以 Autoload `time_scale_manager.gd` 管理全局/分层时间倍率；实体实现 `time_entity.gd` 或组合式脚本。历史伪代码中的组件映射为 Godot节点脚本，后处理映射为 Viewport/CanvasItem Shader。

---

## 2.1 系统架构（TimeScaleManager 分层时间缩放）

### 2.1.1 核心架构总览

```
┌─────────────────────────────────────────────────────────┐
│                    TimeScaleManager                      │
│  (全局单例，通过 ServiceRegistry 访问)                     │
├─────────────────────────────────────────────────────────┤
│  IsGlobalTimeStopped : bool                             │
│  GlobalTimeScale     : float (默认1.0)                   │
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │ TimeEntity    │  │ TimeEntity    │  │ TimeEntity  │ │
│  │ (玩家)        │  │ (敌人A)       │  │ (敌人B)     │ │
│  │ LocalScale=1.0│  │ LocalScale=0.0│  │ LocalScale=0.4│
│  └───────────────┘  └───────────────┘  └─────────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │ TimeEffectRegistry (空间分区查询)                    ││
│  │ SpatialGrid 2m×2m                                   ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │ TimeEnergySystem (时之能量管理)                      ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │ SnapshotBuffer (状态快照环形缓冲区)                  ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 2.1.2 TimeScaleManager 实现

```text
using System.Collections.Generic;
using Godot;

public enum TimeEffectType
{
    Stop,
    Slow,
    Accelerate,
    Rift
}

public struct TimeEffect
{
    public TimeEffectType Type;
    public float Strength;           // 0.0~1.0, 影响强度
    public float RemainingDuration;  // 剩余时间(真实秒)
    public int SourceId;             // 来源实体ID(防止同源叠加)
    public int Priority;             // 优先级(用于冲突解决)
}

public class TimeScaleManager : Node
{
    // ── 单例(通过 ServiceRegistry 注册) ──
    public static TimeScaleManager Instance { get; private set; }

    // ── 全局状态 ──
    public bool IsGlobalTimeStopped { get; private set; }
    public float GlobalStopRemainingTime { get; private set; }
    public float FreezeDamageMultiplier { get; private set; } = 1.3f;

    // ── 空间分区 ──
    private TimeEffectRegistry _registry;

    // ── 注册的时间实体 ──
    private List<TimeEntity> _timeEntities = new List<TimeEntity>(128);
    private List<TimeEntity> _pendingAdd = new List<TimeEntity>();
    private List<TimeEntity> _pendingRemove = new List<TimeEntity>();

    // ── 时间停止事件 ──
    public event System.Action OnTimeStopBegin;
    public event System.Action OnTimeStopEnd;

    private void Awake()
    {
        Instance = this;
        ServiceRegistry.Register(this);
        _registry = new TimeEffectRegistry(cellSize: 2f);
    }

    private void On.queue_free()
    {
        ServiceRegistry.Unregister<TimeScaleManager>();
    }

    // ── 实体注册/注销 ──
    public void RegisterEntity(TimeEntity entity)
    {
        if (!_timeEntities.Contains(entity) && !_pendingAdd.Contains(entity))
            _pendingAdd.Add(entity);
    }

    public void UnregisterEntity(TimeEntity entity)
    {
        _pendingRemove.Add(entity);
    }

    // ── 全局时间停止 ──
    public void ApplyGlobalTimeStop(float duration, float damageMultiplier = 1.3f)
    {
        IsGlobalTimeStopped = true;
        GlobalStopRemainingTime = duration;
        FreezeDamageMultiplier = damageMultiplier;
        OnTimeStopBegin?.Invoke();
        EventBus.Publish(new TimeStopEvent { Duration = duration, IsBegin = true });
    }

    private void EndGlobalTimeStop()
    {
        IsGlobalTimeStopped = false;
        GlobalStopRemainingTime = 0f;
        OnTimeStopEnd?.Invoke();
        EventBus.Publish(new TimeStopEvent { Duration = 0f, IsBegin = false });
    }

    // ── 主循环更新 ──
    private void Update()
    {
        float rawDeltaTime = Time.unscaledDeltaTime;

        // 处理待添加/移除
        for (int i = 0; i < _pendingAdd.Count; i++)
            _timeEntities.Add(_pendingAdd[i]);
        _pendingAdd.Clear();
        for (int i = 0; i < _pendingRemove.Count; i++)
            _timeEntities.Remove(_pendingRemove[i]);
        _pendingRemove.Clear();

        // 全局时间停止倒计时
        if (IsGlobalTimeStopped)
        {
            GlobalStopRemainingTime -= rawDeltaTime;
            if (GlobalStopRemainingTime <= 0f)
                EndGlobalTimeStop();
        }

        // 更新每个实体的 LocalTimeScale
        for (int i = 0; i < _timeEntities.Count; i++)
        {
            UpdateEntityTimeScale(_timeEntities[i], rawDeltaTime);
        }
    }

    private void UpdateEntityTimeScale(TimeEntity entity, float rawDeltaTime)
    {
        // 全局时停检查
        if (IsGlobalTimeStopped && entity.TimeAffinity > 0)
        {
            float resistanceMultiplier = entity.GetTimeResistance(TimeEffectType.Stop);
            if (resistanceMultiplier <= 0f)
            {
                // 完全免疫(如时间构造体)
                entity.SetLocalTimeScale(1.0f);
                return;
            }
            // 有抗性的实体按比例受影响
            entity.SetLocalTimeScale(0f);
            // 但持续时间按抗性缩短
            return;
        }

        // 计算局部效果
        float maxSlowdown = 1.0f;
        float totalAcceleration = 0f;
        bool isStopped = false;

        var effects = entity.ActiveTimeEffects;
        for (int j = effects.Count - 1; j >= 0; j--)
        {
            var effect = effects[j];
            switch (effect.Type)
            {
                case TimeEffectType.Stop:
                    if (entity.TimeAffinity > 0)
                        isStopped = true;
                    break;
                case TimeEffectType.Slow:
                    float slowResist = entity.GetTimeResistance(TimeEffectType.Slow);
                    float effectiveSlow = effect.Strength * slowResist;
                    maxSlowdown = math.Min(maxSlowdown, 1.0f - effectiveSlow);
                    break;
                case TimeEffectType.Accelerate:
                    totalAcceleration += effect.Strength;
                    break;
                case TimeEffectType.Rift:
                    if (entity.CompareTag("Enemy"))
                    {
                        float riftResist = entity.GetTimeResistance(TimeEffectType.Rift);
                        float effectiveRiftSlow = effect.Strength * 0.6f * riftResist;
                        maxSlowdown = math.Min(maxSlowdown, 1.0f - effectiveRiftSlow);
                    }
                    else if (entity.CompareTag("Player"))
                    {
                        totalAcceleration += 0.15f; // CD加速
                    }
                    break;
            }

            // 更新持续时间
            effect.RemainingDuration -= rawDeltaTime;
            if (effect.RemainingDuration <= 0f)
                effects.RemoveAt(j);
            else
                effects[j] = effect;
        }

        if (isStopped)
            entity.SetLocalTimeScale(0f);
        else
            entity.SetLocalTimeScale(math.Max(0.05f, maxSlowdown + totalAcceleration));

        // 应用到子系统的缩放delta
        entity.ScaledDeltaTime = Time.unscaledDeltaTime * entity.LocalTimeScale;
    }

    // ── 裂隙范围查询 ──
    public void ApplyRiftEffect(Vector3 center, float radius, float duration, int sourceId)
    {
        _registry.QueryCircle(center, radius, entity =>
        {
            entity.AddTimeEffect(new TimeEffect
            {
                Type = TimeEffectType.Rift,
                Strength = 0.6f,
                RemainingDuration = duration,
                SourceId = sourceId,
                Priority = 0
            });
        });
    }

    // ── 移除指定来源的效果 ──
    public void RemoveEffectBySource(int sourceId)
    {
        foreach (var entity in _timeEntities)
        {
            entity.ActiveTimeEffects.RemoveAll(e => e.SourceId == sourceId);
        }
    }
}

// ── 事件结构 ──
public struct TimeStopEvent
{
    public float Duration;
    public bool IsBegin;
}
```

---

## 2.2 TimeEnergySystem 实现

### 2.2.1 能量系统核心类

```text
using System;
using Godot;

public class TimeEnergySystem : Node
{
    // ── 基础参数 ──
    private const float BASE_MAX_CHRONOS = 100f;
    private const float HARD_MAX_CHRONOS = 200f;
    private const float BASE_REGEN = 3.0f;
    private const float MOVE_REGEN_MODIFIER = 0.67f;
    private const float NON_COMBAT_REGEN_MODIFIER = 1.5f;
    private const float ACTION_REGEN_MODIFIER = 0.0f;

    // ── 击杀恢复 ──
    private const float KILL_REGEN_NORMAL = 8f;
    private const float KILL_REGEN_ELITE = 20f;
    private const float KILL_REGEN_BOSS = 35f;
    private const float KILL_REGEN_BOSS_PHASE = 15f;

    // ── 完美操作恢复 ──
    private const float PERFECT_DODGE_REGEN = 15f;
    private const float PERFECT_PARRY_REGEN = 12f;
    private const float COMBO_MAINTAIN_REGEN = 5f;
    private const int COMBO_MAINTAIN_THRESHOLD = 10;

    // ── 受伤惩罚 ──
    private const float DAMAGE_PENALTY = 5f;

    // ── Haste连用惩罚 ──
    private const float HASTE_WINDOW = 8f;
    private static readonly float[] HasteMultipliers = { 1.0f, 1.2f, 1.5f, 1.8f };

    // ── 内部状态 ──
    private float _currentEnergy;
    private float _maxEnergy;
    private float _costReduction;       // 上限 0.5
    private float _regenBonus;          // 上限 1.0 (+100%)
    private float _killRegenBonus;      // 上限 1.0
    private float _perfectBonus;        // 上限 1.5 (+150%)

    // ── Haste追踪 ──
    private int _consecutiveSkillCount;
    private float _lastSkillUseTime;
    private CombatState _combatState;

    // ── 击杀衰减追踪 ──
    private float _lastKillTime;

    // ── 连击追踪 ──
    private int _currentCombo;

    // ── 事件 ──
    public event Action<float, float> OnEnergyChanged;    // (current, max)
    public event Action<float> OnEnergySpent;              // (amount)
    public event Action<float> OnEnergyGained;             // (amount)
    public event Action OnEnergyDepleted;

    public float CurrentEnergy => _currentEnergy;
    public float MaxEnergy => _maxEnergy;
    public float EnergyPercent => _currentEnergy / _maxEnergy;
    public bool IsDepleted => _currentEnergy <= 0f;

    private void Awake()
    {
        _maxEnergy = BASE_MAX_CHRONOS;
        _currentEnergy = _maxEnergy;
        _costReduction = 0f;
        _regenBonus = 0f;
        _killRegenBonus = 0f;
        _perfectBonus = 0f;
        _combatState = CombatState.NonCombat;
    }

    // ── 消耗公式 ──
    public float CalculateActualCost(float baseCost)
    {
        float costReductionClamped = math.Min(_costReduction, 0.5f);
        float hasteMultiplier = GetHasteMultiplier();
        float actualCost = baseCost * (1f - costReductionClamped) * hasteMultiplier;
        return math.Max(0f, actualCost);
    }

    public bool TrySpendEnergy(float baseCost, out float actualCost)
    {
        actualCost = CalculateActualCost(baseCost);
        if (_currentEnergy >= actualCost)
        {
            _currentEnergy -= actualCost;
            _lastSkillUseTime = Time.unscaledTime;
            _consecutiveSkillCount = math.Min(_consecutiveSkillCount + 1, HasteMultipliers.Length - 1);
            OnEnergySpent?.Invoke(actualCost);
            OnEnergyChanged?.Invoke(_currentEnergy, _maxEnergy);
            if (_currentEnergy <= 0f)
                OnEnergyDepleted?.Invoke();
            return true;
        }
        return false;
    }

    private float GetHasteMultiplier()
    {
        if (Time.unscaledTime - _lastSkillUseTime > HASTE_WINDOW)
        {
            _consecutiveSkillCount = 0;
            return 1.0f;
        }
        int index = math.Min(_consecutiveSkillCount, HasteMultipliers.Length - 1);
        return HasteMultipliers[index];
    }

    // ── 自然恢复公式 ──
    // RegenPerSecond = BaseRegen × (1 + RegenBonus) × CombatStateModifier
    public float GetRegenRate()
    {
        float stateModifier = _combatState switch
        {
            CombatState.NonCombat => NON_COMBAT_REGEN_MODIFIER,
            CombatState.Standing => 1.0f,
            CombatState.Moving => MOVE_REGEN_MODIFIER,
            CombatState.Attacking => ACTION_REGEN_MODIFIER,
            CombatState.Dodging => ACTION_REGEN_MODIFIER,
            _ => 1.0f
        };
        return BASE_REGEN * (1f + math.Min(_regenBonus, 1.0f)) * stateModifier;
    }

    private void Update()
    {
        // 自然恢复
        float regenRate = GetRegenRate();
        if (regenRate > 0f)
        {
            float regenAmount = regenRate * Time.unscaledDeltaTime;
            AddEnergy(regenAmount, EnergySource.NaturalRegen);
        }

        // Haste衰减
        if (Time.unscaledTime - _lastSkillUseTime > HASTE_WINDOW)
            _consecutiveSkillCount = 0;
    }

    // ── 击杀恢复公式 ──
    // KillRegen = BaseKillRegen × (1 + KillRegenBonus) × ElapsedTimeDecay
    public void OnKillEnemy(EnemyType enemyType)
    {
        float baseRegen = enemyType switch
        {
            EnemyType.Normal => KILL_REGEN_NORMAL,
            EnemyType.Elite => KILL_REGEN_ELITE,
            EnemyType.Boss => KILL_REGEN_BOSS,
            _ => KILL_REGEN_NORMAL
        };

        float elapsedDecay = CalculateKillDecay();
        float killBonusClamped = math.Min(_killRegenBonus, 1.0f);
        float amount = baseRegen * (1f + killBonusClamped) * elapsedDecay;
        AddEnergy(amount, EnergySource.Kill);
        _lastKillTime = Time.unscaledTime;
    }

    public void OnBossPhaseChange()
    {
        float amount = KILL_REGEN_BOSS_PHASE * (1f + math.Min(_killRegenBonus, 1.0f));
        AddEnergy(amount, EnergySource.Kill);
    }

    private float CalculateKillDecay()
    {
        float elapsed = Time.unscaledTime - _lastKillTime;
        if (elapsed <= 2f) return 1.0f;
        if (elapsed <= 5f) return math.Lerp(1.0f, 0.6f, (elapsed - 2f) / 3f);
        return 0.6f;
    }

    // ── 完美操作恢复公式 ──
    // PerfectRegen = BasePerfectRegen × (1 + PerfectBonus) × ComboMultiplier
    public void OnPerfectDodge()
    {
        float comboMult = GetComboMultiplier();
        float bonusClamped = math.Min(_perfectBonus, 1.5f);
        float amount = PERFECT_DODGE_REGEN * (1f + bonusClamped) * comboMult;
        AddEnergy(amount, EnergySource.PerfectAction);
    }

    public void OnPerfectParry()
    {
        float comboMult = GetComboMultiplier();
        float bonusClamped = math.Min(_perfectBonus, 1.5f);
        float amount = PERFECT_PARRY_REGEN * (1f + bonusClamped) * comboMult;
        AddEnergy(amount, EnergySource.PerfectAction);
    }

    public void OnComboHit(int comboCount)
    {
        _currentCombo = comboCount;
        if (comboCount >= COMBO_MAINTAIN_THRESHOLD)
        {
            float comboMult = GetComboMultiplier();
            float bonusClamped = math.Min(_perfectBonus, 1.5f);
            float amount = COMBO_MAINTAIN_REGEN * (1f + bonusClamped) * comboMult;
            AddEnergy(amount, EnergySource.Combo);
        }
    }

    private float GetComboMultiplier()
    {
        if (_currentCombo < 5) return 1.0f;
        if (_currentCombo < 15) return 1.2f;
        if (_currentCombo < 30) return 1.5f;
        return 2.0f;
    }

    // ── 受伤惩罚 ──
    public void OnTakeDamage()
    {
        _currentEnergy = math.Max(0f, _currentEnergy - DAMAGE_PENALTY);
        OnEnergyChanged?.Invoke(_currentEnergy, _maxEnergy);
        if (_currentEnergy <= 0f)
            OnEnergyDepleted?.Invoke();
    }

    // ── 通用增减 ──
    public void AddEnergy(float amount, EnergySource source)
    {
        _currentEnergy = math.Min(_maxEnergy, _currentEnergy + amount);
        OnEnergyGained?.Invoke(amount);
        OnEnergyChanged?.Invoke(_currentEnergy, _maxEnergy);
    }

    // ── 外部修正设置 ──
    public void SetMaxEnergyBonus(float bonus)
    {
        _maxEnergy = math.Min(BASE_MAX_CHRONOS + bonus, HARD_MAX_CHRONOS);
        _currentEnergy = math.Min(_currentEnergy, _maxEnergy);
    }

    public void AddCostReduction(float amount) => _costReduction = math.Min(_costReduction + amount, 0.5f);
    public void AddRegenBonus(float amount) => _regenBonus = math.Min(_regenBonus + amount, 1.0f);
    public void AddKillRegenBonus(float amount) => _killRegenBonus = math.Min(_killRegenBonus + amount, 1.0f);
    public void AddPerfectBonus(float amount) => _perfectBonus = math.Min(_perfectBonus + amount, 1.5f);
    public void SetCombatState(CombatState state) => _combatState = state;
}

public enum CombatState { NonCombat, Standing, Moving, Attacking, Dodging }
public enum EnergySource { NaturalRegen, Kill, PerfectAction, Combo, Item, Other }
public enum EnemyType { Normal, Elite, Boss }
```

---

## 2.3 四大时间技能实现

### 2.3.1 TimeStop（时间停止）

```text
using System.Collections;
using Godot;

public class TimeStop : Node, ITimeSkill
{
    // ── 帧数据(60FPS→秒) ──
    private const float WINDUP_DURATION = 12f / 60f;      // 200ms
    private const float EFFECT_DURATION = 3f;               // 基础3秒
    private const float MAX_EXTENDED_DURATION = 6f;
    private const float FADE_DURATION = 30f / 60f;          // 500ms
    private const int BASE_COST = 35;
    private const float BASE_COOLDOWN = 12f;

    // ── 冻结伤害加成 ──
    private const float BASE_FREEZE_DAMAGE_MULT = 1.3f;
    private const float PER_SECOND_BONUS = 0.05f;
    private const float MAX_FREEZE_DAMAGE_MULT = 1.45f;

    // ── 升级等级 ──
    private int _skillLevel = 1;
    private int _relatedBlessingCount = 0;

    // ── 运行时状态 ──
    private float _currentDuration;
    private float _cooldownTimer;
    private bool _isActive;
    private Coroutine _activeCoroutine;

    // ── 引用 ──
    private TimeEnergySystem _energySystem;
    private TimeScaleManager _timeManager;
    private PlayerController _player;

    public string SkillName => "Chrono Freeze";
    public float CooldownRemaining => _cooldownTimer;
    public bool IsOnCooldown => _cooldownTimer > 0f;
    public bool IsActive => _isActive;
    public int SkillLevel { get => _skillLevel; set => _skillLevel = value; }

    public void Initialize(TimeEnergySystem energySystem, TimeScaleManager timeManager, PlayerController player)
    {
        _energySystem = energySystem;
        _timeManager = timeManager;
        _player = player;
    }

    public bool CanActivate()
    {
        return !_isActive && _cooldownTimer <= 0f &&
               _energySystem.CurrentEnergy >= _energySystem.CalculateActualCost(BASE_COST);
    }

    public void Activate()
    {
        if (!CanActivate()) return;

        if (!_energySystem.TrySpendEnergy(BASE_COST, out float actualCost))
            return;

        if (_activeCoroutine != null)
            StopCoroutine(_activeCoroutine);
        _activeCoroutine = StartCoroutine(ExecuteTimeStop());
    }

    private async流程 ExecuteTimeStop()
    {
        _isActive = true;

        // Lv.4: 取消前摇
        if (_skillLevel < 4)
        {
            // 前摇: 玩家举起左手, 掌心出现时钟符文; 可移动但不可攻击
            _player.SetCanAttack(false);
            yield return new WaitForSecondsRealtime(WINDUP_DURATION);
            _player.SetCanAttack(true);
        }

        // 生效: 全屏时间冻结脉冲波扩散(纯视觉)
        PlayPulseWaveEffect();
        EventBus.Publish(new SkillActivateEvent { SkillType = TimeSkillType.Stop });

        // 计算持续时间
        _currentDuration = EFFECT_DURATION;
        // 祝福/道具延长
        _currentDuration += GetDurationBonus();
        _currentDuration = math.Min(_currentDuration, MAX_EXTENDED_DURATION);

        // 计算冻结伤害加成
        float freezeMult = BASE_FREEZE_DAMAGE_MULT;

        // 应用全局时间停止
        _timeManager.ApplyGlobalTimeStop(_currentDuration, freezeMult);

        // 持续期间: 每秒增加伤害加成
        float elapsed = 0f;
        while (elapsed < _currentDuration)
        {
            float dt = Time.unscaledDeltaTime;
            elapsed += dt;

            // 每冻结1秒, 倍率+0.05
            freezeMult = math.Min(
                BASE_FREEZE_DAMAGE_MULT + (elapsed * PER_SECOND_BONUS),
                MAX_FREEZE_DAMAGE_MULT
            );
            _timeManager.FreezeDamageMultiplier = freezeMult;

            // 祝福: 绝对零度护符 - 冻结目标每秒受攻击力×5%时之伤害
            ApplyAbsoluteZeroTick(dt);

            // 祝福: 碎时者之戒 - 停止中击杀恢复能量(在Enemy.OnDeath中处理)
            // 祝福: 冰川之心 - 停止期间玩家攻速+30%(在PlayerController中处理)

            yield return null;
        }

        // 消退阶段
        PlayFadeEffect(); // 冰晶碎裂粒子效果, 被冻结目标逐步恢复

        // 祝福: 时光织女的祝福 - 消退后2秒敌人移速-20%
        ApplyWeaverSlowBuff();

        // Lv.3: 消退时产生时之冲击波
        if (_skillLevel >= 3)
            PlayShockwaveEffect();

        _isActive = false;
        _cooldownTimer = GetActualCooldown();

        // Haste衰减后重置
        _timeManager.EndGlobalTimeStop();
    }

    private float GetDurationBonus()
    {
        float bonus = 0f;
        // Lv.2: +0.5秒
        if (_skillLevel >= 2) bonus += 0.5f;
        // 永恒沙漏: +1秒
        if (HasBlessing("EternalHourglass")) bonus += 1f;
        return bonus;
    }

    private float GetActualCooldown()
    {
        float cdr = GetCooldownReduction(); // CDR上限60%
        return BASE_COOLDOWN * (1f - math.Min(cdr, 0.6f));
    }

    // ── 祝福/道具查询(示例) ──
    private bool HasBlessing(string blessingId) => false; // 从Inventory/Registry查询
    private float GetCooldownReduction() => 0f;

    private void PlayPulseWaveEffect() { /* VFX: 从玩家位置向外圆形冲击波 */ }
    private void PlayFadeEffect() { /* VFX: 冰晶碎裂粒子 */ }
    private void PlayShockwaveEffect() { /* Lv.3: 半径3m冲击波, 攻击力×40%伤害 */ }
    private void ApplyAbsoluteZeroTick(float dt) { /* 绝对零度护符: 每秒攻击力×5%时之伤害 */ }
    private void ApplyWeaverSlowBuff() { /* 时光织女: 消退后2秒减速20% */ }

    private void Update()
    {
        if (_cooldownTimer > 0f)
            _cooldownTimer -= Time.unscaledDeltaTime;
    }
}
```

### 2.3.2 TimeRewind（时间回溯）

```text
using System.Collections;
using Godot;

public class TimeRewind : Node, ITimeSkill
{
    // ── 帧数据 ──
    private const float WINDUP_DURATION = 8f / 60f;    // 133ms
    private const float EFFECT_DURATION = 6f / 60f;     // 100ms
    private const float INVINCIBLE_FRAMES = 30f / 60f;  // 500ms
    private const float PHANTOM_DURATION = 2f;
    private const float PHANTOM_FADE = 20f / 60f;       // 333ms

    // ── 回溯参数 ──
    private const float BASE_RECALL_SECONDS = 5f;
    private const float PHANTOM_EXPLOSION_RADIUS = 3.5f;
    private const float PHANTOM_DAMAGE_MULT = 0.6f;   // 攻击力×60%
    private const float PHANTOM_SLOW_STRENGTH = 0.3f;
    private const float PHANTOM_SLOW_DURATION = 0.5f;

    // ── 消耗/冷却 ──
    private const int BASE_COST = 45;
    private const float BASE_COOLDOWN = 15f;

    // ── 回溯保底 ──
    private const float MIN_HP_AFTER_REWIND = 1f;
    private const float MIN_ENERGY_AFTER_REWIND = 10f;

    // ── 升级等级 ──
    private int _skillLevel = 1;
    private float _recallSeconds = BASE_RECALL_SECONDS;

    // ── 运行时 ──
    private float _cooldownTimer;
    private bool _isActive;
    private SnapshotBuffer _snapshotBuffer;

    // ── 引用 ──
    private TimeEnergySystem _energySystem;
    private PlayerController _player;
    private PlayerHealth _playerHealth;

    public string SkillName => "Chrono Recall";
    public float CooldownRemaining => _cooldownTimer;
    public bool IsOnCooldown => _cooldownTimer > 0f;
    public bool IsActive => _isActive;
    public int SkillLevel { get => _skillLevel; set => _skillLevel = value; }

    // ── 可选回溯时间(Lv.4) ──
    private int _recallOptionIndex; // 0=3秒, 1=5秒, 2=7秒
    private static readonly float[] RecallOptions = { 3f, 5f, 7f };

    public void Initialize(TimeEnergySystem energySystem, PlayerController player,
                           PlayerHealth health, SnapshotBuffer buffer)
    {
        _energySystem = energySystem;
        _player = player;
        _playerHealth = health;
        _snapshotBuffer = buffer;
    }

    public bool CanActivate()
    {
        return !_isActive && _cooldownTimer <= 0f &&
               _energySystem.CurrentEnergy >= _energySystem.CalculateActualCost(BASE_COST);
    }

    public void Activate()
    {
        if (!CanActivate()) return;
        if (!_energySystem.TrySpendEnergy(BASE_COST, out _)) return;

        // Lv.4: 选择回溯时间
        if (_skillLevel >= 4)
            _recallSeconds = RecallOptions[_recallOptionIndex];
        else
            _recallSeconds = BASE_RECALL_SECONDS;

        // 回忆之镜祝福: 回溯距离+7秒
        if (HasBlessing("MirrorOfMemories"))
            _recallSeconds = 7f;

        StartCoroutine(ExecuteRewind());
    }

    // ── 长按切换回溯时间(Lv.4) ──
    public void ToggleRecallOption()
    {
        if (_skillLevel >= 4)
            _recallOptionIndex = (_recallOptionIndex + 1) % RecallOptions.Length;
    }

    private async流程 ExecuteRewind()
    {
        _isActive = true;

        // 1. 查找目标快照
        float targetTime = GameTime.Current - _recallSeconds;
        PlayerSnapshot target = _snapshotBuffer.GetSnapshotAtTime(targetTime);

        if (target.Equals(default(PlayerSnapshot)))
        {
            // 无可用快照, 回溯失败, 返还50%能量
            _energySystem.AddEnergy(BASE_COST * 0.5f, EnergySource.Other);
            _isActive = false;
            yield break;
        }

        // 2. 前摇: VHS倒带条纹噪点, 身体半透明化
        _player.PlayRewindWindupVFX();
        yield return new WaitForSecondsRealtime(WINDUP_DURATION);

        // 3. 保存当前位置作为残影生成点
        Vector3 phantomPos = _player.transform.position;
        Quaternion phantomRot = _player.transform.rotation;

        // 4. 生效: 瞬移至目标位置, 回溯状态
        yield return new WaitForSecondsRealtime(EFFECT_DURATION);
        ApplySnapshot(target, phantomPos, phantomRot);

        // 5. 清除"未来"快照
        _snapshotBuffer.ClearSnapshotsAfter(targetTime);

        // 6. 生成时之残影
        SpawnChronoPhantom(phantomPos, phantomRot);

        // 7. 无敌窗口
        _player.SetInvincible(INVINCIBLE_FRAMES);

        // 8. 播放回溯轨迹线
        PlayRewindTrail(phantomPos, _player.transform.position);

        _isActive = false;
        _cooldownTimer = GetActualCooldown();
    }

    private void ApplySnapshot(PlayerSnapshot snapshot, Vector3 phantomPos, Quaternion phantomRot)
    {
        _player.transform.position = snapshot.Position;
        _player.transform.rotation = snapshot.Rotation;

        // 回溯血量(保底1HP)
        float rewoundHP = math.Max(snapshot.Health, MIN_HP_AFTER_REWIND);
        _playerHealth.SetHealth(rewoundHP);

        // 回溯能量(保底10, 取5秒前与当前较大者, 不超上限)
        float rewoundEnergy = math.Max(snapshot.ChronosEnergy, MIN_ENERGY_AFTER_REWIND);
        float finalEnergy = math.Max(rewoundEnergy, _energySystem.CurrentEnergy);
        finalEnergy = math.Min(finalEnergy, _energySystem.MaxEnergy);
        _energySystem.SetEnergy(finalEnergy);

        // 清除当前Debuff
        _player.RemoveAllDebuffs();
        // 恢复5秒前的Buff
        _player.ApplyBuffs(snapshot.Buffs);

        // 回溯武器状态
        _player.SetComboCount(snapshot.ComboCount);

        // 强制回到Idle
        _player.ForceIdleState();

        // 因果逆转符: 清除Debuff恢复能量(每个+5)
        if (HasBlessing("CausalityReversal"))
        {
            int debuffCount = _player.GetClearedDebuffCount();
            _energySystem.AddEnergy(debuffCount * 5f, EnergySource.Item);
        }

        // 轮回之线: 回溯后3秒内伤害+20%
        if (HasBlessing("ThreadOfReincarnation"))
            _player.AddBuff(new DamageBonusBuff(0.2f, 3f));

        // 不灭刻印: 回血量>30%最大生命时额外2秒无敌
        if (HasBlessing("EternalSeal"))
        {
            float healAmount = rewoundHP - _playerHealth.CurrentHealth;
            if (healAmount > _playerHealth.MaxHealth * 0.3f)
                _player.SetInvincible(2f);
        }
    }

    private void SpawnChronoPhantom(Vector3 position, Quaternion rotation)
    {
        var phantomObj = new Node("ChronoPhantom");
        phantomObj.transform.position = position;
        phantomObj.transform.rotation = rotation;

        var phantom = phantomObj.AddComponent<ChronoPhantom>();
        phantom.Duration = PHANTOM_DURATION + GetPhantomDurationBonus();
        phantom.ExplosionRadius = PHANTOM_EXPLOSION_RADIUS;
        phantom.ExplosionDamage = _player.AttackPower * PHANTOM_DAMAGE_MULT;
        phantom.SlowStrength = PHANTOM_SLOW_STRENGTH;
        phantom.SlowDuration = PHANTOM_SLOW_DURATION;

        // 时之残响: 残影伤害+50%, 爆散半径+1.5m
        if (HasBlessing("ChronoEcho"))
        {
            phantom.ExplosionDamage *= 1.5f;
            phantom.ExplosionRadius += 1.5f;
        }
    }

    private float GetPhantomDurationBonus()
    {
        // Lv.2: +1秒
        return _skillLevel >= 2 ? 1f : 0f;
    }

    private float GetActualCooldown()
    {
        float cdr = GetCooldownReduction();
        return BASE_COOLDOWN * (1f - math.Min(cdr, 0.6f));
    }

    private void PlayRewindTrail(Vector3 from, Vector3 to) { /* LineRenderer淡蓝色光轨1秒淡出 */ }
    private bool HasBlessing(string id) => false;
    private float GetCooldownReduction() => 0f;

    private void Update()
    {
        if (_cooldownTimer > 0f)
            _cooldownTimer -= Time.unscaledDeltaTime;
    }
}
```

### 2.3.3 TimeAccelerate（时间加速）

```text
using System.Collections;
using Godot;

public class TimeAccelerate : Node, ITimeSkill
{
    // ── 帧数据 ──
    private const float WINDUP_DURATION = 6f / 60f;   // 100ms
    private const float MAX_DURATION = 10f;
    private const float EXIT_DURATION = 15f / 60f;     // 250ms
    private const float BACKLASH_STUN = 45f / 60f;     // 750ms

    // ── 消耗 ──
    private const int BASE_COST = 25;
    private const float OVERTIME_COST_PER_SECOND = 8f;

    // ── 冷却 ──
    private const float BASE_COOLDOWN = 8f;

    // ── 加速数值 ──
    private const float MOVE_SPEED_MULT = 1.6f;
    private const float ATTACK_SPEED_MULT = 1.4f;
    private const float DODGE_IFRAME_MULT = 1.3f;
    private const float SKILL_CD_MULT = 1.5f;
    private const float ENERGY_REGEN_MULT = 0.5f;

    // ── 过载 ──
    private const float OVERLOAD_MAX = 100f;
    private const float OVERLOAD_RATE = 12f;            // /秒
    private const float OVERLOAD_HIT_BONUS = 3f;
    private const float OVERLOAD_DAMAGE_BONUS = 8f;
    private const float OVERLOAD_WARN_THRESHOLD = 70f;

    // ── 附带时之伤害 ──
    private const float CHRONOS_DAMAGE_MULT = 0.15f;   // 攻击力×15%

    // ── 升级等级 ──
    private int _skillLevel = 1;

    // ── 运行时 ──
    private float _cooldownTimer;
    private bool _isActive;
    private bool _isOverloaded;
    private float _overloadValue;
    private float _overtimeEnergyAccum;
    private Coroutine _activeCoroutine;

    // ── 引用 ──
    private TimeEnergySystem _energySystem;
    private PlayerController _player;

    public string SkillName => "Chrono Accelerate";
    public float CooldownRemaining => _cooldownTimer;
    public bool IsOnCooldown => _cooldownTimer > 0f;
    public bool IsActive => _isActive;
    public int SkillLevel { get => _skillLevel; set => _skillLevel = value; }
    public float OverloadValue => _overloadValue;
    public float OverloadPercent => _overloadValue / OVERLOAD_MAX;

    public void Initialize(TimeEnergySystem energySystem, PlayerController player)
    {
        _energySystem = energySystem;
        _player = player;
    }

    public bool CanActivate()
    {
        return !_isActive && _cooldownTimer <= 0f &&
               _energySystem.CurrentEnergy >= _energySystem.CalculateActualCost(BASE_COST);
    }

    public void Activate()
    {
        if (!CanActivate()) return;
        if (!_energySystem.TrySpendEnergy(BASE_COST, out _)) return;

        _activeCoroutine = StartCoroutine(ExecuteAccelerate());
    }

    public void Deactivate() // 主动取消
    {
        if (!_isActive) return;
        if (_activeCoroutine != null)
            StopCoroutine(_activeCoroutine);
        ExitAccelerate(wasOverloaded: false);
    }

    private async流程 ExecuteAccelerate()
    {
        _isActive = true;
        _overloadValue = 0f;
        _isOverloaded = false;

        // 前摇
        _player.PlayAccelerateWindupVFX();
        yield return new WaitForSecondsRealtime(WINDUP_DURATION);

        // 应用加速buff
        ApplyAccelerateBuffs();

        // 持续运行
        float elapsed = 0f;
        while (elapsed < MAX_DURATION && _overloadValue < OVERLOAD_MAX)
        {
            float dt = Time.unscaledDeltaTime;
            elapsed += dt;

            // 过载增长
            float overloadRate = OVERLOAD_RATE;
            // 过载抑制器: -4/秒
            if (HasBlessing("OverloadSuppressor")) overloadRate -= 4f;
            // Lv.2: -2/秒
            if (_skillLevel >= 2) overloadRate -= 2f;
            _overloadValue += overloadRate * dt;
            _overloadValue = math.Min(_overloadValue, OVERLOAD_MAX);

            // 持续消耗时之能量
            float overtimeCost = OVERTIME_COST_PER_SECOND * (1f - math.Min(GetCostReduction(), 0.5f)) * dt;
            _overtimeEnergyAccum += overtimeCost;
            if (_overtimeEnergyAccum >= 1f)
            {
                float toSpend = math.Floor(_overtimeEnergyAccum);
                _energySystem.TrySpendEnergyRaw(toSpend);
                _overtimeEnergyAccum -= toSpend;
            }

            // 如果能量耗尽, 退出
            if (_energySystem.IsDepleted)
            {
                ExitAccelerate(wasOverloaded: false);
                yield break;
            }

            // 过载预警(70+)
            if (_overloadValue >= OVERLOAD_WARN_THRESHOLD)
                PlayOverloadWarning();

            // 永动机碎片: 击杀恢复过载值(在OnKillEnemy中处理)

            yield return null;
        }

        // 过载退出
        ExitAccelerate(wasOverloaded: true);
    }

    private void ApplyAccelerateBuffs()
    {
        float moveMult = MOVE_SPEED_MULT;
        float atkMult = ATTACK_SPEED_MULT;

        // 闪电之心: 移速+0.2
        if (HasBlessing("HeartOfLightning")) moveMult += 0.2f;

        _player.AddBuff(new SpeedBuff(moveMult, atkMult, DODGE_IFRAME_MULT, SKILL_CD_MULT));
        _energySystem.SetRegenOverride(ENERGY_REGEN_MULT); // 恢复减半
    }

    private void RemoveAccelerateBuffs()
    {
        _player.RemoveBuff<SpeedBuff>();
        _energySystem.ClearRegenOverride();
    }

    private void ExitAccelerate(bool wasOverloaded)
    {
        _isActive = false;
        RemoveAccelerateBuffs();

        if (wasOverloaded)
        {
            // 过载退出: 反噬硬直750ms, 不可使用时间技能
            _isOverloaded = true;
            _player.ApplyBacklashStun(BACKLASH_STUN);
            PlayBacklashVFX();

            // 冷却 ×1.0
            _cooldownTimer = BASE_COOLDOWN * (1f - math.Min(GetCooldownReduction(), 0.6f));

            // 反噬结束后恢复
            StartCoroutine(BacklashRecovery());
        }
        else
        {
            // 主动取消: 冷却 ×0.6
            _cooldownTimer = BASE_COOLDOWN * (1f - math.Min(GetCooldownReduction(), 0.6f)) * 0.6f;

            // Lv.3: 主动取消时1秒无敌+30%伤害加成
            if (_skillLevel >= 3)
            {
                _player.SetInvincible(1f);
                _player.AddBuff(new DamageBonusBuff(0.3f, 1f));
            }
        }

        // 退出减速动画
        _player.PlayAccelerateExitVFX();
    }

    private async流程 BacklashRecovery()
    {
        yield return new WaitForSecondsRealtime(BACKLASH_STUN);
        _isOverloaded = false;
    }

    // ── 外部触发 ──
    public void OnHitEnemy() // 攻击命中: 过载+3
    {
        if (_isActive) _overloadValue += OVERLOAD_HIT_BONUS;
    }

    public void OnTakeDamage() // 受伤: 过载+8
    {
        if (_isActive) _overloadValue += OVERLOAD_DAMAGE_BONUS;
    }

    public void OnKillEnemy() // 永动机碎片: 击杀恢复5过载值
    {
        if (_isActive && HasBlessing("PerpetualFragment"))
            _overloadValue = math.Max(0f, _overloadValue - 5f);
    }

    // ── 时之伤害(加速期间攻击附带) ──
    public float GetChronosDamageBonus()
    {
        if (!_isActive) return 0f;
        float mult = CHRONOS_DAMAGE_MULT;
        if (HasBlessing("TimeBurner")) mult += 0.10f; // 15%→25%
        return _player.AttackPower * mult;
    }

    private void PlayOverloadWarning() { /* 屏幕边缘橙色脉冲, 频率随过载值增加 */ }
    private void PlayBacklashVFX() { /* 白闪1帧→灰度化0.5秒→恢复 */ }
    private bool HasBlessing(string id) => false;
    private float GetCostReduction() => 0f;
    private float GetCooldownReduction() => 0f;

    private void Update()
    {
        if (_cooldownTimer > 0f)
            _cooldownTimer -= Time.unscaledDeltaTime;
    }
}
```

### 2.3.4 TimeRift（时间裂隙）

```text
using System.Collections;
using System.Collections.Generic;
using Godot;

public class TimeRift : Node, ITimeSkill
{
    // ── 帧数据 ──
    private const float WINDUP_DURATION = 18f / 60f;   // 300ms
    private const float PROJECTILE_SPEED = 15f;         // 15m/s
    private const float MAX_RANGE = 12f;
    private const float EXPAND_DURATION = 15f / 60f;    // 250ms
    private const float RIFT_DURATION = 6f;
    private const float COLLAPSE_WARN_TIME = 1f;
    private const float COLLAPSE_DURATION = 12f / 60f;  // 200ms

    // ── 消耗/冷却 ──
    private const int BASE_COST = 30;
    private const float BASE_COOLDOWN = 10f;

    // ── 裂隙参数 ──
    private const float BASE_RADIUS = 4.0f;
    private const float MAX_RADIUS = 6.5f;
    private const float ENEMY_SLOW_MULT = 0.4f;
    private const float ELITE_SLOW_MULT = 0.65f;
    private const float ENEMY_ACTION_DELAY_FRAMES = 8f;
    private const float PLAYER_CD_MULT = 1.5f;
    private const float PLAYER_DAMAGE_MULT = 1.15f;
    private const float BULLET_SLOW_MULT = 0.3f;

    // ── 坍缩 ──
    private const float COLLAPSE_DAMAGE_MULT = 0.8f;   // 攻击力×80%
    private const float COLLAPSE_SLOW = 0.3f;
    private const float COLLAPSE_SLOW_DURATION = 2f;

    // ── 最大同屏裂隙 ──
    private const int MAX_RIFTS = 2;

    // ── 升级等级 ──
    private int _skillLevel = 1;

    // ── 运行时 ──
    private float _cooldownTimer;
    private List<RiftInstance> _activeRifts = new List<RiftInstance>(3);
    private int _riftIdCounter;

    // ── 引用 ──
    private TimeEnergySystem _energySystem;
    private TimeScaleManager _timeManager;
    private PlayerController _player;

    public string SkillName => "Chrono Rift";
    public float CooldownRemaining => _cooldownTimer;
    public bool IsOnCooldown => _cooldownTimer > 0f;
    public bool IsActive => _activeRifts.Count > 0;
    public int SkillLevel { get => _skillLevel; set => _skillLevel = value; }
    public int ActiveRiftCount => _activeRifts.Count;

    // ── 可手动引爆(Lv.4) ──
    private bool _pendingManualDetonate;

    public void Initialize(TimeEnergySystem energySystem, TimeScaleManager timeManager, PlayerController player)
    {
        _energySystem = energySystem;
        _timeManager = timeManager;
        _player = player;
    }

    public bool CanActivate()
    {
        return _cooldownTimer <= 0f &&
               _energySystem.CurrentEnergy >= _energySystem.CalculateActualCost(BASE_COST);
    }

    public void Activate()
    {
        if (!CanActivate()) return;
        if (!_energySystem.TrySpendEnergy(BASE_COST, out _)) return;

        StartCoroutine(ExecuteRift());
    }

    // ── 手动提前引爆(Lv.4) ──
    public void ManualDetonate()
    {
        if (_skillLevel >= 4 && _activeRifts.Count > 0)
        {
            var oldest = _activeRifts[0];
            oldest.ManualDetonate = true;
        }
    }

    private async流程 ExecuteRift()
    {
        // 前摇: 发射裂隙投射物
        _player.PlayRiftWindupVFX();

        float projSpeed = PROJECTILE_SPEED;
        if (_skillLevel >= 2) projSpeed *= 1.5f; // Lv.2: +50%飞行速度

        Vector3 targetPos = CalculateRiftPosition();

        // 投射飞行(简化: 瞬间到达或短延迟)
        float flightTime = Vector3.Distance(_player.transform.position, targetPos) / projSpeed;
        yield return new WaitForSecondsRealtime(flightTime);

        // 展开动画
        yield return new WaitForSecondsRealtime(EXPAND_DURATION - (_skillLevel >= 2 ? 5f / 60f : 0f));

        // 如果已有MAX_RIFTS个裂隙, 替换最早的
        int maxRifts = MAX_RIFTS;
        if (HasBlessing("TwinRift")) maxRifts += 1; // 双生裂隙: 最多3个

        while (_activeRifts.Count >= maxRifts)
        {
            CollapseRift(_activeRifts[0], immediate: true);
        }

        // 创建裂隙实例
        int riftId = ++_riftIdCounter;
        float radius = BASE_RADIUS;
        if (HasBlessing("RiftExpander")) radius += 1.5f;
        radius = math.Min(radius, MAX_RADIUS);

        float duration = RIFT_DURATION;
        if (HasBlessing("DimensionAnchor")) duration += 3f;

        var rift = new RiftInstance
        {
            Id = riftId,
            Position = targetPos,
            Radius = radius,
            Duration = duration,
            RemainingTime = duration,
            ManualDetonate = false,
            SourceNode2D = CreateRiftVisual(targetPos, radius)
        };

        _activeRifts.Add(rift);

        // 应用裂隙效果(持续)
        _timeManager.ApplyRiftEffect(targetPos, radius, duration, riftId);

        // 裂隙虹吸: 裂隙中每有一个敌人, 玩家每秒恢复1点时之能量
        if (HasBlessing("RiftSiphon"))
            StartCoroutine(RiftSiphonCoroutine(rift));

        // 引力符文: 裂隙缓慢吸引范围内敌人
        if (HasBlessing("GravityRune"))
            StartCoroutine(GravityPullCoroutine(rift));

        // 启动裂隙生命周期
        StartCoroutine(RiftLifecycle(rift));

        // 冷却
        _cooldownTimer = BASE_COOLDOWN * (1f - math.Min(GetCooldownReduction(), 0.6f));
    }

    private async流程 RiftLifecycle(RiftInstance rift)
    {
        // 持续阶段
        while (rift.RemainingTime > COLLAPSE_WARN_TIME && !rift.ManualDetonate)
        {
            rift.RemainingTime -= Time.unscaledDeltaTime;
            yield return null;
        }

        // 坍缩预警
        if (!rift.ManualDetonate)
        {
            PlayCollapseWarning(rift);
            while (rift.RemainingTime > 0f && !rift.ManualDetonate)
            {
                rift.RemainingTime -= Time.unscaledDeltaTime;
                yield return null;
            }
        }

        // 坍缩
        CollapseRift(rift, immediate: false);
    }

    private void CollapseRift(RiftInstance rift, bool immediate)
    {
        _activeRifts.Remove(rift);
        _timeManager.RemoveEffectBySource(rift.Id);

        float damageMult = COLLAPSE_DAMAGE_MULT;
        float radius = rift.Radius + 1f; // 坍缩爆发半径 = 裂隙半径+1m

        // 时间坍缩核心: 坍缩伤害+60%
        if (HasBlessing("TimeCollapseCore")) damageMult *= 1.6f;

        // Lv.4手动引爆: 伤害×1.5但范围×0.7
        if (rift.ManualDetonate && _skillLevel >= 4)
        {
            damageMult *= 1.5f;
            radius *= 0.7f;
        }

        // 空间震荡器: 坍缩时击退3m
        float knockback = HasBlessing("SpaceOscillator") ? 3f : 0f;

        float damage = _player.AttackPower * damageMult;
        ApplyCollapseDamage(rift.Position, radius, damage, knockback);

        // Lv.3: 坍缩时额外生成3个时之碎片追踪最近敌人
        if (_skillLevel >= 3)
            SpawnChronoFragments(rift.Position, 3);

        // 清除视觉
        if (rift.SourceNode2D != null)
            rift.SourceNode2D.gameObject.queue_free();
    }

    private void ApplyCollapseDamage(Vector3 center, float radius, float damage, float knockback)
    {
        Collider[] hits = PhysicsQuery.OverlapSphere(center, radius, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var health = hit.GetComponent<EnemyHealth>();
            if (health != null)
            {
                health.TakeDamage(damage, DamageType.Chronos);
                if (knockback > 0f)
                {
                    var dir = (hit.transform.position - center).normalized;
                    hit.GetComponent<EnemyMovement>()?.ApplyKnockback(dir * knockback);
                }
                health.ApplySlow(COLLAPSE_SLOW, COLLAPSE_SLOW_DURATION);
            }
        }
        PlayCollapseVFX(center, radius);
    }

    // ── 裂隙虹吸(每秒恢复能量) ──
    private async流程 RiftSiphonCoroutine(RiftInstance rift)
    {
        while (_activeRifts.Contains(rift))
        {
            int enemyCount = CountEnemiesInRadius(rift.Position, rift.Radius);
            if (enemyCount > 0)
                _energySystem.AddEnergy(enemyCount * 1f, EnergySource.Item);
            yield return new WaitForSecondsRealtime(1f);
        }
    }

    // ── 引力符文(拉力2m/s²) ──
    private async流程 GravityPullCoroutine(RiftInstance rift)
    {
        while (_activeRifts.Contains(rift))
        {
            Collider[] hits = PhysicsQuery.OverlapSphere(rift.Position, rift.Radius, collision_mask.GetMask("Enemy"));
            foreach (var hit in hits)
            {
                var rb = hit.GetComponent<Rigidbody>();
                if (rb != null)
                {
                    Vector3 dir = (rift.Position - hit.transform.position).normalized;
                    rb.AddForce(dir * 2f, ForceMode.Acceleration);
                }
            }
            yield return new WaitForSecondsRealtime(0.1f);
        }
    }

    private Vector3 CalculateRiftPosition()
    {
        // 基于玩家朝向和瞄准方向计算, 最远12m
        Vector3 dir = _player.AimDirection;
        RaycastHit hit;
        if (PhysicsQuery.Raycast(_player.transform.position, dir, out hit, MAX_RANGE, collision_mask.GetMask("Default")))
            return hit.point;
        return _player.transform.position + dir * MAX_RANGE;
    }

    private int CountEnemiesInRadius(Vector3 center, float radius)
    {
        return PhysicsQuery.OverlapSphere(center, radius, collision_mask.GetMask("Enemy")).Length;
    }

    private Node2D CreateRiftVisual(Vector3 pos, float radius) { /* 深紫色漩涡纹理+半透明球壳 */ return null; }
    private void PlayCollapseWarning(RiftInstance rift) { /* 边缘收缩抖动, 亮度增加 */ }
    private void PlayCollapseVFX(Vector3 center, float radius) { /* 紫色+白色粒子爆散 */ }
    private void SpawnChronoFragments(Vector3 center, int count) { /* 3个追踪碎片弹, 每个攻击力×30% */ }
    private bool HasBlessing(string id) => false;
    private float GetCooldownReduction() => 0f;

    private void Update()
    {
        if (_cooldownTimer > 0f)
            _cooldownTimer -= Time.unscaledDeltaTime;
    }
}

// ── 裂隙实例数据 ──
public class RiftInstance
{
    public int Id;
    public Vector3 Position;
    public float Radius;
    public float Duration;
    public float RemainingTime;
    public bool ManualDetonate;
    public Node2D SourceNode2D;
}
```

### 2.3.5 ITimeSkill 接口

```text
public interface ITimeSkill
{
    string SkillName { get; }
    float CooldownRemaining { get; }
    bool IsOnCooldown { get; }
    bool IsActive { get; }
    int SkillLevel { get; set; }

    bool CanActivate();
    void Activate();
}

public enum TimeSkillType
{
    Stop,
    Recall,
    Accelerate,
    Rift
}

public struct SkillActivateEvent
{
    public TimeSkillType SkillType;
}
```

---

## 2.4 状态快照系统

### 2.4.1 PlayerSnapshot 数据结构

```text
using System;
using System.Collections.Generic;
using Godot;

[System.Serializable]
public struct PlayerSnapshot
{
    public float Timestamp;           // 快照时间(GameTime)
    public Vector3 Position;          // 世界坐标
    public Quaternion Rotation;       // 朝向
    public float Health;              // 当前生命
    public float ChronosEnergy;       // 当前时之能量
    public int ComboCount;            // 连击数
    public WeaponState WeaponState;   // 武器状态

    // ── Buff/Debuff(预分配池避免GC) ──
    public int BuffCount;
    public BuffData[] Buffs;          // 固定长度16, 实际用BuffCount
    public int DebuffCount;
    public DebuffData[] Debuffs;

    // ── 技能冷却 ──
    public float CooldownStop;
    public float CooldownRecall;
    public float CooldownAccelerate;
    public float CooldownRift;

    // ── 路径点(用于轨迹线) ──
    public Vector3 PathPoint;
}

[System.Serializable]
public struct BuffData
{
    public string BuffId;
    public float RemainingDuration;
    public float Strength;
}

[System.Serializable]
public struct DebuffData
{
    public string DebuffId;
    public float RemainingDuration;
    public float Strength;
}

[System.Serializable]
public struct WeaponState
{
    public WeaponType CurrentWeapon;
    public int CurrentComboStep;
    public bool IsInAttack;
    public float AttackTimer;
}

public enum WeaponType { Sword, Bow, Spear, Staff, Gauntlet }
```

### 2.4.2 SnapshotBuffer 环形缓冲区

```text
public class SnapshotBuffer
{
    private readonly PlayerSnapshot[] _buffer;
    private int _head;      // 写入位置
    private int _count;     // 当前数量
    private readonly int _capacity;

    // ── 5秒回溯: 30快照(每10帧1个); 7秒: 42快照 ──
    public SnapshotBuffer(int capacity = 42)
    {
        _capacity = capacity;
        _buffer = new PlayerSnapshot[_capacity];
        _head = 0;
        _count = 0;
    }

    public int Count => _count;
    public int Capacity => _capacity;

    // ── 推入新快照 ──
    public void Push(PlayerSnapshot snapshot)
    {
        _buffer[_head] = snapshot;
        _head = (_head + 1) % _capacity;
        if (_count < _capacity) _count++;
    }

    // ── 获取目标时间的快照(找最接近的) ──
    public PlayerSnapshot GetSnapshotAtTime(float targetTime)
    {
        if (_count == 0) return default;

        int bestIndex = -1;
        float bestDiff = float.MaxValue;

        // 从最新到最旧搜索
        for (int i = 0; i < _count; i++)
        {
            int idx = (_head - 1 - i + _capacity) % _capacity;
            float diff = math.Abs(_buffer[idx].Timestamp - targetTime);
            if (diff < bestDiff)
            {
                bestDiff = diff;
                bestIndex = idx;
            }
            if (_buffer[idx].Timestamp < targetTime)
                break; // 已过目标时间, 不需继续
        }

        return bestIndex >= 0 ? _buffer[bestIndex] : default;
    }

    // ── 清除"未来"快照(回溯后调用, 防止重复回溯) ──
    public void ClearSnapshotsAfter(float time)
    {
        for (int i = 0; i < _count; i++)
        {
            int idx = (_head - 1 - i + _capacity) % _capacity;
            if (_buffer[idx].Timestamp > time)
                _buffer[idx] = default;
        }
        // 重新计算count
        RecountAfter(time);
    }

    private void RecountAfter(float time)
    {
        int newCount = 0;
        for (int i = 0; i < _capacity; i++)
        {
            if (!_buffer[i].Equals(default(PlayerSnapshot)) && _buffer[i].Timestamp <= time)
                newCount++;
        }
        _count = newCount;
    }

    // ── 获取最新快照 ──
    public PlayerSnapshot GetLatest()
    {
        if (_count == 0) return default;
        int idx = (_head - 1 + _capacity) % _capacity;
        return _buffer[idx];
    }

    // ── 清空 ──
    public void Clear()
    {
        for (int i = 0; i < _capacity; i++)
            _buffer[i] = default;
        _head = 0;
        _count = 0;
    }
}
```

### 2.4.3 快照采集器

```text
public class SnapshotCollector : Node
{
    // ── 每10帧(~166ms)拍摄一次 ──
    private const float SNAPSHOT_INTERVAL = 10f / 60f;
    private const int DEFAULT_CAPACITY = 42; // 7秒×6快照/秒

     private int _capacity = DEFAULT_CAPACITY;

    private SnapshotBuffer _buffer;
    private float _snapshotTimer;
    private List<Vector3> _pathPoints = new List<Vector3>(42);

    // ── 引用 ──
    private PlayerController _player;
    private PlayerHealth _health;
    private TimeEnergySystem _energy;

    public SnapshotBuffer Buffer => _buffer;
    public IReadOnlyList<Vector3> PathPoints => _pathPoints;

    private void Awake()
    {
        _buffer = new SnapshotBuffer(_capacity);
    }

    public void Initialize(PlayerController player, PlayerHealth health, TimeEnergySystem energy)
    {
        _player = player;
        _health = health;
        _energy = energy;
    }

    private void Update()
    {
        _snapshotTimer += Time.unscaledDeltaTime;
        if (_snapshotTimer >= SNAPSHOT_INTERVAL)
        {
            _snapshotTimer -= SNAPSHOT_INTERVAL;
            CaptureSnapshot();
        }
    }

    private void CaptureSnapshot()
    {
        var snapshot = new PlayerSnapshot
        {
            Timestamp = GameTime.Current,
            Position = _player.transform.position,
            Rotation = _player.transform.rotation,
            Health = _health.CurrentHealth,
            ChronosEnergy = _energy.CurrentEnergy,
            ComboCount = _player.ComboCount,
            WeaponState = _player.GetWeaponState(),
            PathPoint = _player.transform.position
        };

        // 填充Buff/Debuff(预分配16槽)
        snapshot.Buffs = new BuffData[16];
        snapshot.Debuffs = new DebuffData[16];
        _player.GetCurrentBuffs(snapshot.Buffs, out snapshot.BuffCount);
        _player.GetCurrentDebuffs(snapshot.Debuffs, out snapshot.DebuffCount);

        // 技能冷却
        snapshot.CooldownStop = _player.GetSkillCooldown(TimeSkillType.Stop);
        snapshot.CooldownRecall = _player.GetSkillCooldown(TimeSkillType.Recall);
        snapshot.CooldownAccelerate = _player.GetSkillCooldown(TimeSkillType.Accelerate);
        snapshot.CooldownRift = _player.GetSkillCooldown(TimeSkillType.Rift);

        _buffer.Push(snapshot);
        _pathPoints.Add(_player.transform.position);
        if (_pathPoints.Count > _capacity)
            _pathPoints.RemoveAt(0);
    }
}
```

### 2.4.4 ChronoPhantom（时之残影）

```text
public class ChronoPhantom : Node
{
    public float Duration = 2f;
    public float ExplosionRadius = 3.5f;
    public float ExplosionDamage;
    public float SlowStrength = 0.3f;
    public float SlowDuration = 0.5f;

    private float _timer;
    private Renderer _renderer;

    private void Awake()
    {
        _renderer = GetComponent<Renderer>();
    }

    private void Update()
    {
        _timer += Time.unscaledDeltaTime;

        // 吸引附近敌人仇恨
        Collider[] hits = PhysicsQuery.OverlapSphere(transform.position, 8f, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var enemyAI = hit.GetComponent<EnemyAI>();
            if (enemyAI != null && !enemyAI.IsBoss)
            {
                float attractDuration = enemyAI.IsElite ? 1f : 2f;
                enemyAI.OverrideTarget(gameObject, attractDuration);
            }
        }

        // 残影消散动画(最后333ms闪烁)
        if (_timer > Duration - 0.333f)
        {
            float flashPhase = (_timer - (Duration - 0.333f)) / 0.333f;
            float flashRate = math.Lerp(2f, 10f, flashPhase);
            if (_renderer != null)
                _renderer.material.SetFloat("_FlashRate", flashRate);
        }

        if (_timer >= Duration)
        {
            Explode();
            queue_free();
        }
    }

    private void Explode()
    {
        Collider[] hits = PhysicsQuery.OverlapSphere(transform.position, ExplosionRadius, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var health = hit.GetComponent<EnemyHealth>();
            if (health != null)
            {
                health.TakeDamage(ExplosionDamage, DamageType.Chronos);
                health.ApplySlow(SlowStrength, SlowDuration);
            }
        }
        EffectManager.Play("ChronoPhantomExplode", transform.position);
    }
}
```

---

## 2.5 时间缩放架构

### 2.5.1 ITimeAffected 接口

```text
public interface ITimeAffected
{
    /// <summary>实体的时间亲和度(0=免疫, 1~10=优先级)</summary>
    int TimeAffinity { get; }

    /// <summary>获取对特定时间效果的抗性系数(1.0=完全受影响, 0.0=免疫)</summary>
    float GetTimeResistance(TimeEffectType effectType);

    /// <summary>当前局部时间缩放</summary>
    float LocalTimeScale { get; }

    /// <summary>本帧的缩放delta时间</summary>
    float ScaledDeltaTime { get; }
}
```

### 2.5.2 TimeEntity 基类

```text
using System.Collections.Generic;
using Godot;

[RequireComponent(typeof(AnimationPlayer或AnimationTree))]
public class TimeEntity : Node, ITimeAffected
{
    // ── 核心时间缩放 ──
    public float LocalTimeScale { get; private set; } = 1.0f;
    public float ScaledDeltaTime { get; set; } = 1.0f;
    public int TimeAffinity { get; set; } = 5;

    // ── 时间抗性(7级) ──
     private TimeResistanceLevel _resistanceLevel = TimeResistanceLevel.None;

    // ── 活跃时间效果 ──
    private List<TimeEffect> _activeTimeEffects = new List<TimeEffect>(8);
    public List<TimeEffect> ActiveTimeEffects => _activeTimeEffects;

    // ── 缓存组件 ──
    private AnimationPlayer或AnimationTree _animator;
    private List<GPUParticles2D> _particleSystems;
    private Rigidbody _rigidbody;
    private AudioSource _audioSource;

    // ── 物理系统处理 ──
    private Vector3 _baseVelocity;
    private bool _wasKinematic;

    private void Awake()
    {
        _animator = GetComponent<AnimationPlayer或AnimationTree>();
        _particleSystems = new List<GPUParticles2D>(GetComponentsInChildren<GPUParticles2D>());
        _rigidbody = GetComponent<Rigidbody>();
        _audioSource = GetComponent<AudioSource>();
    }

    private void OnEnable()
    {
        TimeScaleManager.Instance?.RegisterEntity(this);
    }

    private void OnDisable()
    {
        TimeScaleManager.Instance?.UnregisterEntity(this);
    }

    // ── 设置LocalTimeScale(由TimeScaleManager调用) ──
    public void SetLocalTimeScale(float scale)
    {
        float prevScale = LocalTimeScale;
        LocalTimeScale = scale;

        // 动画系统
        if (_animator != null)
            _animator.speed = scale;

        // 粒子系统
        UpdateParticleTimeScales(scale);

        // 音频(可选)
        if (_audioSource != null && _audioSource.clip != null)
            _audioSource.pitch = scale;

        // 物理: 被完全停止时设为Kinematic
        if (_rigidbody != null)
        {
            if (scale <= 0.001f && !_wasKinematic)
            {
                _wasKinematic = _rigidbody.isKinematic;
                _baseVelocity = _rigidbody.velocity;
                _rigidbody.isKinematic = true;
            }
            else if (scale > 0.001f && _wasKinematic)
            {
                _rigidbody.isKinematic = false;
                _rigidbody.velocity = _baseVelocity;
                _wasKinematic = false;
            }
            else if (_rigidbody != null && !_rigidbody.isKinematic)
            {
                _rigidbody.velocity = _baseVelocity * scale;
            }
        }
    }

    private void UpdateParticleTimeScales(float scale)
    {
        foreach (var ps in _particleSystems)
        {
            if (ps == null) continue;
            if (!ps.main.simulationSpeed.Equals(scale))
            {
                var main = ps.main;
                main.simulationSpeed = scale;
            }
        }
    }

    // ── 添加时间效果 ──
    public void AddTimeEffect(TimeEffect effect)
    {
        // 防止同源叠加
        int existingIndex = _activeTimeEffects.FindIndex(e => e.SourceId == effect.SourceId);
        if (existingIndex >= 0)
            _activeTimeEffects[existingIndex] = effect;
        else
            _activeTimeEffects.Add(effect);
    }

    // ── 移除时间效果 ──
    public void RemoveTimeEffect(int sourceId)
    {
        _activeTimeEffects.RemoveAll(e => e.SourceId == sourceId);
    }

    // ── 时间抗性实现(7级) ──
    public float GetTimeResistance(TimeEffectType effectType)
    {
        return _resistanceLevel switch
        {
            TimeResistanceLevel.None => 1.0f,
            TimeResistanceLevel.Slight => 0.8f,
            TimeResistanceLevel.Moderate => 0.6f,
            TimeResistanceLevel.High => 0.4f,
            TimeResistanceLevel.TimeConstruct => GetTimeConstructResistance(effectType),
            TimeResistanceLevel.TimeWalker => GetTimeWalkerResistance(effectType),
            TimeResistanceLevel.Boss => 0.15f,
            TimeResistanceLevel.FinalBoss => GetFinalBossResistance(effectType),
            _ => 1.0f
        };
    }

    private float GetTimeConstructResistance(TimeEffectType type)
    {
        // 时间构造体: 减速50%, 停止免疫, 裂隙50%
        return type switch
        {
            TimeEffectType.Slow => 0.5f,
            TimeEffectType.Stop => 0f,      // 免疫
            TimeEffectType.Rift => 0.5f,
            _ => 0.5f
        };
    }

    private float GetTimeWalkerResistance(TimeEffectType type)
    {
        // 时间行者: 减速30%, 停止反弹25%, 裂隙0.5秒后适应
        return type switch
        {
            TimeEffectType.Slow => 0.3f,
            TimeEffectType.Stop => -1f,     // -1表示反弹(特殊处理)
            TimeEffectType.Rift => 0f,      // 0.5秒后适应=效果很快消失
            _ => 0.3f
        };
    }

    private float GetFinalBossResistance(TimeEffectType type)
    {
        // 最终Boss: 减速免疫, 停止免疫(1秒硬直), 裂隙免疫减速
        return type switch
        {
            TimeEffectType.Slow => 0f,
            TimeEffectType.Stop => 0f,
            TimeEffectType.Rift => 0f,
            _ => 0f
        };
    }

    // ── 标签辅助 ──
    public bool CompareTag(string tag) => gameObject.CompareTag(tag);
}

/// <summary>
/// 敌人时间抗性7级
/// 0=无抗性  1=轻微  2=中度  3=高度(精英)  4=时间构造体  5=时间行者  6=Boss  7=最终Boss
/// </summary>
public enum TimeResistanceLevel
{
    None = 0,           // 减速100%, 停止100%, 裂隙100%
    Slight = 1,         // 减速80%, 停止80%, 裂隙80%
    Moderate = 2,       // 减速60%, 停止60%, 裂隙60%
    High = 3,           // 减速40%, 停止40%, 裂隙40% (精英)
    TimeConstruct = 4,  // 减速50%, 停止免疫, 裂隙50%
    TimeWalker = 5,     // 减速30%, 停止反弹25%, 裂隙0.5秒适应
    Boss = 6,           // 减速15%, 停止递减, 裂隙15%
    FinalBoss = 7       // 减速免疫, 停止1秒硬直, 裂隙免疫
}
```

---

## 2.6 武器-时间联动实现

### 2.6.1 IWeaponTimeResonance 接口

```text
public interface IWeaponTimeResonance
{
    WeaponType WeaponType { get; }
    bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill);
    void ExecuteResonance(PlayerController player, EnemyHealth target);
}
```

### 2.6.2 ChronoSlash（剑——时之斩击）

```text
public class ChronoSlash : IWeaponTimeResonance
{
    public WeaponType WeaponType => WeaponType.Sword;

    // ── 伤害/范围 ──
    private const float DAMAGE_MULTIPLIER = 1.8f;
    private const float CHRONOS_DAMAGE_MULT = 0.25f;   // 攻击力×25%时之附加
    private const float ARC_DEGREES = 120f;
    private const float RANGE = 3.5f;
    private const float RESIDUE_DURATION = 3f;          // 时之残痕持续3秒
    private const float RESIDUE_DAMAGE_MULT = 1.3f;     // 残痕标记伤害+30%

    // ── 帧数据 ──
    private const int WINDUP_FRAMES = 20;
    private const int ACTIVE_FRAMES = 3;
    private const int RECOVERY_FRAMES = 25;
    private const int CANCEL_WINDOW_START = 5;
    private const int CANCEL_WINDOW_END = 15;

    // ── 能量恢复 ──
    private const int KILL_ENERGY_BONUS = 12;  // 比普通击杀多4点

    public bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill)
    {
        // 条件1: 时间停止或加速状态中, 执行重攻击(长按≥0.3秒)
        if (activeTimeSkill == TimeSkillType.Stop || activeTimeSkill == TimeSkillType.Accelerate)
            return player.IsHeavyAttackCharged(0.3f);

        // 条件2: 完美格挡成功后1秒内按下攻击键
        if (player.IsWithinPerfectParryWindow(1f))
            return player.IsAttacking;

        return false;
    }

    public void ExecuteResonance(PlayerController player, EnemyHealth target)
    {
        float baseDamage = player.HeavyAttackDamage * DAMAGE_MULTIPLIER;
        float chronosDamage = player.AttackPower * CHRONOS_DAMAGE_MULT;
        Vector3 center = player.transform.position;
        Vector3 forward = player.transform.forward;

        // 扇形范围检测
        Collider[] hits = PhysicsQuery.OverlapSphere(center, RANGE, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            Vector3 dirToTarget = (hit.transform.position - center).normalized;
            float angle = Vector3.Angle(forward, dirToTarget);
            if (angle <= ARC_DEGREES * 0.5f)
            {
                var health = hit.GetComponent<EnemyHealth>();
                if (health != null)
                {
                    health.TakeDamage(baseDamage, DamageType.Physical);
                    health.TakeDamage(chronosDamage, DamageType.Chronos);

                    // 施加时之残痕
                    health.ApplyBuff(new ChronoResidueMark(RESIDUE_DURATION, RESIDUE_DAMAGE_MULT));
                }
            }
        }

        // VFX: 扇形蓝色斩击弧
        EffectManager.Play("ChronoSlash_Arc", center, forward, ARC_DEGREES, RANGE);
    }
}
```

### 2.6.3 ChronoArrow（弓——时之箭矢）

```text
public class ChronoArrow : IWeaponTimeResonance
{
    public WeaponType WeaponType => WeaponType.Bow;

    private const float DAMAGE_MULTIPLIER = 2.0f;
    private const float CHRONOS_DAMAGE_MULT = 0.35f;
    private const int MAX_PIERCE = 3;
    private const float PIERCE_DECAY = 0.7f;
    private const float ANCHOR_RADIUS = 2f;
    private const float ANCHOR_DURATION = 3f;
    private const float ANCHOR_SLOW = 0.4f;
    private const int MAX_ANCHORS = 3;

    // 蓄力参数
    private const float CHARGE_TIME = 1.2f;          // 72帧
    private const int PERFECT_WINDOW_HALF = 3;       // ±3帧
    private const int CHARGE_FRAMES = 72;
    private const int PERFECT_WINDOW_START = 72;
    private const int PERFECT_WINDOW_END = 78;

    public bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill)
    {
        // 条件1: 蓄力完成瞬间(金色闪光窗口±6帧内)释放
        if (player.IsBowCharging)
        {
            int chargeFrame = player.BowChargeFrame;
            return chargeFrame >= PERFECT_WINDOW_START && chargeFrame <= PERFECT_WINDOW_END;
        }

        // 条件2: 在时间裂隙区域内蓄力射击
        if (activeTimeSkill == TimeSkillType.Rift && player.IsInRift)
            return player.IsBowFullyCharged;

        return false;
    }

    public void ExecuteResonance(PlayerController player, EnemyHealth target)
    {
        float baseDamage = player.ChargedArrowDamage * DAMAGE_MULTIPLIER;
        float chronosDamage = player.AttackPower * CHRONOS_DAMAGE_MULT;

        // 时之锚点
        if (target != null)
        {
            CreateTimeAnchor(target.transform.position);
        }

        // 箭矢穿透逻辑在ArrowProjectile中处理
        player.LaunchChronoArrow(baseDamage, chronosDamage, MAX_PIERCE, PIERCE_DECAY);
    }

    private void CreateTimeAnchor(Vector3 position)
    {
        // 同一时间最多3个锚点, 超出则最早消失
        var anchors = Object.FindObjectsOfType<TimeAnchor>();
        if (anchors.Length >= MAX_ANCHORS)
            anchors[0].gameObject.queue_free();

        var anchorObj = new Node("TimeAnchor");
        anchorObj.transform.position = position;
        var anchor = anchorObj.AddComponent<TimeAnchor>();
        anchor.Radius = ANCHOR_RADIUS;
        anchor.Duration = ANCHOR_DURATION;
        anchor.SlowAmount = ANCHOR_SLOW;
    }
}

public class TimeAnchor : Node
{
    public float Radius = 2f;
    public float Duration = 3f;
    public float SlowAmount = 0.4f;

    private void Update()
    {
        Duration -= Time.unscaledDeltaTime;
        if (Duration <= 0f) queue_free();

        // 锚点区域内敌人减速40%
        Collider[] hits = PhysicsQuery.OverlapSphere(transform.position, Radius, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var health = hit.GetComponent<EnemyHealth>();
            health?.ApplySlow(SlowAmount, Time.unscaledDeltaTime + 0.1f);
        }
    }
}
```

### 2.6.4 ChronoThrust（枪——时之突刺）

```text
public class ChronoThrust : IWeaponTimeResonance
{
    public WeaponType WeaponType => WeaponType.Spear;

    private const float DAMAGE_MULTIPLIER = 1.6f;
    private const float CHRONOS_DAMAGE_MULT = 0.20f;
    private const float ARMOR_PENETRATION = 0.3f;      // 无视30%防御
    private const int INERTIA_FRAMES = 5;
    private const float SHOCKWAVE_DAMAGE_MULT = 0.30f;
    private const float SHOCKWAVE_WIDTH = 1f;
    private const float SHOCKWAVE_DURATION = 0.5f;

    public bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill)
    {
        // 条件1: 冲刺攻击+冲刺开始后第8~14帧内精准按下攻击键
        if (player.IsDashing)
        {
            int dashFrame = player.DashFrame;
            return dashFrame >= 8 && dashFrame <= 14 && player.IsAttacking;
        }

        // 条件2: 时间加速状态下执行任意攻击
        if (activeTimeSkill == TimeSkillType.Accelerate)
            return player.IsAttacking;

        return false;
    }

    public void ExecuteResonance(PlayerController player, EnemyHealth target)
    {
        float baseDamage = player.DashAttackDamage * DAMAGE_MULTIPLIER;
        float chronosDamage = player.AttackPower * CHRONOS_DAMAGE_MULT;
        float shockwaveDamage = player.AttackPower * SHOCKWAVE_DAMAGE_MULT;

        // 突刺命中: 无视30%防御
        if (target != null)
        {
            target.TakeDamage(baseDamage, DamageType.Physical, ARMOR_PENETRATION);
            target.TakeDamage(chronosDamage, DamageType.Chronos);
        }

        // 时之惯性: 突刺后保持高速移动5帧
        player.MaintainDashMomentum(INERTIA_FRAMES);

        // 冲击波: 突刺路径两侧1m内
        Vector3 thrustDir = player.transform.forward;
        float thrustDist = player.DashDistance;
        CreateShockwaveAlongPath(player.transform.position, thrustDir, thrustDist, shockwaveDamage);
    }

    private void CreateShockwaveAlongPath(Vector3 start, Vector3 dir, float distance, float damage)
    {
        // 沿突刺路径生成冲击波(宽1m, 长distance), 持续0.5秒
        // 对两侧1m内敌人造成时之伤害
        Vector3 end = start + dir * distance;
        Collider[] hits = PhysicsQuery.OverlapCapsule(start, end, SHOCKWAVE_WIDTH, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var health = hit.GetComponent<EnemyHealth>();
            health?.TakeDamage(damage, DamageType.Chronos);
        }
    }
}
```

### 2.6.5 ChronoSpell（杖——时之法术）

```text
public class ChronoSpell : IWeaponTimeResonance
{
    public WeaponType WeaponType => WeaponType.Staff;

    private const float SPELL_DAMAGE_MULT = 1.5f;
    private const float SPLASH_RADIUS = 2.5f;
    private const float SPLASH_DAMAGE_MULT = 0.4f;
    private const float MARK_DURATION = 5f;
    private const float MARK_CHRONOS_BONUS = 0.25f;    // +25%时之伤害
    private const int MAX_MARK_STACKS = 3;
    private const int PERFECT_WINDOW_HALF = 4;         // ±4帧
    private const float CAST_SPEED_REDUCTION = 0.3f;    // 施法前摇-30%

    public bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill)
    {
        // 条件1: 法杖施法前摇最后一帧(完美施法窗口±4帧)使用时间技能
        if (player.IsCasting)
        {
            int castFrame = player.CastFrame;
            int totalCastFrames = player.TotalCastFrames;
            return math.Abs(castFrame - totalCastFrames) <= PERFECT_WINDOW_HALF
                   && player.IsTimeSkillInputActive;
        }

        // 条件2: 在时间裂隙内施法
        if (activeTimeSkill == TimeSkillType.Rift && player.IsInRift)
            return player.IsCasting;

        return false;
    }

    public void ExecuteResonance(PlayerController player, EnemyHealth target)
    {
        if (target == null) return;

        // 法术伤害×1.5
        float spellDamage = player.CurrentSpellDamage * SPELL_DAMAGE_MULT;
        target.TakeDamage(spellDamage, DamageType.Magical);

        // 时之溅射: 半径2.5m, 法术伤害×40%
        float splashDamage = spellDamage * SPLASH_DAMAGE_MULT;
        Collider[] splashHits = PhysicsQuery.OverlapSphere(target.transform.position, SPLASH_RADIUS, collision_mask.GetMask("Enemy"));
        foreach (var hit in splashHits)
        {
            if (hit.gameObject != target.gameObject)
            {
                var health = hit.GetComponent<EnemyHealth>();
                health?.TakeDamage(splashDamage, DamageType.Chronos);

                // 施加时之印记
                health.ApplyBuff(new ChronoMarkBuff(MARK_DURATION, MARK_CHRONOS_BONUS, MAX_MARK_STACKS));
            }
        }

        // 主目标也施加时之印记
        target.ApplyBuff(new ChronoMarkBuff(MARK_DURATION, MARK_CHRONOS_BONUS, MAX_MARK_STACKS));

        // 施法速度-30%
        player.ReduceCastTime(CAST_SPEED_REDUCTION);
    }
}
```

### 2.6.6 ChronoCombo（拳套——时之连击）

```text
public class ChronoCombo : IWeaponTimeResonance
{
    public WeaponType WeaponType => WeaponType.Gauntlet;

    private const float FINISH_DAMAGE_MULT = 2.2f;
    private const float CHRONOS_IMPACT_DAMAGE_MULT = 0.45f;
    private const float IMPACT_ARC = 90f;
    private const float IMPACT_RANGE = 2.5f;
    private const float ACCUMULATION_MAX = 10;
    private const float ACCUMULATION_DELAY_PER_STACK = 2f / 60f;  // +2帧/层
    private const float ACCUMULATION_BURST_DAMAGE_MULT = 1.0f;
    private const float ACCUMULATION_BURST_RADIUS = 2f;
    private const float ACCUMULATION_DECAY_TIME = 5f;
    private const int COMBO_WINDOW_FRAMES = 20;  // 连击窗口≤20帧

    public bool CheckTriggerCondition(PlayerController player, TimeSkillType? activeTimeSkill)
    {
        // 条件1: 5秒内完成完整连击(轻→轻→重), 每次间隔≤20帧
        if (player.CompletedComboSequence(WeaponType.Gauntlet, COMBO_WINDOW_FRAMES))
            return true;

        // 条件2: 时间加速状态下连续命中3次
        if (activeTimeSkill == TimeSkillType.Accelerate)
            return player.ConsecutiveHitCount >= 3;

        return false;
    }

    public void ExecuteResonance(PlayerController player, EnemyHealth target)
    {
        if (target == null) return;

        // 连击终结伤害: 重攻击×2.2
        float finishDamage = player.HeavyAttackDamage * FINISH_DAMAGE_MULT;
        target.TakeDamage(finishDamage, DamageType.Physical);

        // 时之冲击: 前方扇形90°半径2.5m
        float impactDamage = player.AttackPower * CHRONOS_IMPACT_DAMAGE_MULT;
        ApplyFanImpact(player, impactDamage);

        // 时之蓄积: 每次命中+1层
        var accum = target.GetComponent<ChronoAccumulation>();
        if (accum == null)
        {
            accum = target.gameObject.AddComponent<ChronoAccumulation>();
            accum.MaxStacks = (int)ACCUMULATION_MAX;
            accum.DelayPerStack = ACCUMULATION_DELAY_PER_STACK;
            accum.DecayTime = ACCUMULATION_DECAY_TIME;
        }
        accum.AddStack();

        // 10层蓄积+终结击触发蓄积爆发
        if (accum.CurrentStacks >= ACCUMULATION_MAX)
        {
            float burstDamage = player.AttackPower * ACCUMULATION_BURST_DAMAGE_MULT;
            Collider[] hits = PhysicsQuery.OverlapSphere(target.transform.position, ACCUMULATION_BURST_RADIUS, collision_mask.GetMask("Enemy"));
            foreach (var hit in hits)
            {
                hit.GetComponent<EnemyHealth>()?.TakeDamage(burstDamage, DamageType.Chronos);
            }
            accum.ResetStacks();
        }
    }

    private void ApplyFanImpact(PlayerController player, float damage)
    {
        Vector3 center = player.transform.position;
        Vector3 forward = player.transform.forward;
        Collider[] hits = PhysicsQuery.OverlapSphere(center, IMPACT_RANGE, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            Vector3 dir = (hit.transform.position - center).normalized;
            if (Vector3.Angle(forward, dir) <= IMPACT_ARC * 0.5f)
            {
                hit.GetComponent<EnemyHealth>()?.TakeDamage(damage, DamageType.Chronos);
            }
        }
    }
}
```

---

## 2.7 时间抗性系统

### 2.7.1 敌人7级抗性实现

抗性已在 `TimeEntity.GetTimeResistance()` 中实现(见2.5.2)。以下是完整的抗性对照表和Boss时间耐受值系统:

```text
/// <summary>
/// Boss时间耐受值管理器 - Boss每次被时间技能影响, 耐受值+1
/// 耐受值影响Boss对该时间技能的反应
/// 60秒未受时间技能影响, 耐受值-1(最低0); 阶段切换时重置为0
/// </summary>
public class BossTemporalTolerance : Node
{
     private int _toleranceValue;
    private float _lastAffectedTime;
    private const float DECAY_INTERVAL = 60f;

    public int ToleranceValue => _toleranceValue;

    public void OnTimeSkillAffected(TimeSkillType skillType)
    {
        _toleranceValue = math.Min(_toleranceValue + 1, 10);
        _lastAffectedTime = Time.unscaledTime;
    }

    public void OnPhaseTransition()
    {
        _toleranceValue = 0;
    }

    // ── 时间停止对Boss的效果 ──
    public float GetTimeStopDurationMultiplier()
    {
        return _toleranceValue switch
        {
            0 => 0.4f,   // 持续×0.4(1.2秒)
            1 => 0.2f,   // 持续×0.2(0.6秒)
            2 => 0.1f,   // 持续×0.1(0.3秒)
            _ => 0f       // 免疫(但0.2秒硬直)
        };
    }

    // ── 时间加速对Boss的效果 ──
    public float GetBossAttackSpeedBonus()
    {
        // Boss攻速随耐受值增加
        return _toleranceValue switch
        {
            0 => 0f,
            1 => 0.10f,  // +10%
            2 => 0.20f,  // +20%
            _ => 0.30f   // +30%
        };
    }

    // ── 时间裂隙对Boss的减速效果 ──
    public float GetRiftSlowMultiplier()
    {
        return _toleranceValue switch
        {
            0 => 0.3f,   // 减速×0.3
            1 => 0.15f,  // 减速×0.15
            2 => 0.05f,  // 减速×0.05
            _ => 0f       // 免疫(坍缩伤害×0.5)
        };
    }

    // ── 时间回溯对Boss的效果 ──
    public float GetRewindPenalty()
    {
        return _toleranceValue switch
        {
            0 => 0f,                      // 正常
            1 => 3f,                      // 3秒"时间预知"
            2 => 5f,                      // 5秒"时间预知"
            _ => 0.5f                     // 回溯时50%被时间锁定
        };
    }

    // ── 耐受值衰减 ──
    private void Update()
    {
        if (_toleranceValue > 0 && Time.unscaledTime - _lastAffectedTime > DECAY_INTERVAL)
        {
            _toleranceValue = math.Max(0, _toleranceValue - 1);
            _lastAffectedTime = Time.unscaledTime;
        }
    }
}
```

---

## 2.8 视觉效果实现

### 2.8.1 时停灰度+波纹 Shader（Viewport/CanvasItem Shader）

```hlsl
// Shader: Hidden/TimeStopPostProcess
Shader "Hidden/TimeStopPostProcess"
{
    Properties
    {
        _MainTex ("Source", 2D) = "white" {}
        _GrayscaleAmount ("Grayscale", Range(0,1)) = 0
        _BlueTint ("Blue Tint", Color) = (0.1, 0.2, 0.4, 0)
        _PulseCenter ("Pulse Center", Vector) = (0.5, 0.5, 0, 0)
        _PulseRadius ("Pulse Radius", Float) = 0
        _PulseWidth ("Pulse Width", Float) = 0.05
        _PulseAlpha ("Pulse Alpha", Range(0,1)) = 0
        _VignetteIntensity ("Vignette", Range(0,1)) = 0
    }

    SubShader
    {
        Tags { RenderType=Opaque RenderPipeline=UniversalPipeline }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            # Godot实现使用CanvasItem Shader或Viewport后处理，不依赖外部HLSL include

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float _GrayscaleAmount;
            float4 _BlueTint;
            float2 _PulseCenter;
            float _PulseRadius;
            float _PulseWidth;
            float _PulseAlpha;
            float _VignetteIntensity;

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = Node2DObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                // 灰度化: 饱和度降至30% + 蓝色色调
                half gray = dot(color.rgb, half3(0.299, 0.587, 0.114));
                half3 desaturated = lerp(color.rgb, gray.xxx, _GrayscaleAmount);
                desaturated = lerp(desaturated, desaturated * _BlueTint.rgb + _BlueTint.rgb * 0.3,
                                   _GrayscaleAmount * 0.5);

                // 脉冲波纹(从玩家位置扩散)
                float dist = distance(input.uv, _PulseCenter);
                float pulse = smoothstep(_PulseRadius - _PulseWidth, _PulseRadius, dist)
                            * smoothstep(_PulseRadius + _PulseWidth, _PulseRadius, dist);
                desaturated += pulse * _PulseAlpha * half3(1, 1, 1);

                // 能量预警晕影
                float2 uvCenter = input.uv - 0.5;
                float vignette = 1.0 - dot(uvCenter, uvCenter) * 2.0;
                vignette = saturate(vignette);
                desaturated *= lerp(1.0, vignette, _VignetteIntensity);

                color.rgb = desaturated;
                return color;
            }
            ENDHLSL
        }
    }
}
```

### 2.8.2 Post-Processing Volume 控制

```text
using Godot;
using Godot.Rendering;
using Godot.Rendering.Universal;

public class TimeStopPostProcess : Node
{
     private Volume _volume;
    private Material _material;

    // ── 目标值(由技能驱动) ──
    private float _targetGrayscale;
    private float _targetPulseRadius;
    private float _targetPulseAlpha;
    private float _targetVignette;
    private Vector2 _pulseCenterUV;

    // ── 过渡速度 ──
    private const float TRANSITION_SPEED = 8f;

    private void Awake()
    {
        _material = new Material(Shader.Find("Hidden/TimeStopPostProcess"));
    }

    public void OnTimeStopBegin(Vector3 worldPulseCenter)
    {
        _targetGrayscale = 0.7f;    // 饱和度降至30%
        _targetPulseAlpha = 0.6f;
        _targetVignette = 0f;

        // 世界坐标→UV
        _pulseCenterUV = WorldToScreenUV(worldPulseCenter);
        _targetPulseRadius = 0f;    // 从0开始扩散
    }

    public void OnTimeStopEnd()
    {
        _targetGrayscale = 0f;
        _targetPulseAlpha = 0f;
    }

    public void OnLowEnergyWarning(float energyPercent)
    {
        if (energyPercent < 0.2f)
            _targetVignette = math.Lerp(0.15f, 0f, energyPercent / 0.2f);
        else
            _targetVignette = 0f;
    }

    private void Update()
    {
        // 脉冲波纹扩散
        if (_targetPulseAlpha > 0.01f)
            _targetPulseRadius += Time.unscaledDeltaTime * 1.2f;

        // 平滑过渡
        _material.SetFloat("_GrayscaleAmount",
            math.Lerp(_material.GetFloat("_GrayscaleAmount"), _targetGrayscale, TRANSITION_SPEED * delta));
        _material.SetFloat("_PulseRadius", _targetPulseRadius);
        _material.SetFloat("_PulseAlpha",
            math.Lerp(_material.GetFloat("_PulseAlpha"), _targetPulseAlpha, TRANSITION_SPEED * delta));
        _material.SetVector("_PulseCenter", _pulseCenterUV);
        _material.SetFloat("_VignetteIntensity",
            math.Lerp(_material.GetFloat("_VignetteIntensity"), _targetVignette, TRANSITION_SPEED * delta));
    }

    private Vector2 WorldToScreenUV(Vector3 worldPos)
    {
        Vector3 screenPos = Camera.main.WorldToScreenPoint(worldPos);
        return new Vector2(screenPos.x / Screen.width, screenPos.y / Screen.height);
    }
}
```

### 2.8.3 裂隙视觉效果实现

```text
// 裂隙地面效果: 使用Projector组件(而非实时生成网格)
// 裂隙边缘: 单个环形Mesh + 扭曲Shader
public class RiftVisualController : Node
{
     private Projector _groundProjector;
     private MeshRenderer _edgeRing;
     private float _rotationSpeed = 180f; // 0.5转/秒

    private Material _groundMat;
    private Material _edgeMat;
    private float _currentRadius;

    public void Initialize(float radius)
    {
        _currentRadius = radius;
        _groundProjector.orthographicSize = radius;
        _groundProjector.farClipPlane = radius * 2f;
    }

    private void Update()
    {
        // 地面纹理旋转
        _groundMat?.SetFloat("_Rotation", runtime_time * _rotationSpeed * math.Deg2Rad);

        // 边缘环缩放
        _edgeRing.transform.localScale = Vector3.one * _currentRadius * 2f;

        // 后处理: 区域内色彩偏紫(饱和度+15%), 轻微鱼眼扭曲
    }
}
```

---

## 2.9 性能优化

### 2.9.1 TimeEffectRegistry 空间分区

```text
using System.Collections.Generic;
using Godot;

/// <summary>
/// 时间效果空间分区注册表
/// 使用2m×2m网格快速查询区域内的受影响实体
/// 典型场景60m×60m = 30×30 = 900格
/// </summary>
public class TimeEffectRegistry
{
    private readonly float _cellSize;
    private readonly Dictionary<int, List<TimeEntity>> _grid = new Dictionary<int, List<TimeEntity>>();

    public TimeEffectRegistry(float cellSize = 2f)
    {
        _cellSize = cellSize;
    }

    public void Register(TimeEntity entity)
    {
        int cellKey = GetCellKey(entity.transform.position);
        if (!_grid.TryGetValue(cellKey, out var list))
        {
            list = new List<TimeEntity>(4);
            _grid[cellKey] = list;
        }
        if (!list.Contains(entity))
            list.Add(entity);
    }

    public void Unregister(TimeEntity entity)
    {
        int cellKey = GetCellKey(entity.transform.position);
        if (_grid.TryGetValue(cellKey, out var list))
            list.Remove(entity);
    }

    public void UpdateEntityCell(TimeEntity entity, Vector3 oldPos, Vector3 newPos)
    {
        int oldKey = GetCellKey(oldPos);
        int newKey = GetCellKey(newPos);
        if (oldKey == newKey) return;

        if (_grid.TryGetValue(oldKey, out var oldList))
            oldList.Remove(entity);
        if (!_grid.TryGetValue(newKey, out var newList))
        {
            newList = new List<TimeEntity>(4);
            _grid[newKey] = newList;
        }
        newList.Add(entity);
    }

    /// <summary>
    /// 查询圆形范围内的所有TimeEntity
    /// </summary>
    public void QueryCircle(Vector3 center, float radius, System.Action<TimeEntity> callback)
    {
        int minCellX = math.FloorToInt((center.x - radius) / _cellSize);
        int maxCellX = math.FloorToInt((center.x + radius) / _cellSize);
        int minCellZ = math.FloorToInt((center.z - radius) / _cellSize);
        int maxCellZ = math.FloorToInt((center.z + radius) / _cellSize);
        float radiusSq = radius * radius;

        for (int x = minCellX; x <= maxCellX; x++)
        {
            for (int z = minCellZ; z <= maxCellZ; z++)
            {
                int key = GetCellKey(x, z);
                if (!_grid.TryGetValue(key, out var list)) continue;

                foreach (var entity in list)
                {
                    float distSq = (entity.transform.position - center).sqrMagnitude;
                    if (distSq <= radiusSq)
                        callback(entity);
                }
            }
        }
    }

    private int GetCellKey(Vector3 pos)
    {
        int x = math.FloorToInt(pos.x / _cellSize);
        int z = math.FloorToInt(pos.z / _cellSize);
        return GetCellKey(x, z);
    }

    private int GetCellKey(int x, int z) => (x << 16) | (z & 0xFFFF);
}
```

### 2.9.2 优化策略总览

| 优化项 | 策略 | 预期收益 |
|--------|------|----------|
| 快照内存 | 使用struct值类型+预分配Buff池(16槽) | 42快照≈8.4KB, 无GC |
| 时间缩放查询 | 空间分区(SpatialGrid 2m×2m)替代PhysicsQuery.OverlapSphere | 查询O(n)→O(√n) |
| 全局时停 | 维护IsGlobalTimeStopped标志, 各实体自行检查 | 避免遍历设置所有敌人 |
| 裂隙渲染 | Projector组件替代实时网格生成 | 3裂隙=3 Projector, GPU开销可控 |
| 加速拖尾 | TrailRenderer替代全屏MotionBlur后处理 | 像素级开销→顶点级开销 |
| 粒子缩放 | 缓存simulationSpeed, 仅值变化时更新 | 避免每帧创建GPUParticles2D process_material |
| 物理冻结 | PhysicsBody2D冻结替代Engine.time_scale | 不影响全局物理步进 |
| 帧率无关 | 所有时序用unscaledDeltaTime×LocalTimeScale | 30FPS/120FPS行为一致 |
| 回溯轨迹 | LineRenderer, 顶点数≤30, 简单Unlit材质 | 单次Draw Call |
| 调试工具 | Inspector显示LocalTimeScale, Gizmos画裂隙范围 | 开发期快速定位问题 |

---

## 2.10 测试计划

### 2.10.1 单元测试

| 测试ID | 测试内容 | 预期结果 |
|--------|---------|---------|
| T-E-01 | TimeEnergySystem.TrySpendEnergy 正常消耗 | 能量减少, 返回true |
| T-E-02 | 能量不足时TrySpendEnergy | 返回false, 能量不变 |
| T-E-03 | HasteMultiplier连续使用递增 | 第1次1.0→第2次1.2→第3次1.5→第4次1.8 |
| T-E-04 | 8秒后HasteMultiplier重置 | 连续技能间隔>8秒, 乘数回1.0 |
| T-E-05 | 击杀恢复衰减计算 | ≤2秒:1.0, 2~5秒线性降至0.6, >5秒:0.6 |
| T-E-06 | 完美操作Combo乘数 | <5:1.0, 5~14:1.2, 15~29:1.5, ≥30:2.0 |
| T-E-07 | CostReduction上限50% | 超过0.5后钳制 |
| T-E-08 | 能量硬顶200 | 任何增益不可超过200 |

### 2.10.2 集成测试

| 测试ID | 测试内容 | 预期结果 |
|--------|---------|---------|
| T-I-01 | TimeStop冻结所有TimeAffinity>0的敌人 | 敌人LocalTimeScale=0, 动画停止 |
| T-I-02 | TimeStop不影响TimeAffinity=0的实体 | 玩家正常行动 |
| T-I-03 | TimeRewind回溯到5秒前状态 | 位置/HP/能量/Buff正确恢复, Debuff清除 |
| T-I-04 | TimeRewind无可用快照时 | 返还50%能量, 不执行回溯 |
| T-I-05 | TimeAccelerate过载满自动退出 | 反噬硬直0.75秒, 不可使用时间技能 |
| T-I-06 | TimeAccelerate主动取消 | 冷却×0.6, Lv.3+额外无敌+伤害加成 |
| T-I-07 | TimeRift最大2个同屏 | 第3个裂隙替换最早的一个 |
| T-I-08 | TimeRift坍缩伤害 | 攻击力×80%范围伤害+减速30%×2秒 |
| T-I-09 | SnapshotBuffer环形覆盖 | 超过capacity后旧快照被新快照覆盖 |
| T-I-10 | 7级抗性正确生效 | 各级抗性对Stop/Slow/Rift效果正确缩放 |

### 2.10.3 性能测试

| 测试ID | 测试内容 | 通过标准 |
|--------|---------|---------|
| T-P-01 | 时间停止(20个敌人)帧率 | ≥55 FPS |
| T-P-02 | 2个裂隙同屏帧率 | ≥55 FPS |
| T-P-03 | 时间加速+10个粒子系统 | ≥55 FPS |
| T-P-04 | 回溯快照采集42帧无GC | 零GC分配 |
| T-P-05 | 空间分区查询100实体 | ≤0.5ms/帧 |
| T-P-06 | 30FPS/120FPS帧率无关一致性 | 伤害/冷却/时间结果在±5%内 |

### 2.10.4 游戏性测试

| 测试ID | 测试内容 | 验证目标 |
|--------|---------|---------|
| T-G-01 | 剑时之斩击延长TimeStop | 每命中1次+0.5秒, 最多延长3秒 |
| T-G-02 | 弓时之箭矢锚点引爆combo | 残影经过锚点, 锚点爆散攻击力×50% |
| T-G-03 | 枪时之突刺穿裂隙加成 | 穿过裂隙: 距离+3m, 伤害+25% |
| T-G-04 | 杖时之印记3层引爆 | 3层印记+40%时之伤害 |
| T-G-05 | 拳套蓄积10层爆发 | 蓄积爆发: 攻击力×100% AOE |
| T-G-06 | Boss耐受值递减效果 | 每次TimeStop效果递减直至免疫 |
| T-G-07 | 时间行者反弹TimeStop | 25%概率反弹, 玩家减速50%×1.5秒 |
| T-G-08 | 四技能组合效果(8种组合) | 每种组合效果按设计文档正确触发 |

---

*文档版本: v1.0 | 最后更新: 2026-04-22*
