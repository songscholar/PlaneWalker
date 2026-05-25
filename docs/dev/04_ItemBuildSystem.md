# 04 道具与Build系统开发文档

> **文档版本**：v1.0  
> **最后更新**：2026-04-22  
> **适用项目**：《Plane Walker: Chronicles of Collapse》  
> **引擎**：Godot 4.x + GDScript 2.0  
> **架构依赖**：EventBus Autoload, ServiceRegistry, StateMachine, Registry  

> **Godot迁移约束**：道具、祝福、诅咒、天赋均使用 Resource(`.tres`) 或 JSON 数据；效果逻辑使用 `ItemEffect extends Resource` + EventBus订阅。

> **v1.1实现约束**：若本文档与 `docs/0_深度收敛与系统职责设计.md` 冲突，以v1.1收敛文档为准。首发默认只实现40-60个道具、25-30个祝福、15-18个诅咒、5路线×3层核心天赋；旧版大池、隐藏组合、10层节奏和大量纯数值节点均视为储备/扩展内容。

---

## 4.1 道具系统架构

### 4.1.1 架构总览

```
┌───────────────────────────────────────────────────────────────┐
│                      道具系统架构                              │
│                                                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐       │
│  │ ItemRegistry │    │  ItemData   │    │ ItemInstance │       │
│  │  (注册中心)  │───→│ (SO定义)    │───→│ (运行时实例) │       │
│  └──────┬──────┘    └─────────────┘    └──────┬──────┘       │
│         │                                     │               │
│         ▼                                     ▼               │
│  ┌─────────────┐    ┌─────────────────────────────────┐      │
│  │  Inventory   │    │      ItemEffectProcessor        │      │
│  │ (槽位管理)   │    │      (效果处理器)                │      │
│  └──────┬──────┘    └──────────────┬──────────────────┘      │
│         │                          │                          │
│         ▼                          ▼                          │
│  ┌─────────────┐    ┌─────────────────────────────────┐      │
│  │SynergyEngine│    │       EventBus (事件驱动)        │      │
│  │ (联动引擎)  │    │  OnItemAcquired / OnHit / ...    │      │
│  └─────────────┘    └─────────────────────────────────┘      │
│                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │BlessingMgr  │  │  CurseMgr   │  │ TalentTree  │          │
│  │(祝福管理)   │  │(诅咒管理)   │  │(天赋树)     │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ShopCtrl     │  │  ItemPool   │  │ SetBonusMgr │          │
│  │(商店控制)   │  │(道具池/掉落)│  │(套装管理)   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└───────────────────────────────────────────────────────────────┘
```

### 4.1.2 核心类职责

| 类 | 职责 | 生命周期 |
|----|------|---------|
| `ItemRegistry` | 全局道具注册中心，存储所有ItemData SO引用 | 全局单例，游戏启动时加载 |
| `ItemData` | Resource，定义道具静态数据 | 编辑时创建，运行时只读 |
| `ItemInstance` | 运行时道具实例，含堆叠数、唯一ID | 随Inventory创建/销毁 |
| `Inventory` | 玩家背包，管理20被动+2主动槽位 | 随Player创建 |
| `ItemEffectProcessor` | 事件驱动的道具效果触发与执行 | 全局单例 |
| `SynergyEngine` | 联动条件检测与联动效果应用 | 全局单例 |
| `BlessingManager` | 祝福获取/移除/效果应用 | 全局单例 |
| `CurseManager` | 诅咒获取/移除/双刃剑效果处理 | 全局单例 |
| `TalentTree` | 天赋选择/路线管理/效果应用 | 随Player创建 |
| `ShopController` | 商店商品生成/定价/交易 | 房间级 |
| `ItemPool` | 道具池管理/权重选择/稀有度判定 | 全局单例 |
| `SetBonusManager` | 套装件数检测/套装效果应用 | 全局单例 |

### 4.1.3 初始化流程

```text
public class ItemSystemInitializer : Node
{
     private ItemData[] allItemDatas;
     private BlessingData[] allBlessingDatas;
     private CurseData[] allCurseDatas;
    
    private void Awake()
    {
        // 1. 注册所有道具数据
        var registry = ServiceRegistry.Register<ItemRegistry>(new ItemRegistry());
        foreach (var data in allItemDatas)
            registry.Register(data);
            
        // 2. 初始化效果处理器
        var effectProcessor = ServiceRegistry.Register<ItemEffectProcessor>(new ItemEffectProcessor());
        
        // 3. 初始化联动引擎
        var synergyEngine = ServiceRegistry.Register<SynergyEngine>(new SynergyEngine());
        
        // 4. 初始化祝福/诅咒管理器
        ServiceRegistry.Register<BlessingManager>(new BlessingManager(allBlessingDatas));
        ServiceRegistry.Register<CurseManager>(new CurseManager(allCurseDatas));
        
        // 5. 初始化道具池
        ServiceRegistry.Register<ItemPool>(new ItemPool(registry));
        
        // 6. 初始化套装管理器
        ServiceRegistry.Register<SetBonusManager>(new SetBonusManager());
        
        // 7. 初始化商店控制器工厂
        ServiceRegistry.Register<ShopControllerFactory>(new ShopControllerFactory());
    }
}
```

---

## 4.2 ItemData完整结构定义

### 4.2.1 ItemData Resource

```text
[CreateAssetMenu(fileName = "ItemData_", menuName = "PlaneWalker/ItemData")]
public class ItemData : Resource
{
    [Header("基础信息")]
    public string itemId;              // 如 "ATK_RAZOR_EDGE_STK"
    public string displayName;         // 如 "锐利之刃"
    public string flavorText;          // 叙事文本
    public string mechanicText;        // 机制文本
    public Sprite icon;
    public Node pickup_scene;    // 掉落物3D表现
    
    [Header("分类")]
    public ItemCategory category;      // ATK/DEF/UTI/SPC/WEP/TIM/ACT
    public WeaponType weaponType;      // 仅WEP类有效：SWORD/BOW/GUN/STAFF/FIST/NONE
    public ItemRarity rarity;          // COMMON/UNCOMMON/LEGENDARY/MYTHIC
    public ItemTriggerType triggerType;// PASSIVE/CONDITIONAL/ACTIVE/SET/STACK_THRESHOLD
    
    [Header("堆叠")]
    public bool isStackable;
    public int maxStack = 1;
    public StackFormula stackFormula;  // LINEAR/DIMINISHING/THRESHOLD
    
    [Header("套装")]
    public string setTag;              // 如 "time_walker"，空字符串表示不属于套装
    
    [Header("效果")]
    public ItemEffect[] effects;       // 道具效果列表
    public ItemCondition[] conditions; // 触发条件列表
    
    [Header("掉落权重")]
    public float baseDropWeight = 1.0f;
    public int shopBasePrice = 80;
    
    [Header("联动")]
    public string[] synergyIds;        // 可联动的道具ID列表
    public string[] antiSynergyIds;    // 反联动道具ID列表
    
    [Header("解锁")]
    public bool isDefaultUnlocked = true;
    public UnlockCondition unlockCondition;
}

// 枚举定义
public enum ItemCategory { ATK, DEF, UTI, SPC, WEP, TIM, ACT }
public enum WeaponType { NONE, SWORD, BOW, GUN, STAFF, FIST }
public enum ItemRarity { COMMON, UNCOMMON, LEGENDARY, MYTHIC }
public enum ItemTriggerType { PASSIVE, CONDITIONAL, ACTIVE, SET, STACK_THRESHOLD }
public enum StackFormula { LINEAR, DIMINISHING, THRESHOLD }
public enum DamageType { PHYSICAL, FIRE, ICE, LIGHTNING, TIME, VOID, EXISTENTIAL }
public enum StatType { ATK, DEF, HP, SPD, ASPD, CRIT_RATE, CRIT_DMG, LCK, PICKUP_RANGE, LIFESTEAL, TIME_ENERGY_MAX, TIME_ENERGY_REGEN }

// 效果定义
[Serializable]
public class ItemEffect
{
    public string effectId;            // 唯一标识
    public EffectType effectType;      // 效果类型
    public StatType statType;          // 修改的属性
    public float baseValue;            // 基础值
    public float stackMultiplier = 1.0f;// 每层额外乘数
    public DamageType damageType;      // 伤害类型(如有)
    public float triggerChance = 1.0f; // 触发概率
    public float cooldown;             // 冷却时间(秒)
    public float duration;             // 持续时间(秒)
    public float radius;               // 范围(米)
    public string conditionId;         // 依赖的条件ID
    public string description;         // 效果描述
}

public enum EffectType
{
    STAT_MODIFY,           // 属性修改
    ON_HIT_DAMAGE,         // 命中时附加伤害
    ON_KILL_HEAL,          // 击杀时回复
    ON_HIT_BUFF,           // 命中时给自身buff
    ON_DODGE_BUFF,         // 闪避时buff
    ON_TIME_MANIPULATION,  // 时间操控时触发
    SHIELD_GENERATE,       // 护盾生成
    DAMAGE_REFLECT,        // 反伤
    AOE_DAMAGE,            // 范围伤害
    PROJECTILE_EXTRA,      // 额外投射物
    DOT_APPLY,             // 施加DOT
    DEBUFF_APPLY,          // 施加debuff
    SUMMON,                // 召唤物
    SPECIAL                // 特殊效果(需自定义逻辑)
}

// 条件定义
[Serializable]
public class ItemCondition
{
    public string conditionId;
    public ConditionType type;
    public float threshold;
    public float checkInterval;
    public GameEventType listenEvent;  // 监听的事件类型
    
    // 条件类型
    public enum ConditionType
    {
        ON_HIT,              // 命中时
        ON_KILL,             // 击杀时
        ON_DAMAGED,          // 受击时
        ON_DODGE,            // 闪避时
        ON_CRIT,             // 暴击时
        ON_TIME_REWIND,      // 时间回溯时
        ON_TIME_FREEZE,      // 时间冻结时
        ON_TIME_ACCEL,       // 时间加速时
        ON_TIME_SLOW,        // 时间减速时
        HP_BELOW,            // 生命低于阈值
        HP_ABOVE,            // 生命高于阈值
        STACK_COUNT_ABOVE,   // 堆叠数达到阈值
        COMBO_COUNT_ABOVE,   // 连击数达到阈值
        ALWAYS,              // 常驻
        ON_ACTIVE_USE        // 主动使用
    }
}

// 解锁条件
[Serializable]
public class UnlockCondition
{
    public UnlockType type;
    public string parameter;           // 武器类型/Boss ID等
    public int requiredCount = 1;
    
    public enum UnlockType
    {
        KILL_BOSS_WITH_WEAPON,  // 用特定武器击杀Boss
        CLEAR_FLOOR,            // 通关任意难度
        HIDDEN_CHALLENGE,       // 完成隐藏挑战
        CUMULATIVE_ACQUIRE,     // 累计获得N次
        FIRST_SYNERGY,          // 首次触发特定联动
    }
}
```

### 4.2.2 ItemInstance 运行时实例

```text
public class ItemInstance
{
    public string InstanceId { get; }
    public string ItemId { get; }
    public ItemData Data { get; }
    public int StackCount { get; private set; }
    public bool IsDiscovered { get; set; }
    public float CooldownTimer { get; set; }
    public bool IsOnCooldown => CooldownTimer > 0;
    
    private static int _nextInstanceId = 0;
    
    public ItemInstance(ItemData data, int initialStack = 1)
    {
        InstanceId = $"item_{_nextInstanceId++}_{data.itemId}_{System.Guid.NewGuid():N}";
        ItemId = data.itemId;
        Data = data;
        StackCount = math.Clamp(initialStack, 1, data.maxStack);
        IsDiscovered = false;
        CooldownTimer = 0f;
    }
    
    public bool TryAddStack(int amount, out int overflow)
    {
        if (!Data.isStackable)
        {
            overflow = amount;
            return false;
        }
        int newCount = StackCount + amount;
        int max = Data.maxStack;
        StackCount = math.Min(newCount, max);
        overflow = math.Max(0, newCount - max);
        return true;
    }
    
    public void RemoveStack(int amount)
    {
        StackCount = math.Max(0, StackCount - amount);
    }
    
    public void TickCooldown(float deltaTime)
    {
        if (CooldownTimer > 0)
            CooldownTimer = math.Max(0, CooldownTimer - deltaTime);
    }
    
    /// <summary>
    /// 根据堆叠公式计算当前效果值
    /// </summary>
    public float GetEffectValue(ItemEffect effect)
    {
        return Data.stackFormula switch
        {
            StackFormula.LINEAR => effect.baseValue + effect.stackMultiplier * (StackCount - 1),
            StackFormula.DIMINISHING => effect.baseValue * (1f - math.Pow(0.3f, StackCount - 1)),
            StackFormula.THRESHOLD => StackCount >= effect.stackMultiplier ? effect.baseValue : 0f,
            _ => effect.baseValue
        };
    }
}
```

### 4.2.3 JSON Schema（ItemData序列化格式）

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ItemData",
  "type": "object",
  "required": ["itemId", "displayName", "category", "rarity", "triggerType", "effects"],
  "properties": {
    "itemId": { "type": "string", "pattern": "^[A-Z]+_[A-Z_]+(_STK)?$" },
    "displayName": { "type": "string", "minLength": 2, "maxLength": 10 },
    "flavorText": { "type": "string", "minLength": 15, "maxLength": 50 },
    "mechanicText": { "type": "string", "minLength": 10 },
    "category": { "enum": ["ATK","DEF","UTI","SPC","WEP","TIM","ACT"] },
    "weaponType": { "enum": ["NONE","SWORD","BOW","GUN","STAFF","FIST"], "default": "NONE" },
    "rarity": { "enum": ["COMMON","UNCOMMON","LEGENDARY","MYTHIC"] },
    "triggerType": { "enum": ["PASSIVE","CONDITIONAL","ACTIVE","SET","STACK_THRESHOLD"] },
    "isStackable": { "type": "boolean", "default": false },
    "maxStack": { "type": "integer", "minimum": 1, "default": 1 },
    "stackFormula": { "enum": ["LINEAR","DIMINISHING","THRESHOLD"], "default": "LINEAR" },
    "setTag": { "type": "string", "default": "" },
    "effects": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["effectId", "effectType", "baseValue"],
        "properties": {
          "effectId": { "type": "string" },
          "effectType": { "enum": ["STAT_MODIFY","ON_HIT_DAMAGE","ON_KILL_HEAL","ON_HIT_BUFF","ON_DODGE_BUFF","ON_TIME_MANIPULATION","SHIELD_GENERATE","DAMAGE_REFLECT","AOE_DAMAGE","PROJECTILE_EXTRA","DOT_APPLY","DEBUFF_APPLY","SUMMON","SPECIAL"] },
          "statType": { "enum": ["ATK","DEF","HP","SPD","ASPD","CRIT_RATE","CRIT_DMG","LCK","PICKUP_RANGE","LIFESTEAL","TIME_ENERGY_MAX","TIME_ENERGY_REGEN"] },
          "baseValue": { "type": "number" },
          "stackMultiplier": { "type": "number", "default": 1.0 },
          "damageType": { "enum": ["PHYSICAL","FIRE","ICE","LIGHTNING","TIME","VOID","EXISTENTIAL"] },
          "triggerChance": { "type": "number", "minimum": 0, "maximum": 1, "default": 1.0 },
          "cooldown": { "type": "number", "minimum": 0, "default": 0 },
          "duration": { "type": "number", "minimum": 0, "default": 0 },
          "radius": { "type": "number", "minimum": 0, "default": 0 }
        }
      }
    },
    "conditions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["conditionId", "type"],
        "properties": {
          "conditionId": { "type": "string" },
          "type": { "enum": ["ON_HIT","ON_KILL","ON_DAMAGED","ON_DODGE","ON_CRIT","ON_TIME_REWIND","ON_TIME_FREEZE","ON_TIME_ACCEL","ON_TIME_SLOW","HP_BELOW","HP_ABOVE","STACK_COUNT_ABOVE","COMBO_COUNT_ABOVE","ALWAYS","ON_ACTIVE_USE"] },
          "threshold": { "type": "number", "default": 0 },
          "checkInterval": { "type": "number", "default": 0 },
          "listenEvent": { "type": "string", "default": "" }
        }
      }
    },
    "baseDropWeight": { "type": "number", "default": 1.0 },
    "shopBasePrice": { "type": "integer", "default": 80 },
    "synergyIds": { "type": "array", "items": { "type": "string" } },
    "antiSynergyIds": { "type": "array", "items": { "type": "string" } },
    "isDefaultUnlocked": { "type": "boolean", "default": true },
    "unlockCondition": {
      "type": "object",
      "properties": {
        "type": { "enum": ["KILL_BOSS_WITH_WEAPON","CLEAR_FLOOR","HIDDEN_CHALLENGE","CUMULATIVE_ACQUIRE","FIRST_SYNERGY"] },
        "parameter": { "type": "string" },
        "requiredCount": { "type": "integer", "default": 1 }
      }
    }
  }
}
```

---

## 4.3 Inventory实现

### 4.3.1 Inventory核心类

```text
public class Inventory
{
    // 槽位常量
    public const int MAX_PASSIVE_SLOTS = 20;
    public const int MAX_ACTIVE_SLOTS = 2;
    
    // 事件
    public event System.Action<ItemInstance, int> OnItemAdded;
    public event System.Action<ItemInstance, int> OnItemRemoved;
    public event System.Action<ItemInstance, int, int> OnItemReplaced; // (newItem, removedSlot, newSlot)
    public event System.Action OnInventoryChanged;
    
    // 被动道具槽位
    private readonly List<ItemInstance> _passiveItems = new(MAX_PASSIVE_SLOTS);
    public IReadOnlyList<ItemInstance> PassiveItems => _passiveItems;
    public int PassiveCount => _passiveItems.Count;
    public bool IsPassiveFull => _passiveItems.Count >= MAX_PASSIVE_SLOTS;
    
    // 主动道具槽位
    private readonly ItemInstance?[] _activeItems = new ItemInstance?[MAX_ACTIVE_SLOTS];
    public ItemInstance? GetActiveItem(int slot) => _activeItems[slot];
    public bool IsActiveSlotOccupied(int slot) => _activeItems[slot] != null;
    
    // 快速查找索引
    private readonly Dictionary<string, ItemInstance> _itemById = new();
    
    /// <summary>
    /// 添加被动道具
    /// </summary>
    /// <returns>是否成功添加</returns>
    public bool TryAddPassiveItem(ItemData data, out ItemInstance instance)
    {
        instance = null;
        
        // 可堆叠道具：检查已有同类
        if (data.isStackable && _itemById.TryGetValue(data.itemId, out var existing))
        {
            int overflow;
            existing.TryAddStack(1, out overflow);
            if (overflow == 0)
            {
                OnInventoryChanged?.Invoke();
                EventBus.Publish(new ItemStackChangedEvent(existing, existing.StackCount));
                return true;
            }
            // 堆叠溢出时作为新实例处理
        }
        
        // 槽位已满
        if (IsPassiveFull)
            return false;
        
        // 创建新实例
        instance = new ItemInstance(data);
        _passiveItems.Add(instance);
        _itemById[data.itemId] = instance;
        
        OnItemAdded?.Invoke(instance, _passiveItems.Count - 1);
        OnInventoryChanged?.Invoke();
        EventBus.Publish(new ItemAcquiredEvent(instance));
        
        return true;
    }
    
    /// <summary>
    /// 添加主动道具
    /// </summary>
    public bool TryAddActiveItem(ItemData data, int slot, out ItemInstance instance)
    {
        instance = null;
        if (slot < 0 || slot >= MAX_ACTIVE_SLOTS)
            return false;
        if (_activeItems[slot] != null)
            return false;
            
        instance = new ItemInstance(data);
        _activeItems[slot] = instance;
        _itemById[data.itemId] = instance;
        
        OnItemAdded?.Invoke(instance, slot);
        OnInventoryChanged?.Invoke();
        EventBus.Publish(new ItemAcquiredEvent(instance));
        
        return true;
    }
    
    /// <summary>
    /// 强制添加道具（槽位满时触发替换选择）
    /// </summary>
    public AddItemResult TryAddItemWithReplacement(ItemData data, System.Action<ItemInstance, ItemData, System.Action<int>> onReplacementNeeded)
    {
        // 优先尝试正常添加
        if (TryAddPassiveItem(data, out var instance))
            return AddItemResult.Added;
        
        if (!data.isStackable && IsPassiveFull)
        {
            // 触发替换流程
            onReplacementNeeded?.Invoke(null, data, (replaceIndex) =>
            {
                ReplacePassiveItem(replaceIndex, data);
            });
            return AddItemResult.PendingReplacement;
        }
        
        return AddItemResult.Failed;
    }
    
    /// <summary>
    /// 替换被动道具
    /// </summary>
    public ItemInstance ReplacePassiveItem(int slotIndex, ItemData newData)
    {
        if (slotIndex < 0 || slotIndex >= _passiveItems.Count)
            throw new System.ArgumentOutOfRangeException(nameof(slotIndex));
            
        var oldItem = _passiveItems[slotIndex];
        _itemById.Remove(oldItem.ItemId);
        
        var newInstance = new ItemInstance(newData);
        _passiveItems[slotIndex] = newInstance;
        _itemById[newData.itemId] = newInstance;
        
        OnItemRemoved?.Invoke(oldItem, slotIndex);
        OnItemReplaced?.Invoke(newInstance, slotIndex, slotIndex);
        OnInventoryChanged?.Invoke();
        
        EventBus.Publish(new ItemRemovedEvent(oldItem));
        EventBus.Publish(new ItemAcquiredEvent(newInstance));
        
        return oldItem;
    }
    
    /// <summary>
    /// 移除被动道具
    /// </summary>
    public bool RemovePassiveItem(string itemId)
    {
        var instance = _passiveItems.Find(i => i.ItemId == itemId);
        if (instance == null) return false;
        
        int index = _passiveItems.IndexOf(instance);
        _passiveItems.RemoveAt(index);
        _itemById.Remove(itemId);
        
        OnItemRemoved?.Invoke(instance, index);
        OnInventoryChanged?.Invoke();
        EventBus.Publish(new ItemRemovedEvent(instance));
        
        return true;
    }
    
    /// <summary>
    /// 获取道具实例
    /// </summary>
    public ItemInstance GetItem(string itemId)
    {
        return _itemById.GetValueOrDefault(itemId);
    }
    
    /// <summary>
    /// 是否拥有某道具
    /// </summary>
    public bool HasItem(string itemId)
    {
        return _itemById.ContainsKey(itemId);
    }
    
    /// <summary>
    /// 获取道具堆叠数
    /// </summary>
    public int GetStackCount(string itemId)
    {
        return _itemById.TryGetValue(itemId, out var inst) ? inst.StackCount : 0;
    }
    
    /// <summary>
    /// 使用主动道具
    /// </summary>
    public bool UseActiveItem(int slot)
    {
        var item = _activeItems[slot];
        if (item == null || item.IsOnCooldown) return false;
        
        item.CooldownTimer = item.Data.effects.FirstOrDefault()?.cooldown ?? 0f;
        EventBus.Publish(new ActiveItemUsedEvent(item, slot));
        return true;
    }
    
    /// <summary>
    /// 更新冷却
    /// </summary>
    public void TickCooldowns(float deltaTime)
    {
        foreach (var item in _passiveItems)
            item.TickCooldown(deltaTime);
        for (int i = 0; i < MAX_ACTIVE_SLOTS; i++)
            _activeItems[i]?.TickCooldown(deltaTime);
    }
    
    /// <summary>
    /// 获取所有道具（被动+主动）
    /// </summary>
    public IEnumerable<ItemInstance> GetAllItems()
    {
        foreach (var item in _passiveItems)
            yield return item;
        for (int i = 0; i < MAX_ACTIVE_SLOTS; i++)
            if (_activeItems[i] != null)
                yield return _activeItems[i]!;
    }
    
    /// <summary>
    /// 清空背包
    /// </summary>
    public void Clear()
    {
        _passiveItems.Clear();
        _itemById.Clear();
        for (int i = 0; i < MAX_ACTIVE_SLOTS; i++)
            _activeItems[i] = null;
        OnInventoryChanged?.Invoke();
    }
}

public enum AddItemResult { Added, Failed, PendingReplacement }
```

### 4.3.2 事件定义

```text
// 道具相关事件
public readonly struct ItemAcquiredEvent : IEvent
{
    public readonly ItemInstance Item;
    public ItemAcquiredEvent(ItemInstance item) => Item = item;
}

public readonly struct ItemRemovedEvent : IEvent
{
    public readonly ItemInstance Item;
    public ItemRemovedEvent(ItemInstance item) => Item = item;
}

public readonly struct ItemStackChangedEvent : IEvent
{
    public readonly ItemInstance Item;
    public readonly int NewCount;
    public ItemStackChangedEvent(ItemInstance item, int newCount) { Item = item; NewCount = newCount; }
}

public readonly struct ActiveItemUsedEvent : IEvent
{
    public readonly ItemInstance Item;
    public readonly int Slot;
    public ActiveItemUsedEvent(ItemInstance item, int slot) { Item = item; Slot = slot; }
}

// 战斗相关事件（供ItemEffectProcessor使用）
public readonly struct OnHitEvent : IEvent
{
    public readonly Entity Attacker;
    public readonly Entity Target;
    public readonly float Damage;
    public readonly DamageType DamageType;
    public readonly bool IsCritical;
    public OnHitEvent(Entity attacker, Entity target, float damage, DamageType dmgType, bool isCrit)
        => (Attacker, Target, Damage, DamageType, IsCritical) = (attacker, target, damage, dmgType, isCrit);
}

public readonly struct OnKillEvent : IEvent
{
    public readonly Entity Killer;
    public readonly Entity Victim;
    public OnKillEvent(Entity killer, Entity victim) => (Killer, Victim) = (killer, victim);
}

public readonly struct OnDamagedEvent : IEvent
{
    public readonly Entity Target;
    public readonly float Damage;
    public readonly Entity Source;
    public OnDamagedEvent(Entity target, float damage, Entity source) => (Target, Damage, Source) = (target, damage, source);
}

public readonly struct OnDodgeEvent : IEvent
{
    public readonly Entity Dodger;
    public readonly Vector3 Position;
    public OnDodgeEvent(Entity dodger, Vector3 pos) => (Dodger, Position) = (dodger, pos);
}

public readonly struct OnTimeManipulationEvent : IEvent
{
    public readonly TimeManipType Type;
    public readonly Entity Caster;
    public readonly float Duration;
    public enum TimeManipType { Rewind, Freeze, Accel, Slow }
    public OnTimeManipulationEvent(TimeManipType type, Entity caster, float duration)
        => (Type, Caster, Duration) = (type, caster, duration);
}
```

---

## 4.4 道具效果处理器

### 4.4.1 ItemEffectProcessor

```text
public class ItemEffectProcessor
{
    private readonly Dictionary<string, System.Action<ItemEffect, ItemInstance, IEvent>> _effectHandlers = new();
    private readonly Dictionary<GameEventType, List<(ItemInstance item, ItemEffect effect, ItemCondition condition)>> _eventSubscribers = new();
    
    private Inventory _inventory;
    private PlayerStats _playerStats;
    
    public void Initialize(Inventory inventory, PlayerStats playerStats)
    {
        _inventory = inventory;
        _playerStats = playerStats;
        
        RegisterBuiltinHandlers();
        SubscribeToEvents();
    }
    
    private void RegisterBuiltinHandlers()
    {
        _effectHandlers[EffectType.STAT_MODIFY.ToString()] = HandleStatModify;
        _effectHandlers[EffectType.ON_HIT_DAMAGE.ToString()] = HandleOnHitDamage;
        _effectHandlers[EffectType.ON_KILL_HEAL.ToString()] = HandleOnKillHeal;
        _effectHandlers[EffectType.ON_HIT_BUFF.ToString()] = HandleOnHitBuff;
        _effectHandlers[EffectType.ON_DODGE_BUFF.ToString()] = HandleOnDodgeBuff;
        _effectHandlers[EffectType.ON_TIME_MANIPULATION.ToString()] = HandleOnTimeManip;
        _effectHandlers[EffectType.SHIELD_GENERATE.ToString()] = HandleShieldGenerate;
        _effectHandlers[EffectType.DAMAGE_REFLECT.ToString()] = HandleDamageReflect;
        _effectHandlers[EffectType.AOE_DAMAGE.ToString()] = HandleAoeDamage;
        _effectHandlers[EffectType.PROJECTILE_EXTRA.ToString()] = HandleProjectileExtra;
        _effectHandlers[EffectType.DOT_APPLY.ToString()] = HandleDotApply;
        _effectHandlers[EffectType.DEBUFF_APPLY.ToString()] = HandleDebuffApply;
        _effectHandlers[EffectType.SUMMON.ToString()] = HandleSummon;
        _effectHandlers[EffectType.SPECIAL.ToString()] = HandleSpecial;
    }
    
    private void SubscribeToEvents()
    {
        EventBus.Subscribe<OnHitEvent>(OnHit);
        EventBus.Subscribe<OnKillEvent>(OnKill);
        EventBus.Subscribe<OnDamagedEvent>(OnDamaged);
        EventBus.Subscribe<OnDodgeEvent>(OnDodge);
        EventBus.Subscribe<OnTimeManipulationEvent>(OnTimeManipulation);
        EventBus.Subscribe<ItemAcquiredEvent>(OnItemAcquired);
        EventBus.Subscribe<ItemRemovedEvent>(OnItemRemoved);
    }
    
    /// <summary>
    /// 注册道具后，解析其条件并订阅对应事件
    /// </summary>
    public void RegisterItemEffects(ItemInstance instance)
    {
        foreach (var effect in instance.Data.effects)
        {
            var condition = instance.Data.conditions.FirstOrDefault(c => c.conditionId == effect.conditionId);
            if (condition == null) continue;
            
            var eventType = ConditionToEventType(condition.type);
            if (!_eventSubscribers.ContainsKey(eventType))
                _eventSubscribers[eventType] = new();
            _eventSubscribers[eventType].Add((instance, effect, condition));
        }
        
        // 被动常驻效果立即应用
        foreach (var effect in instance.Data.effects)
        {
            var condition = instance.Data.conditions.FirstOrDefault(c => c.conditionId == effect.conditionId);
            if (condition != null && condition.type == ItemCondition.ConditionType.ALWAYS)
            {
                ApplyEffect(effect, instance, null);
            }
        }
    }
    
    /// <summary>
    /// 移除道具效果
    /// </summary>
    public void UnregisterItemEffects(ItemInstance instance)
    {
        // 移除事件订阅
        foreach (var kvp in _eventSubscribers)
            kvp.Value.RemoveAll(t => t.item == instance);
        
        // 移除常驻属性修改
        foreach (var effect in instance.Data.effects)
        {
            var condition = instance.Data.conditions.FirstOrDefault(c => c.conditionId == effect.conditionId);
            if (condition != null && condition.type == ItemCondition.ConditionType.ALWAYS)
            {
                RemoveStatEffect(effect, instance);
            }
        }
    }
    
    // ===== 事件回调 =====
    
    private void OnHit(OnHitEvent evt)
    {
        ProcessEvent(GameEventType.ON_HIT, evt, (effect, inst, cond) =>
        {
            if (inst.IsOnCooldown) return;
            if (Random.value > inst.GetEffectValue(effect) * (effect.triggerChance > 0 ? 1 : 1)) return;
            ApplyEffect(effect, inst, evt);
            if (effect.cooldown > 0) inst.CooldownTimer = effect.cooldown;
        });
    }
    
    private void OnKill(OnKillEvent evt)
    {
        ProcessEvent(GameEventType.ON_KILL, evt, (effect, inst, cond) =>
        {
            ApplyEffect(effect, inst, evt);
        });
    }
    
    private void OnDamaged(OnDamagedEvent evt)
    {
        ProcessEvent(GameEventType.ON_DAMAGED, evt, (effect, inst, cond) =>
        {
            if (inst.IsOnCooldown) return;
            float chance = effect.triggerChance > 0 ? effect.triggerChance : 1f;
            if (Random.value > chance) return;
            ApplyEffect(effect, inst, evt);
            if (effect.cooldown > 0) inst.CooldownTimer = effect.cooldown;
        });
    }
    
    private void OnDodge(OnDodgeEvent evt)
    {
        ProcessEvent(GameEventType.ON_DODGE, evt, (effect, inst, cond) =>
        {
            ApplyEffect(effect, inst, evt);
        });
    }
    
    private void OnTimeManipulation(OnTimeManipulationEvent evt)
    {
        ProcessEvent(GameEventType.ON_TIME_MANIP, evt, (effect, inst, cond) =>
        {
            ApplyEffect(effect, inst, evt);
        });
    }
    
    private void OnItemAcquired(ItemAcquiredEvent evt)
    {
        RegisterItemEffects(evt.Item);
    }
    
    private void OnItemRemoved(ItemRemovedEvent evt)
    {
        UnregisterItemEffects(evt.Item);
    }
    
    /// <summary>
    /// 通用事件处理分发
    /// </summary>
    private void ProcessEvent(GameEventType eventType, IEvent evt, 
        System.Action<ItemEffect, ItemInstance, ItemCondition> processor)
    {
        if (!_eventSubscribers.TryGetValue(eventType, out var subscribers)) return;
        foreach (var (item, effect, condition) in subscribers)
        {
            if (!CheckCondition(condition, item, evt)) continue;
            processor(effect, item, condition);
        }
    }
    
    /// <summary>
    /// 条件判定
    /// </summary>
    private bool CheckCondition(ItemCondition condition, ItemInstance item, IEvent evt)
    {
        return condition.type switch
        {
            ItemCondition.ConditionType.ON_HIT => evt is OnHitEvent,
            ItemCondition.ConditionType.ON_KILL => evt is OnKillEvent,
            ItemCondition.ConditionType.ON_DAMAGED => evt is OnDamagedEvent,
            ItemCondition.ConditionType.ON_DODGE => evt is OnDodgeEvent,
            ItemCondition.ConditionType.ON_CRIT => evt is OnHitEvent hit && hit.IsCritical,
            ItemCondition.ConditionType.ON_TIME_REWIND => evt is OnTimeManipulationEvent tm && tm.Type == OnTimeManipulationEvent.TimeManipType.Rewind,
            ItemCondition.ConditionType.ON_TIME_FREEZE => evt is OnTimeManipulationEvent tm2 && tm2.Type == OnTimeManipulationEvent.TimeManipType.Freeze,
            ItemCondition.ConditionType.ON_TIME_ACCEL => evt is OnTimeManipulationEvent tm3 && tm3.Type == OnTimeManipulationEvent.TimeManipType.Accel,
            ItemCondition.ConditionType.ON_TIME_SLOW => evt is OnTimeManipulationEvent tm4 && tm4.Type == OnTimeManipulationEvent.TimeManipType.Slow,
            ItemCondition.ConditionType.HP_BELOW => _playerStats.CurrentHpPercent <= condition.threshold,
            ItemCondition.ConditionType.HP_ABOVE => _playerStats.CurrentHpPercent >= condition.threshold,
            ItemCondition.ConditionType.STACK_COUNT_ABOVE => item.StackCount >= (int)condition.threshold,
            ItemCondition.ConditionType.ALWAYS => true,
            ItemCondition.ConditionType.ON_ACTIVE_USE => evt is ActiveItemUsedEvent,
            _ => false
        };
    }
    
    // ===== 效果应用 =====
    
    private void ApplyEffect(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (_effectHandlers.TryGetValue(effect.effectType.ToString(), out var handler))
            handler(effect, item, evt);
    }
    
    private void HandleStatModify(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        float value = item.GetEffectValue(effect);
        _playerStats.ModifyStat(effect.statType, value, StatModSource.Item, item.InstanceId);
    }
    
    private void RemoveStatEffect(ItemEffect effect, ItemInstance item)
    {
        float value = item.GetEffectValue(effect);
        _playerStats.RemoveModifier(effect.statType, StatModSource.Item, item.InstanceId);
    }
    
    private void HandleOnHitDamage(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnHitEvent hitEvt) return;
        float value = item.GetEffectValue(effect);
        float damage = _playerStats.GetStat(StatType.ATK) * value;
        
        if (Random.value > effect.triggerChance) return;
        if (item.IsOnCooldown) return;
        
        DamageApplier.ApplyDamage(hitEvt.Target, damage, effect.damageType);
        if (effect.cooldown > 0) item.CooldownTimer = effect.cooldown;
    }
    
    private void HandleOnKillHeal(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnKillEvent killEvt) return;
        float value = item.GetEffectValue(effect);
        float healAmount = _playerStats.GetStat(StatType.HP) * value;
        _playerStats.Heal(healAmount);
    }
    
    private void HandleOnHitBuff(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        float value = item.GetEffectValue(effect);
        BuffSystem.ApplyBuff(_playerStats.Entity, effect.effectId, effect.statType, value, effect.duration);
    }
    
    private void HandleOnDodgeBuff(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        float value = item.GetEffectValue(effect);
        BuffSystem.ApplyBuff(_playerStats.Entity, effect.effectId, effect.statType, value, effect.duration);
    }
    
    private void HandleOnTimeManip(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnTimeManipulationEvent tmEvt) return;
        float value = item.GetEffectValue(effect);
        // 具体效果由Special Effect或联动系统处理
        EventBus.Publish(new TimeItemTriggeredEvent(item, tmEvt.Type, value));
    }
    
    private void HandleShieldGenerate(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (item.IsOnCooldown) return;
        float value = item.GetEffectValue(effect);
        float shieldAmount = _playerStats.GetStat(StatType.HP) * value;
        _playerStats.AddShield(shieldAmount, effect.duration > 0 ? effect.duration : 5f);
        if (effect.cooldown > 0) item.CooldownTimer = effect.cooldown;
    }
    
    private void HandleDamageReflect(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnDamagedEvent dmgEvt) return;
        float value = item.GetEffectValue(effect);
        float reflectDamage = dmgEvt.Damage * value;
        DamageApplier.ApplyDamage(dmgEvt.Source, reflectDamage, DamageType.PHYSICAL);
    }
    
    private void HandleAoeDamage(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (item.IsOnCooldown) return;
        float value = item.GetEffectValue(effect);
        float damage = _playerStats.GetStat(StatType.ATK) * value;
        Vector3 center = _playerStats.Entity.Position;
        var hits = PhysicsQuery.OverlapSphere(center, effect.radius, collision_mask.GetMask("Enemy"));
        foreach (var hit in hits)
        {
            var enemy = hit.GetComponent<Entity>();
            if (enemy != null)
                DamageApplier.ApplyDamage(enemy, damage, effect.damageType);
        }
        if (effect.cooldown > 0) item.CooldownTimer = effect.cooldown;
    }
    
    private void HandleProjectileExtra(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        float value = item.GetEffectValue(effect);
        // 通知武器系统发射额外投射物
        EventBus.Publish(new ExtraProjectileEvent((int)value, effect.damageType));
    }
    
    private void HandleDotApply(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnHitEvent hitEvt) return;
        if (Random.value > effect.triggerChance) return;
        float value = item.GetEffectValue(effect);
        float dotDamage = _playerStats.GetStat(StatType.ATK) * value;
        DotSystem.ApplyDot(hitEvt.Target, effect.damageType, dotDamage, effect.duration);
    }
    
    private void HandleDebuffApply(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        if (evt is not OnHitEvent hitEvt) return;
        if (Random.value > effect.triggerChance) return;
        float value = item.GetEffectValue(effect);
        DebuffSystem.ApplyDebuff(hitEvt.Target, effect.effectId, value, effect.duration);
    }
    
    private void HandleSummon(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        float value = item.GetEffectValue(effect);
        SummonSystem.Summon(effect.effectId, _playerStats.Entity, value, effect.duration);
    }
    
    private void HandleSpecial(ItemEffect effect, ItemInstance item, IEvent evt)
    {
        // 特殊效果由各道具的专用处理器处理
        EventBus.Publish(new SpecialEffectTriggeredEvent(item, effect, evt));
    }
    
    // ===== 工具方法 =====
    
    private GameEventType ConditionToEventType(ItemCondition.ConditionType type)
    {
        return type switch
        {
            ItemCondition.ConditionType.ON_HIT => GameEventType.ON_HIT,
            ItemCondition.ConditionType.ON_KILL => GameEventType.ON_KILL,
            ItemCondition.ConditionType.ON_DAMAGED => GameEventType.ON_DAMAGED,
            ItemCondition.ConditionType.ON_DODGE => GameEventType.ON_DODGE,
            ItemCondition.ConditionType.ON_CRIT => GameEventType.ON_HIT,
            ItemCondition.ConditionType.ON_TIME_REWIND => GameEventType.ON_TIME_MANIP,
            ItemCondition.ConditionType.ON_TIME_FREEZE => GameEventType.ON_TIME_MANIP,
            ItemCondition.ConditionType.ON_TIME_ACCEL => GameEventType.ON_TIME_MANIP,
            ItemCondition.ConditionType.ON_TIME_SLOW => GameEventType.ON_TIME_MANIP,
            _ => GameEventType.NONE
        };
    }
}

public enum GameEventType { NONE, ON_HIT, ON_KILL, ON_DAMAGED, ON_DODGE, ON_TIME_MANIP }
```

---

## 4.5 联动引擎

### 4.5.1 SynergyEngine

```text
public class SynergyEngine
{
    private readonly List<SynergyDefinition> _synergyDefinitions = new();
    private readonly Dictionary<string, ActiveSynergy> _activeSynergies = new();
    private readonly List<SynergyDefinition> _synergiesPendingCheck = new();
    
    private Inventory _inventory;
    
    public void Initialize(Inventory inventory)
    {
        _inventory = inventory;
        LoadSynergyDefinitions();
        
        _inventory.OnItemAdded += OnItemAdded;
        _inventory.OnItemRemoved += OnItemRemoved;
        EventBus.Subscribe<ItemAcquiredEvent>(OnItemAcquired);
        EventBus.Subscribe<ItemRemovedEvent>(OnItemRemovedEvent);
    }
    
    /// <summary>
    /// 加载联动定义（从配置文件或硬编码）
    /// </summary>
    private void LoadSynergyDefinitions()
    {
        // 联动 #1: 烈焰之心 + 寒霜核心 = 蒸汽爆发
        _synergyDefinitions.Add(new SynergyDefinition
        {
            synergyId = "SYN_STEAM_BURST",
            itemIdA = "ATK_FLAME_HEART",
            itemIdB = "ATK_FROST_CORE",
            synergyType = SynergyType.NEW_EFFECT,
            effect = new SynergyEffect
            {
                description = "同时对同一敌人施加燃烧和冰冻时，触发蒸汽爆炸",
                damageMultiplier = 1.5f,
                radius = 3f,
                cooldown = 0.5f,
                damageType = DamageType.PHYSICAL
            }
        });
        
        // 联动 #2: 时空裂隙 + 残影透镜 = 回溯斩击
        _synergyDefinitions.Add(new SynergyDefinition
        {
            synergyId = "SYN_REWIND_SLASH",
            itemIdA = "TIM_RIFT_SHARD",
            itemIdB = "TIM_PHANTOM_LENS",
            synergyType = SynergyType.STAT_STACK,
            effect = new SynergyEffect
            {
                description = "残影伤害从ATK×0.5提升至ATK×1.2，残影模仿最后一次攻击",
                statType = StatType.ATK,
                valueOverride = 1.2f
            }
        });
        
        // ... 加载所有30组联动定义 ...
        // 实际项目中从JSON/Resource加载
    }
    
    /// <summary>
    /// 道具获取时检查联动
    /// </summary>
    private void OnItemAcquired(ItemAcquiredEvent evt)
    {
        string newItemId = evt.Item.ItemId;
        
        foreach (var def in _synergyDefinitions)
        {
            if (_activeSynergies.ContainsKey(def.synergyId)) continue;
            
            bool hasA = _inventory.HasItem(def.itemIdA);
            bool hasB = _inventory.HasItem(def.itemIdB);
            
            // 检查是否同时拥有两个联动道具
            if ((def.itemIdA == newItemId && hasB) || (def.itemIdB == newItemId && hasA) || (hasA && hasB))
            {
                ActivateSynergy(def);
            }
        }
        
        // 反联动检查
        CheckAntiSynergies(evt.Item);
    }
    
    /// <summary>
    /// 道具移除时检查联动失效
    /// </summary>
    private void OnItemRemovedEvent(ItemRemovedEvent evt)
    {
        string removedItemId = evt.Item.ItemId;
        
        var toRemove = new List<string>();
        foreach (var kvp in _activeSynergies)
        {
            if (kvp.Value.Definition.itemIdA == removedItemId || 
                kvp.Value.Definition.itemIdB == removedItemId)
            {
                toRemove.Add(kvp.Key);
            }
        }
        
        foreach (var id in toRemove)
            DeactivateSynergy(id);
    }
    
    /// <summary>
    /// 激活联动
    /// </summary>
    private void ActivateSynergy(SynergyDefinition def)
    {
        var active = new ActiveSynergy(def, runtime_time);
        _activeSynergies[def.synergyId] = active;
        
        switch (def.synergyType)
        {
            case SynergyType.STAT_STACK:
                ApplyStatStackSynergy(def);
                break;
            case SynergyType.MECH_REPLACE:
                ApplyMechReplaceSynergy(def);
                break;
            case SynergyType.NEW_EFFECT:
                ApplyNewEffectSynergy(def);
                break;
            case SynergyType.VISUAL:
                ApplyVisualSynergy(def);
                break;
        }
        
        EventBus.Publish(new SynergyActivatedEvent(def));
    }
    
    /// <summary>
    /// 停用联动
    /// </summary>
    private void DeactivateSynergy(string synergyId)
    {
        if (!_activeSynergies.TryGetValue(synergyId, out var active)) return;
        var def = active.Definition;
        
        switch (def.synergyType)
        {
            case SynergyType.STAT_STACK:
                RemoveStatStackSynergy(def);
                break;
            case SynergyType.MECH_REPLACE:
                RemoveMechReplaceSynergy(def);
                break;
            case SynergyType.NEW_EFFECT:
                RemoveNewEffectSynergy(def);
                break;
            case SynergyType.VISUAL:
                RemoveVisualSynergy(def);
                break;
        }
        
        _activeSynergies.Remove(synergyId);
        EventBus.Publish(new SynergyDeactivatedEvent(def));
    }
    
    // ===== 联动类型实现 =====
    
    private void ApplyStatStackSynergy(SynergyDefinition def)
    {
        // 数值叠加：修改道具效果乘数
        var itemA = _inventory.GetItem(def.itemIdA);
        var itemB = _inventory.GetItem(def.itemIdB);
        if (itemA != null && itemB != null)
        {
            // 重算效果值
            foreach (var effect in itemA.Data.effects)
            {
                if (effect.statType == def.effect.statType)
                {
                    // 应用联动加成到PlayerStats
                    ServiceRegistry.Get<PlayerStats>().ModifyStat(
                        def.effect.statType, 
                        def.effect.valueOverride, 
                        StatModSource.Synergy, 
                        def.synergyId);
                }
            }
        }
    }
    
    private void RemoveStatStackSynergy(SynergyDefinition def)
    {
        ServiceRegistry.Get<PlayerStats>().RemoveModifier(
            def.effect.statType, StatModSource.Synergy, def.synergyId);
    }
    
    private void ApplyMechReplaceSynergy(SynergyDefinition def)
    {
        // 机制替换：禁用原有效果，替换为新效果
        // 通过SynergyOverride标记实现
        EventBus.Publish(new SynergyMechOverrideEvent(def.synergyId, def.itemIdA, def.itemIdB, true));
    }
    
    private void RemoveMechReplaceSynergy(SynergyDefinition def)
    {
        EventBus.Publish(new SynergyMechOverrideEvent(def.synergyId, def.itemIdA, def.itemIdB, false));
    }
    
    private void ApplyNewEffectSynergy(SynergyDefinition def)
    {
        // 注册联动事件监听（如蒸汽爆发需要监听双DOT应用）
        if (def.synergyId == "SYN_STEAM_BURST")
        {
            EventBus.Subscribe<OnHitEvent>(OnSteamBurstCheck);
        }
    }
    
    private void RemoveNewEffectSynergy(SynergyDefinition def)
    {
        if (def.synergyId == "SYN_STEAM_BURST")
        {
            EventBus.Unsubscribe<OnHitEvent>(OnSteamBurstCheck);
        }
    }
    
    private void ApplyVisualSynergy(SynergyDefinition def)
    {
        // 纯视觉变化，通知VFX系统
        EventBus.Publish(new SynergyVisualEvent(def.synergyId, true));
    }
    
    private void RemoveVisualSynergy(SynergyDefinition def)
    {
        EventBus.Publish(new SynergyVisualEvent(def.synergyId, false));
    }
    
    // ===== 反联动处理 =====
    
    private void CheckAntiSynergies(ItemInstance newItem)
    {
        foreach (var def in _synergyDefinitions)
        {
            if (def.antiSynergy == null) continue;
            var other = _inventory.GetItem(def.antiSynergy.conflictItemId);
            if (other == null) continue;
            
            // 应用反联动规则
            switch (def.antiSynergy.resolution)
            {
                case AntiSynergyResolution.LATER_WINS:
                    // 后获取的道具使先生效的对同一目标无效
                    other.Data.antiSynergySuppressed = true;
                    break;
                case AntiSynergyResolution.REDUCED_EFFICACY:
                    // 效果减半
                    ApplyEfficacyReduction(newItem, def.antiSynergy.reductionFactor);
                    break;
                case AntiSynergyResolution.MUTUALLY_EXCLUSIVE:
                    // 不应同时出现，记录警告
                    Debug.LogWarning($"Anti-synergy conflict: {newItem.ItemId} + {other.ItemId}");
                    break;
            }
        }
    }
    
    private void ApplyEfficacyReduction(ItemInstance item, float factor)
    {
        // 在ItemEffectProcessor中标记此道具的效果衰减
        ServiceRegistry.Get<ItemEffectProcessor>().SetEfficacyMultiplier(item.InstanceId, factor);
    }
    
    // ===== 蒸汽爆发联动实现 =====
    
    private float _steamBurstCooldown;
    
    private void OnSteamBurstCheck(OnHitEvent evt)
    {
        if (_steamBurstCooldown > 0) return;
        if (!evt.Target.TryGetComponent<StatusEffectHolder>(out var holder)) return;
        
        bool hasBurning = holder.HasStatusEffect("burning");
        bool hasFrozen = holder.HasStatusEffect("frozen");
        
        if (hasBurning && hasFrozen)
        {
            // 触发蒸汽爆发
            float damage = ServiceRegistry.Get<PlayerStats>().GetStat(StatType.ATK) * 1.5f;
            var hits = PhysicsQuery.OverlapSphere(evt.Target.Position, 3f, collision_mask.GetMask("Enemy"));
            foreach (var hit in hits)
            {
                var enemy = hit.GetComponent<Entity>();
                if (enemy != null)
                    DamageApplier.ApplyDamage(enemy, damage, DamageType.PHYSICAL);
            }
            
            // 消耗燃烧和冰冻
            holder.RemoveStatusEffect("burning");
            holder.RemoveStatusEffect("frozen");
            
            _steamBurstCooldown = 0.5f;
        }
    }
    
    public void Update(float deltaTime)
    {
        if (_steamBurstCooldown > 0)
            _steamBurstCooldown -= deltaTime;
    }
}

// ===== 联动数据结构 =====

public enum SynergyType { STAT_STACK, MECH_REPLACE, NEW_EFFECT, VISUAL }

[Serializable]
public class SynergyDefinition
{
    public string synergyId;
    public string itemIdA;
    public string itemIdB;
    public SynergyType synergyType;
    public SynergyEffect effect;
    public AntiSynergyData antiSynergy;
}

[Serializable]
public class SynergyEffect
{
    public string description;
    public StatType statType;
    public float valueOverride;
    public float damageMultiplier;
    public float radius;
    public float cooldown;
    public DamageType damageType;
    public string customEffectId;   // 特殊效果ID
}

[Serializable]
public class AntiSynergyData
{
    public string conflictItemId;
    public AntiSynergyResolution resolution;
    public float reductionFactor = 0.5f;
}

public enum AntiSynergyResolution { LATER_WINS, REDUCED_EFFICACY, MUTUALLY_EXCLUSIVE }

public class ActiveSynergy
{
    public SynergyDefinition Definition { get; }
    public float ActivatedTime { get; }
    public ActiveSynergy(SynergyDefinition def, float time) { Definition = def; ActivatedTime = time; }
}

// 联动事件
public readonly struct SynergyActivatedEvent : IEvent
{
    public readonly SynergyDefinition Definition;
    public SynergyActivatedEvent(SynergyDefinition def) => Definition = def;
}

public readonly struct SynergyDeactivatedEvent : IEvent
{
    public readonly SynergyDefinition Definition;
    public SynergyDeactivatedEvent(SynergyDefinition def) => Definition = def;
}
```

---

## 4.6 祝福系统实现

### 4.6.1 BlessingData Resource

```text
[CreateAssetMenu(fileName = "BlessingData_", menuName = "PlaneWalker/BlessingData")]
public class BlessingData : Resource
{
    public string blessingId;          // 如 "BLS-001", "BG-001", "BT-001"
    public string displayName;
    public string flavorText;
    public string mechanicText;
    public Sprite icon;
    public BlessingRarity rarity;      // COMMON/RARE/EPIC/LEGENDARY
    public BlessingCategory category;  // WEAPON_SWORD/WEAPON_BOW/WEAPON_GUN/WEAPON_STAFF/WEAPON_FIST/GENERAL/TIME
    public WeaponType weaponRestriction;// 仅对该武器类型生效(NONE=通用)
    public BlessingEffect[] effects;
    public string[] advancedSynergyIds; // 进阶效果所需的配合祝福ID
    public float appearWeight = 1f;
}

public enum BlessingRarity { COMMON, RARE, EPIC, LEGENDARY }
public enum BlessingCategory { WEAPON_SWORD, WEAPON_BOW, WEAPON_GUN, WEAPON_STAFF, WEAPON_FIST, GENERAL, TIME }

[Serializable]
public class BlessingEffect
{
    public string effectId;
    public StatType statType;
    public float baseValue;
    public float rarityScaleMultiplier = 1f; // 稀有度系数：COMMON×1.0, RARE×1.5, EPIC×2.0, LEGENDARY×3.0
    public float triggerChance = 1f;
    public float cooldown;
    public float duration;
    public float radius;
    public DamageType damageType;
    public string conditionDescription;
}
```

### 4.6.2 BlessingManager

```text
public class BlessingManager
{
    public const int MAX_BLESSING_SLOTS = 8;
    public const int INITIAL_SLOTS = 3;
    
    private readonly List<BlessingData> _allBlessings;
    private readonly List<BlessingInstance> _activeBlessings = new();
    private readonly HashSet<string> _discoveredBlessings = new();
    private readonly HashSet<string> _lockedOutBlessings = new(); // 本局不再出现的
    
    private int _currentSlots;
    public int CurrentSlots => _currentSlots;
    public int ActiveCount => _activeBlessings.Count;
    public bool IsFull => _activeBlessings.Count >= _currentSlots;
    public IReadOnlyList<BlessingInstance> ActiveBlessings => _activeBlessings;
    
    // 保底计数器
    private int _noRareOrAboveCount = 0;
    private int _noEpicOrAboveCount = 0;
    
    public event System.Action<BlessingInstance> OnBlessingAcquired;
    public event System.Action<BlessingInstance> OnBlessingRemoved;
    public event System.Action<int> OnSlotUnlocked;
    
    public BlessingManager(BlessingData[] allBlessings)
    {
        _allBlessings = new List<BlessingData>(allBlessings);
        _currentSlots = INITIAL_SLOTS;
    }
    
    /// <summary>
    /// 解锁祝福槽位
    /// </summary>
    public void UnlockSlot()
    {
        if (_currentSlots >= MAX_BLESSING_SLOTS) return;
        _currentSlots++;
        OnSlotUnlocked?.Invoke(_currentSlots);
    }
    
    /// <summary>
    /// 根据解锁条件解锁槽位
    /// </summary>
    public void CheckSlotUnlock(int floorIndex, int bossKills)
    {
        // 第2层解锁第4槽
        if (floorIndex >= 2 && _currentSlots < 4) UnlockSlot();
        // 第3层解锁第5槽
        if (floorIndex >= 3 && _currentSlots < 5) UnlockSlot();
        // 击杀第1个Boss解锁第6槽
        if (bossKills >= 1 && _currentSlots < 6) UnlockSlot();
        // 第4层解锁第7槽
        if (floorIndex >= 4 && _currentSlots < 7) UnlockSlot();
        // 击杀最终Boss前解锁第8槽
        if (floorIndex >= 5 && _currentSlots < 8) UnlockSlot();
    }
    
    /// <summary>
    /// 获取祝福选择池（3选1）
    /// </summary>
    public List<BlessingData> GenerateSelectionPool(SeededRNG rng, WeaponType currentWeapon)
    {
        var pool = new List<BlessingData>();
        
        // 过滤可用祝福
        var available = _allBlessings
            .Where(b => !_activeBlessings.Any(a => a.Data.blessingId == b.blessingId)) // 未拥有
            .Where(b => !_lockedOutBlessings.Contains(b.blessingId))                    // 未被锁定
            .Where(b => b.weaponRestriction == WeaponType.NONE || b.weaponRestriction == currentWeapon) // 武器兼容
            .ToList();
        
        // 加入上次未选的祝福(30%概率)
        foreach (var id in _lockedOutBlessings.ToList())
        {
            if (rng.Chance(0.3f))
            {
                var blessing = _allBlessings.Find(b => b.blessingId == id);
                if (blessing != null) available.Add(blessing);
                _lockedOutBlessings.Remove(id);
            }
        }
        
        // 保底机制
        ApplyPitySystem(ref available);
        
        // 加权选择3个
        int count = math.Min(3, available.Count);
        for (int i = 0; i < count; i++)
        {
            var selected = WeightedSelect(available, rng);
            if (selected != null)
            {
                pool.Add(selected);
                available.Remove(selected);
            }
        }
        
        // 记录未选的祝福用于下次30%概率出现
        foreach (var b in pool)
            _lockedOutBlessings.Add(b.blessingId);
        
        return pool;
    }
    
    /// <summary>
    /// 选择祝福
    /// </summary>
    public BlessingInstance AcquireBlessing(BlessingData data)
    {
        _lockedOutBlessings.Remove(data.blessingId);
        
        if (IsFull)
        {
            // 溢出处理：需要先移除一个
            throw new System.InvalidOperationException("Blessing slots full. Use ReplaceBlessing instead.");
        }
        
        var instance = new BlessingInstance(data);
        _activeBlessings.Add(instance);
        
        // 首次发现
        if (!_discoveredBlessings.Contains(data.blessingId))
        {
            _discoveredBlessings.Add(data.blessingId);
            instance.IsFirstDiscovery = true;
        }
        
        ApplyBlessingEffects(instance);
        OnBlessingAcquired?.Invoke(instance);
        EventBus.Publish(new BlessingAcquiredEvent(instance));
        
        // 重置保底计数器
        if (data.rarity >= BlessingRarity.RARE)
            _noRareOrAboveCount = 0;
        if (data.rarity >= BlessingRarity.EPIC)
            _noEpicOrAboveCount = 0;
        
        return instance;
    }
    
    /// <summary>
    /// 替换祝福（溢出时）
    /// </summary>
    public BlessingInstance ReplaceBlessing(int index, BlessingData newData)
    {
        var old = _activeBlessings[index];
        RemoveBlessingEffects(old);
        _activeBlessings.RemoveAt(index);
        OnBlessingRemoved?.Invoke(old);
        EventBus.Publish(new BlessingRemovedEvent(old));
        
        // 补偿1个时间碎片
        EventBus.Publish(new TimeFragmentEarnedEvent(1));
        
        return AcquireBlessing(newData);
    }
    
    /// <summary>
    /// 放弃选择（获得1时间碎片）
    /// </summary>
    public void SkipSelection()
    {
        EventBus.Publish(new TimeFragmentEarnedEvent(1));
    }
    
    /// <summary>
    /// 应用祝福效果
    /// </summary>
    private void ApplyBlessingEffects(BlessingInstance instance)
    {
        float rarityMult = instance.Data.rarity switch
        {
            BlessingRarity.COMMON => 1.0f,
            BlessingRarity.RARE => 1.5f,
            BlessingRarity.EPIC => 2.0f,
            BlessingRarity.LEGENDARY => 3.0f,
            _ => 1.0f
        };
        
        foreach (var effect in instance.Data.effects)
        {
            float finalValue = effect.baseValue * rarityMult;
            if (effect.statType != StatType.ATK) // ATK等属性走PlayerStats
            {
                ServiceRegistry.Get<PlayerStats>().ModifyStat(
                    effect.statType, finalValue, StatModSource.Blessing, instance.Data.blessingId);
            }
        }
        
        // 检查进阶效果
        CheckAdvancedSynergies(instance);
    }
    
    private void RemoveBlessingEffects(BlessingInstance instance)
    {
        foreach (var effect in instance.Data.effects)
        {
            ServiceRegistry.Get<PlayerStats>().RemoveModifier(
                effect.statType, StatModSource.Blessing, instance.Data.blessingId);
        }
    }
    
    /// <summary>
    /// 检查进阶联动效果
    /// </summary>
    private void CheckAdvancedSynergies(BlessingInstance instance)
    {
        foreach (var synergyId in instance.Data.advancedSynergyIds)
        {
            bool hasAll = _activeBlessings.Any(b => b.Data.blessingId == synergyId);
            if (hasAll)
            {
                EventBus.Publish(new BlessingAdvancedSynergyEvent(instance.Data.blessingId, synergyId));
            }
        }
    }
    
    /// <summary>
    /// 保底机制
    /// </summary>
    private void ApplyPitySystem(ref List<BlessingData> available)
    {
        // 连续5次未出现稀有及以上 → 第6次必出
        if (_noRareOrAboveCount >= 5)
        {
            var rareOrAbove = available.Where(b => b.rarity >= BlessingRarity.RARE).ToList();
            if (rareOrAbove.Count > 0)
                available = rareOrAbove;
        }
        
        // 连续10次未出现史诗及以上 → 第11次必出
        if (_noEpicOrAboveCount >= 10)
        {
            var epicOrAbove = available.Where(b => b.rarity >= BlessingRarity.EPIC).ToList();
            if (epicOrAbove.Count > 0)
                available = epicOrAbove;
        }
    }
    
    private BlessingData WeightedSelect(List<BlessingData> pool, SeededRNG rng)
    {
        float total = pool.Sum(b => b.appearWeight);
        float roll = rng.FloatRange(0, total);
        float cumulative = 0;
        foreach (var b in pool)
        {
            cumulative += b.appearWeight;
            if (roll < cumulative) return b;
        }
        return pool.Count > 0 ? pool[pool.Count - 1] : null;
    }
}

public class BlessingInstance
{
    public BlessingData Data { get; }
    public bool IsFirstDiscovery { get; set; }
    public float CooldownTimer { get; set; }
    
    public BlessingInstance(BlessingData data) => Data = data;
}

public readonly struct BlessingAcquiredEvent : IEvent
{
    public readonly BlessingInstance Instance;
    public BlessingAcquiredEvent(BlessingInstance inst) => Instance = inst;
}

public readonly struct BlessingRemovedEvent : IEvent
{
    public readonly BlessingInstance Instance;
    public BlessingRemovedEvent(BlessingInstance inst) => Instance = inst;
}

public readonly struct TimeFragmentEarnedEvent : IEvent
{
    public readonly int Amount;
    public TimeFragmentEarnedEvent(int amount) => Amount = amount;
}
```

---

## 4.7 诅咒系统实现

### 4.7.1 CurseData Resource

```text
[CreateAssetMenu(fileName = "CurseData_", menuName = "PlaneWalker/CurseData")]
public class CurseData : Resource
{
    public string curseId;             // 如 "CU-001"
    public string displayName;
    public string flavorText;
    public string mechanicText;
    public Sprite icon;
    public CurseIntensity intensity;   // MINOR/MODERATE/MAJOR/EXTREME
    public bool hasHiddenNegative;     // 是否有隐藏负面(显示???)
    public string hiddenNegativeDesc;  // 隐藏负面描述
    
    [Header("增益")]
    public CurseEffect[] bonusEffects;
    
    [Header("负面")]
    public CurseEffect[] penaltyEffects;
    
    [Header("风险回报")]
    public float roiEstimate;          // 设计ROI目标值
    public float appearWeight = 1f;
}

public enum CurseIntensity { MINOR, MODERATE, MAJOR, EXTREME }

[Serializable]
public class CurseEffect
{
    public string effectId;
    public StatType statType;
    public float baseValue;
    public bool isPercentage = true;
    public DamageType damageType;
    public string customLogic;         // 自定义逻辑ID
    public float triggerInterval;      // 周期触发间隔(如灼热之触的3秒)
}
```

### 4.7.2 CurseManager

```text
public class CurseManager
{
    public const int MAX_CURSE_SLOTS = 6;
    
    private readonly List<CurseData> _allCurses;
    private readonly List<CurseInstance> _activeCurses = new();
    private readonly Dictionary<string, float> _customTimers = new();
    
    public int ActiveCount => _activeCurses.Count;
    public bool IsFull => _activeCurses.Count >= MAX_CURSE_SLOTS;
    public IReadOnlyList<CurseInstance> ActiveCurses => _activeCurses;
    
    public event System.Action<CurseInstance> OnCurseAccepted;
    public event System.Action<CurseInstance> OnCurseRemoved;
    public event System.Action<CurseInstance> OnCurseRejected;
    
    // 拒绝诅咒后的累积惩罚
    private int _rejectCount = 0;
    public int RejectCount => _rejectCount;
    
    public CurseManager(CurseData[] allCurses)
    {
        _allCurses = new List<CurseData>(allCurses);
    }
    
    /// <summary>
    /// 计算负面效果增幅系数
    /// </summary>
    public float GetPenaltyAmplifier()
    {
        int n = _activeCurses.Count;
        return 1f + 0.15f * (n - 1);
    }
    
    /// <summary>
    /// 获取诅咒选择池（2选1 / 深渊祭坛选择）
    /// </summary>
    public List<CurseData> GenerateSelectionPool(SeededRNG rng, int floorIndex)
    {
        // 第1层不出现诅咒
        if (floorIndex <= 1) return new();
        
        var available = _allCurses
            .Where(c => !_activeCurses.Any(a => a.Data.curseId == c.curseId))
            .Where(c => !IsFull || true) // 满槽仍可选择(替换)
            .ToList();
        
        int count = 2;
        var pool = new List<CurseData>();
        for (int i = 0; i < math.Min(count, available.Count); i++)
        {
            var selected = WeightedSelect(available, rng);
            if (selected != null)
            {
                pool.Add(selected);
                available.Remove(selected);
            }
        }
        
        return pool;
    }
    
    /// <summary>
    /// 接受诅咒
    /// </summary>
    public CurseInstance AcceptCurse(CurseData data)
    {
        if (IsFull)
        {
            throw new System.InvalidOperationException("Curse slots full. Use ReplaceCurse instead.");
        }
        
        var instance = new CurseInstance(data, _activeCurses.Count + 1);
        _activeCurses.Add(instance);
        
        ApplyCurseEffects(instance);
        OnCurseAccepted?.Invoke(instance);
        EventBus.Publish(new CurseAcceptedEvent(instance));
        
        // 检查隐藏诅咒组合
        CheckCurseCombos();
        
        return instance;
    }
    
    /// <summary>
    /// 替换诅咒
    /// </summary>
    public CurseInstance ReplaceCurse(int index, CurseData newData)
    {
        var old = _activeCurses[index];
        RemoveCurseEffects(old);
        _activeCurses.RemoveAt(index);
        OnCurseRemoved?.Invoke(old);
        EventBus.Publish(new CurseRemovedEvent(old));
        
        var newInstance = AcceptCurse(newData);
        // 替换时新诅咒负面+10%
        newInstance.PenaltyMultiplier = 1.1f;
        return newInstance;
    }
    
    /// <summary>
    /// 拒绝诅咒
    /// </summary>
    public void RejectCurse()
    {
        _rejectCount++;
        // 当前房间内所有敌人+10%攻击力和生命值
        EventBus.Publish(new CurseRejectedEvent(_rejectCount));
        OnCurseRejected?.Invoke(null);
    }
    
    /// <summary>
    /// 净化诅咒
    /// </summary>
    public bool PurgeCurse(int index)
    {
        if (index < 0 || index >= _activeCurses.Count) return false;
        
        var curse = _activeCurses[index];
        // 精英诅咒不可净化(设计约束)
        if (curse.Data.intensity == CurseIntensity.EXTREME)
            return false;
            
        RemoveCurseEffects(curse);
        _activeCurses.RemoveAt(index);
        OnCurseRemoved?.Invoke(curse);
        EventBus.Publish(new CurseRemovedEvent(curse));
        
        CheckCurseCombos();
        return true;
    }
    
    /// <summary>
    /// 应用诅咒效果（增益+负面）
    /// </summary>
    private void ApplyCurseEffects(CurseInstance instance)
    {
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        float penaltyAmp = GetPenaltyAmplifier();
        
        // 增益
        foreach (var effect in instance.Data.bonusEffects)
        {
            float value = effect.baseValue;
            playerStats.ModifyStat(effect.statType, value, StatModSource.CurseBonus, instance.InstanceId);
        }
        
        // 负面
        foreach (var effect in instance.Data.penaltyEffects)
        {
            float value = effect.baseValue * penaltyAmp * instance.PenaltyMultiplier;
            playerStats.ModifyStat(effect.statType, -value, StatModSource.CursePenalty, instance.InstanceId);
            
            // 周期性伤害注册
            if (effect.triggerInterval > 0)
            {
                _customTimers[instance.InstanceId + "_" + effect.effectId] = 0f;
            }
        }
    }
    
    private void RemoveCurseEffects(CurseInstance instance)
    {
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        playerStats.RemoveModifiersBySource(StatModSource.CurseBonus, instance.InstanceId);
        playerStats.RemoveModifiersBySource(StatModSource.CursePenalty, instance.InstanceId);
        
        // 清理周期计时器
        var keysToRemove = _customTimers.Keys.Where(k => k.StartsWith(instance.InstanceId)).ToList();
        foreach (var key in keysToRemove)
            _customTimers.Remove(key);
    }
    
    /// <summary>
    /// 更新周期性诅咒效果
    /// </summary>
    public void Update(float deltaTime)
    {
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        
        foreach (var curse in _activeCurses)
        {
            foreach (var effect in curse.Data.penaltyEffects)
            {
                if (effect.triggerInterval <= 0) continue;
                string timerKey = curse.InstanceId + "_" + effect.effectId;
                if (!_customTimers.ContainsKey(timerKey)) continue;
                
                _customTimers[timerKey] += deltaTime;
                if (_customTimers[timerKey] >= effect.triggerInterval)
                {
                    _customTimers[timerKey] -= effect.triggerInterval;
                    
                    // 周期伤害（如灼热之触：每3秒1%最大生命）
                    float dmg = playerStats.GetStat(StatType.HP) * effect.baseValue * GetPenaltyAmplifier();
                    playerStats.TakeDirectDamage(dmg, effect.damageType, ignoreResistance: true);
                }
            }
        }
    }
    
    /// <summary>
    /// 检查隐藏诅咒组合
    /// </summary>
    private void CheckCurseCombos()
    {
        int curseCount = _activeCurses.Count;
        
        // 深渊低语: >=3个中度及以上诅咒
        if (curseCount >= 3)
        {
            int moderateOrAbove = _activeCurses.Count(c => c.Data.intensity >= CurseIntensity.MODERATE);
            if (moderateOrAbove >= 3 && !_hasAbyssalWhisper)
            {
                _hasAbyssalWhisper = true;
                EventBus.Publish(new HiddenCurseComboEvent("ABYSSAL_WHISPER", moderateOrAbove));
            }
        }
        
        // 黑暗蜕变: >=4个诅咒且生命上限<基础60%
        if (curseCount >= 4)
        {
            float hpPercent = ServiceRegistry.Get<PlayerStats>().MaxHpPercent;
            if (hpPercent < 0.6f && !_hasDarkMetamorphosis)
            {
                _hasDarkMetamorphosis = true;
                EventBus.Publish(new HiddenCurseComboEvent("DARK_METAMORPHOSIS", curseCount));
            }
        }
        
        // 终焉华尔兹: >=5个诅咒
        if (curseCount >= 5 && !_hasWaltzOfDemise)
        {
            _hasWaltzOfDemise = true;
            EventBus.Publish(new HiddenCurseComboEvent("WALTZ_OF_DEMISE", curseCount));
        }
        
        // 六道轮回: 6个诅咒满槽
        if (curseCount >= 6 && !_hasSixPaths)
        {
            _hasSixPaths = true;
            EventBus.Publish(new HiddenCurseComboEvent("SIX_PATHS_REINCARNATION", 6));
        }
    }
    
    private bool _hasAbyssalWhisper, _hasDarkMetamorphosis, _hasWaltzOfDemise, _hasSixPaths;
    
    // ===== 工具方法 =====
    
    /// <summary>
    /// 属性硬性下限保护
    /// </summary>
    public static float ApplyFloorCap(StatType stat, float currentValue, float baseValue)
    {
        (float minPercent, _) = stat switch
        {
            StatType.HP => (0.1f, 1f),     // 生命不低于基础10%
            StatType.SPD => (0.4f, 1f),     // 移速不低于基础40%
            StatType.ATK => (0.5f, 1f),     // 攻击力不低于基础50%
            _ => (0f, float.MaxValue)
        };
        return math.Max(currentValue, baseValue * minPercent);
    }
    
    private CurseData WeightedSelect(List<CurseData> pool, SeededRNG rng)
    {
        float total = pool.Sum(c => c.appearWeight);
        float roll = rng.FloatRange(0, total);
        float cumulative = 0;
        foreach (var c in pool)
        {
            cumulative += c.appearWeight;
            if (roll < cumulative) return c;
        }
        return pool.Count > 0 ? pool[pool.Count - 1] : null;
    }
}

public class CurseInstance
{
    public string InstanceId { get; }
    public CurseData Data { get; }
    public int OrderIndex { get; }      // 第几个获取的诅咒
    public float PenaltyMultiplier { get; set; } = 1f;
    
    private static int _nextId = 0;
    
    public CurseInstance(CurseData data, int orderIndex)
    {
        InstanceId = $"curse_{_nextId++}_{data.curseId}";
        Data = data;
        OrderIndex = orderIndex;
    }
}

public readonly struct CurseAcceptedEvent : IEvent
{
    public readonly CurseInstance Instance;
    public CurseAcceptedEvent(CurseInstance inst) => Instance = inst;
}

public readonly struct CurseRemovedEvent : IEvent
{
    public readonly CurseInstance Instance;
    public CurseRemovedEvent(CurseInstance inst) => Instance = inst;
}

public readonly struct CurseRejectedEvent : IEvent
{
    public readonly int TotalRejects;
    public CurseRejectedEvent(int rejects) => TotalRejects = rejects;
}

public readonly struct HiddenCurseComboEvent : IEvent
{
    public readonly string ComboId;
    public readonly int TriggerCount;
    public HiddenCurseComboEvent(string comboId, int count) => (ComboId, TriggerCount) = (comboId, count);
}
```

---

## 4.8 天赋系统实现

### 4.8.1 TalentTree核心类

```text
public class TalentTree
{
    public const int MAX_TALENTS_PER_RUN = 3; // 首发5层：第1/3/5层各1次
    
    private readonly Dictionary<TalentPath, TalentPathData> _pathData = new();
    private readonly List<TalentNodeInstance> _selectedTalents = new();
    private readonly HashSet<TalentPath> _unlockedPaths = new();
    
    public IReadOnlyList<TalentNodeInstance> SelectedTalents => _selectedTalents;
    public int SelectionsMade => _selectedTalents.Count;
    public int RemainingSelections => MAX_TALENTS_PER_RUN - _selectedTalents.Count;
    
    public event System.Action<TalentNodeInstance> OnTalentSelected;
    
    public TalentTree()
    {
        InitializePaths();
        // 初始解锁: 毁灭/钢铁/疾风
        _unlockedPaths.Add(TalentPath.RUIN);
        _unlockedPaths.Add(TalentPath.STEEL);
        _unlockedPaths.Add(TalentPath.GALE);
    }
    
    private void InitializePaths()
    {
        // 毁灭之路
        _pathData[TalentPath.RUIN] = new TalentPathData(TalentPath.RUIN, "毁灭之路", new[]
        {
            new TalentLayer(1, new[]
            {
                new TalentNode("RU-1A", "存在撕裂", "攻击附带ATK×0.15存在伤害", StatType.ATK, 0.15f, TalentPath.RUIN, 1),
                new TalentNode("RU-1B", "致命凝视", "暴击伤害+0.3", StatType.CRIT_DMG, 0.3f, TalentPath.RUIN, 1),
                new TalentNode("RU-1C", "弱点洞悉", "受控敌人+25%伤害", StatType.ATK, 0.25f, TalentPath.RUIN, 1),
            }),
            new TalentLayer(2, new[]
            {
                new TalentNode("RU-2A", "血之饥渴", "击杀后5秒ATK+15%", StatType.ATK, 0.15f, TalentPath.RUIN, 2),
                new TalentNode("RU-2B", "破甲一击", "第6次攻击无视40%防御", StatType.ATK, 0.4f, TalentPath.RUIN, 2),
            }),
            new TalentLayer(3, new[]
            {
                new TalentNode("RU-3A", "毁灭风暴", "15%概率3格AOE ATK×0.8", StatType.ATK, 0.8f, TalentPath.RUIN, 3),
                new TalentNode("RU-3B", "处决者", "HP<30%敌人+40%伤害", StatType.ATK, 0.4f, TalentPath.RUIN, 3),
                new TalentNode("RU-3C", "怒火共鸣", "受击3秒ATK+25%", StatType.ATK, 0.25f, TalentPath.RUIN, 3),
            }),
            new TalentLayer(4, new[]
            {
                new TalentNode("RU-4A", "连环处决", "击杀重置攻击动画", StatType.ASPD, 1f, TalentPath.RUIN, 4),
                new TalentNode("RU-4B", "存在崩裂", "6层崩裂ATK×2.0爆发", StatType.ATK, 2.0f, TalentPath.RUIN, 4),
            }),
            new TalentLayer(5, new[]
            {
                new TalentNode("RU-5A", "终焉之刃", "蓄力攻击+100%", StatType.ATK, 1.0f, TalentPath.RUIN, 5),
                new TalentNode("RU-5B", "万物毁灭", "20%概率200%伤害", StatType.ATK, 2.0f, TalentPath.RUIN, 5),
            }),
        });
        
        // 钢铁之路、疾风之路、永恒之路、混沌之路 同理...
        // 此处省略重复代码，结构与毁灭之路一致
    }
    
    /// <summary>
    /// 生成天赋选择池（3选1）
    /// </summary>
    public List<TalentNode> GenerateSelectionPool(SeededRNG rng, int floorIndex)
    {
        if (RemainingSelections <= 0) return new();
        
        // 解锁检查
        if (floorIndex >= 3) _unlockedPaths.Add(TalentPath.ETERNITY);
        if (floorIndex >= 5) _unlockedPaths.Add(TalentPath.CHAOS);
        
        // 确定当前选择层数
        int targetLayer = SelectionsMade + 1;
        
        var candidates = new List<TalentNode>();
        foreach (var path in _unlockedPaths)
        {
            if (_pathData.TryGetValue(path, out var data))
            {
                if (targetLayer <= data.Layers.Count)
                {
                    var layer = data.Layers[targetLayer - 1];
                    foreach (var node in layer.Nodes)
                    {
                        // 过滤已互斥选择的
                        if (!IsMutuallyExcluded(node))
                            candidates.Add(node);
                    }
                }
            }
        }
        
        // 随机选3个
        var pool = new List<TalentNode>();
        var shuffled = candidates.OrderBy(_ => rng.IntRange(0, 10000)).ToList();
        for (int i = 0; i < math.Min(3, shuffled.Count); i++)
            pool.Add(shuffled[i]);
        
        return pool;
    }
    
    /// <summary>
    /// 选择天赋
    /// </summary>
    public TalentNodeInstance SelectTalent(TalentNode node)
    {
        if (RemainingSelections <= 0)
            throw new System.InvalidOperationException("No remaining talent selections.");
        if (IsMutuallyExcluded(node))
            throw new System.InvalidOperationException($"Talent {node.NodeId} is mutually excluded.");
        
        var instance = new TalentNodeInstance(node, _selectedTalents.Count);
        _selectedTalents.Add(instance);
        
        // 应用天赋效果
        ApplyTalentEffect(instance);
        OnTalentSelected?.Invoke(instance);
        EventBus.Publish(new TalentSelectedEvent(instance));
        
        return instance;
    }
    
    /// <summary>
    /// 放弃天赋选择（获得1时间碎片）
    /// </summary>
    public void SkipTalentSelection()
    {
        EventBus.Publish(new TimeFragmentEarnedEvent(1));
    }
    
    /// <summary>
    /// 检查互斥
    /// </summary>
    private bool IsMutuallyExcluded(TalentNode node)
    {
        // 同路线同层已选则互斥
        return _selectedTalents.Any(s => 
            s.Node.Path == node.Path && s.Node.Layer == node.Layer);
    }
    
    private void ApplyTalentEffect(TalentNodeInstance instance)
    {
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        var node = instance.Node;
        
        // 属性型天赋直接修改
        if (node.StatType != StatType.ATK || node.BaseValue <= 1f) // 区分百分比和倍率
        {
            playerStats.ModifyStat(node.StatType, node.BaseValue, StatModSource.Talent, node.NodeId);
        }
        else
        {
            // 机制型天赋注册到事件系统
            EventBus.Publish(new TalentMechRegisteredEvent(node.NodeId, node));
        }
    }
}

// ===== 天赋数据结构 =====

public enum TalentPath { RUIN, STEEL, GALE, ETERNITY, CHAOS }

public class TalentPathData
{
    public TalentPath Path { get; }
    public string DisplayName { get; }
    public List<TalentLayer> Layers { get; }
    
    public TalentPathData(TalentPath path, string displayName, TalentLayer[] layers)
    {
        Path = path;
        DisplayName = displayName;
        Layers = new List<TalentLayer>(layers);
    }
}

public class TalentLayer
{
    public int LayerIndex { get; }
    public List<TalentNode> Nodes { get; }
    
    public TalentLayer(int index, TalentNode[] nodes)
    {
        LayerIndex = index;
        Nodes = new List<TalentNode>(nodes);
    }
}

[Serializable]
public class TalentNode
{
    public string NodeId { get; }
    public string DisplayName { get; }
    public string Description { get; }
    public StatType StatType { get; }
    public float BaseValue { get; }
    public TalentPath Path { get; }
    public int Layer { get; }
    
    public TalentNode(string id, string name, string desc, StatType stat, float value, TalentPath path, int layer)
    {
        NodeId = id; DisplayName = name; Description = desc;
        StatType = stat; BaseValue = value; Path = path; Layer = layer;
    }
}

public class TalentNodeInstance
{
    public TalentNode Node { get; }
    public int SelectionOrder { get; }
    public TalentNodeInstance(TalentNode node, int order) { Node = node; SelectionOrder = order; }
}

public readonly struct TalentSelectedEvent : IEvent
{
    public readonly TalentNodeInstance Instance;
    public TalentSelectedEvent(TalentNodeInstance inst) => Instance = inst;
}

public readonly struct TalentMechRegisteredEvent : IEvent
{
    public readonly string NodeId;
    public readonly TalentNode Node;
    public TalentMechRegisteredEvent(string id, TalentNode node) => (NodeId, Node) = (id, node);
}
```

---

## 4.9 商店系统实现

### 4.9.1 ShopController

```text
public class ShopController
{
    private readonly ItemPool _itemPool;
    private readonly SeededRNG _rng;
    private readonly int _floorIndex;
    private readonly ShopType _shopType;
    
    public List<ShopItem> CurrentItems { get; private set; } = new();
    public int RerollCount { get; private set; } = 0;
    public int FreeRerollsLeft { get; private set; }
    public bool IsOpen { get; private set; }
    
    public event System.Action<ShopItem> OnItemPurchased;
    public event System.Action OnRerolled;
    public event System.Action OnShopClosed;
    
    public ShopController(ItemPool itemPool, SeededRNG rng, int floorIndex, ShopType shopType)
    {
        _itemPool = itemPool;
        _rng = rng;
        _floorIndex = floorIndex;
        _shopType = shopType;
        FreeRerollsLeft = 1 + GetFortuneCoinBonus(); // 每层1次免费 + 幸运硬币额外
    }
    
    /// <summary>
    /// 开启商店，生成商品
    /// </summary>
    public void OpenShop()
    {
        IsOpen = true;
        GenerateItems();
    }
    
    /// <summary>
    /// 生成商店商品
    /// </summary>
    private void GenerateItems()
    {
        CurrentItems.Clear();
        int itemCount = _shopType switch
        {
            ShopType.Normal => 3,       // 3个道具位
            ShopType.TimeMerchant => 2, // 2个时间系道具位
            _ => 3
        };
        
        // 商品数量限制 = 4 + floor(层数/3)
        int maxItems = 4 + _floorIndex / 3;
        itemCount = math.Min(itemCount, maxItems);
        
        for (int i = 0; i < itemCount; i++)
        {
            var rarity = _shopType == ShopType.TimeMerchant 
                ? ItemRarity.UNCOMMON  // 时间商人优先稀有
                : _itemPool.RollItemRarity(_rng, DropSource.SHOP);
                
            var itemData = _itemPool.RollSpecificItem(_rng, rarity, GetCurrentWeaponType());
            if (itemData != null)
            {
                int price = CalculatePrice(itemData, i);
                CurrentItems.Add(new ShopItem(itemData, price, i));
            }
        }
        
        // 治疗位
        CurrentItems.Add(new ShopItem(
            ShopItemType.HEAL_SMALL, 
            CalculateHealPrice(), 
            CurrentItems.Count));
    }
    
    /// <summary>
    /// 计算商品价格
    /// </summary>
    private int CalculatePrice(ItemData item, int slotIndex)
    {
        float basePrice = item.shopBasePrice;
        
        // 层数系数：每层+15%
        float floorMult = 1f + (_floorIndex - 1) * 0.15f;
        
        // 稀有度系数
        float rarityMult = item.rarity switch
        {
            ItemRarity.COMMON => 1.0f,
            ItemRarity.UNCOMMON => 1.8f,
            ItemRarity.LEGENDARY => 3.0f,
            ItemRarity.MYTHIC => 5.0f,
            _ => 1.0f
        };
        
        // 重roll加价：每次+20%
        float rerollSurcharge = 1f + RerollCount * 0.2f;
        
        // 商人契约折扣
        float merchantPactDiscount = GetMerchantPactDiscount();
        
        // 首发5层通胀控制：第3层×1.10, 第4层×1.20, 第5层×1.35
        float inflationMult = _floorIndex switch
        {
            >= 5 => 1.35f,
            >= 4 => 1.20f,
            >= 3 => 1.10f,
            _ => 1.0f
        };
        
        int finalPrice = math.RoundToInt(basePrice * floorMult * rarityMult * rerollSurcharge * merchantPactDiscount * inflationMult);
        return math.Max(10, finalPrice);
    }
    
    private int CalculateHealPrice()
    {
        float basePrice = 30f;
        float floorMult = 1f + (_floorIndex - 1) * 0.15f;
        return math.RoundToInt(basePrice * floorMult);
    }
    
    /// <summary>
    /// 购买商品
    /// </summary>
    public bool PurchaseItem(int slotIndex, Inventory inventory, PlayerEconomy economy)
    {
        if (slotIndex < 0 || slotIndex >= CurrentItems.Count) return false;
        var shopItem = CurrentItems[slotIndex];
        if (shopItem.IsSold) return false;
        
        if (!economy.TrySpendGold(shopItem.Price)) return false;
        
        if (shopItem.Type == ShopItemType.ITEM && shopItem.ItemData != null)
        {
            if (!inventory.TryAddPassiveItem(shopItem.ItemData, out _))
            {
                // 背包满，需要替换逻辑
                economy.EarnGold(shopItem.Price); // 退款
                return false;
            }
        }
        else if (shopItem.Type == ShopItemType.HEAL_SMALL)
        {
            ServiceRegistry.Get<PlayerStats>().Heal(ServiceRegistry.Get<PlayerStats>().GetStat(StatType.HP) * 0.3f);
        }
        
        shopItem.IsSold = true;
        OnItemPurchased?.Invoke(shopItem);
        return true;
    }
    
    /// <summary>
    /// 重roll商店
    /// </summary>
    public bool Reroll(PlayerEconomy economy)
    {
        if (FreeRerollsLeft > 0)
        {
            FreeRerollsLeft--;
        }
        else
        {
            int cost = 50 * (RerollCount + 1);
            if (!economy.TrySpendGold(cost)) return false;
        }
        
        RerollCount++;
        GenerateItems();
        OnRerolled?.Invoke();
        return true;
    }
    
    /// <summary>
    /// 关闭商店
    /// </summary>
    public void CloseShop()
    {
        IsOpen = false;
        OnShopClosed?.Invoke();
    }
    
    private int GetFortuneCoinBonus()
    {
        var inv = ServiceRegistry.Get<Inventory>();
        return inv?.GetStackCount("UTI_FORTUNE_COIN_STK") ?? 0;
    }
    
    private float GetMerchantPactDiscount()
    {
        var inv = ServiceRegistry.Get<Inventory>();
        if (inv != null && inv.HasItem("UTI_MERCHANT_PACT"))
            return 0.8f; // -20%
        return 1f;
    }
    
    private WeaponType GetCurrentWeaponType()
    {
        // 从玩家状态获取当前武器类型
        return ServiceRegistry.Get<PlayerStats>()?.CurrentWeaponType ?? WeaponType.NONE;
    }
}

public enum ShopType { Normal, TimeMerchant }

public class ShopItem
{
    public ShopItemType Type { get; }
    public ItemData ItemData { get; }
    public int Price { get; }
    public int SlotIndex { get; }
    public bool IsSold { get; set; }
    
    public ShopItem(ItemData data, int price, int slot) 
        => (Type, ItemData, Price, SlotIndex) = (ShopItemType.ITEM, data, price, slot);
    
    public ShopItem(ShopItemType type, int price, int slot) 
        => (Type, ItemData, Price, SlotIndex) = (type, null, price, slot);
}

public enum ShopItemType { ITEM, HEAL_SMALL, HEAL_LARGE, REROLL, CURSE_PURGE, MAP_REVEAL, WEAPON_UPGRADE }
```

---

## 4.10 道具池与掉落系统

### 4.10.1 ItemPool

```text
public class ItemPool
{
    private readonly ItemRegistry _registry;
    private readonly Dictionary<ItemRarity, List<ItemData>> _poolsByRarity = new();
    private readonly HashSet<string> _unlockedItems = new();
    private readonly HashSet<string> _discoveredItems = new();
    
    // 稀有度权重
    private static readonly Dictionary<ItemRarity, float> BASE_RARITY_WEIGHTS = new()
    {
        { ItemRarity.COMMON, 60f },
        { ItemRarity.UNCOMMON, 30f },
        { ItemRarity.LEGENDARY, 9f },
        { ItemRarity.MYTHIC, 1f }
    };
    
    // 掉落源修正
    private static readonly Dictionary<DropSource, RarityModifier> DROP_MODIFIERS = new()
    {
        { DropSource.NORMAL_ENEMY, new RarityModifier(1f, 1f, 0.5f, 0f, 0.05f) },
        { DropSource.ELITE_ENEMY, new RarityModifier(0.8f, 1.5f, 2f, 0.5f, 0.30f) },
        { DropSource.BOSS, new RarityModifier(0.3f, 1f, 3f, 2f, 1f) },
        { DropSource.CHEST_NORMAL, new RarityModifier(1f, 1.5f, 1f, 0.3f, 1f) },
        { DropSource.CHEST_GOLD, new RarityModifier(0.5f, 1f, 2f, 1f, 1f) },
        { DropSource.SHOP, new RarityModifier(0.5f, 1.5f, 2f, 1f, 1f) },
        { DropSource.TIME_RIFT, new RarityModifier(0.2f, 0.5f, 2f, 3f, 1f) },
    };
    
    public ItemPool(ItemRegistry registry)
    {
        _registry = registry;
        BuildPools();
        InitializeDefaultUnlocks();
    }
    
    private void BuildPools()
    {
        foreach (ItemRarity rarity in System.Enum.GetValues(typeof(ItemRarity)))
        {
            _poolsByRarity[rarity] = _registry.GetAll()
                .Where(d => d.rarity == rarity)
                .ToList();
        }
    }
    
    private void InitializeDefaultUnlocks()
    {
        // 初始解锁：50个普通 + 20个稀有
        int commonCount = 0, uncommonCount = 0;
        foreach (var item in _registry.GetAll().OrderBy(_ => System.Guid.NewGuid()))
        {
            if (item.isDefaultUnlocked || 
                (item.rarity == ItemRarity.COMMON && commonCount < 50) ||
                (item.rarity == ItemRarity.UNCOMMON && uncommonCount < 20))
            {
                _unlockedItems.Add(item.itemId);
                if (item.rarity == ItemRarity.COMMON) commonCount++;
                if (item.rarity == ItemRarity.UNCOMMON) uncommonCount++;
            }
        }
    }
    
    /// <summary>
    /// 判定道具是否掉落
    /// </summary>
    public bool ShouldDropItem(DropSource source, SeededRNG rng)
    {
        float dropChance = DROP_MODIFIERS[source].dropChance;
        float luck = ServiceRegistry.Get<PlayerStats>()?.GetStat(StatType.LCK) ?? 0;
        float adjustedChance = dropChance * (1f + luck * 0.01f);
        return rng.Chance(math.Min(adjustedChance, 1f));
    }
    
    /// <summary>
    /// 随机判定稀有度
    /// </summary>
    public ItemRarity RollItemRarity(SeededRNG rng, DropSource source)
    {
        var modifier = DROP_MODIFIERS[source];
        float luck = ServiceRegistry.Get<PlayerStats>()?.GetStat(StatType.LCK) ?? 0;
        
        // 计算各稀有度最终权重
        float commonWeight = BASE_RARITY_WEIGHTS[ItemRarity.COMMON] * modifier.commonMult * (1f - luck * 0.06f);
        float uncommonWeight = BASE_RARITY_WEIGHTS[ItemRarity.UNCOMMON] * modifier.uncommonMult * (1f + luck * 0.02f);
        float legendaryWeight = BASE_RARITY_WEIGHTS[ItemRarity.LEGENDARY] * modifier.legendaryMult * (1f + luck * 0.02f);
        float mythicWeight = BASE_RARITY_WEIGHTS[ItemRarity.MYTHIC] * modifier.mythicMult * (1f + luck * 0.02f);
        
        float total = commonWeight + uncommonWeight + legendaryWeight + mythicWeight;
        float roll = rng.FloatRange(0, total);
        
        float cumulative = 0;
        cumulative += commonWeight;
        if (roll < cumulative) return ItemRarity.COMMON;
        cumulative += uncommonWeight;
        if (roll < cumulative) return ItemRarity.UNCOMMON;
        cumulative += legendaryWeight;
        if (roll < cumulative) return ItemRarity.LEGENDARY;
        return ItemRarity.MYTHIC;
    }
    
    /// <summary>
    /// 从指定稀有度池中随机选取具体道具
    /// </summary>
    public ItemData RollSpecificItem(SeededRNG rng, ItemRarity rarity, WeaponType currentWeapon)
    {
        if (!_poolsByRarity.TryGetValue(rarity, out var pool)) return null;
        
        var available = pool
            .Where(d => _unlockedItems.Contains(d.itemId))              // 已解锁
            .Where(d => !(d.maxStack == 1 && ServiceRegistry.Get<Inventory>()?.HasItem(d.itemId) == true)) // 非已有唯一
            .ToList();
        
        if (available.Count == 0) return null;
        
        // 武器专属道具权重调整
        var weighted = available.Select(d =>
        {
            float weight = d.baseDropWeight;
            if (d.category == ItemCategory.WEP)
            {
                weight *= d.weaponType == currentWeapon ? 3f : 0.1f;
            }
            return (data: d, weight);
        }).ToList();
        
        float totalWeight = weighted.Sum(w => w.weight);
        float roll = rng.FloatRange(0, totalWeight);
        float cumulative = 0;
        
        foreach (var (data, weight) in weighted)
        {
            cumulative += weight;
            if (roll < cumulative) return data;
        }
        
        return weighted.Count > 0 ? weighted[weighted.Count - 1].data : null;
    }
    
    /// <summary>
    /// 完整掉落流程：判定→稀有度→具体道具
    /// </summary>
    public ItemData RollFullDrop(SeededRNG rng, DropSource source, WeaponType currentWeapon)
    {
        if (!ShouldDropItem(source, rng)) return null;
        var rarity = RollItemRarity(rng, source);
        return RollSpecificItem(rng, rarity, currentWeapon);
    }
    
    /// <summary>
    /// 解锁道具
    /// </summary>
    public void UnlockItem(string itemId)
    {
        _unlockedItems.Add(itemId);
    }
    
    /// <summary>
    /// 标记道具为已发现
    /// </summary>
    public void MarkDiscovered(string itemId)
    {
        _discoveredItems.Add(itemId);
    }
    
    public bool IsUnlocked(string itemId) => _unlockedItems.Contains(itemId);
    public bool IsDiscovered(string itemId) => _discoveredItems.Contains(itemId);
}

public enum DropSource { NORMAL_ENEMY, ELITE_ENEMY, BOSS, CHEST_NORMAL, CHEST_GOLD, SHOP, TIME_RIFT }

public readonly struct RarityModifier
{
    public readonly float commonMult, uncommonMult, legendaryMult, mythicMult, dropChance;
    public RarityModifier(float c, float u, float l, float m, float d)
        => (commonMult, uncommonMult, legendaryMult, mythicMult, dropChance) = (c, u, l, m, d);
}
```

---

## 4.11 套装系统实现

### 4.11.1 SetBonusManager

```text
public class SetBonusManager
{
    private readonly Dictionary<string, SetDefinition> _setDefinitions = new();
    private readonly Dictionary<string, ActiveSetBonus> _activeBonuses = new();
    private Inventory _inventory;
    
    public void Initialize(Inventory inventory)
    {
        _inventory = inventory;
        _inventory.OnItemAdded += OnInventoryChanged;
        _inventory.OnItemRemoved += OnInventoryChanged;
        _inventory.OnInventoryChanged += OnInventoryChanged;
        
        LoadSetDefinitions();
    }
    
    private void LoadSetDefinitions()
    {
        // 时间行者套装
        _setDefinitions["time_walker"] = new SetDefinition
        {
            setTag = "time_walker",
            displayName = "时间行者",
            itemIds = new[] { "TIM_RIFT_SHARD", "TIM_PHANTOM_LENS", "TIM_ACCEL_CLOCK", "TIM_SLOW_CLOCK", "TIM_WALKER_MARK" },
            bonus3 = new SetBonusEffect
            {
                description = "时间操控能量消耗-25%，时间回溯距离+2米",
                statModifiers = new[] { (StatType.TIME_ENERGY_MAX, -0.25f) },
                customEffectId = "TIME_WALKER_3"
            },
            bonus5 = new SetBonusEffect
            {
                description = "时间操控无能量消耗(改为8秒CD)，所有时间效果持续时间+50%",
                statModifiers = new[] { (StatType.TIME_ENERGY_MAX, -1.0f) },
                customEffectId = "TIME_WALKER_5"
            }
        };
        
        // 元素使者套装
        _setDefinitions["elementalist"] = new SetDefinition
        {
            setTag = "elementalist",
            displayName = "元素使者",
            itemIds = new[] { "ATK_FLAME_HEART", "ATK_FROST_CORE", "ATK_ELEMENT_CONVERTER", "WEP_STF_ELEMENT_MASTER", "ATK_THUNDER_CALL" },
            bonus3 = new SetBonusEffect
            {
                description = "攻击附带随机元素效果，元素伤害+20%",
                statModifiers = new[] { (StatType.ATK, 0.2f) },
                customEffectId = "ELEMENTALIST_3"
            },
            bonus5 = new SetBonusEffect
            {
                description = "三元素同时触发→元素湮灭(ATK×3范围5m伤害, CD10s)",
                customEffectId = "ELEMENTALIST_5"
            }
        };
        
        // 钢铁堡垒、影之猎手、野蛮之力 同理...
    }
    
    private void OnInventoryChanged()
    {
        RefreshSetBonuses();
    }
    
    /// <summary>
    /// 刷新所有套装效果
    /// </summary>
    public void RefreshSetBonuses()
    {
        if (_inventory == null) return;
        
        var currentSets = CountSetTags();
        
        foreach (var (tag, definition) in _setDefinitions)
        {
            int count = currentSets.GetValueOrDefault(tag, 0);
            
            // 检查5件套
            if (count >= 5 && !_activeBonuses.ContainsKey(tag + "_5"))
            {
                ActivateSetBonus(definition, definition.bonus5, 5);
            }
            else if (count < 5 && _activeBonuses.ContainsKey(tag + "_5"))
            {
                DeactivateSetBonus(tag + "_5", definition.bonus5);
            }
            
            // 检查3件套
            if (count >= 3 && !_activeBonuses.ContainsKey(tag + "_3"))
            {
                ActivateSetBonus(definition, definition.bonus3, 3);
            }
            else if (count < 3 && _activeBonuses.ContainsKey(tag + "_3"))
            {
                DeactivateSetBonus(tag + "_3", definition.bonus3);
            }
        }
    }
    
    /// <summary>
    /// 统计各套装标签的道具数量
    /// </summary>
    private Dictionary<string, int> CountSetTags()
    {
        var counts = new Dictionary<string, int>();
        foreach (var item in _inventory.GetAllItems())
        {
            if (string.IsNullOrEmpty(item.Data.setTag)) continue;
            if (!counts.ContainsKey(item.Data.setTag))
                counts[item.Data.setTag] = 0;
            counts[item.Data.setTag] += item.Data.isStackable ? 1 : 1; // 每个实例算1件
        }
        return counts;
    }
    
    private void ActivateSetBonus(SetDefinition set, SetBonusEffect bonus, int pieceCount)
    {
        string key = set.setTag + "_" + pieceCount;
        _activeBonuses[key] = new ActiveSetBonus(set, bonus, pieceCount);
        
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        foreach (var (stat, value) in bonus.statModifiers)
        {
            playerStats.ModifyStat(stat, value, StatModSource.SetBonus, key);
        }
        
        // 注册自定义效果
        if (!string.IsNullOrEmpty(bonus.customEffectId))
        {
            EventBus.Publish(new SetBonusActivatedEvent(key, bonus.customEffectId));
        }
    }
    
    private void DeactivateSetBonus(string key, SetBonusEffect bonus)
    {
        _activeBonuses.Remove(key);
        
        var playerStats = ServiceRegistry.Get<PlayerStats>();
        foreach (var (stat, _) in bonus.statModifiers)
        {
            playerStats.RemoveModifier(stat, StatModSource.SetBonus, key);
        }
        
        if (!string.IsNullOrEmpty(bonus.customEffectId))
        {
            EventBus.Publish(new SetBonusDeactivatedEvent(key, bonus.customEffectId));
        }
    }
    
    /// <summary>
    /// 获取套装进度信息
    /// </summary>
    public List<SetProgressInfo> GetSetProgress()
    {
        var counts = CountSetTags();
        var result = new List<SetProgressInfo>();
        
        foreach (var (tag, definition) in _setDefinitions)
        {
            int count = counts.GetValueOrDefault(tag, 0);
            if (count > 0)
            {
                result.Add(new SetProgressInfo(definition.displayName, count, definition.itemIds.Length));
            }
        }
        
        return result;
    }
}

// ===== 套装数据结构 =====

public class SetDefinition
{
    public string setTag;
    public string displayName;
    public string[] itemIds;
    public SetBonusEffect bonus3;
    public SetBonusEffect bonus5;
}

[Serializable]
public class SetBonusEffect
{
    public string description;
    public (StatType stat, float value)[] statModifiers;
    public string customEffectId;
}

public class ActiveSetBonus
{
    public SetDefinition Set { get; }
    public SetBonusEffect Bonus { get; }
    public int PieceCount { get; }
    public ActiveSetBonus(SetDefinition set, SetBonusEffect bonus, int pieces) 
        => (Set, Bonus, PieceCount) = (set, bonus, pieces);
}

public readonly struct SetProgressInfo
{
    public readonly string Name;
    public readonly int Current;
    public readonly int Total;
    public SetProgressInfo(string name, int current, int total) => (Name, Current, Total) = (name, current, total);
}

public readonly struct SetBonusActivatedEvent : IEvent
{
    public readonly string Key;
    public readonly string CustomEffectId;
    public SetBonusActivatedEvent(string key, string effectId) => (Key, CustomEffectId) = (key, effectId);
}

public readonly struct SetBonusDeactivatedEvent : IEvent
{
    public readonly string Key;
    public readonly string CustomEffectId;
    public SetBonusDeactivatedEvent(string key, string effectId) => (Key, CustomEffectId) = (key, effectId);
}

public enum StatModSource { Item, Blessing, CurseBonus, CursePenalty, Talent, Synergy, SetBonus, MetaUpgrade, SoulAltar }
```

---

## 4.12 测试计划

### 4.12.1 单元测试

| 测试ID | 测试目标 | 测试内容 | 预期结果 |
|--------|---------|---------|---------|
| UT-INV-01 | Inventory添加 | 添加1个不可堆叠道具 | 被动槽位+1，事件触发 |
| UT-INV-02 | Inventory堆叠 | 添加同ID可堆叠道具 | StackCount+1，不占新槽位 |
| UT-INV-03 | Inventory满槽 | 添加第21个被动道具 | 返回false，不崩溃 |
| UT-INV-04 | Inventory替换 | 替换指定槽位道具 | 旧道具移除，新道具生效 |
| UT-INV-05 | Inventory主动 | 使用主动道具 | 触发ActiveItemUsedEvent，冷却开始 |
| UT-POOL-01 | 道具池权重 | 10000次roll稀有度 | COMMON约60%, UNCOMMON约30% |
| UT-POOL-02 | 幸运值影响 | Luck=50时roll | 稀有+权重明显上升 |
| UT-POOL-03 | 武器适配 | 使用弓时roll WEP类 | 弓专属道具权重×3 |
| UT-SYN-01 | 联动激活 | 同时拥有联动A+B | 联动效果生效 |
| UT-SYN-02 | 联动失效 | 移除联动道具A | 联动效果移除 |
| UT-SYN-03 | 反联动 | 同时拥有冲突道具 | 反联动规则正确执行 |
| UT-BLS-01 | 祝福获取 | 选择祝福 | 槽位+1，效果应用 |
| UT-BLS-02 | 祝福替换 | 满槽替换 | 旧移除，新生效，碎片补偿 |
| UT-BLS-03 | 保底机制 | 连续5次无稀有 | 第6次必出稀有+ |
| UT-CUR-01 | 诅咒接受 | 接受诅咒 | 增益+负面均生效 |
| UT-CUR-02 | 诅咒增幅 | 第3个诅咒 | 负面×1.30 |
| UT-CUR-03 | 诅咒净化 | 净化1个诅咒 | 诅咒移除，效果清除 |
| UT-CUR-04 | 下限保护 | 极端诅咒组合 | 生命≥基础10% |
| UT-TAL-01 | 天赋选择 | 选择同层互斥天赋 | 第二个选择被拒绝 |
| UT-TAL-02 | 路线解锁 | 层3解锁永恒 | 永恒路线可选 |
| UT-SHOP-01 | 商店定价 | 层5购买普通道具 | 价格含层数系数 |
| UT-SHOP-02 | 重roll | 重roll3次 | 价格每次+20% |
| UT-SET-01 | 套装3件 | 拥有3件同套装 | 3件套效果激活 |
| UT-SET-02 | 套件移除 | 从5件减到2件 | 3件和5件套效果均失效 |

### 4.12.2 集成测试

| 测试ID | 测试场景 | 验证内容 |
|--------|---------|---------|
| IT-01 | 完整一局道具获取 | 从空背包到20个道具，所有系统正确交互 |
| IT-02 | 30组联动验证 | 逐一验证30组联动效果的触发与失效 |
| IT-03 | 极端Build: 低血狂暴流 | CU-009+CU-011+BG-008+BG-010，数值正确 |
| IT-04 | 极端Build: 无限时间流 | CU-020+BT-001+BT-006+CU-012，生命上限递减正确 |
| IT-05 | 极端Build: 全诅咒六道轮回 | 6诅咒满槽，隐藏效果触发 |
| IT-06 | 经济平衡验证 | 单局金币获取/消耗在预期范围内 |
| IT-07 | 天赋+祝福+诅咒叠加 | 三者效果不冲突，同类取最高 |

### 4.12.3 性能测试

| 测试项 | 标准 | 测试方法 |
|--------|------|---------|
| 20个被动道具+5个联动+8祝福+3诅咒 | 60fps不降帧 | 满Build场景，持续战斗5分钟 |
| 1000次道具池roll | <5ms | 循环1000次RollFullDrop |
| 联动引擎检测 | <0.1ms/次 | 每次获取道具时的检测耗时 |
| ItemEffectProcessor Update | <0.5ms | 20个条件触发道具的每帧检查 |

### 4.12.4 道具5项测试清单（新增道具必过）

1. **独立性测试**：道具单独使用时效果清晰可感知
2. **堆叠测试**：1/3/5/10层时效果合理，无溢出/死循环
3. **时间交互测试**：回溯/冻结/加速下行为正确
4. **联动冲突测试**：与反联动列表中道具组合有明确规则
5. **趣味性测试**：至少改变1个玩法维度

---

> **文档结束**  
> 本文档为《Plane Walker: Chronicles of Collapse》道具与Build系统的完整开发文档。实现目标为Godot 4.x + GDScript，遵循已有EventBus Autoload/ServiceRegistry/StateMachine/Registry架构。
