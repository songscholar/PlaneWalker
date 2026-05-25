# 03 敌人与Boss系统开发文档

> **引擎**: Godot 4.x  
> **架构依赖**: EventBus Autoload, ServiceRegistry, StateMachine, Registry  
> **基准帧率**: 60FPS, 所有帧数以秒存储  
> **单位基准**: 1格 = 1世界单位, 玩家基准移速 = 5.0格/秒  
> **版本**: v1.0  

> **Godot迁移约束**：敌人/Boss实体使用 `CharacterBody2D`、`Area2D` 和 `NavigationAgent2D`；敌人/Boss静态数据使用 Resource(`.tres`)。`EnemyData` / `BossData` 实现为 `extends Resource`。

---

## 3.1 敌人系统架构

### 3.1.1 架构总览

```
┌───────────────────────────────────────────────────────────┐
│                    Enemy System Architecture               │
├───────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────┐   ┌──────────────┐   ┌───────────┐ │
│  │ EnemySpawner    │──▶│ EnemyFactory │──▶│ EnemyData │ │
│  │ (生成+难度缩放) │   │ (对象池)     │   │ (SO配置) │ │
│  └─────────────────┘   └──────────────┘   └───────────┘ │
│          │                                                 │
│          ▼                                                 │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ EnemyController                                     │ │
│  │  ├─ EnemyFSM (6态状态机)                            │ │
│  │  │   ├─ PatrolState                                │ │
│  │  │   ├─ AlertState                                 │ │
│  │  │   ├─ ChaseState                                 │ │
│  │  │   ├─ AttackState                                │ │
│  │  │   ├─ RetreatState                               │ │
│  │  │   └─ DeathState                                 │ │
│  │  ├─ EnemyHealth                                    │ │
│  │  ├─ EnemyMovement                                  │ │
│  │  ├─ TimeEntity (时间缩放)                           │ │
│  │  ├─ EliteModifier[] (词缀系统)                      │ │
│  │  └─ AttackExecutor[] (攻击执行器)                    │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ BossController                                     │ │
│  │  ├─ BossPhaseManager (多阶段管理)                   │ │
│  │  ├─ BossAttackSelector (权重招式选择)               │ │
│  │  ├─ BossAttackExecutor (帧序列执行)                  │ │
│  │  ├─ BossTemporalTolerance (时间耐受)                  │ │
│  │  └─ BossEnrageSystem (狂暴系统)                      │ │
│  └─────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

---

## 3.2 AI状态机实现

### 3.2.1 EnemyState 枚举与 FSM 核心

```text
using System;
using System.Collections.Generic;
using Godot;

public enum EnemyState
{
    PATROL,
    ALERT,
    CHASE,
    ATTACK,
    RETREAT,
    DEATH
}

public class EnemyFSM
{
    private readonly Dictionary<EnemyState, IEnemyState> _states = new Dictionary<EnemyState, IEnemyState>();
    private IEnemyState _currentState;
    private EnemyState _currentStateType;
    private readonly EnemyController _owner;

    public EnemyState CurrentStateType => _currentStateType;
    public IEnemyState CurrentState => _currentState;

    public event Action<EnemyState, EnemyState> OnStateChanged;

    public EnemyFSM(EnemyController owner)
    {
        _owner = owner;
    }

    public void RegisterState(EnemyState type, IEnemyState state)
    {
        _states[type] = state;
    }

    public void TransitionTo(EnemyState newState)
    {
        if (newState == _currentStateType && _currentState != null) return;

        EnemyState oldState = _currentStateType;
        _currentState?.OnExit(_owner);
        _currentStateType = newState;

        if (_states.TryGetValue(newState, out var state))
        {
            _currentState = state;
            _currentState.OnEnter(_owner);
        }
        else
        {
            Debug.LogError($"State {newState} not registered on {_owner.name}");
            _currentState = null;
        }

        OnStateChanged?.Invoke(oldState, newState);
    }

    public void Update(float deltaTime)
    {
        _currentState?.OnUpdate(_owner, deltaTime);
    }

    public void FixedUpdate(float deltaTime)
    {
        _currentState?.OnFixedUpdate(_owner, deltaTime);
    }
}
```

### 3.2.2 IEnemyState 接口

```text
public interface IEnemyState
{
    void OnEnter(EnemyController owner);
    void OnUpdate(EnemyController owner, float deltaTime);
    void OnFixedUpdate(EnemyController owner, float deltaTime);
    void OnExit(EnemyController owner);
}
```

### 3.2.3 六态完整实现

```text
// ═══════════════════════════════════════════
// PATROL 状态
// ═══════════════════════════════════════════
public class PatrolState : IEnemyState
{
    private float _patrolTimer;
    private Vector3 _patrolTarget;
    private bool _isStationary;

    public void OnEnter(EnemyController owner)
    {
        _patrolTimer = 0f;
        _isStationary = owner.Data.moveSpeed <= 0.01f;

        if (!_isStationary)
        {
            _patrolTarget = owner.GetNextPatrolPoint();
            owner.NavAgent.SetDestination(_patrolTarget);
        }

        owner.animation_player.SetBool("IsPatrolling", true);
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        float scaledDelta = owner.ScaledDeltaTime;

        // 检测玩家
        float distToPlayer = owner.GetDistanceToPlayer();
        if (distToPlayer <= owner.Data.detectRange && owner.HasLineOfSightToPlayer())
        {
            owner.FSM.TransitionTo(EnemyState.ALERT);
            return;
        }

        if (_isStationary)
        {
            // 固定位置敌人: 缓慢转向随机方向
            _patrolTimer += scaledDelta;
            if (_patrolTimer >= 3f)
            {
                _patrolTimer = 0f;
                float randomY = owner.transform.eulerAngles.y + Godot.Random.Range(-90f, 90f);
                owner.transform.rotation = Quaternion.Euler(0f, randomY, 0f);
            }
        }
        else
        {
            // 巡逻路径移动
            if (owner.NavAgent.remainingDistance <= 0.5f)
            {
                _patrolTarget = owner.GetNextPatrolPoint();
                owner.NavAgent.SetDestination(_patrolTarget);
            }
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner)
    {
        owner.animation_player.SetBool("IsPatrolling", false);
        if (owner.NavAgent.isOnNavMesh)
            owner.NavAgent.isStopped = true;
    }
}

// ═══════════════════════════════════════════
// ALERT 状态
// ═══════════════════════════════════════════
public class AlertState : IEnemyState
{
    private float _alertTimer;

    public void OnEnter(EnemyController owner)
    {
        _alertTimer = owner.Data.alertDuration; // 0.3~0.6秒
        owner.FacePlayer();
        owner.animation_player.SetTrigger("Alert");
        owner.PlayAlertVFX(); // 头顶感叹号特效
        owner.NavAgent.isStopped = true;
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        float scaledDelta = owner.ScaledDeltaTime;
        _alertTimer -= scaledDelta;

        // 持续面朝玩家
        owner.FacePlayer();

        // 脱离检测
        float distToPlayer = owner.GetDistanceToPlayer();
        if (distToPlayer > owner.Data.detectRange * 1.5f)
        {
            owner.FSM.TransitionTo(EnemyState.PATROL);
            return;
        }

        // 警戒结束→追击
        if (_alertTimer <= 0f)
        {
            owner.FSM.TransitionTo(EnemyState.CHASE);
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// CHASE 状态
// ═══════════════════════════════════════════
public class ChaseState : IEnemyState
{
    public void OnEnter(EnemyController owner)
    {
        owner.NavAgent.isStopped = false;
        owner.NavAgent.speed = owner.Data.moveSpeed;
        owner.NavAgent.SetDestination(owner.PlayerPosition);
        owner.animation_player.SetBool("IsChasing", true);
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        float scaledDelta = owner.ScaledDeltaTime;

        // 更新目标位置
        owner.NavAgent.SetDestination(owner.PlayerPosition);

        // 攻击范围检测
        float distToPlayer = owner.GetDistanceToPlayer();
        if (distToPlayer <= owner.Data.atkRange)
        {
            owner.FSM.TransitionTo(EnemyState.ATTACK);
            return;
        }

        // 脱离检测
        if (distToPlayer > owner.Data.detectRange * 1.5f)
        {
            owner.FSM.TransitionTo(EnemyState.PATROL);
            return;
        }

        // 远程敌人: 距离维持逻辑
        if (owner.IsRangedType && distToPlayer < owner.PreferredMinDistance)
        {
            owner.MoveAwayFromPlayer(owner.Data.moveSpeed * 1.3f);
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner)
    {
        owner.animation_player.SetBool("IsChasing", false);
        owner.NavAgent.isStopped = true;
    }
}

// ═══════════════════════════════════════════
// ATTACK 状态
// ═══════════════════════════════════════════
public class AttackState : IEnemyState
{
    private int _selectedAttackIndex = -1;
    private AttackPhase _phase;
    private float _phaseTimer;
    private AttackPatternData _currentPattern;

    private enum AttackPhase
    {
        Windup,
        Active,
        Recovery,
        Done
    }

    public void OnEnter(EnemyController owner)
    {
        _selectedAttackIndex = owner.SelectAttackPattern();
        if (_selectedAttackIndex < 0 || _selectedAttackIndex >= owner.Data.attackPatterns.Length)
        {
            owner.FSM.TransitionTo(EnemyState.RETREAT);
            return;
        }

        _currentPattern = owner.Data.attackPatterns[_selectedAttackIndex];
        _phase = AttackPhase.Windup;
        _phaseTimer = _currentPattern.windupSeconds;

        // 面朝玩家
        owner.FacePlayer();

        // 播放前摇动画
        owner.animation_player.SetTrigger(_currentPattern.animationTrigger);
        owner.animation_player.SetFloat("AttackSpeed", 1f);
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        float scaledDelta = owner.ScaledDeltaTime;

        switch (_phase)
        {
            case AttackPhase.Windup:
                _phaseTimer -= scaledDelta;
                if (_phaseTimer <= 0f)
                {
                    _phase = AttackPhase.Active;
                    _phaseTimer = _currentPattern.activeSeconds;
                    owner.OnAttackActiveBegin(_currentPattern);
                }
                break;

            case AttackPhase.Active:
                _phaseTimer -= scaledDelta;
                owner.OnAttackActiveUpdate(_currentPattern, scaledDelta);

                if (_phaseTimer <= 0f)
                {
                    _phase = AttackPhase.Recovery;
                    _phaseTimer = _currentPattern.recoverySeconds;
                    owner.OnAttackActiveEnd(_currentPattern);
                }
                break;

            case AttackPhase.Recovery:
                _phaseTimer -= scaledDelta;
                if (_phaseTimer <= 0f)
                {
                    _phase = AttackPhase.Done;
                }
                break;

            case AttackPhase.Done:
                // 设置攻击冷却
                owner.SetAttackCooldown(_selectedAttackIndex, _currentPattern.cooldownSeconds);

                // 决定下一步
                bool shouldRetreat = owner.Data.retreatAfterAttack;
                if (shouldRetreat)
                    owner.FSM.TransitionTo(EnemyState.RETREAT);
                else
                    owner.FSM.TransitionTo(EnemyState.CHASE);
                break;
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// RETREAT 状态
// ═══════════════════════════════════════════
public class RetreatState : IEnemyState
{
    private float _retreatTimer;
    private Vector3 _retreatTarget;

    public void OnEnter(EnemyController owner)
    {
        _retreatTimer = owner.Data.retreatDuration;
        Vector3 awayDir = (owner.transform.position - owner.PlayerPosition).normalized;
        _retreatTarget = owner.transform.position + awayDir * owner.Data.retreatDistance;
        owner.NavAgent.isStopped = false;
        owner.NavAgent.speed = owner.Data.moveSpeed * 0.6f;
        owner.NavAgent.SetDestination(_retreatTarget);
        owner.animation_player.SetBool("IsRetreating", true);
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        float scaledDelta = owner.ScaledDeltaTime;
        _retreatTimer -= scaledDelta;

        if (_retreatTimer <= 0f || owner.NavAgent.remainingDistance <= 0.3f)
        {
            owner.FSM.TransitionTo(EnemyState.CHASE);
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner)
    {
        owner.animation_player.SetBool("IsRetreating", false);
        owner.NavAgent.isStopped = true;
    }
}

// ═══════════════════════════════════════════
// DEATH 状态
// ═══════════════════════════════════════════
public class DeathState : IEnemyState
{
    private float _deathTimer;
    private bool _hasTriggeredRewind;

    public void OnEnter(EnemyController owner)
    {
        _deathTimer = owner.Data.deathDuration; // 0.4~1.0秒
        _hasTriggeredRewind = false;

        owner.NavAgent.isStopped = true;
        owner.Collider.enabled = false;
        owner.animation_player.SetTrigger("Death");

        // 特殊: 时间守卫回溯检查
        var timeGuard = owner.GetComponent<TimeGuardRewind>();
        if (timeGuard != null && !timeGuard.HasRewound)
        {
            _hasTriggeredRewind = true;
            timeGuard.TriggerRewind();
            return; // 不执行死亡, 回溯后重新进入战斗
        }

        // 永恒猎犬重生检查
        var hound = owner.GetComponent<EternalHoundRespawn>();
        if (hound != null && !hound.HasRespawned)
        {
            _hasTriggeredRewind = true;
            hound.StartRespawn();
            return;
        }

        // 精英词缀: 分裂
        owner.ApplyDeathModifiers();

        // 通知击杀事件
        EventBus.Publish(new EnemyDeathEvent { Enemy = owner });
    }

    public void OnUpdate(EnemyController owner, float deltaTime)
    {
        if (_hasTriggeredRewind) return;

        _deathTimer -= Time.unscaledDeltaTime;
        if (_deathTimer <= 0f)
        {
            // 死亡爆炸效果(腐蚀飞虫等)
            owner.PlayDeathEffect();

            // 掉落物品
            owner.DropLoot();

            // 归还对象池
            EnemyFactory.Instance.Return(owner);
        }
    }

    public void OnFixedUpdate(EnemyController owner, float deltaTime) { }
    public void OnExit(EnemyController owner) { }
}
```

### 3.2.4 EnemyController 核心

```text
using Godot;
using Godot.AI;

[RequireComponent(typeof(NavMeshAgent), typeof(AnimationPlayer或AnimationTree), typeof(TimeEntity))]
public class EnemyController : Node
{
     private EnemyData _data;
    public EnemyData Data => _data;

    // ── 组件引用 ──
    public NavMeshAgent NavAgent { get; private set; }
    public AnimationPlayer或AnimationTree AnimationPlayer或AnimationTree { get; private set; }
    public Collider Collider { get; private set; }
    public EnemyHealth Health { get; private set; }
    public TimeEntity TimeEntity { get; private set; }

    // ── FSM ──
    public EnemyFSM FSM { get; private set; }

    // ── 精英词缀 ──
    private List<EliteModifier> _eliteModifiers = new List<EliteModifier>(2);
    public IReadOnlyList<EliteModifier> EliteModifiers => _eliteModifiers;
    public bool IsElite => _eliteModifiers.Count > 0;
    public bool IsBoss => _data.isBoss;

    // ── 攻击冷却 ──
    private float[] _attackCooldowns;

    // ── 时间缩放 ──
    public float ScaledDeltaTime => TimeEntity?.ScaledDeltaTime ?? delta;

    // ── 玩家引用 ──
    public Vector3 PlayerPosition => PlayerController.Instance?.transform.position ?? Vector3.zero;

    // ── 远程类型标记 ──
    public bool IsRangedType => _data.isRangedType;
    public float PreferredMinDistance => _data.preferredMinDistance;

    // ── 仇恨覆盖(用于时间回溯残影吸引) ──
    private float _overrideTargetTimer;
    private Node _overrideTarget;
    public Node OverrideTarget => _overrideTargetTimer > 0 ? _overrideTarget : null;

    private void Awake()
    {
        NavAgent = GetComponent<NavMeshAgent>();
        AnimationPlayer或AnimationTree = GetComponent<AnimationPlayer或AnimationTree>();
        Collider = GetComponent<Collider>();
        Health = GetComponent<EnemyHealth>();
        TimeEntity = GetComponent<TimeEntity>();

        FSM = new EnemyFSM(this);
        FSM.RegisterState(EnemyState.PATROL, new PatrolState());
        FSM.RegisterState(EnemyState.ALERT, new AlertState());
        FSM.RegisterState(EnemyState.CHASE, new ChaseState());
        FSM.RegisterState(EnemyState.ATTACK, new AttackState());
        FSM.RegisterState(EnemyState.RETREAT, new RetreatState());
        FSM.RegisterState(EnemyState.DEATH, new DeathState());
    }

    public void Initialize(EnemyData data, DifficultyScaling scaling)
    {
        _data = data;
        ApplyDifficultyScaling(scaling);

        _attackCooldowns = new float[data.attackPatterns?.Length ?? 0];
        for (int i = 0; i < _attackCooldowns.Length; i++)
            _attackCooldowns[i] = 0f;

        Health.Initialize(_data.hp, _data.staggerResist);
        NavAgent.speed = _data.moveSpeed;
        TimeEntity.TimeAffinity = _data.timeAffinity;
        TimeEntity.SetResistanceLevel(_data.resistanceLevel);

        FSM.TransitionTo(EnemyState.PATROL);
    }

    private void Update()
    {
        float scaledDelta = ScaledDeltaTime;

        // 更新攻击冷却
        for (int i = 0; i < _attackCooldowns.Length; i++)
            _attackCooldowns[i] -= scaledDelta;

        // 更新仇恨覆盖
        if (_overrideTargetTimer > 0)
            _overrideTargetTimer -= Time.unscaledDeltaTime;

        // FSM更新
        FSM.Update(scaledDelta);

        // 精英词缀更新
        foreach (var mod in _eliteModifiers)
            mod.OnUpdate(this, scaledDelta);
    }

    // ── 攻击模式选择 ──
    public int SelectAttackPattern()
    {
        if (_data.attackPatterns == null || _data.attackPatterns.Length == 0) return -1;

        float dist = GetDistanceToPlayer();
        float bestWeight = -1f;
        int bestIndex = 0;

        for (int i = 0; i < _data.attackPatterns.Length; i++)
        {
            var pattern = _data.attackPatterns[i];
            if (_attackCooldowns[i] > 0f) continue;
            if (dist < pattern.minRange || dist > pattern.maxRange) continue;

            float weight = pattern.selectionWeight;
            if (weight > bestWeight)
            {
                bestWeight = weight;
                bestIndex = i;
            }
        }

        return bestWeight > 0f ? bestIndex : -1;
    }

    public void SetAttackCooldown(int index, float cooldown)
    {
        if (index >= 0 && index < _attackCooldowns.Length)
            _attackCooldowns[index] = cooldown;
    }

    // ── 攻击执行回调 ──
    public void OnAttackActiveBegin(AttackPatternData pattern)
    {
        // 启用伤害判定
        AttackExecutor.Execute(pattern, this);
    }

    public void OnAttackActiveUpdate(AttackPatternData pattern, float deltaTime) { }
    public void OnAttackActiveEnd(AttackPatternData pattern)
    {
        // 关闭伤害判定
    }

    // ── 工具方法 ──
    public float GetDistanceToPlayer()
    {
        return Vector3.Distance(transform.position, PlayerPosition);
    }

    public bool HasLineOfSightToPlayer()
    {
        Vector3 dir = PlayerPosition - transform.position;
        return !PhysicsQuery.Raycast(transform.position + Vector3.up * 0.5f, dir.normalized, dir.magnitude,
            collision_mask.GetMask("Obstacle"));
    }

    public void FacePlayer()
    {
        Vector3 dir = (PlayerPosition - transform.position);
        dir.y = 0f;
        if (dir.sqrMagnitude > 0.01f)
            transform.rotation = Quaternion.LookRotation(dir);
    }

    public void MoveAwayFromPlayer(float speed)
    {
        Vector3 away = (transform.position - PlayerPosition).normalized;
        transform.position += away * speed * ScaledDeltaTime;
    }

    public void OverrideTarget(Node target, float duration)
    {
        _overrideTarget = target;
        _overrideTargetTimer = duration;
    }

    public Vector3 GetNextPatrolPoint()
    {
        Vector3 randomOffset = Godot.Random.insideUnitSphere * 3f;
        randomOffset.y = 0f;
        return transform.position + randomOffset;
    }

    // ── 精英化 ──
    public void ApplyEliteTemplate(EliteModifier[] modifiers)
    {
        _data.hp *= 3f;
        _data.atk *= 1.5f;
        transform.localScale *= 1.15f;

        foreach (var mod in modifiers)
        {
            _eliteModifiers.Add(mod);
            mod.OnApply(this);
        }
    }

    public void ApplyDeathModifiers()
    {
        foreach (var mod in _eliteModifiers)
            mod.OnDeath(this);
    }

    // ── 难度缩放 ──
    private void ApplyDifficultyScaling(DifficultyScaling scaling)
    {
        _data.hp *= scaling.hpMultiplier * scaling.roomHpMultiplier * scaling.urgencyMultiplier;
        _data.atk *= scaling.atkMultiplier * scaling.roomAtkMultiplier * scaling.urgencyMultiplier;
    }

    // ── 掉落 ──
    public void DropLoot() { /* 由LootTable驱动 */ }
    public void PlayAlertVFX() { /* 头顶感叹号 */ }
    public void PlayDeathEffect() { /* 碎裂/爆炸粒子 */ }
}
```

---

## 3.3 敌人行为树节点

### 3.3.1 行为树基础设施

```text
public enum NodeStatus { Success, Failure, Running }

public abstract class BTNode
{
    public abstract NodeStatus Execute(EnemyController owner, float deltaTime);
}

public abstract class BTComposite : BTNode
{
    protected List<BTNode> children = new List<BTNode>();
    public void AddChild(BTNode child) => children.Add(child);
}

public abstract class BTDecorator : BTNode
{
    protected BTNode child;
    public BTDecorator(BTNode child) => this.child = child;
}
```

### 3.3.2 常用行为节点

```text
// ═══════════════════════════════════════════
// 选择器(Selector): 任一子节点成功则成功
// ═══════════════════════════════════════════
public class BTSelector : BTComposite
{
    private int _currentIndex;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        while (_currentIndex < children.Count)
        {
            var status = children[_currentIndex].Execute(owner, deltaTime);
            if (status == NodeStatus.Success) { _currentIndex = 0; return NodeStatus.Success; }
            if (status == NodeStatus.Running) return NodeStatus.Running;
            _currentIndex++;
        }
        _currentIndex = 0;
        return NodeStatus.Failure;
    }
}

// ═══════════════════════════════════════════
// 序列(Sequence): 所有子节点成功则成功
// ═══════════════════════════════════════════
public class BTSequence : BTComposite
{
    private int _currentIndex;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        while (_currentIndex < children.Count)
        {
            var status = children[_currentIndex].Execute(owner, deltaTime);
            if (status == NodeStatus.Failure) { _currentIndex = 0; return NodeStatus.Failure; }
            if (status == NodeStatus.Running) return NodeStatus.Running;
            _currentIndex++;
        }
        _currentIndex = 0;
        return NodeStatus.Success;
    }
}

// ═══════════════════════════════════════════
// 条件节点: 玩家在攻击范围内
// ═══════════════════════════════════════════
public class BTIsPlayerInAttackRange : BTNode
{
    private readonly float _range;

    public BTIsPlayerInAttackRange(float range) => _range = range;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        return owner.GetDistanceToPlayer() <= _range ? NodeStatus.Success : NodeStatus.Failure;
    }
}

// ═══════════════════════════════════════════
// 条件节点: 玩家在检测范围内
// ═══════════════════════════════════════════
public class BTIsPlayerInDetectRange : BTNode
{
    private readonly float _range;

    public BTIsPlayerInDetectRange(float range) => _range = range;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        float dist = owner.GetDistanceToPlayer();
        return dist <= _range && owner.HasLineOfSightToPlayer() ? NodeStatus.Success : NodeStatus.Failure;
    }
}

// ═══════════════════════════════════════════
// 条件节点: 冷却已就绪
// ═══════════════════════════════════════════
public class BTIsCooldownReady : BTNode
{
    private readonly int _attackIndex;
    private readonly float _cooldown;

    public BTIsCooldownReady(int attackIndex, float cooldown)
    {
        _attackIndex = attackIndex;
        _cooldown = cooldown;
    }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        return NodeStatus.Success; // 由EnemyController._attackCooldowns管理
    }
}

// ═══════════════════════════════════════════
// 条件节点: HP低于阈值
// ═══════════════════════════════════════════
public class BTHpBelowThreshold : BTNode
{
    private readonly float _threshold; // 0~1

    public BTHpBelowThreshold(float threshold) => _threshold = threshold;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        return owner.Health.HpPercent <= _threshold ? NodeStatus.Success : NodeStatus.Failure;
    }
}

// ═══════════════════════════════════════════
// 行动节点: 移动到玩家位置
// ═══════════════════════════════════════════
public class BTMoveToPlayer : BTNode
{
    private readonly float _speed;
    private readonly float _arrivalDistance;

    public BTMoveToPlayer(float speed, float arrivalDistance = 0.5f)
    {
        _speed = speed;
        _arrivalDistance = arrivalDistance;
    }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        float dist = owner.GetDistanceToPlayer();
        if (dist <= _arrivalDistance) return NodeStatus.Success;

        owner.NavAgent.speed = _speed;
        owner.NavAgent.SetDestination(owner.PlayerPosition);
        owner.NavAgent.isStopped = false;
        return NodeStatus.Running;
    }
}

// ═══════════════════════════════════════════
// 行动节点: 保持与玩家距离
// ═══════════════════════════════════════════
public class BTMaintainDistance : BTNode
{
    private readonly float _minDist;
    private readonly float _maxDist;
    private readonly float _moveSpeed;

    public BTMaintainDistance(float minDist, float maxDist, float moveSpeed)
    {
        _minDist = minDist;
        _maxDist = maxDist;
        _moveSpeed = moveSpeed;
    }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        float dist = owner.GetDistanceToPlayer();
        if (dist < _minDist)
        {
            owner.MoveAwayFromPlayer(_moveSpeed * 1.3f);
            return NodeStatus.Running;
        }
        if (dist > _maxDist)
        {
            owner.NavAgent.speed = _moveSpeed;
            owner.NavAgent.SetDestination(owner.PlayerPosition);
            return NodeStatus.Running;
        }
        return NodeStatus.Success;
    }
}

// ═══════════════════════════════════════════
// 行动节点: 执行攻击
// ═══════════════════════════════════════════
public class BTExecuteAttack : BTNode
{
    private readonly int _attackIndex;
    private bool _isExecuting;

    public BTExecuteAttack(int attackIndex) => _attackIndex = attackIndex;

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        if (!_isExecuting)
        {
            _isExecuting = true;
            owner.FSM.TransitionTo(EnemyState.ATTACK);
            return NodeStatus.Running;
        }

        // 等待攻击完成
        if (owner.FSM.CurrentStateType == EnemyState.ATTACK)
            return NodeStatus.Running;

        _isExecuting = false;
        return NodeStatus.Success;
    }
}

// ═══════════════════════════════════════════
// 行动节点: 闪现/瞬移(闪断者等)
// ═══════════════════════════════════════════
public class BTBlinkToPosition : BTNode
{
    private readonly float _range;
    private readonly float _cooldown;
    private float _cooldownTimer;

    public BTBlinkToPosition(float range, float cooldown)
    {
        _range = range;
        _cooldown = cooldown;
    }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        _cooldownTimer -= deltaTime;
        if (_cooldownTimer > 0f) return NodeStatus.Failure;

        // 计算目标位置(玩家附近)
        Vector3 offset = Godot.Random.onUnitSphere * _range;
        offset.y = 0f;
        Vector3 target = owner.PlayerPosition + offset;

        // 执行闪现
        owner.transform.position = target;
        _cooldownTimer = _cooldown;
        return NodeStatus.Success;
    }
}

// ═══════════════════════════════════════════
// 装饰器: 反转结果
// ═══════════════════════════════════════════
public class BTInverter : BTDecorator
{
    public BTInverter(BTNode child) : base(child) { }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        var status = child.Execute(owner, deltaTime);
        return status switch
        {
            NodeStatus.Success => NodeStatus.Failure,
            NodeStatus.Failure => NodeStatus.Success,
            _ => NodeStatus.Running
        };
    }
}

// ═══════════════════════════════════════════
// 装饰器: 重复直到失败
// ═══════════════════════════════════════════
public class BTRepeatUntilFail : BTDecorator
{
    public BTRepeatUntilFail(BTNode child) : base(child) { }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        var status = child.Execute(owner, deltaTime);
        if (status == NodeStatus.Failure) return NodeStatus.Failure;
        return NodeStatus.Running;
    }
}

// ═══════════════════════════════════════════
// 装饰器: 冷却门控
// ═══════════════════════════════════════════
public class BTCooldownGate : BTDecorator
{
    private readonly float _cooldown;
    private float _timer;

    public BTCooldownGate(BTNode child, float cooldown) : base(child)
    {
        _cooldown = cooldown;
    }

    public override NodeStatus Execute(EnemyController owner, float deltaTime)
    {
        _timer -= deltaTime;
        if (_timer > 0f) return NodeStatus.Failure;

        var status = child.Execute(owner, deltaTime);
        if (status == NodeStatus.Success || status == NodeStatus.Failure)
            _timer = _cooldown;
        return status;
    }
}
```

---

## 3.4 敌人生成系统

### 3.4.1 EnemySpawner

```text
using System.Collections.Generic;
using Godot;

public class EnemySpawner : Node
{
    [System.Serializable]
    public class SpawnWave
    {
        public string waveName;
        public EnemySpawnEntry[] entries;
        public float delayBeforeWave = 0f;
    }

    [System.Serializable]
    public class EnemySpawnEntry
    {
        public EnemyData enemyData;
        public int count = 1;
        public SpawnPointSelector selector = SpawnPointSelector.RoomEdge;
    }

    public enum SpawnPointSelector { RoomEdge, Random, PlayerFar }

     private SpawnWave[] _waves;
     private Node2D[] _spawnPoints;
     private bool _spawnOnRoomEnter = true;

    private int _currentWaveIndex;
    private List<EnemyController> _aliveEnemies = new List<EnemyController>(16);
    private DifficultyScaling _currentScaling;

    public event System.Action OnAllWavesComplete;
    public event System.Action<EnemyController> OnEnemySpawned;

    public void Initialize(DifficultyScaling scaling)
    {
        _currentScaling = scaling;
    }

    public void StartSpawning()
    {
        _currentWaveIndex = 0;
        SpawnWave(_currentWaveIndex);
    }

    private void SpawnWave(int waveIndex)
    {
        if (waveIndex >= _waves.Length)
        {
            OnAllWavesComplete?.Invoke();
            return;
        }

        var wave = _waves[waveIndex];

        foreach (var entry in wave.entries)
        {
            int actualCount = math.FloorToInt(entry.count * _currentScaling.countMultiplier);
            for (int i = 0; i < actualCount; i++)
            {
                Vector3 spawnPos = GetSpawnPosition(entry.selector);
                var enemy = EnemyFactory.Instance.Get(entry.enemyData, spawnPos, _currentScaling);
                _aliveEnemies.Add(enemy);

                // 精英化检查
                float eliteChance = _currentScaling.eliteChance;
                if (Random.value < eliteChance && enemy.Data.threatLevel >= 1 && !enemy.Data.isSummon && !enemy.Data.isBoss)
                {
                    ApplyEliteModification(enemy);
                }

                // 攻击频率初始偏移(防止同步攻击)
                enemy.SetAttackOffset(Random.Range(0f, 1.5f));

                OnEnemySpawned?.Invoke(enemy);
            }
        }
    }

    private void ApplyEliteModification(EnemyController enemy)
    {
        int layer = _currentScaling.layerIndex;
        int affixCount = layer <= 2 ? 1 : 2;

        var availableAffixes = GetAvailableAffixes(layer);
        var selectedAffixes = SelectRandomAffixes(availableAffixes, affixCount, enemy);

        enemy.ApplyEliteTemplate(selectedAffixes);
    }

    private Vector3 GetSpawnPosition(SpawnPointSelector selector)
    {
        if (_spawnPoints == null || _spawnPoints.Length == 0)
            return transform.position + Random.insideUnitSphere * 5f;

        return selector switch
        {
            SpawnPointSelector.RoomEdge => _spawnPoints[Random.Range(0, _spawnPoints.Length)].position,
            SpawnPointSelector.Random => transform.position + Random.insideUnitSphere * 5f,
            SpawnPointSelector.PlayerFar => GetFarSpawnFromPlayer(),
            _ => transform.position
        };
    }

    private Vector3 GetFarSpawnFromPlayer()
    {
        Vector3 playerPos = PlayerController.Instance.transform.position;
        Node2D farthest = _spawnPoints[0];
        float maxDist = 0f;
        foreach (var sp in _spawnPoints)
        {
            float d = Vector3.Distance(sp.position, playerPos);
            if (d > maxDist) { maxDist = d; farthest = sp; }
        }
        return farthest.position;
    }

    // ── 监听敌人死亡, 释放下一波 ──
    public void OnEnemyDied(EnemyController enemy)
    {
        _aliveEnemies.Remove(enemy);
        if (_aliveEnemies.Count == 0)
        {
            _currentWaveIndex++;
            if (_currentWaveIndex < _waves.Length)
                SpawnWave(_currentWaveIndex);
            else
                OnAllWavesComplete?.Invoke();
        }
    }

    // ── 词缀选择(见3.5) ──
    private List<EliteAffixType> GetAvailableAffixes(int layer) { return new List<EliteAffixType>(); }
    private EliteModifier[] SelectRandomAffixes(List<EliteAffixType> available, int count, EnemyController enemy) { return new EliteModifier[0]; }
}
```

### 3.4.2 EnemyFactory 对象池

```text
using System.Collections.Generic;
using Godot;

public class EnemyFactory : Node
{
    public static EnemyFactory Instance { get; private set; }

    private Dictionary<string, Queue<EnemyController>> _pools = new Dictionary<string, Queue<EnemyController>>();
    private Dictionary<string, EnemyController> _scenes = new Dictionary<string, EnemyController>();

    private void Awake()
    {
        Instance = this;
        ServiceRegistry.Register(this);
    }

    public void RegisterScene(EnemyData data, EnemyController scene)
    {
        _scenes[data.enemyId] = scene;
    }

    public EnemyController Get(EnemyData data, Vector3 position, DifficultyScaling scaling)
    {
        string key = data.enemyId;
        EnemyController enemy;

        if (_pools.TryGetValue(key, out var pool) && pool.Count > 0)
        {
            enemy = pool.Dequeue();
            enemy.gameObject.SetActive(true);
            enemy.transform.position = position;
        }
        else
        {
            var scene = _scenes[key];
            enemy = Instantiate(scene, position, Quaternion.identity);
        }

        enemy.Initialize(data, scaling);
        return enemy;
    }

    public void Return(EnemyController enemy)
    {
        string key = enemy.Data.enemyId;
        enemy.gameObject.SetActive(false);

        if (!_pools.TryGetValue(key, out var pool))
        {
            pool = new Queue<EnemyController>();
            _pools[key] = pool;
        }
        pool.Enqueue(enemy);
    }
}
```

### 3.4.3 DifficultyScaling 数据

```text
[System.Serializable]
public struct DifficultyScaling
{
    // ── 层数缩放 ──
    public int layerIndex;          // L=1~5
    public float hpMultiplier;      // 1.0 + (L-1)*0.35
    public float atkMultiplier;     // 1.0 + (L-1)*0.25
    public float countMultiplier;   // 1.0 + (L-1)*0.15

    // ── 房间缩放 ──
    public int roomIndex;
    public float roomHpMultiplier;  // 1.0 + (R-1)*0.05
    public float roomAtkMultiplier; // 1.0 + (R-1)*0.03
    public float eliteChance;       // 0.08 + (R-1)*0.02, 上限0.35

    // ── 时间紧迫 ──
    public float elapsedMinutes;    // 进入当前层后的实时分钟数
    public float urgencyMultiplier; // 1.0 + max(0, T-5)*0.01

    // ── 计算工厂方法 ──
    public static DifficultyScaling Calculate(int layer, int room, float elapsedMinutes)
    {
        return new DifficultyScaling
        {
            layerIndex = layer,
            hpMultiplier = 1.0f + (layer - 1) * 0.35f,
            atkMultiplier = 1.0f + (layer - 1) * 0.25f,
            countMultiplier = 1.0f + (layer - 1) * 0.15f,
            roomIndex = room,
            roomHpMultiplier = 1.0f + (room - 1) * 0.05f,
            roomAtkMultiplier = 1.0f + (room - 1) * 0.03f,
            eliteChance = math.Min(0.08f + (room - 1) * 0.02f, 0.35f),
            elapsedMinutes = elapsedMinutes,
            urgencyMultiplier = 1.0f + math.Max(0f, elapsedMinutes - 5f) * 0.01f
        };
    }
}
```

---

## 3.5 精英词缀系统

### 3.5.1 EliteModifier 基类与10种词缀

```text
using System;
using System.Collections.Generic;
using Godot;

public enum EliteAffixType
{
    FRENZY,        // 狂暴: ATK+40%, moveSpeed+20%, 受伤+25%
    FORTIFIED,     // 坚韧: HP额外+100%(总×6), knockResist+0.3, moveSpeed-25%
    REGENERATING,  // 再生: 每2秒回复3%最大HP
    TELEPORTING,   // 瞬移: 每8秒随机传送3~5格远
    SPLITTING,     // 分裂: 死亡时分裂为2个HP=33%普通版
    SHIELDED,      // 护盾: 30%最大HP护盾, 20秒重新生成
    NULLIFIED,     // 虚无: 免疫时间操控
    ANCHORED,      // 锚固: 不可击退/击飞/传送, staggerResist=1.0
    CHAINING,      // 连锁: 攻击命中时2格内其他敌人ATK+30%×1.5秒
    MIRRORING      // 镜像: 每15秒生成1个幻影
}

// ── 互斥表 ──
public static class EliteAffixExclusion
{
    private static readonly Dictionary<EliteAffixType, EliteAffixType[]> _exclusions = new()
    {
        { EliteAffixType.FRENZY, new[] { EliteAffixType.FORTIFIED } },
        { EliteAffixType.FORTIFIED, new[] { EliteAffixType.FRENZY } },
        { EliteAffixType.REGENERATING, new[] { EliteAffixType.NULLIFIED } },
        { EliteAffixType.TELEPORTING, new[] { EliteAffixType.ANCHORED } },
        { EliteAffixType.SPLITTING, new[] { EliteAffixType.NULLIFIED } },
        { EliteAffixType.SHIELDED, new[] { EliteAffixType.REGENERATING } },
        { EliteAffixType.NULLIFIED, new[] { EliteAffixType.REGENERATING, EliteAffixType.SPLITTING } },
        { EliteAffixType.ANCHORED, new[] { EliteAffixType.TELEPORTING } },
        { EliteAffixType.CHAINING, new[] { EliteAffixType.SHIELDED } },
        { EliteAffixType.MIRRORING, new[] { EliteAffixType.SPLITTING } }
    };

    public static bool IsExclusive(EliteAffixType a, EliteAffixType b)
    {
        if (!_exclusions.TryGetValue(a, out var exclusions)) return false;
        return Array.IndexOf(exclusions, b) >= 0;
    }

    // ── 可用层 ──
    public static bool IsAvailableForLayer(EliteAffixType type, int layer)
    {
        return type switch
        {
            EliteAffixType.FRENZY => layer >= 1,
            EliteAffixType.FORTIFIED => layer >= 1,
            EliteAffixType.REGENERATING => layer >= 1,
            EliteAffixType.TELEPORTING => layer >= 2,
            EliteAffixType.SPLITTING => layer >= 2,
            EliteAffixType.SHIELDED => layer >= 2,
            EliteAffixType.NULLIFIED => layer >= 3,
            EliteAffixType.ANCHORED => layer >= 3,
            EliteAffixType.CHAINING => layer >= 3,
            EliteAffixType.MIRRORING => layer >= 4,
            _ => false
        };
    }
}

// ═══════════════════════════════════════════
// EliteModifier 抽象基类
// ═══════════════════════════════════════════
public abstract class EliteModifier
{
    public abstract EliteAffixType AffixType { get; }
    public abstract void OnApply(EnemyController owner);
    public abstract void OnUpdate(EnemyController owner, float deltaTime);
    public abstract void OnDeath(EnemyController owner);
}

// ═══════════════════════════════════════════
// 1. 狂暴(FRENZY)
// ═══════════════════════════════════════════
public class FrenzyModifier : EliteModifier
{
    public override EliteAffixType AffixType => EliteAffixType.FRENZY;

    public override void OnApply(EnemyController owner)
    {
        owner.Data.atk *= 1.4f;
        owner.Data.moveSpeed *= 1.2f;
        owner.Health.SetDamageTakenMultiplier(1.25f); // 受伤+25%
        owner.PlayAffixVFX("Frenzy"); // 红色光环+蒸气粒子
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }
    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 2. 坚韧(FORTIFIED)
// ═══════════════════════════════════════════
public class FortifiedModifier : EliteModifier
{
    public override EliteAffixType AffixType => EliteAffixType.FORTIFIED;

    public override void OnApply(EnemyController owner)
    {
        owner.Data.hp *= 2f; // 额外+100%(总×6, 基础已×3)
        owner.Data.knockResist = math.Min(owner.Data.knockResist + 0.3f, 1f);
        owner.Data.moveSpeed *= 0.75f;
        owner.Health.Initialize(owner.Data.hp, owner.Data.staggerResist);
        owner.PlayAffixVFX("Fortified"); // 蓝色石质纹理+地面裂纹
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }
    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 3. 再生(REGENERATING)
// ═══════════════════════════════════════════
public class RegeneratingModifier : EliteModifier
{
    private float _regenTimer;
    private const float REGEN_INTERVAL = 2f;
    private const float REGEN_PERCENT = 0.03f; // 3%最大HP

    public override EliteAffixType AffixType => EliteAffixType.REGENERATING;

    public override void OnApply(EnemyController owner)
    {
        owner.PlayAffixVFX("Regenerating"); // 绿色上升粒子+十字标记
    }

    public override void OnUpdate(EnemyController owner, float deltaTime)
    {
        _regenTimer += deltaTime;
        if (_regenTimer >= REGEN_INTERVAL)
        {
            _regenTimer -= REGEN_INTERVAL;
            float heal = owner.Health.MaxHp * REGEN_PERCENT;
            owner.Health.Heal(heal);
        }
    }

    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 4. 瞬移(TELEPORTING)
// ═══════════════════════════════════════════
public class TeleportingModifier : EliteModifier
{
    private float _teleportTimer;
    private const float TELEPORT_COOLDOWN = 8f;
    private const float MIN_RANGE = 3f;
    private const float MAX_RANGE = 5f;

    public override EliteAffixType AffixType => EliteAffixType.TELEPORTING;

    public override void OnApply(EnemyController owner)
    {
        _teleportTimer = TELEPORT_COOLDOWN;
        owner.PlayAffixVFX("Teleporting"); // 紫色闪烁边缘+残影
    }

    public override void OnUpdate(EnemyController owner, float deltaTime)
    {
        _teleportTimer -= deltaTime;
        if (_teleportTimer <= 0f)
        {
            _teleportTimer = TELEPORT_COOLDOWN;

            // 传送前0.5秒身体闪烁
            owner.StartCoroutine(TeleportSequence(owner));
        }
    }

    private System.Collections.async流程 TeleportSequence(EnemyController owner)
    {
        // 闪烁预警0.5秒
        owner.PlayBlinkWarning(0.5f);
        yield return new Godot.WaitForSeconds(0.5f);

        // 随机传送
        Vector2 randomOffset = Godot.Random.insideUnitCircle.normalized * Godot.Random.Range(MIN_RANGE, MAX_RANGE);
        Vector3 target = owner.transform.position + new Vector3(randomOffset.x, 0f, randomOffset.y);

        // 确保目标点在NavMesh上
        if (Godot.AI.NavMesh.SamplePosition(target, out var hit, 2f, Godot.AI.NavMesh.AllAreas))
            owner.transform.position = hit.position;

        owner.PlayTeleportArriveVFX();
    }

    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 5. 分裂(SPLITTING)
// ═══════════════════════════════════════════
public class SplittingModifier : EliteModifier
{
    public override EliteAffixType AffixType => EliteAffixType.SPLITTING;

    public override void OnApply(EnemyController owner)
    {
        owner.PlayAffixVFX("Splitting"); // 身体裂纹+发光缝隙
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }

    public override void OnDeath(EnemyController owner)
    {
        // 分裂为2个HP=33%的普通版(非精英)
        for (int i = 0; i < 2; i++)
        {
            Vector3 offset = Godot.Random.insideUnitSphere * 1.5f;
            offset.y = 0f;
            Vector3 spawnPos = owner.transform.position + offset;

            var splitEnemy = EnemyFactory.Instance.Get(owner.Data, spawnPos, new DifficultyScaling());
            splitEnemy.Data.hp = owner.Data.hp * 0.33f / 3f; // 去除精英×3, 取33%
            splitEnemy.Data.atk = owner.Data.atk / 1.5f;      // 去除精英×1.5
            splitEnemy.Health.Initialize(splitEnemy.Data.hp, splitEnemy.Data.staggerResist);
        }
    }
}

// ═══════════════════════════════════════════
// 6. 护盾(SHIELDED)
// ═══════════════════════════════════════════
public class ShieldedModifier : EliteModifier
{
    private float _shieldValue;
    private float _maxShield;
    private float _regenTimer;
    private const float SHIELD_PERCENT = 0.3f;    // 30%最大HP
    private const float REGEN_INTERVAL = 20f;

    public override EliteAffixType AffixType => EliteAffixType.SHIELDED;

    public override void OnApply(EnemyController owner)
    {
        _maxShield = owner.Health.MaxHp * SHIELD_PERCENT;
        _shieldValue = _maxShield;
        _regenTimer = REGEN_INTERVAL;
        owner.Health.SetShield(_shieldValue);
        owner.PlayAffixVFX("Shielded"); // 半透明金色穹顶
    }

    public override void OnUpdate(EnemyController owner, float deltaTime)
    {
        _regenTimer -= deltaTime;
        if (_regenTimer <= 0f && _shieldValue < _maxShield)
        {
            _shieldValue = _maxShield;
            owner.Health.SetShield(_shieldValue);
            _regenTimer = REGEN_INTERVAL;
        }
    }

    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 7. 虚无(NULLIFIED)
// ═══════════════════════════════════════════
public class NullifiedModifier : EliteModifier
{
    public override EliteAffixType AffixType => EliteAffixType.NULLIFIED;

    public override void OnApply(EnemyController owner)
    {
        owner.TimeEntity.TimeAffinity = 0; // 免疫时间操控
        owner.TimeEntity.SetResistanceLevel(TimeResistanceLevel.TimeConstruct);
        owner.PlayAffixVFX("Nullified"); // 灰白色消色效果+时间碎片
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }
    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 8. 锚固(ANCHORED)
// ═══════════════════════════════════════════
public class AnchoredModifier : EliteModifier
{
    public override EliteAffixType AffixType => EliteAffixType.ANCHORED;

    public override void OnApply(EnemyController owner)
    {
        owner.Data.knockResist = 1f;
        owner.Data.staggerResist = 1f;
        owner.SetImmuneToTeleport(true);
        owner.PlayAffixVFX("Anchored"); // 脚下金色锁链连接地面
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }
    public override void OnDeath(EnemyController owner) { }
}

// ═══════════════════════════════════════════
// 9. 连锁(CHAINING)
// ═══════════════════════════════════════════
public class ChainingModifier : EliteModifier
{
    private const float BUFF_RADIUS = 2.0f;
    private const float BUFF_DURATION = 1.5f;
    private const float ATK_BONUS = 0.3f;

    public override EliteAffixType AffixType => EliteAffixType.CHAINING;

    public override void OnApply(EnemyController owner)
    {
        owner.Health.OnDealDamage += OnOwnerDealDamage;
        owner.PlayAffixVFX("Chaining"); // 电弧跳到附近敌人
    }

    private void OnOwnerDealDamage(EnemyController owner)
    {
        Collider[] hits = PhysicsQuery.OverlapSphere(owner.transform.position, BUFF_RADIUS, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var otherEnemy = hit.GetComponent<EnemyController>();
            if (otherEnemy != null && otherEnemy != owner)
            {
                otherEnemy.Health.ApplyTempAtkBonus(ATK_BONUS, BUFF_DURATION);
            }
        }
    }

    public override void OnUpdate(EnemyController owner, float deltaTime) { }
    public override void OnDeath(EnemyController owner)
    {
        owner.Health.OnDealDamage -= OnOwnerDealDamage;
    }
}

// ═══════════════════════════════════════════
// 10. 镜像(MIRRORING)
// ═══════════════════════════════════════════
public class MirroringModifier : EliteModifier
{
    private float _mirrorTimer;
    private const float MIRROR_COOLDOWN = 15f;
    private const float PHANTOM_HP_PERCENT = 0.2f;
    private const float PHANTOM_ATK_PERCENT = 0.5f;
    private const float PHANTOM_DURATION = 8f;
    private const int MAX_PHANTOMS = 1;

    private Node _currentPhantom;

    public override EliteAffixType AffixType => EliteAffixType.MIRRORING;

    public override void OnApply(EnemyController owner)
    {
        _mirrorTimer = MIRROR_COOLDOWN;
        owner.PlayAffixVFX("Mirroring"); // 身体旁始终有半透明投影
    }

    public override void OnUpdate(EnemyController owner, float deltaTime)
    {
        _mirrorTimer -= deltaTime;
        if (_mirrorTimer <= 0f && _currentPhantom == null)
        {
            _mirrorTimer = MIRROR_COOLDOWN;
            SpawnPhantom(owner);
        }
    }

    private void SpawnPhantom(EnemyController owner)
    {
        Vector3 offset = Godot.Random.insideUnitSphere * 2f;
        offset.y = 0f;
        Vector3 phantomPos = owner.transform.position + offset;

        var phantom = EnemyFactory.Instance.Get(owner.Data, phantomPos, new DifficultyScaling());
        phantom.Data.hp = owner.Health.MaxHp * PHANTOM_HP_PERCENT;
        phantom.Data.atk = owner.Data.atk * PHANTOM_ATK_PERCENT;
        phantom.Health.Initialize(phantom.Data.hp, phantom.Data.staggerResist);
        phantom.SetLifetime(PHANTOM_DURATION);
        _currentPhantom = phantom.gameObject;

        // 幻影半透明
        phantom.SetAlpha(0.5f);
        // 幻影无词缀
    }

    public override void OnDeath(EnemyController owner)
    {
        if (_currentPhantom != null)
            _currentPhantom.queue_free();
    }
}
```

---

## 3.6 Boss系统架构

### 3.6.1 BossController

```text
using System.Collections;
using System.Collections.Generic;
using Godot;

[RequireComponent(typeof(BossPhaseManager), typeof(BossTemporalTolerance))]
public class BossController : EnemyController
{
    // ── Boss核心组件 ──
    public BossPhaseManager PhaseManager { get; private set; }
    public BossTemporalTolerance TemporalTolerance { get; private set; }
    public BossAttackSelector AttackSelector { get; private set; }

    // ── Boss数据 ──
    private BossData _bossData;

    // ── 狂暴系统 ──
    private float _enrageTimer;
    private bool _isEnraged;
    public bool IsEnraged => _isEnraged;

    // ── 阶段切换 ──
    private bool _isInPhaseTransition;
    public bool IsInPhaseTransition => _isInPhaseTransition;

    // ── 霸体值 ──
    private float _currentPoise;
    private float _poiseRegenRate;
    private bool _isPoiseBroken;

    // ── 事件 ──
    public event System.Action<int> OnPhaseChanged;     // phaseIndex
    public event System.Action OnEnrage;
    public event System.Action OnBossDeath;

    protected override void Awake()
    {
        base.Awake();
        PhaseManager = GetComponent<BossPhaseManager>();
        TemporalTolerance = GetComponent<BossTemporalTolerance>();
        AttackSelector = new BossAttackSelector();
    }

    public void InitializeBoss(BossData data, float hpMultiplier = 1f)
    {
        _bossData = data;
        _enrageTimer = data.enrageTimer;
        _isEnraged = false;
        _currentPoise = data.poise;
        _poiseRegenRate = data.poiseRegenRate;
        _isPoiseBroken = false;

        // 应用HP缩放
        data.hp *= hpMultiplier;

        Health.Initialize(data.hp, data.staggerResist);
        Health.OnHpChanged += OnHpChanged;

        // 初始化阶段管理器
        PhaseManager.Initialize(data.phases);
        PhaseManager.OnPhaseTransition += HandlePhaseTransition;

        // 初始化招式选择器
        AttackSelector.Initialize(data.attackEntries);
    }

    private void Update()
    {
        base.Update();

        if (_isInPhaseTransition || IsDead) return;

        // 狂暴计时
        if (!_isEnraged)
        {
            _enrageTimer -= Time.unscaledDeltaTime;
            if (_enrageTimer <= 0f)
                TriggerEnrage();
        }

        // 霸体恢复
        if (!_isPoiseBroken && _currentPoise < _bossData.poise)
        {
            _currentPoise += _poiseRegenRate * Time.unscaledDeltaTime;
            _currentPoise = math.Min(_currentPoise, _bossData.poise);
        }
    }

    // ── HP变化回调(阶段切换检测) ──
    private void OnHpChanged(float current, float max)
    {
        if (_isInPhaseTransition) return;

        float hpPercent = current / max;
        PhaseManager.CheckPhaseTransition(hpPercent);
    }

    // ── 阶段切换处理 ──
    private void HandlePhaseTransition(int newPhaseIndex, BossPhaseData newPhase)
    {
        if (_isInPhaseTransition) return;
        StartCoroutine(PhaseTransitionCoroutine(newPhaseIndex, newPhase));
    }

    private async流程 PhaseTransitionCoroutine(int newPhaseIndex, BossPhaseData newPhase)
    {
        _isInPhaseTransition = true;

        // HP锁定 + 无敌
        Health.SetInvincible(true);
        Health.SetHpLocked(true);

        // 播放阶段切换演出
        if (newPhase.transitionClip != null)
        {
            animation_player.Play(newPhase.transitionClip);
            yield return new WaitForSecondsRealtime(newPhase.transitionDuration); // 2~3秒
        }

        // 更新Boss属性
        _bossData.atk = newPhase.atk;
        _bossData.moveSpeed = newPhase.moveSpeed;
        _bossData.staggerResist = newPhase.staggerResist;
        _bossData.knockResist = newPhase.knockResist;
        _bossData.poise = newPhase.poise;
        NavAgent.speed = newPhase.moveSpeed;

        // 更新招式池
        AttackSelector.UpdateAvailableAttacks(newPhase.availableAttackIds);

        // 重置时间耐受值
        TemporalTolerance.OnPhaseTransition();

        // 解锁
        Health.SetInvincible(false);
        Health.SetHpLocked(false);
        _isInPhaseTransition = false;

        OnPhaseChanged?.Invoke(newPhaseIndex);
        EventBus.Publish(new BossPhaseChangeEvent { BossId = _bossData.bossId, PhaseIndex = newPhaseIndex });
    }

    // ── 狂暴 ──
    private void TriggerEnrage()
    {
        _isEnraged = true;
        _bossData.atk *= 1.5f;
        _bossData.moveSpeed *= 1.3f;

        // 所有招式冷却-40%
        AttackSelector.ApplyCooldownModifier(0.6f);

        // 新增狂暴专属招式
        AttackSelector.AddEnrageAttacks(_bossData.enrageAttackEntries);

        OnEnrage?.Invoke();
        EventBus.Publish(new BossEnrageEvent { BossId = _bossData.bossId });

        // 视觉: 全身红光脉冲
        PlayEnrageVFX();
    }

    // ── 霸体伤害 ──
    public override void TakeDamage(float amount, DamageType type)
    {
        base.TakeDamage(amount, type);

        if (!_isPoiseBroken)
        {
            _currentPoise -= amount;
            if (_currentPoise <= 0f)
            {
                _isPoiseBroken = true;
                StartCoroutine(PoiseBreakRecovery());
            }
        }
    }

    private async流程 PoiseBreakRecovery()
    {
        animation_player.SetTrigger("Stagger");
        yield return new WaitForSeconds(1f);
        _isPoiseBroken = false;
        _currentPoise = _bossData.poise * 0.5f;
    }

    // ── Boss死亡 ──
    protected override void OnDeath()
    {
        OnBossDeath?.Invoke();
        EventBus.Publish(new BossDeathEvent { BossId = _bossData.bossId });
        FSM.TransitionTo(EnemyState.DEATH);
    }

    // ── 招式选择 ──
    public string SelectBossAttack()
    {
        float distToPlayer = GetDistanceToPlayer();
        float hpPercent = Health.HpPercent;
        return AttackSelector.SelectAttack(distToPlayer, hpPercent, PhaseManager.CurrentPhaseIndex);
    }

    private void PlayEnrageVFX() { /* 全身红光脉冲, BGM变奏 */ }
}
```

---

## 3.7 Boss多阶段状态机

### 3.7.1 BossPhaseManager

```text
using System;
using System.Collections.Generic;
using Godot;

[System.Serializable]
public class BossPhaseData
{
    public string phaseName;
    public int phaseIndex;
    public float hpThreshold;          // HP百分比阈值(0~1), 低于此值进入下一阶段
    public float atk;
    public float moveSpeed;
    public float staggerResist;
    public float knockResist;
    public float poise;
    public float poiseRegenRate = 10f;
    public string transitionClip;      // 阶段切换动画名
    public float transitionDuration = 2.5f;
    public string[] availableAttackIds;
}

public class BossPhaseManager : Node
{
     private BossPhaseData[] _phases;

    private int _currentPhaseIndex;
    private BossPhaseData[] _runtimePhases;
    private bool[] _transitioned;  // 标记每个阶段是否已切换过

    public int CurrentPhaseIndex => _currentPhaseIndex;
    public BossPhaseData CurrentPhase => _runtimePhases[_currentPhaseIndex];
    public int PhaseCount => _runtimePhases.Length;

    public event Action<int, BossPhaseData> OnPhaseTransition;

    public void Initialize(BossPhaseData[] phases)
    {
        _runtimePhases = new BossPhaseData[phases.Length];
        Array.Copy(phases, _runtimePhases, phases.Length);
        _currentPhaseIndex = 0;
        _transitioned = new bool[phases.Length];
    }

    /// <summary>
    /// 检查是否需要阶段切换
    /// 当HP降到当前阶段阈值以下时, 触发切换
    /// </summary>
    public void CheckPhaseTransition(float currentHpPercent)
    {
        // 检查是否应该进入下一阶段
        int nextPhaseIndex = _currentPhaseIndex + 1;
        if (nextPhaseIndex >= _runtimePhases.Length) return;
        if (_transitioned[nextPhaseIndex]) return;

        float nextThreshold = _runtimePhases[nextPhaseIndex].hpThreshold;
        if (currentHpPercent <= nextThreshold)
        {
            _transitioned[nextPhaseIndex] = true;
            _currentPhaseIndex = nextPhaseIndex;
            OnPhaseTransition?.Invoke(nextPhaseIndex, _runtimePhases[nextPhaseIndex]);
        }
    }

    /// <summary>
    /// 强制切换到指定阶段(用于狂暴等特殊触发)
    /// </summary>
    public void ForcePhaseTransition(int phaseIndex)
    {
        if (phaseIndex < 0 || phaseIndex >= _runtimePhases.Length) return;
        _currentPhaseIndex = phaseIndex;
        _transitioned[phaseIndex] = true;
        OnPhaseTransition?.Invoke(phaseIndex, _runtimePhases[phaseIndex]);
    }

    /// <summary>
    /// 检查指定招式在当前阶段是否可用
    /// </summary>
    public bool IsAttackAvailableInPhase(string attackId)
    {
        var current = _runtimePhases[_currentPhaseIndex];
        if (current.availableAttackIds == null) return true;
        foreach (var id in current.availableAttackIds)
            if (id == attackId) return true;
        return false;
    }
}
```

---

## 3.8 Boss招式系统

### 3.8.1 BossAttackData

```text
[System.Serializable]
public class BossAttackEntry
{
    public string attackId;
    public float baseWeight = 10f;
    public float cooldown = 4f;
    public float lastUsedTime = float.NegativeInfinity;
    public int consecutiveCount;
    public float maxConsecutive = 2f;
    public string[] requiredPhases;       // 可用阶段
    public float minHPPercent = 0f;       // 最低HP%才可用
    public float maxDistance = 15f;       // 最大使用距离
    public float minDistance = 0f;        // 最小使用距离

    // ── 帧序列数据 ──
    public BossAttackFrameData frameData;
}

[System.Serializable]
public class BossAttackFrameData
{
    // 所有时间以秒存储(帧数/60)
    public float warningSeconds;    // 预警帧
    public float windupSeconds;     // 前摇帧
    public float activeSeconds;     // 判定帧
    public float recoverySeconds;   // 后摇帧
    public float idleSeconds;       // 空闲帧

    // ── 伤害参数 ──
    public float damage;
    public AttackShape shape;       // CIRCLE / RECT / SECTOR / LINE
    public float range;             // 范围(半径/长度)
    public float angle;             // 扇形角度(SECTOR类型)
    public float width;             // 宽度(LINE/RECT类型)
    public float knockback;         // 击退距离

    // ── 判定参数 ──
    public int hitCount = 1;                // 多段判定次数
    public float hitIntervalSeconds = 0f;   // 多段判定间隔
    public bool isSustained;                // 是否持续判定(如射线)
    public float sustainedTickInterval = 0.167f; // 持续判定tick间隔(默认10帧)

    // ── 附加效果 ──
    public string[] effectIds;              // 附加效果ID列表(DOT, 减速, 定身等)
    public string animationTrigger;         // AnimationPlayer或AnimationTree触发器名
    public string vfxPath;                  // 特效路径
    public string sfxPath;                  // 音效路径
    public string warningVfxPath;           // 预警特效路径

    // ── 属性 ──
    public float totalDuration => warningSeconds + windupSeconds + activeSeconds + recoverySeconds;
    public float playerReactionWindow => warningSeconds + windupSeconds; // 玩家反应时间
    public float playerDamageWindow => recoverySeconds + idleSeconds;   // 玩家输出窗口
}

public enum AttackShape { CIRCLE, RECT, SECTOR, LINE }
```

### 3.8.2 BossAttackSelector

```text
using System.Collections.Generic;
using System.Linq;
using Godot;

public class BossAttackSelector
{
    private List<BossAttackEntry> _allAttacks = new List<BossAttackEntry>();
    private List<BossAttackEntry> _availableAttacks = new List<BossAttackEntry>();
    private float _cooldownModifier = 1f;
    private int _currentPhaseIndex;

    public void Initialize(BossAttackEntry[] entries)
    {
        _allAttacks = entries.ToList();
        _availableAttacks = _allAttacks.ToList();
    }

    public void UpdateAvailableAttacks(string[] phaseAttackIds)
    {
        if (phaseAttackIds == null) return;
        var phaseSet = new HashSet<string>(phaseAttackIds);
        // 保留所有招式, 但阶段过滤在选择时应用
    }

    public void AddEnrageAttacks(BossAttackEntry[] enrageAttacks)
    {
        if (enrageAttacks != null)
            _availableAttacks.AddRange(enrageAttacks);
    }

    public void ApplyCooldownModifier(float modifier)
    {
        _cooldownModifier = modifier;
    }

    public void SetCurrentPhase(int phaseIndex)
    {
        _currentPhaseIndex = phaseIndex;
    }

    /// <summary>
    /// 基于权重的招式选择
    /// 考虑: 冷却, 连续使用惩罚, 距离适配, HP适配, 阶段可用性
    /// </summary>
    public string SelectAttack(float distToPlayer, float hpPercent, int currentPhase)
    {
        var validAttacks = _availableAttacks.Where(a =>
        {
            // 阶段检查
            if (a.requiredPhases != null && a.requiredPhases.Length > 0)
            {
                bool phaseValid = a.requiredPhases.Any(p => p == $"phase_{currentPhase}" || p == "all");
                if (!phaseValid) return false;
            }

            // 冷却检查
            if (Time.unscaledTime - a.lastUsedTime < a.cooldown * _cooldownModifier) return false;

            // HP检查
            if (hpPercent < a.minHPPercent) return false;

            // 距离检查
            if (distToPlayer > a.maxDistance || distToPlayer < a.minDistance) return false;

            return true;
        }).ToList();

        if (validAttacks.Count == 0) return "idle";

        // 计算权重
        var weights = validAttacks.Select(a => GetAttackWeight(a, distToPlayer, hpPercent)).ToList();
        float totalWeight = weights.Sum();

        if (totalWeight <= 0f) return "idle";

        // 加权随机
        float roll = Random.Range(0f, totalWeight);
        float cumulative = 0f;
        for (int i = 0; i < validAttacks.Count; i++)
        {
            cumulative += weights[i];
            if (roll <= cumulative)
            {
                // 更新使用记录
                var selected = validAttacks[i];
                selected.lastUsedTime = Time.unscaledTime;
                selected.consecutiveCount++;
                return selected.attackId;
            }
        }

        return validAttacks.Last().attackId;
    }

    private float GetAttackWeight(BossAttackEntry entry, float distToPlayer, float hpPercent)
    {
        float weight = entry.baseWeight;

        // 连续使用惩罚: 连续使用越多权重越低
        weight *= math.Pow(0.4f, entry.consecutiveCount);

        // 距离适配: 距离越远, 近战招式权重越低
        float optimalDist = (entry.minDistance + entry.maxDistance) / 2f;
        float distRange = (entry.maxDistance - entry.minDistance) / 2f;
        float distFactor = 1.0f - math.Abs(distToPlayer - optimalDist) / math.Max(distRange, 0.01f);
        weight *= math.Max(0.3f, distFactor);

        // HP越低, 高威胁招式权重越高
        if (hpPercent < 0.3f)
            weight *= (entry.baseWeight > 5f) ? 1.5f : 0.8f;

        return weight;
    }

    /// <summary>
    /// 重置招式连续计数(攻击执行后可选调用)
    /// </summary>
    public void ResetConsecutiveCount(string attackId)
    {
        var entry = _allAttacks.Find(a => a.attackId == attackId);
        if (entry != null)
            entry.consecutiveCount = 0;
    }
}
```

### 3.8.3 BossAttackExecutor（帧数据解析）

```text
using System.Collections;
using Godot;

public class BossAttackExecutor : Node
{
    private BossController _boss;

    public void Initialize(BossController boss)
    {
        _boss = boss;
    }

    /// <summary>
    /// 执行Boss招式的完整帧序列
    /// </summary>
    public async流程 ExecuteAttack(BossAttackEntry entry)
    {
        var frame = entry.frameData;
        if (frame == null) yield break;

        // ── 预警阶段 ──
        if (frame.warningSeconds > 0f)
        {
            _boss.animation_player.SetTrigger(frame.animationTrigger + "_Warning");
            if (!string.IsNullOrEmpty(frame.warningVfxPath))
                EffectManager.Play(frame.warningVfxPath, _boss.transform.position);
            if (!string.IsNullOrEmpty(frame.sfxPath))
                AudioManager.PlaySFX(frame.sfxPath + "_Warning");

            yield return new WaitForSecondsRealtime(frame.warningSeconds);
        }

        // ── 前摇阶段 ──
        _boss.animation_player.SetTrigger(frame.animationTrigger + "_Windup");
        yield return new WaitForSecondsRealtime(frame.windupSeconds);

        // ── 判定阶段 ──
        _boss.animation_player.SetTrigger(frame.animationTrigger + "_Active");

        if (frame.isSustained)
        {
            // 持续判定(如射线、旋风)
            float elapsed = 0f;
            float tickTimer = 0f;
            while (elapsed < frame.activeSeconds)
            {
                float dt = Time.unscaledDeltaTime;
                elapsed += dt;
                tickTimer += dt;

                if (tickTimer >= frame.sustainedTickInterval)
                {
                    tickTimer -= frame.sustainedTickInterval;
                    ApplyHitDetection(frame, frame.damage / math.Max(1, frame.activeSeconds / frame.sustainedTickInterval));
                }
                yield return null;
            }
        }
        else if (frame.hitCount > 1)
        {
            // 多段判定
            for (int i = 0; i < frame.hitCount; i++)
            {
                ApplyHitDetection(frame, frame.damage / frame.hitCount);

                if (i < frame.hitCount - 1)
                    yield return new WaitForSecondsRealtime(frame.hitIntervalSeconds);
            }
        }
        else
        {
            // 单次判定
            ApplyHitDetection(frame, frame.damage);
        }

        // ── 后摇阶段(玩家输出窗口) ──
        _boss.animation_player.SetTrigger(frame.animationTrigger + "_Recovery");
        yield return new WaitForSecondsRealtime(frame.recoverySeconds);

        // ── 空闲阶段 ──
        if (frame.idleSeconds > 0f)
            yield return new WaitForSecondsRealtime(frame.idleSeconds);
    }

    /// <summary>
    /// 伤害判定: 根据AttackShape检测玩家
    /// </summary>
    private void ApplyHitDetection(BossAttackFrameData frame, float damage)
    {
        Vector3 bossPos = _boss.transform.position;
        Vector3 bossForward = _boss.transform.forward;

        Collider[] hits = frame.shape switch
        {
            AttackShape.CIRCLE => PhysicsQuery.OverlapSphere(bossPos + bossForward * (frame.range * 0.5f), frame.range, collision_mask.GetMask("Player")),
            AttackShape.SECTOR => GetSectorHits(bossPos, bossForward, frame.range, frame.angle),
            AttackShape.LINE => GetLineHits(bossPos, bossForward, frame.range, frame.width),
            AttackShape.RECT => GetRectHits(bossPos, bossForward, frame.range, frame.width),
            _ => new Collider[0]
        };

        foreach (var hit in hits)
        {
            var playerHealth = hit.GetComponent<PlayerHealth>();
            if (playerHealth != null && !playerHealth.IsInvincible)
            {
                playerHealth.TakeDamage(damage, DamageType.Physical);

                // 击退
                if (frame.knockback > 0f)
                {
                    Vector3 knockDir = (hit.transform.position - bossPos).normalized;
                    PlayerController.Instance.ApplyKnockback(knockDir * frame.knockback);
                }

                // 附加效果
                ApplyEffects(frame, hit.gameObject);
            }
        }

        // 播放判定特效
        if (!string.IsNullOrEmpty(frame.vfxPath))
            EffectManager.Play(frame.vfxPath, bossPos + bossForward * frame.range * 0.5f);
        if (!string.IsNullOrEmpty(frame.sfxPath))
            AudioManager.PlaySFX(frame.sfxPath);
    }

    private Collider[] GetSectorHits(Vector3 origin, Vector3 forward, float radius, float angle)
    {
        List<Collider> results = new List<Collider>();
        Collider[] sphereHits = PhysicsQuery.OverlapSphere(origin, radius, collision_mask.GetMask("Player"));
        foreach (var hit in sphereHits)
        {
            Vector3 dir = (hit.transform.position - origin).normalized;
            if (Vector3.Angle(forward, dir) <= angle * 0.5f)
                results.Add(hit);
        }
        return results.ToArray();
    }

    private Collider[] GetLineHits(Vector3 origin, Vector3 forward, float length, float width)
    {
        Vector3 end = origin + forward * length;
        return PhysicsQuery.OverlapCapsule(origin, end, width * 0.5f, collision_mask.GetMask("Player"));
    }

    private Collider[] GetRectHits(Vector3 origin, Vector3 forward, float length, float width)
    {
        return GetLineHits(origin, forward, length, width);
    }

    private void ApplyEffects(BossAttackFrameData frame, Node target)
    {
        if (frame.effectIds == null) return;
        foreach (var effectId in frame.effectIds)
        {
            EffectSystem.ApplyEffect(effectId, target);
        }
    }
}
```

---

## 3.9 难度缩放公式实现

```text
public static class DifficultyCalculator
{
    // ═══════════════════════════════════════════
    // 全局缩放(基于层数 L, L=1~5)
    // ═══════════════════════════════════════════

    /// <summary>
    /// HP倍率 = 1.0 + (L - 1) * 0.35
    /// </summary>
    public static float GetLayerHpMultiplier(int layer)
    {
        return 1.0f + (layer - 1) * 0.35f;
    }

    /// <summary>
    /// ATK倍率 = 1.0 + (L - 1) * 0.25
    /// </summary>
    public static float GetLayerAtkMultiplier(int layer)
    {
        return 1.0f + (layer - 1) * 0.25f;
    }

    /// <summary>
    /// 数量倍率 = 1.0 + (L - 1) * 0.15
    /// </summary>
    public static float GetLayerCountMultiplier(int layer)
    {
        return 1.0f + (layer - 1) * 0.15f;
    }

    // ═══════════════════════════════════════════
    // 房间内缩放(基于房间序号 R)
    // ═══════════════════════════════════════════

    /// <summary>
    /// HP额外倍率 = 1.0 + (R - 1) * 0.05
    /// </summary>
    public static float GetRoomHpMultiplier(int room)
    {
        return 1.0f + (room - 1) * 0.05f;
    }

    /// <summary>
    /// ATK额外倍率 = 1.0 + (R - 1) * 0.03
    /// </summary>
    public static float GetRoomAtkMultiplier(int room)
    {
        return 1.0f + (room - 1) * 0.03f;
    }

    /// <summary>
    /// 精英概率 = 0.08 + (R - 1) * 0.02, 上限0.35
    /// </summary>
    public static float GetEliteChance(int room)
    {
        return math.Min(0.08f + (room - 1) * 0.02f, 0.35f);
    }

    // ═══════════════════════════════════════════
    // 时间因子(实时分钟 T)
    // ═══════════════════════════════════════════

    /// <summary>
    /// 紧迫倍率 = 1.0 + max(0, T - 5) * 0.01
    /// </summary>
    public static float GetUrgencyMultiplier(float elapsedMinutes)
    {
        return 1.0f + math.Max(0f, elapsedMinutes - 5f) * 0.01f;
    }

    // ═══════════════════════════════════════════
    // 最终属性计算
    // ═══════════════════════════════════════════

    /// <summary>
    /// finalHP = baseHP × HP倍率 × HP额外倍率 × 紧迫倍率
    /// </summary>
    public static float CalculateFinalHP(float baseHP, int layer, int room, float elapsedMinutes)
    {
        return baseHP
            * GetLayerHpMultiplier(layer)
            * GetRoomHpMultiplier(room)
            * GetUrgencyMultiplier(elapsedMinutes);
    }

    /// <summary>
    /// finalATK = baseATK × ATK倍率 × ATK额外倍率 × 紧迫倍率
    /// </summary>
    public static float CalculateFinalATK(float baseATK, int layer, int room, float elapsedMinutes)
    {
        return baseATK
            * GetLayerAtkMultiplier(layer)
            * GetRoomAtkMultiplier(room)
            * GetUrgencyMultiplier(elapsedMinutes);
    }

    /// <summary>
    /// finalCount = floor(baseCount × 数量倍率)
    /// </summary>
    public static int CalculateFinalCount(int baseCount, int layer)
    {
        return math.FloorToInt(baseCount * GetLayerCountMultiplier(layer));
    }

    // ═══════════════════════════════════════════
    // Boss专用缩放
    // ═══════════════════════════════════════════

    /// <summary>
    /// Boss基础HP = 层级基准HP × (1 + (层数L - 1) × 0.5)
    /// </summary>
    public static float CalculateBossBaseHP(float tierBaseHP, int layer)
    {
        return tierBaseHP * (1f + (layer - 1) * 0.5f);
    }

    /// <summary>
    /// Boss实际HP = Boss基础HP × 路径缩放 × 游戏难度系数
    /// 路径缩放 = 1.0 + (房间数R - 8) × 0.02
    /// </summary>
    public static float CalculateBossFinalHP(float tierBaseHP, int layer, int roomCount, float difficultyCoefficient = 1f)
    {
        float baseHP = CalculateBossBaseHP(tierBaseHP, layer);
        float pathScaling = 1.0f + (roomCount - 8) * 0.02f;
        return baseHP * pathScaling * difficultyCoefficient;
    }

    /// <summary>
    /// 狂暴计时(秒): L1=300, L2=270, L3=240, L4=210, L5=180
    /// </summary>
    public static float GetEnrageTimer(int layer)
    {
        return 300f - (layer - 1) * 30f;
    }
}
```

---

## 3.10 敌人数据配置

### 3.10.1 EnemyData Resource

```text
using Godot;

[CreateAssetMenu(fileName = "EnemyData", menuName = "Game/Enemy Data")]
public class EnemyData : Resource
{
    [Header("基础标识")]
    public string enemyId;
    public string displayName;
    public string description;
    public int layerIndex;               // 出现层数(1~5)
    public bool isBoss;
    public bool isSummon;                // 召唤物标记(不可精英化)
    public bool isRangedType;
    public float preferredMinDistance;    // 远程敌人距离维持

    [Header("基础属性")]
    public float hp = 80f;
    public float atk = 12f;
    public float moveSpeed = 2.0f;
    public float atkFreq = 2.5f;         // 秒/次
    public float detectRange = 6.0f;
    public float atkRange = 1.8f;
    public float knockResist = 0.6f;      // 0~1
    public float staggerResist = 0.4f;    // 0~1
    public int threatLevel = 1;           // 1~5

    [Header("AI行为参数")]
    public float alertDuration = 0.5f;
    public bool retreatAfterAttack = true;
    public float retreatDuration = 0.8f;
    public float retreatDistance = 1.2f;
    public float deathDuration = 0.6f;
    public float attackOffset;            // 初始攻击偏移(防同步)

    [Header("攻击模式")]
    public AttackPatternData[] attackPatterns;

    [Header("时间抗性")]
    public int timeAffinity = 5;           // 0=免疫, 1~10
    public TimeResistanceLevel resistanceLevel = TimeResistanceLevel.None;

    [Header("掉落")]
    public LootTable lootTable;

    [Header("视觉")]
    public Node model_scene;
    public AnimationLibrary animatorController;
    public string alertVfxPath;
    public string deathVfxPath;
    public string eliteVfxPath;
}

[System.Serializable]
public struct AttackPatternData
{
    public string name;
    public float windupSeconds;         // 前摇(秒)
    public float activeSeconds;         // 活动(秒)
    public float recoverySeconds;       // 后摇(秒)
    public float damage;                // 伤害值
    public float damageMultiplier = 1f;
    public float range;                 // 攻击范围(格)
    public float minRange;              // 最小使用距离
    public float maxRange;              // 最大使用距离
    public float angle;                 // 扇形角度
    public AttackShape shape;
    public float cooldown;              // 冷却(秒)
    public float selectionWeight = 1f;  // 选择权重
    public string[] effectIds;
    public string animationTrigger;
    public string vfxPath;
    public string sfxPath;
}
```

### 3.10.2 BossData Resource

```text
[CreateAssetMenu(fileName = "BossData", menuName = "Game/Boss Data")]
public class BossData : EnemyData
{
    [Header("Boss专有属性")]
    public float dashSpeed = 7f;
    public float turnSpeed = 180f;
    public float poise = 200f;
    public float poiseRegenRate = 10f;
    public float enrageTimer = 300f;

    [Header("阶段配置")]
    public BossPhaseData[] phases;

    [Header("招式配置")]
    public BossAttackEntry[] attackEntries;
    public BossAttackEntry[] enrageAttackEntries;

    [Header("战利品")]
    public BossLootTable bossLootTable;
}

[System.Serializable]
public class BossLootTable
{
    public int baseGold = 150;
    public int chronosFragmentCount = 1;
    public int blessingChoices = 3;
    public BossDropItem[] specialDrops;
}

[System.Serializable]
public class BossDropItem
{
    public string itemId;
    public string itemName;
    public float dropChance;    // 0~1
    public ItemRarity rarity;
}

public enum ItemRarity { Common, Rare, Epic, Legendary, Mythic }
```

### 3.10.3 LootTable

```text
[System.Serializable]
public class LootTable
{
    public LootEntry[] entries;

    public void RollDrop(Vector3 position)
    {
        foreach (var entry in entries)
        {
            if (Random.value <= entry.dropChance)
            {
                ItemSpawner.Spawn(entry.itemId, position, entry.count);
            }
        }
    }
}

[System.Serializable]
public struct LootEntry
{
    public string itemId;
    public float dropChance;    // 0~1
    public int count = 1;
}
```

---

## 3.11 测试计划

### 3.11.1 单元测试

| 测试ID | 测试内容 | 预期结果 |
|--------|---------|---------|
| T-E-01 | DifficultyCalculator层数缩放 | L1=1.0, L2=1.35, L5=2.40 (HP) |
| T-E-02 | DifficultyCalculator房间缩放 | R1=1.0, R5=1.20 (HP) |
| T-E-03 | DifficultyCalculator精英概率 | R1=8%, R10=28%, >14=35%(上限) |
| T-E-04 | DifficultyCalculator紧迫倍率 | T<5: 1.0, T=10: 1.05 |
| T-E-05 | DifficultyCalculator Boss HP | L1=×1.0, L3=×2.0, L5=×3.0 |
| T-E-06 | EnemyFSM状态转换 | PATROL→ALERT→CHASE→ATTACK→RETREAT→CHASE |
| T-E-07 | EnemyFSM脱离检测 | 距离>detectRange×1.5→PATROL |
| T-E-08 | SnapshotBuffer环形覆盖 | 超capacity后旧数据被覆盖 |
| T-E-09 | EliteAffixExclusion互斥检查 | FRENZY与FORTIFIED互斥返回true |
| T-E-10 | BossAttackSelector权重选择 | 冷却中权重=0, 连续使用权重递减 |

### 3.11.2 集成测试

| 测试ID | 测试内容 | 预期结果 |
|--------|---------|---------|
| T-I-01 | 敌人完整生命周期 | PATROL→检测→追击→攻击→后撤→循环 |
| T-I-02 | 精英敌人属性变化 | HP×3, ATK×1.5, 体型×1.15 |
| T-I-03 | 精英分裂词缀死亡 | 生成2个HP=33%普通版敌人 |
| T-I-04 | 精英虚无词缀免疫 | 时间停止对虚无精英无效果 |
| T-I-05 | Boss阶段切换 | HP≤60%时触发P2, 演出2.5秒 |
| T-I-06 | Boss阶段切换HP锁定 | 演出期间Boss无敌且HP不变 |
| T-I-07 | Boss狂暴触发 | 超过enrageTimer后ATK×1.5, moveSpeed×1.3 |
| T-I-08 | Boss时间耐受值 | 每次被时间技能影响+1, 60秒衰减-1 |
| T-I-09 | Boss招式帧序列 | 预警→前摇→判定→后摇→空闲, 时序正确 |
| T-I-10 | EnemySpawner波次生成 | 第1波40%威胁, 逐波递减比例 |

### 3.11.3 性能测试

| 测试ID | 测试内容 | 通过标准 |
|--------|---------|---------|
| T-P-01 | 10个普通敌人同屏 | ≥55 FPS |
| T-P-02 | 3个精英+5个普通 | ≥55 FPS |
| T-P-03 | Boss战(单Boss+2召唤物) | ≥55 FPS |
| T-P-04 | EnemyFactory对象池复用 | 0 GC分配(复用时) |
| T-P-05 | BossAttackSelector选择耗时 | ≤0.1ms/次 |
| T-P-06 | 30个敌人FSM并行Update | ≤1ms/帧 |

### 3.11.4 游戏性测试

| 测试ID | 测试内容 | 验证目标 |
|--------|---------|---------|
| T-G-01 | 第1层敌人组合平衡 | 3个碎岩卫兵错峰攻击, 不致命 |
| T-G-02 | 裂隙看守优先击杀策略 | 先杀看守→被滋养敌人进入虚弱3秒 |
| T-G-03 | 石壳行者缩壳/破壳窗口 | 受击→缩壳2秒→0.5秒破壳窗口(受伤+30%) |
| T-G-04 | 遗迹守护者Boss全招式 | 4个P1招式+3个P2招式正确执行 |
| T-G-05 | Boss招式可闪避窗口 | 每招warning+windup≥23帧(最低反应时间) |
| T-G-06 | Boss后摇输出窗口 | 石拳砸击后摇+空闲=60帧(1秒) |
| T-G-07 | 遗迹守护者裂隙射线掩体 | 射线可被场地障碍物阻挡 |
| T-G-08 | 时间抗性正确生效 | 精英(抗性3)减速=正常×40% |
| T-G-09 | 难度缩放第1层→第4层 | HP/ATK/数量按公式正确增长 |
| T-G-10 | 腐蚀飞虫连锁爆炸 | 2.5格内其他孢子连锁, 最多5次 |

### 3.11.5 回归测试清单

每次版本更新后必须执行:

- [ ] 所有敌人FSM状态转换正确
- [ ] Boss阶段切换无死锁
- [ ] 精英词缀无互斥冲突
- [ ] 难度缩放公式输出与设计文档一致
- [ ] 对象池无泄漏(内存稳定)
- [ ] 时间操控对敌人效果(时停/减速/回溯残影)正常
- [ ] Boss耐受值衰减正常
- [ ] 狂暴计时器正确触发

---

*文档版本: v1.0 | 最后更新: 2026-04-22*
