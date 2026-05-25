# 08 — 局外系统开发文档

**版本**: 1.0  
**日期**: 2026-04-22  
**引擎**: Godot 4.x  
**语言**: GDScript 2.0（性能瓶颈可用GDExtension/C++）  
**关联文档**: [00_Architecture](00_Architecture.md) / [8.1 局外枢纽与死亡结算](../8.1_局外枢纽与死亡结算设计.md) / [8.3 局内选择与抽卡外观](../8.3_局内选择与抽卡外观设计.md) / [8.5 系统功能与运营规划](../8.5_系统功能与运营规划设计.md)

---

> **Godot迁移约束**：Hub区域、NPC、结算面板、抽卡和外观界面均使用 `.tscn` 场景；配置使用 Resource/JSON；区域加载使用 `ResourceLoader.load/preload`，音频触发使用 AudioStream 路径或 AudioBus 参数。

## 1. HubController — 枢纽9区域管理 + NPC交互触发

### 1.1 概述

`HubController` 管理"时之枢纽"场景中的9个功能区域（议会大厅、守心者书房、训练场、赫尔墨斯店铺、锻造区、冥想室、裂隙入口、行者画廊、时光之镜），负责区域激活/封锁、Meta进度驱动的修复状态、玩家交互检测及区域间转场。

### 1.2 区域枚举与数据

```text
/// <summary>
/// 枢纽9个功能区域枚举
/// </summary>
public enum HubArea
{
    CouncilHall,      // 议会大厅
    WardensArchive,   // 守心者书房
    TrainingGrounds,  // 训练场
    HermesEmporium,   // 赫尔墨斯店铺
    PlanarForge,      // 锻造区
    MeditationChamber,// 冥想室
    RiftGateway,      // 裂隙入口
    WalkersGallery,   // 行者画廊
    MirrorOfEpochs    // 时光之镜
}

/// <summary>
/// 区域修复等级，由Meta进度驱动
/// </summary>
public enum HubRepairLevel
{
    Ruined,    // 初始荒废
    Partial,   // 部分修复
    Restored,  // 完全修复
    Flourishing// 繁荣扩展
}

/// <summary>
/// 单个区域的运行时数据
/// </summary>
[Serializable]
public class HubAreaData
{
    public HubArea Area;
    public string AreaId;              // 如 "council_hall"
    public Rect Bounds;                // 区域矩形范围 (x1,y1,x2,y2)
    public Vector2 EntryPoint;         // 入口坐标
    public HubRepairLevel RepairLevel;
    public string RequiredMetaNode;    // 解锁所需Meta节点ID，空=初始可用
    public string[] NpcIds;            // 区域内NPC ID列表
    public string[] InteractionIds;    // 区域内交互点ID列表
    public bool IsUnlocked;
    public bool IsCurrentArea;         // 玩家是否在此区域内
}
```

### 1.3 HubController 主类

```text
/// <summary>
/// 枢纽总控制器 — 管理9区域、玩家位置检测、交互触发
/// 挂载于Hub场景根节点，单例
/// </summary>
public class HubController : Node
{
    // ── 单例 ──────────────────────────────────────────
    public static HubController Instance { get; private set; }

    // ── 序列化字段 ─────────────────────────────────────
     private HubAreaData[] _areaDataList;
     private Node2D _playerNode2D;
     private HubAreaConfigSO _areaConfig;        // Resource
     private float _interactionRadius = 80f;     // 交互检测半径(像素)
     private float _areaTransitionDuration = 0.4f;

    // ── 运行时状态 ─────────────────────────────────────
    private Dictionary<HubArea, HubAreaData> _areaMap;
    private HubArea _currentArea;
    private HubArea _previousArea;
    private IInteractable _nearestInteractable;
    private List<IInteractable> _activeInteractables;
    private Dictionary<string, Node> _areaRootObjects;     // 区域根节点
    private Dictionary<HubArea, HubRepairLevel> _repairLevels;

    // ── 事件 ───────────────────────────────────────────
    public event Action<HubArea, HubArea> OnAreaChanged;         // (oldArea, newArea)
    public event Action<HubArea, HubRepairLevel> OnAreaRepaired; // (area, newLevel)
    public event Action<IInteractable> OnInteractableFocused;
    public event Action<IInteractable> OnInteractableLost;

    // ── 生命周期 ───────────────────────────────────────
    private void Awake()
    {
        if (Instance != null && Instance != this) { queue_free(); return; }
        Instance = this;
        InitializeAreas();
    }

    private void Update()
    {
        DetectCurrentArea();
        FindNearestInteractable();
    }

    // ── 公有方法 ───────────────────────────────────────

    /// <summary>初始化所有区域数据与状态</summary>
    public void InitializeAreas();

    /// <summary>根据Meta进度刷新所有区域的解锁/修复状态</summary>
    public void RefreshAreaStates(PersistentData persistent);

    /// <summary>获取指定区域的数据</summary>
    public HubAreaData GetAreaData(HubArea area);

    /// <summary>获取当前玩家所在区域</summary>
    public HubArea GetCurrentArea();

    /// <summary>获取区域修复等级</summary>
    public HubRepairLevel GetRepairLevel(HubArea area);

    /// <summary>设置区域修复等级（由Meta进度系统调用）</summary>
    public void SetRepairLevel(HubArea area, HubRepairLevel level);

    /// <summary>获取区域内所有交互点</summary>
    public IReadOnlyList<IInteractable> GetInteractables(HubArea area);

    /// <summary>触发玩家交互（由InputManager调用）</summary>
    public void TriggerInteraction();

    /// <summary>传送玩家到指定区域入口</summary>
    public void TeleportToArea(HubArea area);

    /// <summary>解锁区域（由Meta解锁事件触发）</summary>
    public void UnlockArea(HubArea area);

    /// <summary>锁定区域</summary>
    public void LockArea(HubArea area);

    /// <summary>获取所有已解锁区域列表</summary>
    public IReadOnlyList<HubArea> GetUnlockedAreas();

    /// <summary>获取枢纽整体修复度百分比(0~100)</summary>
    public float GetOverallRepairPercentage();

    /// <summary>播放区域修复动画</summary>
    public async流程 PlayRepairAnimation(HubArea area, HubRepairLevel newLevel);

    /// <summary>设置区域环境氛围（灯光/粒子/音效）</summary>
    public void SetAreaAmbience(HubArea area, HubRepairLevel level);

    // ── 私有方法 ───────────────────────────────────────

    /// <summary>根据玩家位置检测当前所在区域</summary>
    private void DetectCurrentArea();

    /// <summary>查找最近的可交互对象</summary>
    private void FindNearestInteractable();

    /// <summary>处理区域切换逻辑</summary>
    private void HandleAreaTransition(HubArea from, HubArea to);

    /// <summary>加载区域根物体（按需实例化）</summary>
    private void LoadAreaRoot(HubArea area);

    /// <summary>卸载区域根物体（不可见区域释放资源）</summary>
    private void UnloadAreaRoot(HubArea area);

    /// <summary>更新区域视觉（修复等级→外观映射）</summary>
    private void UpdateAreaVisuals(HubArea area, HubRepairLevel level);
}

/// <summary>
/// 可交互接口 — 枢纽内所有可交互对象实现
/// </summary>
public interface IInteractable
{
    string InteractId { get; }
    Vector2 Position { get; }
    HubArea Area { get; }
    bool IsAvailable { get; }
    float InteractionRadius { get; }
    void OnFocus();
    void OnLoseFocus();
    void OnInteract(PlayerHubController player);
}

/// <summary>
/// 玩家枢纽控制器 — 管理玩家在枢纽中的移动与交互
/// </summary>
public class PlayerHubController : Node
{
     private float _moveSpeed = 200f;   // 像素/秒
     private float _runSpeed = 350f;

    private CharacterBody2D _rb;
    private AnimationPlayer或AnimationTree _anim;
    private Vector2 _moveInput;
    private bool _isRunning;
    private bool _isInteracting;   // 对话/菜单中不可移动

    public HubArea CurrentArea => HubController.Instance.GetCurrentArea();
    public bool IsInteracting => _isInteracting;

    public void Initialize(CharacterData characterData);
    public void MoveTo(Vector2 target, Action onArrived);
    public void SetInteracting(bool interacting);
    public void PlayEmote(string emoteId);
    public void UpdateSkin(string skinId);
}
```

### 1.4 HubAreaConfigSO — 区域配置Resource

```text
/// <summary>
/// 枢纽区域配置数据，由策划在Inspector中配置
/// </summary>
[CreateAssetMenu(fileName = "HubAreaConfig", menuName = "PWC/Hub/AreaConfig")]
public class HubAreaConfigSO : Resource
{
    public HubAreaEntry[] Areas;

    [Serializable]
    public class HubAreaEntry
    {
        public HubArea Area;
        public string AreaId;
        public Rect Bounds;
        public Vector2 EntryPoint;
        public HubRepairLevel InitialRepairLevel;
        public string RequiredMetaNode;
        public string AreaPrefabPath;           // Resource路径
        public string AmbienceEventPath;        // Godot AudioBus事件路径
        public RepairThreshold[] RepairThresholds;
    }

    [Serializable]
    public class RepairThreshold
    {
        public HubRepairLevel Level;
        public int RequiredMetaNodesCount;      // 需要解锁的Meta节点总数
        public string[] AdditionalRequirements; // 额外Meta节点ID
    }
}
```

---

## 2. NPCSystem — NPCController + 对话系统 + 好感度 + 任务

### 2.1 概述

NPC系统包含NPC控制器、对话引擎、好感度管理和任务系统四部分。6位枢纽NPC（奥德修斯、菲娅、墨菲斯、赫尔墨斯、熔炉匠师、虚无歌者 + 时痕行者/永恒之心守护者）各有独立好感度、对话分支和任务线。

### 2.2 NPCController

```text
/// <summary>
/// NPC控制器 — 管理单个NPC的位置、动画、交互、好感度
/// 挂载于NPCPackedScene上
/// </summary>
public class NPCController : Node, IInteractable
{
    // ── 身份 ───────────────────────────────────────────
     private string _npcId;          // 如 "odysseus"
     private string _npcName;        // 显示名
     private NPCDataSO _npcData;
     private HubArea _area;

    // ── 组件 ───────────────────────────────────────────
    private AnimationPlayer或AnimationTree _animator;
    private SpriteRenderer _renderer;
    private DialogueController _dialogueController;

    // ── 状态 ───────────────────────────────────────────
    private int _affinity;                           // 0~100
    private NPCEmotion _currentEmotion;
    private string _activeQuestId;
    private HashSet<string> _completedQuests;
    private HashSet<string> _dialogueFlags;          // 已触发对话标记
    private HashSet<string> _giftCooldown;           // 本Run赠送冷却
    private bool _isConversationActive;

    // ── IInteractable实现 ──────────────────────────────
    public string InteractId => $"npc_{_npcId}";
    public Vector2 Position => transform.position;
    public HubArea Area => _area;
    public bool IsAvailable => !IsLockedByMeta();
    public float InteractionRadius => 60f;

    // ── 公有属性 ───────────────────────────────────────
    public string NpcId => _npcId;
    public string NpcName => _npcName;
    public int Affinity => _affinity;
    public AffinityLevel AffinityLevel => GetAffinityLevel(_affinity);
    public bool IsConversationActive => _isConversationActive;
    public string ActiveQuestId => _activeQuestId;

    // ── 事件 ───────────────────────────────────────────
    public event Action<string, int, int> OnAffinityChanged;   // (npcId, oldVal, newVal)
    public event Action<string, AffinityLevel> OnAffinityLevelUp;
    public event Action<string> OnConversationStarted;
    public event Action<string> OnConversationEnded;
    public event Action<string, string> OnQuestAccepted;       // (npcId, questId)
    public event Action<string, string> OnQuestCompleted;

    // ── 生命周期 ───────────────────────────────────────
    private void Awake()
    {
        _animator = GetComponent<AnimationPlayer或AnimationTree>();
        _renderer = GetComponent<SpriteRenderer>();
        _dialogueController = GetComponent<DialogueController>();
        _completedQuests = new HashSet<string>();
        _dialogueFlags = new HashSet<string>();
        _giftCooldown = new HashSet<string>();
    }

    // ── 公有方法 ───────────────────────────────────────

    /// <summary>初始化NPC（从存档恢复好感度等数据）</summary>
    public void Initialize(NPCSaveData saveData);

    /// <summary>获取当前好感度对应的等级</summary>
    public AffinityLevel GetAffinityLevel(int affinity);

    /// <summary>增加好感度</summary>
    public void AddAffinity(int delta, string reason);

    /// <summary>赠送礼物</summary>
    public GiftResult GiveGift(string itemId);

    /// <summary>开始对话（IInteractable.OnInteract调用）</summary>
    public void OnFocus();
    public void OnLoseFocus();
    public void OnInteract(PlayerHubController player);

    /// <summary>启动对话流程</summary>
    public void StartConversation();

    /// <summary>结束对话流程</summary>
    public void EndConversation();

    /// <summary>获取当前可用对话节点</summary>
    public string GetCurrentDialogueNodeId();

    /// <summary>选择对话选项</summary>
    public void SelectChoice(int choiceIndex);

    /// <summary>推进到下一对话节点（无选择时自动）</summary>
    public void AdvanceDialogue();

    /// <summary>接受任务</summary>
    public void AcceptQuest(string questId);

    /// <summary>完成任务</summary>
    public void CompleteQuest(string questId);

    /// <summary>获取当前可用任务列表</summary>
    public IReadOnlyList<QuestData> GetAvailableQuests();

    /// <summary>获取进行中任务</summary>
    public IReadOnlyList<QuestData> GetActiveQuests();

    /// <summary>播放NPC动画</summary>
    public void PlayAnimation(string triggerName);

    /// <summary>设置NPC表情</summary>
    public void SetEmotion(NPCEmotion emotion);

    /// <summary>Run结束后重置每次Run限制（对话冷却/礼物冷却）</summary>
    public void OnRunEnded();

    /// <summary>检查Meta解锁条件</summary>
    public bool IsLockedByMeta();

    /// <summary>设置NPC可见性（未解锁NPC隐藏）</summary>
    public void SetVisible(bool visible);

    /// <summary>导出NPC存档数据</summary>
    public NPCSaveData ExportSaveData();
}

/// <summary>
/// 好感度等级
/// </summary>
public enum AffinityLevel
{
    Stranger,   // 0~19 陌生
    Familiar,   // 20~39 熟悉
    Trusted,    // 40~59 信任
    Intimate,   // 60~79 亲密
    Bonded      // 80~100 羁绊
}

public enum NPCEmotion { Neutral, Happy, Sad, Angry, Surprised, Thinking }

public struct GiftResult
{
    public bool Accepted;
    public int AffinityDelta;
    public string ResponseDialogueId;
    public string RejectionReason;
}

[Serializable]
public class NPCSaveData
{
    public string NpcId;
    public int Affinity;
    public List<string> CompletedQuests;
    public List<string> DialogueFlags;
    public List<string> DiscoveredSecrets;
}
```

### 2.3 DialogueController — 对话引擎

```text
/// <summary>
/// 对话控制器 — 管理对话节点流转、条件检测、选项展示
/// 对话数据由JSON外置，运行时按需加载
/// </summary>
public class DialogueController : Node
{
     private string _npcId;
     private DialogueUI _dialogueUI;

    private DialogueNode _currentNode;
    private Dictionary<string, DialogueNode> _nodeCache;
    private Stack<string> _nodeHistory;              // 回退栈
    private StringBuilder _textBuilder;
    private bool _isTyping;                          // 打字机效果进行中
    private Coroutine _typewriterCoroutine;

    // ── 事件 ───────────────────────────────────────────
    public event Action<DialogueNode> OnNodeDisplayed;
    public event Action<DialogueChoice> OnChoiceSelected;
    public event Action OnDialogueEnded;

    // ── 公有方法 ───────────────────────────────────────

    /// <summary>从JSON加载对话数据</summary>
    public void LoadDialogueData(string npcId);

    /// <summary>开始对话（从指定节点或自动选择首节点）</summary>
    public void StartDialogue(string startNodeId = null);

    /// <summary>显示指定对话节点</summary>
    public void DisplayNode(string nodeId);

    /// <summary>选择对话选项</summary>
    public void SelectChoice(int index);

    /// <summary>自动推进到下一节点（无选项时）</summary>
    public void AutoAdvance();

    /// <summary>跳过打字机效果，立即显示全文</summary>
    public void SkipTypewriter();

    /// <summary>回退到上一对话节点</summary>
    public void GoBack();

    /// <summary>结束对话</summary>
    public void EndDialogue();

    /// <summary>获取当前可用对话选项列表</summary>
    public IReadOnlyList<DialogueChoice> GetCurrentChoices();

    /// <summary>检测当前节点的前置条件是否满足</summary>
    public bool CheckPreconditions(DialoguePrecondition precondition);

    /// <summary>应用对话效果（好感度变化/设标记/给奖励）</summary>
    public void ApplyEffects(DialogueEffect effect);

    /// <summary>获取对话历史记录</summary>
    public IReadOnlyList<string> GetDialogueHistory();

    // ── 私有方法 ───────────────────────────────────────
    private async流程 TypewriterEffect(string text, float charDelay);
    private string ResolveVariables(string text);       // 替换{player_name}等变量
    private DialogueNode FindBestAvailableNode();       // 自动查找当前条件匹配的首节点
}

/// <summary>
/// 对话节点数据结构（对应JSON）
/// </summary>
[Serializable]
public class DialogueNode
{
    public string NodeId;
    public string NpcId;
    public DialoguePrecondition Precondition;
    public string Text;
    public DialogueChoice[] Choices;
    public string AutoNext;              // 无选择时自动跳转节点
    public string VoiceLine;             // 语音文件路径
    public string AnimationTrigger;      // NPC动画触发
    public string PortraitExpression;    // 肖像表情
}

[Serializable]
public class DialoguePrecondition
{
    public int MinAffinity;
    public int MaxAffinity;
    public string[] QuestFlags;          // 需要完成的任务
    public string[] ItemFlags;           // 需要持有的物品
    public int MinRunCount;              // 最低Run次数
    public int MinLayerReached;          // 最低到达层数
    public string[] BossKilled;          // 需要击杀的Boss
    public string[] ChoicesMade;         // 需要做的关键选择
}

[Serializable]
public class DialogueChoice
{
    public string Text;
    public int AffinityDelta;
    public string NextNode;
    public string SetFlag;               // 设置标记
    public DialogueReward Reward;        // 奖励
}

[Serializable]
public class DialogueReward
{
    public CurrencyReward[] Currencies;
    public string ItemId;
    public string QuestId;
}

[Serializable]
public class CurrencyReward
{
    public CurrencyType Type;
    public int Amount;
}

[Serializable]
public class DialogueEffect
{
    public int AffinityDelta;
    public string SetFlag;
    public CurrencyReward[] Currencies;
    public string ItemId;
    public string QuestId;
    public string TriggerAnimation;
}
```

### 2.4 AffinitySystem — 好感度管理

```text
/// <summary>
/// 好感度系统 — 管理所有NPC的好感度、等级阈值、冷却
/// RefCounted类，不依赖Node
/// </summary>
public class AffinitySystem
{
    private Dictionary<string, int> _affinityMap;             // npcId → 好感度值
    private Dictionary<string, HashSet<string>> _giftCooldowns; // npcId → 本Run已赠物品
    private HashSet<string> _runDialogueTriggered;             // 本Run已对话NPC

    // 好感度阈值
    private static readonly (AffinityLevel level, int min, int max)[] THRESHOLDS =
    {
        (AffinityLevel.Stranger,  0,  19),
        (AffinityLevel.Familiar, 20,  39),
        (AffinityLevel.Trusted,  40,  59),
        (AffinityLevel.Intimate, 60,  79),
        (AffinityLevel.Bonded,   80, 100)
    };

    // 好感度增量配置
    private const int DIALOGUE_DELTA = 2;          // Run后对话
    private const int QUEST_DELTA_MIN = 5;         // 任务奖励
    private const int QUEST_DELTA_MAX = 15;
    private const int GIFT_DELTA_MIN = 3;          // 赠礼
    private const int GIFT_DELTA_MAX = 8;
    private const int RUN_GOAL_DELTA = 5;          // Run中完成NPC提及目标
    private const int CHOICE_DELTA_MIN = 2;        // 对话选项
    private const int CHOICE_DELTA_MAX = 5;

    public AffinitySystem();

    /// <summary>初始化（从存档恢复）</summary>
    public void Initialize(Dictionary<string, int> savedAffinity);

    /// <summary>获取NPC好感度</summary>
    public int GetAffinity(string npcId);

    /// <summary>设置好感度（直接，用于存档恢复）</summary>
    public void SetAffinity(string npcId, int value);

    /// <summary>增加好感度（带上限clamp与事件发布）</summary>
    public int AddAffinity(string npcId, int delta, string reason);

    /// <summary>获取好感度等级</summary>
    public AffinityLevel GetLevel(string npcId);

    /// <summary>获取好感度等级（静态工具方法）</summary>
    public static AffinityLevel GetLevel(int affinity);

    /// <summary>检查赠礼冷却</summary>
    public bool CanGiveGift(string npcId, string itemId);

    /// <summary>记录赠礼（标记冷却）</summary>
    public void RecordGift(string npcId, string itemId);

    /// <summary>检查Run后对话是否可用</summary>
    public bool CanDialogueThisRun(string npcId);

    /// <summary>记录Run后对话</summary>
    public void RecordDialogue(string npcId);

    /// <summary>Run结束时重置冷却</summary>
    public void OnRunEnded();

    /// <summary>获取所有NPC好感度快照</summary>
    public Dictionary<string, int> GetAllAffinity();

    /// <summary>计算赠礼好感度增量（基于NPC偏好）</summary>
    public int CalculateGiftAffinity(string npcId, string itemId, NPCPreferenceData preferences);
}

[Serializable]
public class NPCPreferenceData
{
    public string NpcId;
    public PreferenceEntry[] Preferences;   // 物品类别→偏好倍率

    [Serializable]
    public class PreferenceEntry
    {
        public string ItemCategory;   // 如 "warden_relic", "deep_fragment", "wine"
        public int AffinityBonus;     // +3~+8
    }
}
```

### 2.5 QuestSystem — 任务系统

```text
/// <summary>
/// 任务系统 — 管理NPC任务的接受、进度跟踪、完成
/// </summary>
public class QuestSystem
{
    private Dictionary<string, QuestInstance> _activeQuests;    // questId → 实例
    private HashSet<string> _completedQuests;
    private QuestRegistry _registry;

    public QuestSystem(QuestRegistry registry);

    /// <summary>获取NPC当前可用任务列表</summary>
    public IReadOnlyList<QuestData> GetAvailableQuests(string npcId, int affinity, HashSet<string> flags);

    /// <summary>接受任务</summary>
    public bool AcceptQuest(string questId);

    /// <summary>更新任务进度</summary>
    public void UpdateProgress(string questId, string objectiveId, int delta);

    /// <summary>完成任务</summary>
    public QuestReward CompleteQuest(string questId);

    /// <summary>放弃任务</summary>
    public void AbandonQuest(string questId);

    /// <summary>检查任务是否可完成</summary>
    public bool IsQuestCompletable(string questId);

    /// <summary>获取进行中任务列表</summary>
    public IReadOnlyList<QuestInstance> GetActiveQuests();

    /// <summary>获取指定NPC的任务线进度</summary>
    public QuestLineProgress GetQuestLineProgress(string questLineId);

    /// <summary>检查任务完成条件</summary>
    public bool CheckObjective(QuestObjective objective);

    /// <summary>由事件驱动的任务进度更新</summary>
    public void OnGameEvent(IEvent evt);

    /// <summary>导出/导入存档数据</summary>
    public QuestSaveData ExportSaveData();
    public void ImportSaveData(QuestSaveData data);
}

[Serializable]
public class QuestData : IRegistryEntry
{
    public string Id { get; set; }
    public string NpcId;
    public string QuestName;
    public string Description;
    public int RequiredAffinity;          // 最低好感度
    public string[] RequiredFlags;        // 前置标记
    public QuestObjective[] Objectives;
    public QuestReward Reward;
    public bool IsRepeatable;
    public string QuestLineId;            // 所属任务线
    public int QuestLineOrder;            // 任务线内顺序
}

[Serializable]
public class QuestObjective
{
    public string ObjectiveId;
    public ObjectiveType Type;            // Kill, Collect, Reach, Talk, ClearFloor, BossKill
    public string TargetId;               // 目标实体ID
    public int RequiredCount;
    public int CurrentCount;
    public bool IsCompleted;
}

public enum ObjectiveType { Kill, Collect, Reach, Talk, ClearFloor, BossKill, UseTimeSkill }

[Serializable]
public class QuestReward
{
    public int ChronosShards;
    public int ExistentialImprints;
    public string ItemId;
    public int AffinityDelta;
    public string UnlockFlag;
}

[Serializable]
public class QuestInstance
{
    public string QuestId;
    public QuestState State;
    public Dictionary<string, int> ObjectiveProgress;
    public float StartTime;
    public float CompletionTime;

    public enum QuestState { Inactive, Active, Completable, Completed, Failed }
}

[Serializable]
public class QuestSaveData
{
    public List<QuestInstance> ActiveQuests;
    public List<string> CompletedQuests;
}
```

---

## 3. DeathScreenController — 死亡动画 + Run总结 + 货币结算

### 3.1 概述

玩家死亡时触发死亡流程：慢动作→屏幕暗角→角色消散动画→死亡画面渐入→Run总结统计→货币结算→解锁提示→返回枢纽。设计目标：15~25秒完成，给予情感缓冲同时快速回到游戏。

### 3.2 DeathScreenController

```text
/// <summary>
/// 死亡画面控制器 — 管理死亡动画序列、Run总结、货币结算
/// 挂载于DeathScreen UIPackedScene
/// </summary>
public class DeathScreenController : Node
{
    // ── 序列化引用 ─────────────────────────────────────
    [Header("UI引用")]
     private CanvasLayer/Control _rootCanvasLayer/Control;
     private TMPro.Label _deathTitleText;
     private TMPro.Label _deathQuoteText;     // 随机死亡台词
     private RunSummaryPanel _summaryPanel;
     private CurrencySettlementPanel _currencyPanel;
     private UnlockNotificationPanel _unlockPanel;
     private Button _returnToHubButton;

    [Header("动画")]
     private AnimationCurve _timeSlowCurve;
     private AnimationCurve _fadeInCurve;
     private float _deathAnimDuration = 2.5f;          // 死亡动画总时长
     private float _summaryDelay = 1.0f;               // 死亡动画后延迟
     private float _summaryFadeInDuration = 0.5f;
     private float _currencyCountDuration = 1.5f;      // 货币滚动计数时间
     private string[] _deathQuotes;                    // 随机死亡台词池

    // ── 运行时状态 ─────────────────────────────────────
    private DeathPhase _currentPhase;
    private RunStats _runStats;
    private RunData _runData;
    private CurrencySettlement _settlement;
    private List<UnlockEntry> _newUnlocks;

    // ── 事件 ───────────────────────────────────────────
    public event Action OnDeathSequenceStarted;
    public event Action OnDeathAnimComplete;
    public event Action<CurrencySettlement> OnCurrencySettled;
    public event Action OnReturnToHubRequested;

    // ── 公有方法 ───────────────────────────────────────

    /// <summary>启动死亡序列（由GameState进入Death阶段时调用）</summary>
    public void StartDeathSequence(RunData runData, RunStats runStats);

    /// <summary>跳过死亡动画，直接显示总结</summary>
    public void SkipDeathAnimation();

    /// <summary>显示Run总结面板</summary>
    public void ShowRunSummary();

    /// <summary>开始货币结算动画</summary>
    public void ShowCurrencySettlement();

    /// <summary>显示新解锁内容</summary>
    public void ShowUnlocks(List<UnlockEntry> unlocks);

    /// <summary>确认返回枢纽</summary>
    public void ConfirmReturnToHub();

    /// <summary>获取当前死亡阶段</summary>
    public DeathPhase GetCurrentPhase();

    // ── 私有方法（动画序列）─────────────────────────────

    /// <summary>阶段1: 时间减速 + 暗角渐入</summary>
    private async流程 Phase_TimeSlow();

    /// <summary>阶段2: 角色消散特效</summary>
    private async流程 Phase_PlayerDissolve();

    /// <summary>阶段3: 死亡画面渐入</summary>
    private async流程 Phase_DeathScreenFadeIn();

    /// <summary>阶段4: Run总结展示</summary>
    private async流程 Phase_RunSummary();

    /// <summary>阶段5: 货币结算计数动画</summary>
    private async流程 Phase_CurrencyCounting();

    /// <summary>阶段6: 解锁提示</summary>
    private async流程 Phase_UnlockNotifications();

    /// <summary>计算本次Run货币结算</summary>
    private CurrencySettlement CalculateSettlement(RunData runData, RunStats runStats);

    /// <summary>获取随机死亡台词</summary>
    private string GetRandomDeathQuote();

    /// <summary>执行货币写入（结算确认后）</summary>
    private void ApplyCurrencySettlement(CurrencySettlement settlement);

    /// <summary>检测本次Run触发的新解锁</summary>
    private List<UnlockEntry> DetectNewUnlocks(RunStats runStats);
}

/// <summary>
/// 死亡流程阶段
/// </summary>
public enum DeathPhase
{
    None,
    TimeSlow,          // 时间减速
    PlayerDissolve,    // 角色消散
    DeathScreenFadeIn, // 画面渐入
    RunSummary,        // Run总结
    CurrencyCounting,  // 货币结算
    UnlockNotification,// 解锁提示
    ReadyToReturn      // 等待返回
}

/// <summary>
/// Run总结面板
/// </summary>
public class RunSummaryPanel : Node
{
    public void Display(RunStats stats, RunData runData);
    public void AnimateIn(float duration);
    public void AnimateOut(float duration);
}

/// <summary>
/// 货币结算面板
/// </summary>
public class CurrencySettlementPanel : Node
{
    public void Display(CurrencySettlement settlement);
    public async流程 AnimateCounting(CurrencySettlement settlement, float duration);
}

/// <summary>
/// 解锁通知面板
/// </summary>
public class UnlockNotificationPanel : Node
{
    public void Display(List<UnlockEntry> unlocks);
    public async流程 ShowSequential(List<UnlockEntry> unlocks, float eachDuration);
}

/// <summary>
/// 货币结算数据
/// </summary>
[Serializable]
public class CurrencySettlement
{
    public int GoldEarned;                   // 本Run获得金币
    public int SoulEarned;                   // 本Run获得魂
    public int ChronosShardsEarned;          // 本Run获得时之碎片
    public int ExistentialImprintsEarned;    // 本Run获得存在印记
    public int TotalGold;                    // 结算后总金币
    public int TotalSoul;                    // 结算后总魂
    public int TotalChronosShards;           // 结算后总时之碎片
    public int TotalExistentialImprints;     // 结算后总存在印记
    public float ShardsMultiplier;           // 乘数（Meta加成）
    public List<SettlementLineItem> LineItems;

    [Serializable]
    public class SettlementLineItem
    {
        public string Description;    // 如 "击杀敌人×187"
        public CurrencyType Type;
        public int Amount;
        public bool IsBonus;          // 是否为Meta加成
    }
}

[Serializable]
public class UnlockEntry
{
    public UnlockType Type;
    public string Id;
    public string Name;
    public string Description;
    public Sprite Icon;
}

public enum UnlockType { MetaNode, Item, Character, Weapon, Achievement, Cosmetic, NPCDialogue }
```

---

## 4. GachaSystem — 时空祈愿 + 保底 + 碎片兑换

### 4.1 概述

"时空祈愿"是本游戏的抽卡系统，使用"时之碎片"作为抽卡货币，产出角色皮肤、武器外观、称号、特效等纯外观道具。保底机制确保长期投入的玩家不会永远落空。碎片兑换允许用重复道具碎片兑换指定道具。

### 4.2 GachaSystem

```text
/// <summary>
/// 抽卡系统 — 时空祈愿的核心逻辑
/// RefCounted类，不依赖Node
/// </summary>
public class GachaSystem
{
    private GachaPoolRegistry _poolRegistry;
    private PityTracker _pityTracker;
    private CosmeticManager _cosmeticManager;
    private CurrencyManager _currencyManager;
    private RNG _rng;

    // 抽卡消耗
    private const int SINGLE_PULL_COST = 10;        // 时之碎片
    private const int TEN_PULL_COST = 90;           // 十连优惠
    private const int FRAGMENT_EXCHANGE_RATE = 30;   // 30碎片兑换1指定道具

    public GachaSystem(GachaPoolRegistry poolRegistry, CosmeticManager cosmeticManager,
                       CurrencyManager currencyManager, RNG rng);

    /// <summary>执行单次祈愿</summary>
    public GachaResult Pull(string poolId);

    /// <summary>执行十连祈愿</summary>
    public GachaResult[] TenPull(string poolId);

    /// <summary>获取抽卡结果（计算但不确定认，用于预览）</summary>
    public GachaPreview PreviewPull(string poolId);

    /// <summary>确认抽卡结果（写入库存）</summary>
    public void ConfirmPull(GachaResult result);

    /// <summary>使用碎片兑换指定外观道具</summary>
    public ExchangeResult ExchangeWithFragments(string cosmeticId);

    /// <summary>获取当前保底计数</summary>
    public PityStatus GetPityStatus(string poolId);

    /// <summary>获取卡池信息</summary>
    public GachaPoolInfo GetPoolInfo(string poolId);

    /// <summary>获取所有可用卡池列表</summary>
    public IReadOnlyList<GachaPoolInfo> GetAllPools();

    /// <summary>检查是否可抽（货币足够+卡池开放）</summary>
    public bool CanPull(string poolId, int count);

    /// <summary>获取抽卡消耗</summary>
    public int GetPullCost(string poolId, int count);

    /// <summary>重置保底计数（卡池切换时）</summary>
    public void ResetPity(string poolId);

    // ── 核心抽取逻辑 ──────────────────────────────────

    /// <summary>根据权重随机抽取一个结果</summary>
    private GachaEntry RollEntry(string poolId, int currentPity);

    /// <summary>检查保底触发</summary>
    private bool CheckPityTrigger(string poolId, int currentPity, out Rarity guaranteedRarity);

    /// <summary>处理重复道具（转换为碎片）</summary>
    private DuplicateHandleResult HandleDuplicate(string cosmeticId, int ownedCount);

    /// <summary>更新保底计数</summary>
    private void UpdatePity(string poolId, Rarity pulledRarity);
}

/// <summary>
/// 抽卡结果
/// </summary>
[Serializable]
public class GachaResult
{
    public string ResultId;            // 唯一结果ID
    public string PoolId;
    public string CosmeticId;          // 获得的外观道具ID
    public Rarity Rarity;
    public bool IsNew;                 // 是否首次获得
    public bool IsPity;                // 是否保底触发
    public bool IsGuaranteed;          // 是否大保底
    public int FragmentReceived;       // 重复获得时的碎片数
    public Sprite Icon;
    public string DisplayName;
    public string Description;
}

/// <summary>
/// 保底追踪器
/// </summary>
public class PityTracker
{
    private Dictionary<string, int> _pullSinceLastRarity;   // poolId → 距上次稀有以上的抽数
    private Dictionary<string, int> _pullSinceLastMythic;   // poolId → 距上次神话的抽数
    private Dictionary<string, bool> _isGuaranteed;         // poolId → 是否触发大保底

    // 保底阈值
    private const int LEGENDARY_PITY = 50;     // 50抽必出传说
    private const int MYTHIC_PITY = 120;       // 120抽必出神话
    private const int LEGENDARY_SOFT_PITY = 40;// 40抽开始概率提升

    /// <summary>记录一次抽卡</summary>
    public void RecordPull(string poolId, Rarity rarity);

    /// <summary>获取当前保底计数</summary>
    public PityStatus GetStatus(string poolId);

    /// <summary>检查是否触发保底</summary>
    public bool ShouldTriggerPity(string poolId, out Rarity rarity);

    /// <summary>计算当前传说概率（含软保底加成）</summary>
    public float GetLegendaryProbability(string poolId);

    /// <summary>计算当前神话概率（含软保底加成）</summary>
    public float GetMythicProbability(string poolId);

    /// <summary>重置卡池保底</summary>
    public void ResetPool(string poolId);

    /// <summary>导出/导入存档数据</summary>
    public PitySaveData ExportSaveData();
    public void ImportSaveData(PitySaveData data);
}

[Serializable]
public class PityStatus
{
    public string PoolId;
    public int PullsSinceLegendary;
    public int PullsSinceMythic;
    public bool IsGuaranteedLegendary;
    public int PullsToLegendary;       // 距保底还差几抽
    public int PullsToMythic;
}

/// <summary>
/// 卡池数据
/// </summary>
[Serializable]
public class GachaPoolData : IRegistryEntry
{
    public string Id { get; set; }
    public string PoolName;
    public string Description;
    public bool IsPermanent;           // 常驻池 vs 限时池
    public string StartTime;           // 限时池开始时间
    public string EndTime;             // 限时池结束时间
    public GachaEntry[] Entries;       // 池内条目
    public float LegendaryRate;        // 基础传说概率
    public float MythicRate;           // 基础神话概率
}

[Serializable]
public class GachaEntry
{
    public string CosmeticId;
    public Rarity Rarity;
    public float Weight;               // 权重
    public bool IsRateUp;              // 是否UP
    public float RateUpMultiplier;
}

public struct GachaPreview { public string PoolId; public int Cost; public PityStatus Pity; }

public struct ExchangeResult
{
    public bool Success;
    public string CosmeticId;
    public int FragmentsSpent;
    public int FragmentsRemaining;
    public string FailReason;
}

public struct DuplicateHandleResult
{
    public int FragmentsGranted;
    public Rarity Rarity;
}

[Serializable]
public class PitySaveData
{
    public Dictionary<string, int> PullSinceLegendary;
    public Dictionary<string, int> PullSinceMythic;
    public Dictionary<string, bool> IsGuaranteed;
}
```

---

## 5. CosmeticManager — 皮肤/外观/称号管理

### 5.1 概述

管理所有纯外观道具（角色皮肤、武器外观、称号、特效、头像框），处理装备/卸装、库存管理、碎片系统。外观道具不影响游戏性，纯视觉差异化。

### 5.2 CosmeticManager

```text
/// <summary>
/// 外观管理器 — 管理所有纯外观道具的库存、装备、碎片
/// RefCounted类，通过ServiceRegistry全局访问
/// </summary>
public class CosmeticManager
{
    private CosmeticRegistry _registry;
    private Dictionary<string, OwnedCosmetic> _inventory;   // cosmeticId → 拥有信息
    private Dictionary<CosmeticSlot, string> _equipped;     // 槽位 → 装备的cosmeticId
    private Dictionary<string, int> _fragments;             // cosmeticId → 碎片数

    public CosmeticManager(CosmeticRegistry registry);

    // ── 库存管理 ───────────────────────────────────────

    /// <summary>添加外观道具到库存（抽卡/成就/商店获得）</summary>
    public AddCosmeticResult AddCosmetic(string cosmeticId, string source);

    /// <summary>移除外观道具（一般不允许，仅碎片兑换时消耗）</summary>
    public bool RemoveCosmetic(string cosmeticId);

    /// <summary>检查是否拥有指定外观</summary>
    public bool Owns(string cosmeticId);

    /// <summary>获取指定外观的拥有信息</summary>
    public OwnedCosmetic GetOwnedInfo(string cosmeticId);

    /// <summary>获取所有已拥有外观列表</summary>
    public IReadOnlyList<OwnedCosmetic> GetAllOwned();

    /// <summary>按类型筛选已拥有外观</summary>
    public IReadOnlyList<OwnedCosmetic> GetOwnedByType(CosmeticType type);

    /// <summary>按角色筛选已拥有外观</summary>
    public IReadOnlyList<OwnedCosmetic> GetOwnedByCharacter(string characterId);

    // ── 装备管理 ───────────────────────────────────────

    /// <summary>装备外观到指定槽位</summary>
    public EquipResult Equip(string cosmeticId, CosmeticSlot slot);

    /// <summary>卸下指定槽位外观</summary>
    public void Unequip(CosmeticSlot slot);

    /// <summary>获取当前装备的外观</summary>
    public string GetEquippedId(CosmeticSlot slot);

    /// <summary>获取所有装备槽当前装备</summary>
    public IReadOnlyDictionary<CosmeticSlot, string> GetAllEquipped();

    /// <summary>重置到默认外观</summary>
    public void ResetToDefault();

    // ── 碎片系统 ───────────────────────────────────────

    /// <summary>添加碎片（重复道具转化）</summary>
    public void AddFragments(string cosmeticId, int count);

    /// <summary>消耗碎片（兑换指定道具）</summary>
    public bool SpendFragments(string cosmeticId, int count);

    /// <summary>获取碎片数量</summary>
    public int GetFragmentCount(string cosmeticId);

    /// <summary>获取碎片兑换所需数量</summary>
    public int GetExchangeCost(string cosmeticId);

    /// <summary>检查碎片是否足够兑换</summary>
    public bool CanExchange(string cosmeticId);

    // ── 存档 ───────────────────────────────────────────

    /// <summary>导出存档数据</summary>
    public CosmeticSaveData ExportSaveData();

    /// <summary>导入存档数据</summary>
    public void ImportSaveData(CosmeticSaveData data);
}

/// <summary>
/// 外观类型
/// </summary>
public enum CosmeticType
{
    CharacterSkin,      // 角色皮肤
    WeaponSkin,         // 武器外观
    Title,              // 称号
    Effect,             // 特效（击杀特效/脚步特效等）
    PortraitFrame,      // 头像框
    Emote,              // 表情动作
    BGMReplacement      // 可替换BGM
}

/// <summary>
/// 外观装备槽位
/// </summary>
public enum CosmeticSlot
{
    CharacterSkin,
    WeaponSkin_Sword,
    WeaponSkin_Bow,
    WeaponSkin_Spear,
    WeaponSkin_Staff,
    WeaponSkin_Gauntlet,
    Title,
    KillEffect,
    FootstepEffect,
    PortraitFrame
}

/// <summary>
/// 已拥有外观数据
/// </summary>
[Serializable]
public class OwnedCosmetic
{
    public string CosmeticId;
    public CosmeticType Type;
    public Rarity Rarity;
    public string Source;              // 获得来源: "gacha", "achievement", "daily_challenge", "shop"
    public string AcquiredDate;        // ISO8601
    public bool IsEquipped;
    public int DuplicateCount;         // 重复获得次数
}

/// <summary>
/// 外观注册表条目（Resource数据）
/// </summary>
[Serializable]
public class CosmeticData : IRegistryEntry
{
    public string Id { get; set; }
    public string DisplayName;
    public string Description;
    public CosmeticType Type;
    public Rarity Rarity;
    public string CharacterId;         // 适用角色（空=通用）
    public string WeaponType;          // 适用武器类型（武器外观专用）
    public CosmeticSlot Slot;
    public Sprite Icon;
    public string AssetPath;           // Resource路径
    public int FragmentExchangeCost;   // 碎片兑换所需数量
    public bool IsDefault;             // 是否默认外观
    public string[] Tags;              // 标签（用于筛选）
}

public struct AddCosmeticResult
{
    public bool IsNew;
    public int FragmentsGranted;       // 重复时转化的碎片数
}

public struct EquipResult
{
    public bool Success;
    public string PreviousCosmeticId;  // 被替换的外观
    public string FailReason;
}

[Serializable]
public class CosmeticSaveData
{
    public List<OwnedCosmetic> Inventory;
    public Dictionary<string, string> Equipped;     // slot → cosmeticId
    public Dictionary<string, int> Fragments;
}
```

---

## 6. SaveManager — 3槽 + Steam Cloud + 加密 + 防篡改

### 6.1 概述

存档系统支持3个常规存档槽 + 1个每日挑战槽，采用MessagePack二进制序列化 + AES-256-GCM加密，Steam Cloud自动同步，原子写入+双备份防损坏，多重校验防篡改。

### 6.2 SaveManager

```text
/// <summary>
/// 存档管理器 — 负责存档的读写、加密、校验、同步
/// RefCounted类，通过ServiceRegistry全局访问
/// </summary>
public class SaveManager
{
    private const string MAGIC = "PWCS";
    private const int CURRENT_VERSION = 1;
    private const int MAX_SLOTS = 3;
    private const int BACKUP_COUNT = 2;
    private const long AUTO_SAVE_INTERVAL_MS = 300000;  // 5分钟

    private readonly string _saveRoot;                     // 存档根目录
    private readonly byte[] _masterKeyPart1;               // 混淆密钥段1
    private readonly byte[] _masterKeyPart2;               // 混淆密钥段2
    private Dictionary<int, SaveSlot> _slots;              // slotIndex → SaveSlot
    private SaveSlot _activeSlot;
    private SaveSettings _settings;
    private GlobalStats _globalStats;
    private SteamCloudSync _cloudSync;
    private CancellationTokenSource _autoSaveCts;
    private bool _isSaving;
    private long _lastAutoSaveTime;

    public SaveManager(string saveRoot, SteamCloudSync cloudSync);

    // ── 存档槽管理 ─────────────────────────────────────

    /// <summary>获取所有存档槽元信息（用于UI展示）</summary>
    public IReadOnlyList<SaveSlotMeta> GetAllSlotMetas();

    /// <summary>获取指定槽位元信息</summary>
    public SaveSlotMeta GetSlotMeta(int slotIndex);

    /// <summary>创建新存档</summary>
    public int CreateSaveSlot(string characterId, Difficulty difficulty);

    /// <summary>加载存档</summary>
    public SaveData LoadSave(int slotIndex);

    /// <summary>保存当前存档（全量）</summary>
    public void SaveCurrent(SaveTriggerReason reason);

    /// <summary>增量保存（仅更新变化字段）</summary>
    public void SaveIncremental(SaveTriggerReason reason, string[] changedFields);

    /// <summary>删除存档</summary>
    public bool DeleteSave(int slotIndex);

    /// <summary>获取活跃存档槽</summary>
    public SaveSlot GetActiveSlot();

    /// <summary>设置活跃存档槽</summary>
    public void SetActiveSlot(int slotIndex);

    /// <summary>检查存档是否存在</summary>
    public bool SaveExists(int slotIndex);

    /// <summary>获取存档槽数量</summary>
    public int SlotCount => MAX_SLOTS;

    // ── 每日挑战存档 ───────────────────────────────────

    /// <summary>加载每日挑战存档</summary>
    public DailyChallengeSaveData LoadDailyChallenge();

    /// <summary>保存每日挑战存档</summary>
    public void SaveDailyChallenge(DailyChallengeSaveData data);

    /// <summary>重置每日挑战存档（每日0:00）</summary>
    public void ResetDailyChallenge();

    // ── 全局数据 ───────────────────────────────────────

    /// <summary>加载全局设置</summary>
    public SaveSettings LoadSettings();

    /// <summary>保存全局设置</summary>
    public void SaveSettings(SaveSettings settings);

    /// <summary>加载全局统计</summary>
    public GlobalStats LoadGlobalStats();

    /// <summary>保存全局统计</summary>
    public void SaveGlobalStats(GlobalStats stats);

    // ── 加密/解密 ──────────────────────────────────────

    /// <summary>加密存档数据</summary>
    public byte[] Encrypt(byte[] data, int slotIndex, byte[] salt);

    /// <summary>解密存档数据</summary>
    public byte[] Decrypt(byte[] encryptedData, int slotIndex, byte[] salt, byte[] tag);

    /// <summary>派生密钥（SHA256(masterKey + slotId + salt)）</summary>
    private byte[] DeriveKey(int slotIndex, byte[] salt);

    /// <summary>拼接主密钥（运行时从两段混淆密钥组合）</summary>
    private byte[] CombineMasterKey();

    // ── 完整性校验 ─────────────────────────────────────

    /// <summary>校验存档完整性（Header+Checksum+GCM标签）</summary>
    public ValidationResult ValidateSave(int slotIndex);

    /// <summary>逻辑范围校验（HP/金币/层数等合理性）</summary>
    public bool ValidateLogic(SaveData data);

    /// <summary>时间线校验（保存时间>=创建时间<=当前时间）</summary>
    public bool ValidateTimeline(SaveHeader header);

    /// <summary>统计一致性校验</summary>
    public bool ValidateStatsConsistency(SaveData data);

    /// <summary>运行时内存校验（每60秒调用一次）</summary>
    public bool ValidateRuntimeMemory();

    // ── 损坏恢复 ───────────────────────────────────────

    /// <summary>尝试恢复损坏存档</summary>
    public RecoveryResult TryRecover(int slotIndex);

    /// <summary>从备份恢复</summary>
    private RecoveryResult RecoverFromBackup(int slotIndex, int backupIndex);

    /// <summary>从Steam Cloud恢复</summary>
    private RecoveryResult RecoverFromCloud(int slotIndex);

    // ── 原子写入 ───────────────────────────────────────

    /// <summary>原子写入（写临时文件→校验→重命名）</summary>
    private void AtomicWrite(string filePath, byte[] data);

    /// <summary>备份轮转（当前→backup_1→backup_2）</summary>
    private void RotateBackups(int slotIndex);

    // ── Steam Cloud同步 ────────────────────────────────

    /// <summary>上传存档到Steam Cloud</summary>
    public void UploadToCloud(int slotIndex);

    /// <summary>从Steam Cloud下载存档</summary>
    public void DownloadFromCloud(int slotIndex);

    /// <summary>处理Cloud冲突</summary>
    public CloudConflictResolution ResolveCloudConflict(int slotIndex);

    /// <summary>检查Cloud同步状态</summary>
    public CloudSyncStatus GetCloudSyncStatus();

    // ── 自动保存 ───────────────────────────────────────

    /// <summary>启动自动保存循环</summary>
    public void StartAutoSave();

    /// <summary>停止自动保存循环</summary>
    public void StopAutoSave();

    /// <summary>自动保存循环（后台线程）</summary>
    private async流程 AutoSaveLoop();

    // ── 防篡改 ─────────────────────────────────────────

    /// <summary>标记存档为受污染</summary>
    public void MarkContaminated(int slotIndex);

    /// <summary>检查存档是否受污染</summary>
    public bool IsContaminated(int slotIndex);

    /// <summary>受污染存档是否禁用排行榜</summary>
    public bool IsLeaderboardDisabled(int slotIndex);

    /// <summary>受污染存档是否禁用成就</summary>
    public bool IsAchievementDisabled(int slotIndex);
}

/// <summary>
/// 存档槽运行时数据
/// </summary>
public class SaveSlot
{
    public int SlotIndex;
    public SaveData Data;
    public SaveSlotMeta Meta;
    public bool IsContaminated;
    public bool IsActive;
    public DateTime LastSaveTime;
}

/// <summary>
/// 存档元信息（不加密，用于UI预览）
/// </summary>
[Serializable]
public class SaveSlotMeta
{
    public int SlotIndex;
    public string Version;
    public string Timestamp;           // ISO8601
    public int PlayTimeSeconds;
    public int CurrentLayer;
    public string CurrentRoomId;
    public string WeaponType;
    public int PlayerLevel;
    public int BlessingCount;
    public int CurseCount;
    public ulong Seed;
    public bool IsDaily;
    public bool IsEnded;               // 死亡/通关后标记
    public bool IsContaminated;
    public string ScreenshotPath;
}

/// <summary>
/// 存档头部
/// </summary>
[Serializable]
public class SaveHeader
{
    public string Magic;               // "PWCS"
    public int Version;
    public string Checksum;            // SHA-256
    public string CreatedAt;
    public string LastSavedAt;
    public int SlotIndex;
    public byte[] Salt;
    public byte[] AuthTag;             // AES-GCM认证标签
    public bool IsContaminated;
}

/// <summary>
/// 存档主体数据
/// </summary>
[Serializable]
public class SaveData
{
    public SaveHeader Header;
    public PlayerSaveData Player;
    public InventorySaveData Inventory;
    public DungeonSaveData Dungeon;
    public TimeMechanicsSaveData TimeMechanics;
    public StatisticsSaveData Statistics;
    public MetaProgressionSaveData Meta;
    public NPCSaveDataCollection NPCData;
    public CosmeticSaveData Cosmetics;
}

[Serializable]
public class PlayerSaveData
{
    public float HP;
    public float MaxHP;
    public float MP;
    public float MaxMP;
    public int Level;
    public int Exp;
    public int ExpNext;
    public int Gold;
    public string CharacterId;
    public string WeaponId;
    public int WeaponEnhancementLevel;
    public string[] EnchantmentIds;
}

[Serializable]
public class InventorySaveData
{
    public string[] WeaponIds;
    public ItemSaveEntry[] Items;
    public string[] ActiveBlessingIds;
    public string[] ActiveCurseIds;
    public TalentSaveData TalentTree;
}

[Serializable]
public class ItemSaveEntry
{
    public string ItemId;
    public int StackCount;
    public int SlotIndex;
}

[Serializable]
public class DungeonSaveData
{
    public ulong Seed;
    public int CurrentLayer;
    public string CurrentRoomId;
    public string[] ExploredRooms;
    public string[] UnlockedDoors;
    public Dictionary<string, object> LayerState;
}

[Serializable]
public class TimeMechanicsSaveData
{
    public int RewindCharges;
    public int MaxRewindCharges;
    public float SlowCooldownRemaining;
    public string[] ActiveEffects;
}

[Serializable]
public class StatisticsSaveData
{
    public int KillsTotal;
    public Dictionary<string, int> KillsByWeapon;
    public int Deaths;
    public int BossKills;
    public int RoomsCleared;
    public float HighestSingleDamage;
    public int ItemsCollected;
    public int TimeSkillUses;
    public int PerfectParries;
    public int PerfectReloads;
}

[Serializable]
public class MetaProgressionSaveData
{
    public int ChronosShards;
    public int ExistentialImprints;
    public string[] UnlockedNodes;
    public string[] DiscoveredItems;
    public string[] UnlockedCharacters;
    public string[] UnlockedWeapons;
    public Dictionary<string, int> WeaponProficiency;
    public string[] UnlockedAchievements;
}

[Serializable]
public class NPCSaveDataCollection
{
    public Dictionary<string, int> Affinity;             // npcId → 好感度
    public List<string> CompletedQuests;
    public List<string> DialogueFlags;
}

[Serializable]
public class TalentSaveData
{
    public string SelectedPath;
    public string[] UnlockedNodes;
    public int PathPoints;
}

[Serializable]
public class DailyChallengeSaveData
{
    public string ChallengeId;
    public string Date;
    public int AttemptsRemaining;
    public DailyChallengeResult BestResult;
}

[Serializable]
public class DailyChallengeResult
{
    public int Score;
    public int LayerReached;
    public int Kills;
    public float TimeElapsed;
}

public enum SaveTriggerReason
{
    RoomChange, ItemAcquired, BossKill, LayerChange,
    PlayerLevelUp, TimeSkillUse, AutoSave, PauseMenu,
    ApplicationQuit, RunEnd
}

public enum CloudConflictResolution { UseLocal, UseCloud, Cancel }

public struct ValidationResult
{
    public bool IsValid;
    public ValidationFailure Failure;
    public string Details;
}

public enum ValidationFailure
{
    None, InvalidMagic, ChecksumMismatch, DecryptionFailed,
    DeserializationFailed, LogicRangeError, TimelineError,
    StatsInconsistency, AuthTagMismatch
}

public struct RecoveryResult
{
    public bool Success;
    public RecoverySource Source;
    public string Message;
}

public enum RecoverySource { Primary, Backup1, Backup2, SteamCloud, Reset }

public struct CloudSyncStatus
{
    public bool IsSyncing;
    public bool HasConflict;
    public DateTime? LastSyncTime;
    public float Progress;
}
```

### 6.3 SteamCloudSync

```text
/// <summary>
/// Steam Cloud存档同步封装
/// </summary>
public class SteamCloudSync
{
    private const string REMOTE_SAVE_DIR = "save";
    private const string REMOTE_SETTINGS_DIR = "settings";
    private const string REMOTE_STATS_DIR = "stats";

    /// <summary>初始化Steam Cloud</summary>
    public void Initialize();

    /// <summary>上传文件到Steam Cloud</summary>
    public bool UploadFile(string localPath, string remotePath);

    /// <summary>从Steam Cloud下载文件</summary>
    public bool DownloadFile(string remotePath, string localPath);

    /// <summary>检查Steam Cloud是否可用</summary>
    public bool IsCloudAvailable();

    /// <summary>获取Steam Cloud剩余配额</summary>
    public long GetRemainingQuotaBytes();

    /// <summary>同步所有存档文件</summary>
    public async流程 SyncAll(Action<CloudSyncResult> onComplete);

    /// <summary>检测冲突</summary>
    public bool HasConflict(int slotIndex);

    /// <summary>获取冲突详情</summary>
    public CloudConflictInfo GetConflictInfo(int slotIndex);
}

public struct CloudSyncResult
{
    public bool Success;
    public int FilesUploaded;
    public int FilesDownloaded;
    public int ConflictsDetected;
    public string Error;
}

public struct CloudConflictInfo
{
    public int SlotIndex;
    public SaveSlotMeta LocalMeta;
    public SaveSlotMeta CloudMeta;
}
```

---

## 7. SocialManager — 排行榜 + 每日挑战 + 好友Ghost + Build分享码

### 7.1 概述

社交系统整合Steam排行榜（10个分类）、每日挑战、好友Ghost数据、Build方案分享码。所有网络交互通过Steamworks API，无需自建服务器。

### 7.2 SocialManager

```text
/// <summary>
/// 社交管理器 — 排行榜/每日挑战/好友Ghost/Build分享
/// RefCounted类，通过ServiceRegistry全局访问
/// </summary>
public class SocialManager
{
    private LeaderboardManager _leaderboardManager;
    private DailyChallengeManager _dailyChallengeManager;
    private GhostManager _ghostManager;
    private BuildShareManager _buildShareManager;
    private bool _isModActive;    // Mod激活时禁用排行榜/成就

    public SocialManager(SteamworksProvider steamProvider);

    /// <summary>初始化所有子系统</summary>
    public void Initialize();

    /// <summary>设置Mod激活状态</summary>
    public void SetModActive(bool active);

    // ── 排行榜代理 ─────────────────────────────────────

    public void RequestLeaderboard(string leaderboardId, int rangeStart, int rangeEnd,
                                    Action<LeaderboardResult> onComplete);
    public void RequestFriendLeaderboard(string leaderboardId,
                                          Action<LeaderboardResult> onComplete);
    public void SubmitScore(string leaderboardId, int score, string metadata,
                            Action<bool> onComplete);
    public int GetGlobalRank(string leaderboardId);
    public int GetFriendRank(string leaderboardId);

    // ── 每日挑战代理 ───────────────────────────────────

    public DailyChallengeInfo GetDailyChallengeInfo();
    public void StartDailyChallenge(Action<bool> onComplete);
    public void SubmitDailyChallengeScore(int score, Action<bool> onComplete);
    public int GetDailyAttemptsRemaining();
    public void RefreshDailyChallenge();

    // ── 好友Ghost代理 ──────────────────────────────────

    public void RequestFriendGhosts(string roomId, Action<GhostData[]> onComplete);
    public GhostData SelectGhostForRoom(string roomId);
    public void UploadGhostData(GhostData ghost);
    public void SetGhostDisplayEnabled(bool enabled);

    // ── Build分享代理 ──────────────────────────────────

    public string GenerateBuildShareCode(BuildData build);
    public BuildShareResult ParseBuildShareCode(string code);
    public void ShareBuildToSteam(BuildData build);
}
```

### 7.3 LeaderboardManager

```text
/// <summary>
/// 排行榜管理器 — 封装Steam Leaderboard API
/// </summary>
public class LeaderboardManager
{
    private Dictionary<string, SteamLeaderboard_t> _leaderboardHandles;
    private Dictionary<string, int> _cachedPersonalRank;

    // 排行榜ID常量
    public const string LB_SPEEDRUN = "LB_SPEEDRUN";
    public const string LB_KILLS = "LB_KILLS";
    public const string LB_ITEMS = "LB_ITEMS";
    public const string LB_NO_HIT = "LB_NO_HIT";
    public const string LB_DAILY = "LB_DAILY";
    public const string LB_WEAPON_SWORD = "LB_WEAPON_SWORD";
    public const string LB_WEAPON_BOW = "LB_WEAPON_BOW";
    public const string LB_WEAPON_SPEAR = "LB_WEAPON_SPEAR";
    public const string LB_WEAPON_STAFF = "LB_WEAPON_STAFF";
    public const string LB_WEAPON_GAUNTLET = "LB_WEAPON_GAUNTLET";

    /// <summary>初始化排行榜句柄（异步请求所有排行榜ID）</summary>
    public async流程 InitializeAll(Action onComplete);

    /// <summary>请求排行榜数据</summary>
    public void RequestEntries(string leaderboardId, int start, int end,
                               Action<LeaderboardEntry[]> onComplete);

    /// <summary>请求好友排行榜</summary>
    public void RequestFriendEntries(string leaderboardId,
                                      Action<LeaderboardEntry[]> onComplete);

    /// <summary>提交分数</summary>
    public void UploadScore(string leaderboardId, int score, int[] details,
                            Action<bool> onComplete);

    /// <summary>获取个人排名</summary>
    public int GetPersonalRank(string leaderboardId);

    /// <summary>获取个人最佳分数</summary>
    public int GetPersonalBest(string leaderboardId);

    /// <summary>生成排行榜元数据字符串（武器+层数+击杀等）</summary>
    public string BuildMetadata(RunData runData, RunStats stats);
}

[Serializable]
public struct LeaderboardEntry
{
    public int Rank;
    public ulong SteamId;
    public string PlayerName;
    public int Score;
    public string Metadata;
    public bool IsFriend;
    public bool IsSelf;
}

public struct LeaderboardResult
{
    public string LeaderboardId;
    public LeaderboardEntry[] Entries;
    public int TotalCount;
    public bool Success;
    public string Error;
}
```

### 7.4 DailyChallengeManager

```text
/// <summary>
/// 每日挑战管理器 — 生成/管理/结算每日挑战
/// </summary>
public class DailyChallengeManager
{
    private const int MAX_DAILY_ATTEMPTS = 3;
    private DailyChallengeInfo _currentChallenge;
    private DailyChallengeResult _bestResult;
    private int _attemptsToday;
    private DateTime _lastRefreshDate;

    /// <summary>获取/刷新当日挑战</summary>
    public DailyChallengeInfo GetOrRefresh();

    /// <summary>开始每日挑战</summary>
    public bool StartAttempt();

    /// <summary>提交挑战成绩</summary>
    public void SubmitResult(DailyChallengeResult result, Action<bool> onComplete);

    /// <summary>获取剩余尝试次数</summary>
    public int AttemptsRemaining => MAX_DAILY_ATTEMPTS - _attemptsToday;

    /// <summary>获取当日最佳成绩</summary>
    public DailyChallengeResult GetBestResult();

    /// <summary>获取近7日挑战预告</summary>
    public DailyChallengeInfo[] GetWeeklyPreview();

    /// <summary>生成每日挑战（基于日期种子）</summary>
    private DailyChallengeInfo GenerateChallenge(DateTime date);

    /// <summary>检查并重置（跨日时）</summary>
    private void CheckDailyReset();
}

[Serializable]
public class DailyChallengeInfo
{
    public string ChallengeId;
    public string Date;                 // ISO8601日期
    public string ChallengeName;
    public string Description;
    public string SpecialRule;          // 特殊规则描述
    public ChallengeModifier[] Modifiers;
    public string RecommendedWeapon;
    public int Participants;
    public DailyChallengeReward[] Rewards;
}

[Serializable]
public class ChallengeModifier
{
    public string ModifierId;
    public ModifierType Type;           // CurseDouble, TimeRewindDisable, etc.
    public string Description;
    public float Value;
}

public enum ModifierType
{
    CurseDouble, TimeRewindDisable, TimeSlowReduce,
    EnemyHpBonus, EnemySpeedBonus, NoHealing, GoldHalf
}

[Serializable]
public class DailyChallengeReward
{
    public int RankPercentile;          // Top X%
    public string RewardType;           // skin, title, token
    public string RewardId;
    public int RewardAmount;
    public bool IsPermanent;
}
```

### 7.5 GhostManager

```text
/// <summary>
/// 好友Ghost管理器 — 管理好友通关路径Ghost数据
/// </summary>
public class GhostManager
{
    private Dictionary<string, GhostData> _ghostCache;   // friendSteamId → GhostData
    private bool _displayEnabled = true;
    private HashSet<ulong> _enabledFriends;
    private const float GHOST_SPAWN_CHANCE = 0.05f;     // 5%概率

    /// <summary>请求好友Ghost数据</summary>
    public void RequestGhosts(Action<GhostData[]> onComplete);

    /// <summary>为指定房间选择一个Ghost（概率触发）</summary>
    public GhostData SelectGhostForRoom(string roomId);

    /// <summary>上传自己通关的Ghost数据</summary>
    public void UploadMyGhost(GhostData ghost);

    /// <summary>设置Ghost显示开关</summary>
    public void SetDisplayEnabled(bool enabled);

    /// <summary>设置仅显示特定好友的Ghost</summary>
    public void SetEnabledFriends(HashSet<ulong> friendIds);

    /// <summary>清除缓存</summary>
    public void ClearCache();
}

[Serializable]
public class GhostData
{
    public ulong OwnerSteamId;
    public string OwnerName;
    public string WeaponType;
    public GhostPathNode[] PathNodes;    // 房间路径序列
    public float TotalTime;
    public int TotalKills;
    public string GameVersion;
}

[Serializable]
public class GhostPathNode
{
    public string RoomId;
    public float EnterTime;             // 进入时间(秒)
    public float ExitTime;              // 离开时间(秒)
    public float PositionX;             // 入口X
    public float PositionY;             // 入口Y
    public float ExitX;                 // 出口X
    public float ExitY;                 // 出口Y
}
```

### 7.6 BuildShareManager

```text
/// <summary>
/// Build分享管理器 — 生成/解析分享码
/// </summary>
public class BuildShareManager
{
    private const string CODE_PREFIX = "PWC-BLD-";

    /// <summary>从Build数据生成分享码</summary>
    public string GenerateCode(BuildData build);

    /// <summary>从分享码解析Build数据</summary>
    public BuildShareResult ParseCode(string code);

    /// <summary>分享到Steam Activity Feed</summary>
    public void ShareToSteam(BuildData build, string comment);

    /// <summary>验证分享码格式</summary>
    public bool ValidateCode(string code);
}

[Serializable]
public class BuildData
{
    public string CharacterId;
    public string WeaponId;
    public string[] ItemIds;
    public string[] BlessingIds;
    public string[] CurseIds;
    public string TalentPath;
    public string[] TalentNodes;
    public string Note;                 // 备注(最多20字)
    public float ClearTime;             // 通关时间(秒)
    public int Kills;
}

public struct BuildShareResult
{
    public bool Success;
    public BuildData Build;
    public string Error;
}
```

---

## 8. ReplaySystem — 输入记录 + 确定性回放 + 播放器

### 8.1 概述

录像系统基于"输入记录+种子→确定性回放"原理，每帧记录玩家输入状态(12字节/帧)，30分钟录像约300~500KB压缩后。支持播放/暂停/变速/跳转/自由视角，可上传Steam Workshop，排行榜Top10自动公开回放。

### 8.2 ReplayRecorder

```text
/// <summary>
/// 录像记录器 — 在游戏运行时逐帧记录输入
/// 挂载于GameManager，每局自动开始记录
/// </summary>
public class ReplayRecorder
{
    private List<ReplayFrame> _frames;
    private ReplayHeader _header;
    private List<ReplayEventMarker> _eventMarkers;
    private bool _isRecording;
    private uint _frameCounter;
    private float _totalTime;
    private LZ4Codec _compressor;

    /// <summary>开始录像</summary>
    public void StartRecording(ulong seed, string weaponId, string gameVersion);

    /// <summary>记录一帧输入（每帧FixedUpdate调用）</summary>
    public void RecordFrame(ReplayInputState input);

    /// <summary>记录关键事件标记</summary>
    public void RecordEvent(ReplayEventType eventType, string detail);

    /// <summary>暂停录像（暂停菜单时）</summary>
    public void PauseRecording();

    /// <summary>恢复录像</summary>
    public void ResumeRecording();

    /// <summary>结束录像并保存</summary>
    public ReplaySaveResult FinishRecording(RunResult result);

    /// <summary>崩溃时尝试紧急保存</summary>
    public void EmergencySave();

    /// <summary>获取当前录像时长</summary>
    public float GetRecordingDuration();

    /// <summary>获取当前帧数</summary>
    public uint GetCurrentFrameCount();

    /// <summary>是否正在录像</summary>
    public bool IsRecording => _isRecording;
}

/// <summary>
/// 每帧输入状态（12字节）
/// </summary>
[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct ReplayFrame
{
    public uint FrameNumber;       // 4字节
    public byte MovementFlags;     // 1字节: WASD 4bit
    public byte ActionFlags;       // 1字节: 攻击/技能/闪避/交互等 8bit
    public byte ItemFlags;         // 1字节: 道具键位1234 4bit
    public byte SystemFlags;       // 1字节: 暂停/地图等 8bit
    public ushort MouseX;          // 2字节: 归一化0~65535
    public ushort MouseY;          // 2字节: 归一化0~65535
    public byte MouseButtons;      // 1字节: 左/右/中键 3bit
}

/// <summary>
/// 输入状态读取（从InputManager采集）
/// </summary>
public struct ReplayInputState
{
    public Vector2 MoveInput;      // -1~1
    public bool AttackPressed;
    public bool SkillPressed;
    public bool DodgePressed;
    public bool InteractPressed;
    public bool Item1Pressed;
    public bool Item2Pressed;
    public bool Item3Pressed;
    public bool Item4Pressed;
    public bool PausePressed;
    public bool MapPressed;
    public Vector2 MousePosition;  // 屏幕像素坐标
    public bool MouseLeftDown;
    public bool MouseRightDown;
    public bool MouseMiddleDown;
}

/// <summary>
/// 录像头部信息
/// </summary>
[Serializable]
public class ReplayHeader
{
    public string Magic;               // "PWREP"
    public int Version;
    public string GameVersion;
    public ulong Seed;
    public string WeaponId;
    public string CharacterId;
    public Difficulty Difficulty;
    public float TotalDuration;        // 秒
    public uint TotalFrames;
    public RunResult Result;
    public int LayerReached;
    public int TotalKills;
    public string RecordDate;          // ISO8601
    public ReplayEventMarker[] EventMarkers;
    public long DataOffset;            // 帧数据在文件中的偏移
    public long DataSize;              // 帧数据大小
    public string Checksum;            // SHA-256
}

/// <summary>
/// 关键事件标记
/// </summary>
[Serializable]
public class ReplayEventMarker
{
    public uint FrameNumber;
    public ReplayEventType Type;
    public string Detail;
}

public enum ReplayEventType
{
    RunStart, FloorStart, FloorEnd, BossStart, BossEnd,
    ItemAcquired, BlessingAcquired, CurseAccepted, TalentSelected,
    Death, RunClear, TimeSkillUse, PerfectParry
}

public enum RunResult { Death, Clear, Abandoned }

public struct ReplaySaveResult
{
    public bool Success;
    public string FilePath;
    public long FileSizeBytes;
    public string Error;
}
```

### 8.3 ReplayPlayer — 回放播放器

```text
/// <summary>
/// 回放播放器 — 读取录像文件并驱动确定性回放
/// </summary>
public class ReplayPlayer
{
    private ReplayHeader _header;
    private ReplayFrame[] _frames;
    private ReplayEventMarker[] _markers;
    private int _currentFrameIndex;
    private ReplayPlaybackState _state;
    private float _playbackSpeed = 1.0f;
    private ReplayCameraMode _cameraMode = ReplayCameraMode.FollowPlayer;
    private HashSet<ReplayLayer> _visibleLayers;
    private bool _isLoaded;

    // ── 加载/卸载 ──────────────────────────────────────

    /// <summary>加载录像文件</summary>
    public async流程 LoadReplay(string filePath, Action<bool> onComplete);

    /// <summary>从内存加载录像</summary>
    public void LoadReplayFromMemory(byte[] data);

    /// <summary>卸载录像</summary>
    public void Unload();

    /// <summary>检查版本兼容性</summary>
    public bool CheckVersionCompatibility(string replayVersion, string currentVersion);

    // ── 播放控制 ───────────────────────────────────────

    /// <summary>播放</summary>
    public void Play();

    /// <summary>暂停</summary>
    public void Pause();

    /// <summary>切换播放/暂停</summary>
    public void TogglePlayPause();

    /// <summary>设置播放速度 (0.25x / 0.5x / 1x / 2x / 4x)</summary>
    public void SetSpeed(float speed);

    /// <summary>快进指定秒数</summary>
    public void FastForward(float seconds);

    /// <summary>快退指定秒数</summary>
    public void Rewind(float seconds);

    /// <summary>跳转到指定帧</summary>
    public void SeekToFrame(uint frameNumber);

    /// <summary>跳转到指定时间点</summary>
    public void SeekToTime(float timeSeconds);

    /// <summary>跳转到上一层</summary>
    public void SeekToFloor(int floorIndex);

    /// <summary>跳转到下一个事件</summary>
    public void SeekToNextEvent();

    /// <summary>跳转到开头</summary>
    public void SeekToStart();

    /// <summary>跳转到结尾</summary>
    public void SeekToEnd();

    // ── 视角控制 ───────────────────────────────────────

    /// <summary>设置摄像机模式</summary>
    public void SetCameraMode(ReplayCameraMode mode);

    /// <summary>自由视角移动</summary>
    public void MoveCamera(Vector2 delta);

    /// <summary>自由视角缩放</summary>
    public void ZoomCamera(float delta);

    // ── 显示图层控制 ───────────────────────────────────

    /// <summary>切换图层可见性</summary>
    public void ToggleLayer(ReplayLayer layer);

    /// <summary>设置图层可见性</summary>
    public void SetLayerVisible(ReplayLayer layer, bool visible);

    // ── 查询 ───────────────────────────────────────────

    /// <summary>获取当前帧号</summary>
    public uint GetCurrentFrame();

    /// <summary>获取当前时间</summary>
    public float GetCurrentTime();

    /// <summary>获取总时长</summary>
    public float GetTotalDuration();

    /// <summary>获取播放进度(0~1)</summary>
    public float GetProgress();

    /// <summary>获取播放状态</summary>
    public ReplayPlaybackState GetState();

    /// <summary>获取事件标记列表</summary>
    public IReadOnlyList<ReplayEventMarker> GetEventMarkers();

    /// <summary>获取录像头部信息</summary>
    public ReplayHeader GetHeader();

    /// <summary>获取当前层信息</summary>
    public int GetCurrentFloor();

    // ── 回放驱动 ───────────────────────────────────────

    /// <summary>每帧更新（由外部Update调用，驱动回放帧推进）</summary>
    public void UpdatePlayback(float deltaTime);

    /// <summary>从当前帧读取输入状态并注入游戏</summary>
    private ReplayInputState ReadCurrentInput();

    /// <summary>根据种子重建地牢（确定性）</summary>
    private async流程 RebuildDungeon(ulong seed);

    /// <summary>跳转时重新模拟到目标帧（确保状态同步）</summary>
    private async流程 ResimulateToFrame(uint targetFrame);

    // ── Workshop上传 ───────────────────────────────────

    /// <summary>上传到Steam Workshop</summary>
    public void UploadToWorkshop(string title, string description, string[] tags,
                                  Action<bool> onComplete);
}

public enum ReplayPlaybackState { Loading, Playing, Paused, Ended, Error }

public enum ReplayCameraMode { FollowPlayer, FreeCamera, Overview }

public enum ReplayLayer { Player, Enemies, Items, Effects, DamageNumbers }
```

### 8.4 ReplayStorageManager

```text
/// <summary>
/// 录像存储管理 — 本地录像文件的增删查+自动清理
/// </summary>
public class ReplayStorageManager
{
    private const int MAX_REPLAYS = 50;
    private const long MAX_STORAGE_MB = 50;
    private readonly string _replayDir;

    public ReplayStorageManager(string replayDir);

    /// <summary>保存录像文件</summary>
    public string SaveReplay(byte[] data, ReplayHeader header);

    /// <summary>加载录像文件</summary>
    public byte[] LoadReplay(string filename);

    /// <summary>删除录像</summary>
    public bool DeleteReplay(string filename);

    /// <summary>获取录像索引列表</summary>
    public IReadOnlyList<ReplayIndexEntry> GetReplayIndex();

    /// <summary>刷新索引（扫描目录）</summary>
    public void RefreshIndex();

    /// <summary>自动清理超限录像（优先删除非通关录像）</summary>
    public void AutoCleanup();

    /// <summary>获取已用存储空间(MB)</summary>
    public float GetUsedStorageMB();

    /// <summary>获取录像数量</summary>
    public int GetReplayCount();

    /// <summary>搜索录像</summary>
    public IReadOnlyList<ReplayIndexEntry> SearchReplays(
        string weaponFilter = null, RunResult? resultFilter = null,
        int? minFloor = null, DateTime? fromDate = null);
}

[Serializable]
public class ReplayIndexEntry
{
    public string Filename;
    public string Date;
    public float DurationSeconds;
    public string Weapon;
    public RunResult Result;
    public int Layer;
    public int Kills;
    public ulong Seed;
    public string GameVersion;
    public long FileSizeKB;
    public bool IsUploaded;
    public string[] Tags;
}
```

---

## 9. 测试计划

### 9.1 单元测试

| 模块 | 测试类 | 核心测试用例 |
|------|--------|-------------|
| HubController | HubControllerTests | 区域检测准确性 / 区域切换事件 / 解锁/锁定状态 / 修复等级映射 |
| NPCController | NPCControllerTests | 好感度增减clamp / 好感度等级阈值 / 赠礼冷却 / Meta解锁检测 / 对话条件检查 |
| DialogueController | DialogueControllerTests | 节点条件满足/不满足 / 选项跳转正确性 / 变量替换 / 效果应用 |
| AffinitySystem | AffinitySystemTests | 好感度边界值(0/100) / 等级判定全覆盖 / 冷却重置 / 赠礼偏好计算 |
| QuestSystem | QuestSystemTests | 任务接受条件 / 进度更新 / 完成判定 / 重复任务 / 事件驱动进度 |
| DeathScreenController | DeathScreenTests | 货币结算计算 / 解锁检测 / 阶段序列完整 |
| GachaSystem | GachaSystemTests | 概率分布统计(10000抽) / 保底触发确定性 / 重复处理 / 碎片兑换 |
| PityTracker | PityTrackerTests | 软保底概率计算 / 硬保底触发 / 大保底逻辑 / 重置 |
| CosmeticManager | CosmeticManagerTests | 添加/移除 / 装备/卸装 / 碎片增减 / 存档序列化 |
| SaveManager | SaveManagerTests | 加密解密往返 / 校验逻辑 / 原子写入 / 损坏恢复 / 备份轮转 |
| SocialManager | SocialManagerTests | 分享码生成解析往返 / 排行榜元数据构建 / Ghost选择概率 |
| ReplayRecorder | ReplayRecorderTests | 帧数据结构正确性 / 事件标记记录 / 压缩解压往返 / 紧急保存 |
| ReplayPlayer | ReplayPlayerTests | 加载/跳转/变速 / 版本兼容检查 / 图层切换 |

### 9.2 集成测试

| 场景 | 测试流程 | 验证点 |
|------|---------|--------|
| 枢纽完整流程 | 进入Hub → 与NPC对话 → 接受任务 → 购买商品 → 出发 | 区域切换正常、NPC交互响应、货币扣除正确、出发准备流程完整 |
| 死亡→结算→枢纽 | 战斗中死亡 → 死亡动画 → Run总结 → 货币结算 → 返回枢纽 | 死亡动画序列、货币结算数值、解锁通知、枢纽状态刷新 |
| 抽卡→装备→外观 | 购买祈愿 → 获得外观 → 装备 → 进入地牢查看 | 抽卡概率正确、重复碎片转化、装备状态持久化、外观渲染正确 |
| 存档完整流程 | 创建存档 → 游玩 → 存档 → 退出 → 重启 → 加载 | 数据完整恢复、加密校验通过、Steam Cloud同步、备份可用 |
| 回放完整流程 | 游玩一局 → 保存录像 → 打开播放器 → 全速播放 → 跳转 → 截图 | 录像帧完整、回放结果一致、跳转后状态同步、速度切换流畅 |
| 排行榜提交 | 通关 → 提交分数 → 查看排行榜 → 查看好友 | 提交成功、排名更新、好友标识正确 |
| 每日挑战 | 进入每日 → 尝试3次 → 最佳成绩提交 → 次日重置 | 尝试次数限制、成绩提交、日重置 |

### 9.3 回归测试（自动化回放）

```
1. 收集10组典型通关录像作为回归基准
2. 每次版本更新后自动回放这10组录像
3. 验证指标：
   - 每帧玩家位置偏差 < 0.1 单位
   - 最终通关状态与基准一致
   - 统计数据（击杀/伤害/道具）一致
4. 偏差超过阈值 → 标记"回放回归Bug"，P1优先级修复
```

### 9.4 性能测试

| 指标 | 目标 | 测试方法 |
|------|------|---------|
| 枢纽场景帧率 | ≥60fps (1920×1080) | 在枢纽自由移动5分钟，记录帧率 |
| 枢纽内存 | ≤300MB | 枢纽场景驻留内存 |
| 存档写入时间 | ≤100ms (全量) | 房间切换时计时 |
| 加密/解密时间 | ≤50ms | AES-256-GCM加密2MB数据 |
| 回放加载时间 | ≤3秒 | 加载30分钟录像 |
| 回放播放帧率 | ≥60fps | 全速回放 |
| 抽卡动画帧率 | ≥60fps | 十连动画 |
| NPC对话响应 | ≤100ms | 从选择到下一节点显示 |

### 9.5 边界与异常测试

| 场景 | 预期行为 |
|------|---------|
| 存档写入时崩溃 | 原子写入保证：临时文件未完成则原文件完好 |
| Steam Cloud冲突 | 弹出选择对话框，保留冲突备份 |
| 加密存档被篡改 | AES-GCM认证失败，标记损坏走恢复流程 |
| 录像文件损坏 | 检测到损坏提示用户，不崩溃 |
| 好感度溢出(>100) | Clamp到100 |
| 保底计数溢出 | 正常触发保底并重置 |
| 排行榜提交时网络断开 | 缓存本地，下次启动重试 |
| 每日挑战跨日切换 | 正在进行的挑战继续，新挑战刷新入口 |
| 全外观已收集后抽卡 | 所有结果为重复→碎片 |
| 回放版本不兼容 | 提示"录像版本不兼容"，不播放 |
