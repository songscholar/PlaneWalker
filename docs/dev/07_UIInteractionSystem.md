# 07 UI与交互系统开发文档

**引擎**: Godot 4.x  
**基准分辨率**: 1920×1080  
**UI系统**: Godot Control节点 + Theme + AnimationPlayer（HUD使用固定锚点Control，菜单使用容器布局）

---

> **Godot迁移约束**：所有UI面板使用 `.tscn` 场景和 Control派生节点；按钮、滑条、列表、Tab等交互使用Godot原生Control节点；输入来自InputMap。

> **视觉约束**：实现必须遵循 Dead Cells 式现代像素风；Control主题使用硬边像素框、低圆角(0~4px)、Nearest过滤、像素字体/位图图标；禁止玻璃拟态、大圆角SaaS卡片、模糊背景、装饰性渐变球、网页落地页式布局。

## 7.1 UI系统架构

### 7.1.1 核心类设计

```text
/// <summary>
/// UI管理器单例，管理所有UI面板的显示/隐藏/层级
/// </summary>
public class UIManager : Node
{
    public static UIManager Instance { get; private set; }
    
    [Header("Canvas References")]
     private Canvas _hudCanvas;          // 始终存在的HUD层
     private Canvas _popupCanvas;        // 弹出选择层
     private Canvas _menuCanvas;         // 全屏菜单层
     private Canvas _overlayCanvas;      // 叠加层(过场/黑屏)
    
    // 面板栈 — 支持返回上一级
    private Stack<UIPanel> _panelStack = new Stack<UIPanel>();
    
    // 面板注册表 — 按类型缓存
    private Dictionary<Type, UIPanel> _panelRegistry = new Dictionary<Type, UIPanel>();
    
    /// <summary>打开面板（压栈）</summary>
    public T OpenPanel<T>() where T : UIPanel;
    
    /// <summary>关闭当前面板（弹栈）</summary>
    public void CloseCurrentPanel();
    
    /// <summary>关闭所有面板</summary>
    public void CloseAll();
    
    /// <summary>获取当前顶部面板</summary>
    public UIPanel CurrentPanel => _panelStack.Count > 0 ? _panelStack.Peek() : null;
    
    /// <summary>暂停规则：有菜单面板打开时暂停游戏</summary>
    public bool IsGamePaused => _panelStack.Any(p => p.PausesGame);
}

/// <summary>
/// UI面板基类，所有面板继承此基类
/// </summary>
public abstract class UIPanel : Node
{
    public abstract string PanelId { get; }
    public virtual bool PausesGame => false;     // 是否暂停游戏
    public virtual bool CacheOnClose => true;    // 关闭时是否缓存(不销毁)
    public virtual int SortOrder => 0;           // 层级排序
    
    protected CanvasLayer/Control _canvasGroup;
    
    public virtual void OnOpen(params object[] args) { Show(); }
    public virtual void OnClose() { Hide(); }
    public virtual void OnBack() { UIManager.Instance.CloseCurrentPanel(); }
    
    protected void Show() { _canvasGroup.alpha = 1; _canvasGroup.blocksRaycasts = true; _canvasGroup.interactable = true; }
    protected void Hide() { _canvasGroup.alpha = 0; _canvasGroup.blocksRaycasts = false; _canvasGroup.interactable = false; }
}
```

### 7.1.2 Canvas层级设计

| Canvas | SortOrder | 用途 | 渲染模式 |
|--------|-----------|------|---------|
| HUD | 10 | 战斗信息常驻显示 | Screen Space - Overlay |
| Popup | 20 | 道具/祝福/天赋选择 | Screen Space - Overlay |
| Menu | 30 | 全屏菜单(设置/暂停/角色选择) | Screen Space - Overlay |
| Overlay | 40 | 转场/黑屏/过场动画 | Screen Space - Overlay |

---

## 7.2 HUD实现

### 7.2.1 HUD控制器

```text
/// <summary>
/// HUD控制器，管理所有战斗界面元素的更新
/// 在战斗场景中始终存在，响应事件总线更新UI
/// </summary>
public class HUDController : Node
{
    [Header("HP")]
     private HPBar _hpBar;           // 左下角HP条
    
    [Header("Energy")]
     private EnergyBar _energyBar;   // HP条上方，时之能量
    
    [Header("Dodge")]
     private DodgeIndicator _dodgeIndicator; // 闪避次数(HP条下方)
    
    [Header("Weapon")]
     private WeaponStatus _weaponStatus; // 右下角武器图标+状态
    
    [Header("Items")]
     private ActiveItemSlot[] _activeItemSlots; // 2个主动道具槽
     private PassiveItemGrid _passiveGrid;       // 按住展开
    
    [Header("Buffs")]
     private BuffIconBar _blessingBar;  // 左下祝福图标
     private BuffIconBar _curseBar;     // 左下诅咒图标
    
    [Header("Map")]
     private MiniMap _miniMap;       // 右上角小地图120×120
    
    [Header("Combat Info")]
     private ComboCounter _comboCounter; // 连击计数
     private DamageNumberPool _damageNumbers; // 伤害数字池
     private DirectionIndicator _hitIndicator; // 受击方向
    
    void OnEnable()
    {
        EventBus.Subscribe<DamageReceivedEvent>(OnDamageReceived);
        EventBus.Subscribe<TimeEnergyChangedEvent>(OnEnergyChanged);
        EventBus.Subscribe<ComboHitEvent>(OnComboHit);
        EventBus.Subscribe<CurrencyChangedEvent>(OnCurrencyChanged);
        // ...
    }
    
    void OnDamageReceived(DamageReceivedEvent evt) { _hpBar.SetValues(evt...); _hitIndicator.Show(evt...); }
    void OnEnergyChanged(TimeEnergyChangedEvent evt) { _energyBar.SetValue(evt.Current / evt.Max); }
    void OnComboHit(ComboHitEvent evt) { _comboCounter.Show(evt.ComboCount); }
}
```

### 7.2.2 HP条实现

```text
/// <summary>
/// HP条：延迟伤害条 + 即时伤害条 + 低血量预警
/// 位置：屏幕底部居中偏左
/// 尺寸：300×20px
/// </summary>
public class HPBar : Node
{
     private Image _delayBar;   // 延迟条(红色，受伤后缓慢收缩)
     private Image _hpBar;      // 即时条(绿色→黄色→红色渐变)
     private Image _border;     // 边框
     private Text _hpText;      // "45/100" 文字
    
    private float _displayHP;
    private float _delayHP;
    private float _maxHP;
    private const float DELAY_SPEED = 0.3f; // 延迟条收缩速度(每秒30%)
    
    public void Initialize(float maxHP)
    {
        _maxHP = maxHP;
        _displayHP = maxHP;
        _delayHP = maxHP;
        UpdateVisual();
    }
    
    public void SetValues(float currentHP, float maxHP, float damage = 0)
    {
        _maxHP = maxHP;
        _displayHP = currentHP;
        _delayHP = currentHP + damage; // 延迟条先保持高值，慢慢收缩
        UpdateVisual();
    }
    
    void Update()
    {
        // 延迟条缓慢收缩到当前HP
        if (_delayHP > _displayHP)
        {
            _delayHP = math.MoveTowards(_delayHP, _displayHP, _maxHP * DELAY_SPEED * delta);
            UpdateVisual();
        }
    }
    
    void UpdateVisual()
    {
        float ratio = _displayHP / _maxHP;
        _hpBar.fillAmount = ratio;
        _delayBar.fillAmount = _delayHP / _maxHP;
        
        // 颜色渐变：>60%绿, 30-60%黄, <30%红
        _hpBar.color = ratio > 0.6f ? Color.green : ratio > 0.3f ? Color.yellow : Color.red;
        _hpText.text = $"{math.CeilToInt(_displayHP)}/{math.CeilToInt(_maxHP)}";
    }
}
```

### 7.2.3 能量条 / 闪避指示 / 小地图

```text
/// <summary>时之能量条 — HP条正上方，200×10px，紫色渐变</summary>
public class EnergyBar : Node
{
     private Image _bar;
     private Image _warningOverlay; // <20%时闪烁
    public void SetValue(float ratio) { _bar.fillAmount = ratio; _warningOverlay.enabled = ratio < 0.2f; }
}

/// <summary>闪避次数指示 — HP条下方，2个圆形图标</summary>
public class DodgeIndicator : Node
{
     private Image[] _dodgeIcons; // 2个
    public void SetCharges(int current, int max)
    {
        for (int i = 0; i < _dodgeIcons.Length; i++)
            _dodgeIcons[i].color = i < current ? Color.white : new Color(1,1,1,0.2f);
    }
}

/// <summary>小地图 — 右上角120×120px</summary>
public class MiniMap : Node
{
     private Image _mapImage;
     private Control _playerDot;
     private Dictionary<string, RoomIcon> _roomIcons;
    
    public void AddRoom(string roomId, Vector2 position, RoomType type, bool explored);
    public void SetCurrentRoom(string roomId);
    public void ClearMap();
}
```

---

## 7.3 统一选择界面

### 7.3.1 泛型选择面板基类

```text
/// <summary>
/// 通用选择面板 — 支持N选1
/// 所有"选择"类UI（道具/祝福/诅咒/天赋/事件）的基类
/// </summary>
public class SelectionPanel<TOption> : UIPanel where TOption : class
{
    [Header("Layout")]
     protected Node2D _cardContainer;  // 卡片容器
     protected SelectionCard _card_scene; // 卡片PackedScene
     protected Text _titleText;           // 标题
     protected Button _skipButton;        // 跳过按钮(如可跳过)
    
    protected List<SelectionCard> _cards = new List<SelectionCard>();
    protected Action<TOption> _onSelected;
    protected Action _onSkipped;
    
    public override void OnOpen(params object[] args)
    {
        // args[0] = List<TOption>, args[1] = onSelected, args[2] = onSkipped(可选)
        var options = args[0] as List<TOption>;
        _onSelected = args[1] as Action<TOption>;
        _onSkipped = args.Length > 2 ? args[2] as Action : null;
        
        PopulateCards(options);
        Show();
    }
    
    protected virtual void PopulateCards(List<TOption> options)
    {
        ClearCards();
        for (int i = 0; i < options.Count; i++)
        {
            var card = Instantiate(_card_scene, _cardContainer);
            card.Setup(i, GetCardData(options[i]));
            card.OnSelected += () => OnCardSelected(options[i]);
            _cards.Add(card);
        }
    }
    
    protected abstract CardDisplayData GetCardData(TOption option);
    
    protected virtual void OnCardSelected(TOption option)
    {
        _onSelected?.Invoke(option);
        Close();
    }
    
    protected void ClearCards()
    {
        foreach (var card in _cards) card.gameObject.queue_free();
        _cards.Clear();
    }
    
    void Close()
    {
        _onSelected = null;
        _onSkipped = null;
        OnClose();
    }
}

/// <summary>卡片显示数据</summary>
public struct CardDisplayData
{
    public string Name;
    public string Description;
    public string FlavorText;
    public Sprite Icon;
    public Rarity Rarity;          // 普通/稀有/传说/神话
    public List<string> Tags;      // 联动提示标签
    public string CompareHint;     // 对比提示(如"替换: 敏捷之靴")
}
```

### 7.3.2 六种特化选择面板

```text
/// <summary>道具选择 — 精英房3选1, 宝藏房2选1</summary>
public class ItemSelectionPanel : SelectionPanel<ItemInstance>
{
    protected override CardDisplayData GetCardData(ItemInstance item)
    {
        return new CardDisplayData
        {
            Name = item.Data.DisplayName,
            Description = item.Data.MechanicText,
            FlavorText = item.Data.FlavorText,
            Icon = item.Data.Icon,
            Rarity = item.Data.Rarity,
            Tags = item.Data.SynergyHints,
            CompareHint = GetCompareHint(item)  // 与当前装备对比
        };
    }
    
    private string GetCompareHint(ItemInstance newItem)
    {
        // 如果槽位已满，显示将被替换的道具
        var inventory = ServiceRegistry.Get<IInventoryManager>();
        if (inventory.IsFull && newItem.Data.Slot >= 0)
        {
            var existing = inventory.GetSlot(newItem.Data.Slot);
            return existing != null ? $"替换: {existing.Data.DisplayName}" : null;
        }
        return null;
    }
}

/// <summary>祝福选择 — 每层结束3选1</summary>
public class BlessingSelectionPanel : SelectionPanel<BlessingData> { ... }

/// <summary>诅咒接受 — 风险提示双栏展示</summary>
public class CurseAcceptPanel : SelectionPanel<CurseData>
{
    protected override CardDisplayData GetCardData(CurseData curse)
    {
        // 特殊：诅咒卡片分为增益(绿)和负面(红)两栏
        return new CardDisplayData
        {
            Name = curse.DisplayName,
            Description = $"<color=green>+{curse.BonusText}</color>\n<color=red>-{curse.PenaltyText}</color>",
            // ...
        };
    }
}

/// <summary>天赋选择 — 显示天赋路线可视化</summary>
public class TalentSelectionPanel : SelectionPanel<TalentNode> { ... }

/// <summary>事件选择 — 对话式/卡片式</summary>
public class EventChoicePanel : SelectionPanel<EventOption> { ... }

/// <summary>商店购买 — 展示4个商品+购买/出售/重roll</summary>
public class ShopPanel : UIPanel
{
     private ShopItemCard[] _itemCards;    // 4个商品卡片
     private Button _rerollButton;         // 重roll
     private Text _goldText;               // 当前金币
     private Button _sellModeButton;       // 出售模式切换
    
    private int _rerollCount;
    
    public void SetupShop(List<ItemInstance> items, int rerollCount);
    public void OnBuyItem(int slotIndex);
    public void OnReroll(); // 消耗: 50 × (已重roll次数 + 1) 金币
    public void OnSellMode();
}
```

---

## 7.4 菜单系统

```text
/// <summary>主菜单</summary>
public class MainMenuPanel : UIPanel
{
     private Button _startButton;
     private Button _continueButton; // 有存档时可用
     private Button _settingsButton;
     private Button _quitButton;
    
    void Start()
    {
        _continueButton.interactable = SaveManager.HasAnySave();
        _startButton.onClick.AddListener(OnNewGame);
        _continueButton.onClick.AddListener(OnContinue);
        _settingsButton.onClick.AddListener(() => UIManager.Instance.OpenPanel<SettingsPanel>());
        _quitButton.onClick.AddListener(() => Application.Quit());
    }
    
    void OnNewGame() => SceneLoader.LoadScene("Hub");
    void OnContinue() => SaveManager.LoadLatest();
}

/// <summary>角色选择面板</summary>
public class CharacterSelectPanel : UIPanel
{
     private CharacterCard[] _characterCards; // 5个角色
     private CharacterPreview _preview;       // 3D预览
     private Button _confirmButton;
    
    public void OnCharacterSelected(string characterId);
    public void OnWeaponSelected(string weaponId);
    public void OnDifficultySelected(Difficulty difficulty);
    public void OnConfirm() => EventBus.Publish(new RunStartEvent { CharacterId = ..., WeaponId = ..., Difficulty = ... });
}

/// <summary>设置面板</summary>
public class SettingsPanel : UIPanel
{
    // 视频: 分辨率/全屏/帧率/特效质量
    // 音频: BGM音量/SFX音量/Voice音量
    // 操控: 键位自定义入口/手柄振动开关
    // 可访问性: 色盲模式/字体大小/UI缩放/屏幕震动
    // 语言: 语言选择
}
```

---

## 7.5 InputManager

```text
/// <summary>
/// 输入管理器 — 封装Godot InputMap
/// 支持键鼠+手柄双输入、运行时键位自定义
/// </summary>
public class InputManager : Node, IInputManager
{
    // 新InputMap
    private GameInput _gameInput; // InputMap封装脚本
    
    // 当前输入设备
    public InputDeviceType CurrentDevice { get; private set; } = InputDeviceType.KeyboardMouse;
    
    // 便捷属性 — 各系统直接读取
    public Vector2 MoveInput => _gameInput.Gameplay.Move.ReadValue<Vector2>();
    public bool AttackPressed => _gameInput.Gameplay.Attack.WasPressedThisFrame();
    public bool AttackHeld => _gameInput.Gameplay.Attack.IsPressed();
    public bool SpecialPressed => _gameInput.Gameplay.Special.WasPressedThisFrame();
    public bool DodgePressed => _gameInput.Gameplay.Dodge.WasPressedThisFrame();
    public bool ParryPressed => _gameInput.Gameplay.Parry.WasPressedThisFrame();
    public bool TimeSkillPressed => _gameInput.Gameplay.TimeSkill.WasPressedThisFrame();
    public bool InteractPressed => _gameInput.Gameplay.Interact.WasPressedThisFrame();
    public bool ItemSlot1Pressed => _gameInput.Gameplay.ItemSlot1.WasPressedThisFrame();
    public bool ItemSlot2Pressed => _gameInput.Gameplay.ItemSlot2.WasPressedThisFrame();
    public bool PausePressed => _gameInput.Gameplay.Pause.WasPressedThisFrame();
    
    // 键位自定义
    private KeyBindingManager _keyBindingManager;
    
    void Awake()
    {
        _gameInput = new GameInput();
        _keyBindingManager = new KeyBindingManager(_gameInput);
        
        // 检测设备切换
        InputSystem.onActionChange += OnActionChange;
    }
    
    void OnActionChange(object obj, InputActionChange change)
    {
        if (change == InputActionChange.ActionPerformed)
        {
            var device = (obj as InputAction)?.lastControl?.device;
            CurrentDevice = device is Gamepad ? InputDeviceType.Gamepad : InputDeviceType.KeyboardMouse;
            EventBus.Publish(new InputDeviceChangedEvent { Device = CurrentDevice });
        }
    }
    
    void OnEnable() => _gameInput.Enable();
    void OnDisable() => _gameInput.Disable();
}

public enum InputDeviceType { KeyboardMouse, Gamepad }
```

### 7.5.1 键位自定义

```text
/// <summary>
/// 键位自定义管理器
/// 5套预设(3只读默认+2自定义)，保存到本地JSON
/// </summary>
public class KeyBindingManager
{
    private GameInput _gameInput;
    private BindingPreset[] _presets = new BindingPreset[5];
    private int _activePresetIndex = 0;
    
    // 预设名称: "默认", "左手版", "手柄A", "自定义1", "自定义2"
    
    public void LoadPresets();            // 从JSON加载
    public void SavePresets();            // 保存到JSON
    public void ApplyPreset(int index);   // 应用预设
    public void RebindAction(string actionId, int bindingIndex, InputActionRebindingExtensions.RebindingOperation rebindingOp);
    public bool HasConflict(string actionId, KeyCombo newBinding, out string conflictAction);
    public void ResetPreset(int index);   // 重置为默认
}

[Serializable]
public class BindingPreset
{
    public string Name;
    public bool ReadOnly;
    public Dictionary<string, string> ActionBindings; // actionId → bindingPath
}
```

---

## 7.6 TutorialManager

```text
/// <summary>
/// 新手教学管理器
/// 10个教学点，首次触发时显示，可跳过
/// </summary>
public class TutorialManager : Node
{
     private TutorialTipUI _tipUI; // 非阻塞提示UI
    
    // 教学点完成状态 — 保存到PersistentData
    private HashSet<TutorialPoint> _completedPoints = new HashSet<TutorialPoint>();
    
    // 教学配置
    private static readonly TutorialConfig[] TUTORIALS = new[]
    {
        new TutorialConfig(TutorialPoint.Move, "移动", "使用 WASD 移动角色", "尝试移动到标记点"),
        new TutorialConfig(TutorialPoint.Dodge, "闪避", "按空格键闪避", "闪避3次完成教学"),
        new TutorialConfig(TutorialPoint.Attack, "攻击", "鼠标左键攻击", "击杀1个敌人"),
        new TutorialConfig(TutorialPoint.Special, "特殊技能", "鼠标右键使用特殊技能", "使用1次特殊技能"),
        new TutorialConfig(TutorialPoint.TimeStop, "时间停止", "按Q键发动时间停止", "在时间停止中击杀1个敌人"),
        new TutorialConfig(TutorialPoint.TimeRewind, "时间回溯", "按住Q键回溯时间", "使用1次时间回溯"),
        new TutorialConfig(TutorialPoint.ItemPickup, "拾取道具", "按E键拾取道具", "拾取1个道具"),
        new TutorialConfig(TutorialPoint.RoomClear, "房间奖励", "清关后选择奖励", "完成1次3选1选择"),
        new TutorialConfig(TutorialPoint.MiniMap, "小地图", "右上角小地图显示位置", "查看小地图1次"),
        new TutorialConfig(TutorialPoint.Boss, "Boss战", "Boss门前做好准备", "无操作要求"),
    };
    
    /// <summary>触发教学 — 各系统在适当时机调用</summary>
    public void TriggerTutorial(TutorialPoint point)
    {
        if (_completedPoints.Contains(point)) return;
        if (IsVeteranPlayer()) return; // 老玩家跳过
        
        var config = TUTORIALS[(int)point];
        _tipUI.Show(config.Title, config.Description, config.PracticeGoal);
    }
    
    /// <summary>完成教学 — 玩家完成练习后调用</summary>
    public void CompleteTutorial(TutorialPoint point)
    {
        _completedPoints.Add(point);
        _tipUI.Hide();
        SaveTutorialProgress();
    }
    
    /// <summary>检测老玩家（有存档且通关过1层以上）</summary>
    private bool IsVeteranPlayer()
    {
        var data = ServiceRegistry.Get<IGameManager>().State.Persistent;
        return data != null && data.UnlockedCharacters.Count > 1; // 解锁了第二个角色说明玩过
    }
    
    /// <summary>重置所有教学 — 设置选项</summary>
    public void ResetAllTutorials()
    {
        _completedPoints.Clear();
        SaveTutorialProgress();
    }
}

public enum TutorialPoint { Move, Dodge, Attack, Special, TimeStop, TimeRewind, ItemPickup, RoomClear, MiniMap, Boss }

public struct TutorialConfig
{
    public TutorialPoint Point;
    public string Title;
    public string Description;
    public string PracticeGoal;
}
```

---

## 7.7 新手保护系统

```text
/// <summary>
/// 新手保护 — 前3局提供逐步减弱的保护
/// 保护强度: 局1(强) → 局2(中) → 局3(弱) → 局4(无)
/// </summary>
public class BeginnerProtection
{
    private int _totalRuns; // 累计局数(跨存档)
    
    public BeginnerProtection(int totalRuns) { _totalRuns = totalRuns; }
    
    // 各项保护的倍率/加成
    public float EnemyATKMultiplier => _totalRuns switch
    {
        0 => 0.75f,   // 第1局敌人攻击-25%
        1 => 0.85f,   // 第2局-15%
        2 => 0.95f,   // 第3局-5%
        _ => 1.0f     // 第4局起无保护
    };
    
    public float EnemyHPMultiplier => _totalRuns switch
    {
        0 => 0.80f,   // 第1局敌人HP-20%
        1 => 0.90f,
        2 => 0.95f,
        _ => 1.0f
    };
    
    public float BossHPMultiplier => _totalRuns switch
    {
        0 => 0.85f,   // 第1局Boss HP-15%
        1 => 0.92f,
        2 => 0.97f,
        _ => 1.0f
    };
    
    public float GoldMultiplier => _totalRuns switch
    {
        0 => 1.3f,    // 第1局金币+30%
        1 => 1.15f,
        2 => 1.05f,
        _ => 1.0f
    };
    
    public float DropRateBonus => _totalRuns switch
    {
        0 => 0.1f,    // 第1局掉率+10%
        1 => 0.05f,
        2 => 0.02f,
        _ => 0f
    };
    
    public bool ShowAttackWarnings => _totalRuns < 3; // 前3局显示攻击预警线
    public bool ShowDodgeHints => _totalRuns < 2;     // 前2局闪避时机提示
    public bool FirstBossHPReduce => _totalRuns == 0;  // 首次Boss战额外-15%
    
    /// <summary>应用保护到难度缩放</summary>
    public DifficultyScaling ApplyProtection(DifficultyScaling baseScaling)
    {
        return new DifficultyScaling
        {
            HPMultiplier = baseScaling.HPMultiplier * EnemyHPMultiplier,
            ATKMultiplier = baseScaling.ATKMultiplier * EnemyATKMultiplier,
            BossHPMultiplier = baseScaling.BossHPMultiplier * BossHPMultiplier,
            GoldMultiplier = baseScaling.GoldMultiplier * GoldMultiplier,
            DropRateBonus = baseScaling.DropRateBonus + DropRateBonus,
        };
    }
}
```

---

## 7.8 UI性能优化

### 7.8.1 Canvas拆分策略

| Canvas | 拆分理由 | 重建频率 |
|--------|---------|---------|
| HUD_Static | HP条边框/武器图标/小地图背景 | 仅初始化时 |
| HUD_Dynamic | HP条填充/能量条/连击数/伤害数字 | 每帧或高频更新 |
| Selection_Cards | 选择卡片 | 仅打开/选择时 |
| Menu | 全屏菜单 | 仅打开时 |

**关键规则**：
- 静态文本和动态数值分到不同Canvas，避免整个Canvas重建
- HP条等高频更新使用 `Image.fillAmount` 而非修改Control
- 伤害数字使用独立Canvas + 对象池

### 7.8.2 对象池复用

```text
/// <summary>伤害数字对象池</summary>
public class DamageNumberPool : Node
{
     private DamageNumber _scene;
     private int _poolSize = 20;
    private Queue<DamageNumber> _pool = new Queue<DamageNumber>();
    
    public DamageNumber Get()
    {
        if (_pool.Count == 0) return Instantiate(_scene, transform);
        var num = _pool.Dequeue();
        num.gameObject.SetActive(true);
        return num;
    }
    
    public void Return(DamageNumber num)
    {
        num.gameObject.SetActive(false);
        _pool.Enqueue(num);
    }
}
```

### 7.8.3 DrawCall优化

- 图集策略：HUD元素合入1张2048×2048图集，选择界面用单独图集
- 避免UI元素Z轴偏移（导致打断合批）
- 文字组件使用 `Label`，统一材质
- 同一Canvas内减少材质种类

---

## 7.9 测试计划

### 单元测试 (25项)

| 测试项 | 验证内容 |
|--------|---------|
| UIManager_OpenClose | 面板打开/关闭/栈管理正确 |
| UIManager_Back | 返回上一级面板正确 |
| UIManager_PauseRule | 有PausesGame面板时游戏暂停 |
| HPBar_Update | HP值变化时条形正确更新 |
| HPBar_ColorGradient | 不同HP比例颜色正确 |
| HPBar_DelayBar | 延迟条收缩速度正确 |
| EnergyBar_Warning | 能量<20%预警闪烁 |
| DodgeIndicator_Charges | 闪避次数显示正确 |
| SelectionPanel_CardCount | 卡片数量与选项数一致 |
| SelectionPanel_Select | 选择后回调正确触发 |
| SelectionPanel_Skip | 跳过后回调正确触发 |
| ItemSelection_Compare | 替换提示正确显示 |
| CurseAccept_RiskDisplay | 增益/负面分色显示 |
| ShopPanel_RerollCost | 重roll消耗公式正确 |
| KeyBinding_Rebind | 键位重绑定生效 |
| KeyBinding_Conflict | 冲突检测正确 |
| KeyBinding_PresetSwitch | 预设切换生效 |
| TutorialManager_Trigger | 教学触发条件正确 |
| TutorialManager_Skip | 已完成教学不重复触发 |
| TutorialManager_Veteran | 老玩家跳过教学 |
| BeginnerProtection_Multiplier | 各保护倍率正确 |
| BeginnerProtection_RunBased | 保护随局数逐步撤出 |
| InputManager_DeviceSwitch | 键鼠/手柄切换检测 |
| MiniMap_RoomAdd | 房间添加到地图正确 |
| DamageNumber_Pool | 对象池分配/回收正确 |

### 集成测试 (8项)

| 测试场景 | 验证内容 |
|---------|---------|
| 完整HUD更新流程 | 受伤→HP条变化→能量变化→连击显示 |
| 道具选择完整流程 | 清关→弹出3选1→选择→道具生效→HUD更新 |
| 祝福选择完整流程 | 层结束→弹出选择→选择→祝福生效 |
| 商店购买流程 | 进入商店→浏览→购买/出售→金币变化 |
| 教学到实战 | 第1层逐房间触发教学→完成→不再触发 |
| 新手保护验证 | 第1局保护生效→第4局保护消失 |
| 键位自定义流程 | 打开设置→改键→保存→游戏中生效 |
| 手柄全流程 | 手柄完成：进入游戏→选角色→战斗→选道具→暂停→退出 |

### 性能测试

| 指标 | 目标 | 测试方法 |
|------|------|---------|
| HUD更新CPU | <0.5ms/帧 | Profiler |
| 选择界面打开 | <100ms | 计时 |
| Canvas重建频率 | HUD_Dynamic: 每帧, 其他: 按需 | Frame Debugger |
| DrawCall (HUD) | <15 | Frame Debugger |
| 伤害数字池 | 20个同时显示无卡顿 | 实测 |
