# 09 — 基础设施开发文档

**版本**: 1.0  
**日期**: 2026-04-22  
**引擎**: Godot 4.x  
**语言**: GDScript 2.0（性能瓶颈可用GDExtension/C++）  
**关联文档**: [00_Architecture](00_Architecture.md) / [8.5 系统功能与运营规划](../8.5_系统功能与运营规划设计.md)

---

## 1. 项目初始化 — Godot配置 + 像素导入预设 + Git + .gitignore

### 1.1 Godot项目配置

```
Godot版本: 4.x稳定版
渲染: Forward+ 或 Compatibility（按目标显卡实测选择）
设计分辨率: 1920x1080
像素基准: 320x180 / 480x270 逻辑画布，整数缩放到目标分辨率
纹理过滤: Nearest
纹理重复: Disabled
帧率目标: 60fps
物理帧率: 60Hz
VSync: 关闭（由游戏内设置控制）
目标平台: Windows 64-bit
输入: InputMap + 手柄自动识别
音频: AudioServer + AudioBus
后处理: Viewport/CanvasItem Shader
资源加载: ResourceLoader.load_threaded_request
```

### 1.2 项目设置清单

```
Project Settings:
├── Application
│   ├── Config/Name: Plane Walker: Chronicles of Collapse
│   ├── Config/Version: 0.1.0
│   └── Run/Main Scene: res://scenes/boot/boot.tscn
├── Display/Window
│   ├── Size/Viewport Width: 1920
│   ├── Size/Viewport Height: 1080
│   ├── Size/Mode: Windowed 或 Fullscreen（设置项控制）
│   ├── Stretch/Mode: canvas_items
│   ├── Stretch/Aspect: keep
│   └── VSync/VSync Mode: Disabled
├── Rendering/Textures
│   ├── Canvas Textures/Default Texture Filter: Nearest
│   └── Canvas Textures/Default Texture Repeat: Disabled
├── Physics/Common
│   ├── Physics Ticks Per Second: 60
│   └── Max Physics Steps Per Frame: 8
├── Input Map
│   ├── move_up/down/left/right
│   ├── attack/heavy_attack/special/dodge/interact
│   ├── time_stop/time_rewind/time_accelerate/time_rift
│   └── ui_accept/ui_cancel/ui_focus_next/ui_focus_prev
├── Audio
│   ├── Buses: Master / BGM / SFX / Voice / Ambient / UI
│   └── 默认使用流式BGM与短音效池
└── Autoload
    ├── EventBus
    ├── GameState
    ├── ServiceRegistry
    ├── SceneLoader
    ├── SaveManager
    ├── AudioManager
    ├── InputManager
    └── PoolManager
```

### 1.3 .gitignore

```gitignore
# Godot
.godot/
.import/
export.cfg
export_presets.cfg
*.translation

# Godot .NET disabled by default; do not add gameplay .cs files unless explicitly approved
.mono/
*.csproj
*.sln

# IDE
.vs/
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Build outputs
/builds/
/exports/
/.steam/
/*.exe
/*.app

# Secrets (密钥文件不入库)
*.key
*.pem
*.keystore
Secrets/

# Generated docs
/docs/api/
```

### 1.4 Git分支与提交规范

```
分支策略:
main           ← 稳定发布分支，仅合并PR
  └── dev      ← 开发主分支，每日集成
       ├── feature/combat-sword          ← 功能分支
       ├── feature/hub-controller
       ├── feature/save-system
       ├── fix/death-screen-anim-bug     ← 修复分支
       └── refactor/eventbus-optimize    ← 重构分支

提交格式: [模块] 描述
示例:
  [Combat] 实现剑武器4段连击
  [Hub] 完成NPC对话引擎条件检测
  [Save] 修复AES-GCM加密往返测试
  [Audio] 实现Godot AudioBus动态音乐系统

PR规范:
  - 必须通过CI检查（编译+单元测试+代码规范）
  - 至少1人Review
  - 描述包含：改了什么/为什么改/如何测试
```

---

## 2. SceneLoader — 异步加载 + 转场

### 2.1 概述

场景加载器负责游戏场景间的异步切换（Boot→Hub→Dungeon→BossArena→Hub），支持进度条、转场动画、加载期间资源预加载。使用 `ResourceLoader.load_threaded_request()` 与 `PackedScene.instantiate()` 实现场景资源按需加载。

### 2.2 SceneLoader

```gdscript
# autoload/scene_loader.gd
extends Node

signal scene_load_started(from_scene: StringName, to_scene: StringName)
signal load_progress_changed(progress: float)
signal scene_load_completed(scene_name: StringName)

const SCENE_BOOT := &"boot"
const SCENE_HUB := &"hub"
const SCENE_DUNGEON := &"dungeon"
const SCENE_BOSS_ARENA := &"boss_arena"

var current_scene: StringName = SCENE_BOOT
var _loading_scene: StringName
var _is_loading := false
var _target_scene_path := ""

func _ready() -> void:
    ServiceRegistry.register(&"scene_loader", self)

func load_scene(scene_name: StringName, scene_path: String, preload_tasks: Array[Callable] = []) -> void:
    if _is_loading:
        return
    _is_loading = true
    _loading_scene = scene_name
    _target_scene_path = scene_path
    scene_load_started.emit(current_scene, scene_name)
    ResourceLoader.load_threaded_request(scene_path)
    await _wait_for_scene_load(preload_tasks)

func reload_current_scene(scene_path: String) -> void:
    load_scene(current_scene, scene_path)

func _wait_for_scene_load(preload_tasks: Array[Callable]) -> void:
    var progress := [0.0]
    while true:
        var status := ResourceLoader.load_threaded_get_status(_target_scene_path, progress)
        load_progress_changed.emit(progress[0])
        if status == ResourceLoader.THREAD_LOAD_LOADED:
            break
        await get_tree().process_frame

    for task in preload_tasks:
        await task.call()

    var packed := ResourceLoader.load_threaded_get(_target_scene_path) as PackedScene
    get_tree().change_scene_to_packed(packed)
    current_scene = _loading_scene
    _is_loading = false
    scene_load_completed.emit(current_scene)
```

---

## 3. AudioManager — Godot AudioBus集成 + 动态音乐 + 音效池

### 3.1 概述

音频系统基于Godot AudioServer，支持动态音乐（战斗强度→音乐层切换）、BGM交叉淡入淡出、3D空间音效、音效池（避免同时播放过多音效）、音频总线控制（Master/BGM/SFX/Voice/Ambient）。

### 3.2 AudioManager

```gdscript
# autoload/audio_manager.gd
extends Node

signal bgm_started(bgm_id: StringName)
signal bgm_stopped(bgm_id: StringName)
signal sfx_played(sfx_id: StringName)

const BUS_MASTER := &"Master"
const BUS_BGM := &"BGM"
const BUS_SFX := &"SFX"
const BUS_VOICE := &"Voice"
const BUS_AMBIENT := &"Ambient"

var current_bgm_id: StringName
var _current_bgm: AudioStreamPlayer
var _sfx_pool: Dictionary[StringName, Array] = {}

func _ready() -> void:
    ServiceRegistry.register(&"audio_manager", self)
    _current_bgm = AudioStreamPlayer.new()
    _current_bgm.bus = String(BUS_BGM)
    add_child(_current_bgm)

func play_bgm(bgm_id: StringName, stream: AudioStream, fade_time: float = 0.5) -> void:
    current_bgm_id = bgm_id
    _current_bgm.stream = stream
    _current_bgm.play()
    bgm_started.emit(bgm_id)

func stop_bgm(fade_time: float = 0.5) -> void:
    var old_id := current_bgm_id
    _current_bgm.stop()
    bgm_stopped.emit(old_id)

func play_sfx(sfx_id: StringName, stream: AudioStream, position: Vector2 = Vector2.INF) -> AudioStreamPlayer:
    var player := _get_sfx_player(sfx_id)
    player.stream = stream
    player.bus = String(BUS_SFX)
    player.play()
    sfx_played.emit(sfx_id)
    return player

func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
    var bus_index := AudioServer.get_bus_index(String(bus_name))
    AudioServer.set_bus_volume_db(bus_index, linear_to_db(clamp(linear_volume, 0.0, 1.0)))

func set_music_intensity(intensity: float) -> void:
    # 动态音乐分层由BGMController根据强度控制多个AudioStreamPlayer音量。
    EventBus.publish(&"music_intensity_changed", {"intensity": intensity})

func _get_sfx_player(sfx_id: StringName) -> AudioStreamPlayer:
    var pool := _sfx_pool.get_or_add(sfx_id, [])
    for player in pool:
        if not player.playing:
            return player
    var player := AudioStreamPlayer.new()
    add_child(player)
    pool.append(player)
    return player
```

---

## 4. PoolManager — 通用对象池

### 4.1 概述

通用对象池系统，支持Node/PackedScene池化和RefCounted对象池化（如DamageInfo、Event payload等）。自动扩容/缩容，支持预热（Prewarm），池化对象生命周期管理。

### 4.2 PoolManager

```gdscript
# autoload/pool_manager.gd
extends Node

var _scene_pools: Dictionary[StringName, Array] = {}
var _scene_paths: Dictionary[StringName, String] = {}

func _ready() -> void:
    ServiceRegistry.register(&"pool_manager", self)

func register_scene_pool(pool_id: StringName, scene_path: String, initial_size: int = 0) -> void:
    _scene_paths[pool_id] = scene_path
    _scene_pools[pool_id] = []
    for i in initial_size:
        var node := _create_node(pool_id)
        node.visible = false
        _scene_pools[pool_id].append(node)

func spawn(pool_id: StringName, parent: Node, position: Vector2 = Vector2.ZERO) -> Node:
    var pool := _scene_pools.get_or_add(pool_id, [])
    var node: Node = pool.pop_back() if not pool.is_empty() else _create_node(pool_id)
    parent.add_child(node)
    if node is Node2D:
        node.global_position = position
    node.visible = true
    if node.has_method("on_spawned"):
        node.on_spawned()
    return node

func despawn(pool_id: StringName, node: Node) -> void:
    if node.has_method("on_despawned"):
        node.on_despawned()
    node.visible = false
    if node.get_parent():
        node.get_parent().remove_child(node)
    _scene_pools.get_or_add(pool_id, []).append(node)

func clear_pool(pool_id: StringName) -> void:
    for node in _scene_pools.get(pool_id, []):
        node.queue_free()
    _scene_pools[pool_id] = []

func _create_node(pool_id: StringName) -> Node:
    var scene := load(_scene_paths[pool_id]) as PackedScene
    return scene.instantiate()
```

---

## 5. 构建管线 — Godot Export + ResourceLoader策略

### 5.1 构建管线概述

```
构建策略:
├── 开发构建:  Development Build + Script Debugging
├── 测试构建:  Development Build (无Debugging)
├── Beta构建:  Release Build + Steam Beta分支
└── 正式构建:  Release Build + Steam正式分支

自动化:
├── CI: GitHub Actions → Godot headless export → 自动构建+测试
├── 版本号: Major.Minor.Patch.Build (如 1.2.3.456)
├── 构建号: Git commit count
└── Changelog: 自动从Git log生成
```

### 5.2 资源分组与预加载策略

```
资源分组策略:
├── Group: Core (始终加载)
│   ├── UIPackedScene、核心Shader、基础材质
│   └── 打包方式: 打入首包
├── Group: Hub (枢纽场景)
│   ├── Hub场景、NPCPackedScene、枢纽专属美术
│   └── 打包方式: Local Bundle (首包包含)
├── Group: Dungeon (地牢场景)
│   ├── 地牢场景、房间模板、Tilemap
│   └── 打包方式: Local Bundle (首包包含)
├── Group: Characters (角色)
│   ├── 5个角色PackedScene + 共享动画
│   └── 打包方式: Local Bundle
├── Group: Enemies (敌人)
│   ├── 基础敌人PackedScene (Layer 1-3)
│   └── 打包方式: Local Bundle
├── Group: Enemies_Deep (深层敌人)
│   ├── Layer 4-5敌人 + BossPackedScene
│   └── 打包方式: Local Bundle
├── Group: Items (道具图标+效果)
│   ├── 道具图标Sprite、特效PackedScene
│   └── 打包方式: Local Bundle
├── Group: Cosmetics (外观)
│   ├── 角色皮肤Sprite、武器外观Sprite
│   └── 打包方式: Local Bundle (抽卡后按需加载)
├── Group: Localization (本地化)
│   ├── 各语言JSON文件
│   └── 打包方式: Local Bundle (按语言分Bundle)
├── Group: Fonts (字体)
│   ├── CJK字体包 (8-12MB/包)
│   └── 打包方式: Local Bundle (按需加载)
├── Group: Audio_BGM
│   ├── BGM音频文件
│   └── 打包方式: Local Bundle
└── Group: DLC (未来DLC内容)
    ├── DLC专用资源
    └── 打包方式: Remote Bundle (下载后加载)

PCK命名: pwc_{group}_{variant}_{hash}.pck
压缩方式: Godot导出压缩配置（加载速度优先）
更新检测: 通过manifest.json记录资源hash，发布后资源只追加不覆盖
```

### 5.3 Godot导出脚本

```text
# scripts/tools/export_build.gd
# Godot headless导出入口，CI/CD调用：
# godot --headless --path . --script scripts/tools/export_build.gd -- --target windows --channel beta

const BUILD_OUTPUT_DIR := "builds"
const PRODUCT_NAME := "Plane Walker"

func build_development() -> void: pass
func build_release() -> void: pass
func build_beta() -> void: pass
func perform_build(build_type: StringName) -> void: pass
func generate_version_string() -> String: pass
func get_git_commit_count() -> int: pass
func get_git_branch() -> String: pass
func generate_changelog(version: String) -> void: pass
func validate_build(build_path: String) -> bool: pass
func upload_to_steam(build_path: String, branch: String) -> void: pass
func post_build_process(build_path: String) -> void: pass
func generate_build_report(build_path: String, build_time: float) -> void: pass
```

### 5.4 ResourceManager资源管理器

```gdscript
# autoload/resource_manager.gd
extends Node

var _loaded: Dictionary[String, Resource] = {}
var _ref_counts: Dictionary[String, int] = {}
var _loading_progress: Dictionary[String, float] = {}

func load_async(path: String) -> Resource:
    if _loaded.has(path):
        retain(path)
        return _loaded[path]
    ResourceLoader.load_threaded_request(path)
    var progress := [0.0]
    while true:
        var status := ResourceLoader.load_threaded_get_status(path, progress)
        _loading_progress[path] = progress[0]
        if status == ResourceLoader.THREAD_LOAD_LOADED:
            break
        await get_tree().process_frame
    var resource := ResourceLoader.load_threaded_get(path)
    _loaded[path] = resource
    _ref_counts[path] = 1
    return resource

func retain(path: String) -> void:
    _ref_counts[path] = _ref_counts.get(path, 0) + 1

func release(path: String) -> void:
    if not _ref_counts.has(path):
        return
    _ref_counts[path] -= 1
    if _ref_counts[path] <= 0:
        _loaded.erase(path)
        _ref_counts.erase(path)

func release_all() -> void:
    _loaded.clear()
    _ref_counts.clear()

func get_loading_progress(path: String) -> float:
    return _loading_progress.get(path, 0.0)

func is_loaded(path: String) -> bool:
    return _loaded.has(path)
```

---

## 6. LocalizationManager — JSON外置 + 语言切换 + 字体

### 6.1 概述

本地化管理器负责运行时多语言切换，文本数据以JSON外置（按`{类别}.{子类}.{ID}.{字段}`键值规范），支持运行时热重载、字体按需加载、占位符替换、文本长度自适应。

### 6.2 LocalizationManager

```text
/// <summary>
/// 本地化管理器 — 多语言切换、JSON文本加载、字体管理
/// 单例，通过ServiceRegistry全局访问
/// </summary>
public class LocalizationManager : Node
{
    // ── 单例 ──────────────────────────────────────────
    public static LocalizationManager Instance { get; private set; }

    // ── 配置 ───────────────────────────────────────────
     private LocalizationConfigSO _config;
     private SystemLanguage _defaultLanguage = SystemLanguage.Chinese;

    // ── 运行时状态 ─────────────────────────────────────
    private string _currentLanguage;                          // 当前语言代码如 "zh-CN"
    private Dictionary<string, string> _currentTexts;         // key → localized text
    private Dictionary<string, Dictionary<string, string>> _languageCache; // 语言缓存
    private Dictionary<string, FontFile> _loadedFonts;   // 已加载字体
    private FontFile _currentFont;
    private FontFile _fallbackFont;
    private bool _isInitialized;

    // ── 事件 ───────────────────────────────────────────
    public event Action<string> OnLanguageChanged;            // 新语言代码
    public event Action OnFontChanged;

    // ── 生命周期 ───────────────────────────────────────
    private void Awake()
    {
        if (Instance != null && Instance != this) { queue_free(); return; }
        Instance = this;
        Autoload常驻;
    }

    // ── 初始化 ─────────────────────────────────────────

    /// <summary>初始化本地化系统</summary>
    public async流程 Initialize();

    /// <summary>检测系统语言并设置默认语言</summary>
    public string DetectSystemLanguage();

    /// <summary>获取支持的语言列表</summary>
    public IReadOnlyList<LanguageInfo> GetSupportedLanguages();

    // ── 语言切换 ───────────────────────────────────────

    /// <summary>设置当前语言</summary>
    public async流程 SetLanguage(string languageCode);

    /// <summary>获取当前语言代码</summary>
    public string GetCurrentLanguage();

    /// <summary>获取当前语言显示名</summary>
    public string GetCurrentLanguageName();

    /// <summary>检查是否支持指定语言</summary>
    public bool IsLanguageSupported(string languageCode);

    // ── 文本获取 ───────────────────────────────────────

    /// <summary>获取本地化文本</summary>
    public string GetText(string key);

    /// <summary>获取本地化文本（带参数替换）</summary>
    public string GetText(string key, params object[] args);

    /// <summary>获取本地化文本（带默认值）</summary>
    public string GetText(string key, string defaultValue);

    /// <summary>批量获取本地化文本</summary>
    public Dictionary<string, string> GetTextsByPrefix(string prefix);

    /// <summary>检查键是否存在</summary>
    public bool HasKey(string key);

    /// <summary>获取带命名空间的完整键</summary>
    public string GetFullKey(string category, string subCategory, string id, string field);

    // ── 字体管理 ───────────────────────────────────────

    /// <summary>加载指定语言字体</summary>
    public async流程 LoadFontForLanguage(string languageCode);

    /// <summary>获取当前字体</summary>
    public FontFile GetCurrentFont();

    /// <summary>获取回退字体</summary>
    public FontFile GetFallbackFont();

    /// <summary>应用字体到所有TMP组件</summary>
    public void ApplyFontToAll();

    // ── 文本加载 ───────────────────────────────────────

    /// <summary>加载指定语言的JSON文本文件</summary>
    public async流程 LoadLanguageData(string languageCode, Action<bool> onComplete);

    /// <summary>热重载当前语言（开发期调试用）</summary>
    public async流程 ReloadCurrentLanguage();

    /// <summary>解析JSON文本为扁平键值对</summary>
    private Dictionary<string, string> ParseLanguageJSON(string jsonText, string prefix = "");

    /// <summary>合并多个JSON文件</summary>
    private Dictionary<string, string> MergeLanguageFiles(Dictionary<string, string>[] files);

    // ── 占位符处理 ─────────────────────────────────────

    /// <summary>替换占位符 {0} {1} ...</summary>
    public string ReplacePlaceholders(string text, params object[] args);

    /// <summary>替换变量占位符 {player_name} 等</summary>
    public string ReplaceVariables(string text, Dictionary<string, string> variables);

    // ── 文本长度工具 ───────────────────────────────────

    /// <summary>获取文本膨胀系数（当前语言相对中文）</summary>
    public float GetExpansionFactor();

    /// <summary>根据膨胀系数自适应字号</summary>
    public int GetAdjustedFontSize(int baseFontSize);

    // ── 存档 ───────────────────────────────────────────

    /// <summary>获取语言设置</summary>
    public LocalizationSettingsData GetSettings();

    /// <summary>应用语言设置</summary>
    public void ApplySettings(LocalizationSettingsData settings);
}

/// <summary>
/// 语言信息
/// </summary>
[Serializable]
public class LanguageInfo
{
    public string Code;             // "zh-CN", "en", "ja"
    public string DisplayName;      // "简体中文", "English", "日本語"
    public string FontAssetPath;    // Resource路径
    public string FallbackFontPath;
    public float ExpansionFactor;   // 膨胀系数
    public bool IsCjk;              // 是否CJK语言
    public bool IsRightToLeft;      // 是否RTL（预留）
    public string TextAssetPath;    // JSON文本Resource路径
    public string[] AdditionalTextPaths; // 扩展文本(DLC等)
}

/// <summary>
/// 本地化配置Resource
/// </summary>
[CreateAssetMenu(fileName = "LocalizationConfig", menuName = "PWC/Localization/Config")]
public class LocalizationConfigSO : Resource
{
    public LanguageInfo[] SupportedLanguages;
    public string DefaultLanguageCode;
    public string MissingTextFormat = "[MISSING:{0}]";
    public bool LogMissingKeys = true;
    public int BaseFontSize = 24;
    public int MinFontSize = 14;
}

/// <summary>
/// 本地化设置存档数据
/// </summary>
[Serializable]
public class LocalizationSettingsData
{
    public string LanguageCode;
    public int FontSizeOverride;    // 0=自动
}
```

---

## 7. Mod SDK — IMod接口 + ModLoader + Workshop

### 7.1 概述

Mod SDK提供标准化的Mod开发接口，包含IMod生命周期接口、数据修改API、资源替换API、事件监听API。ModLoader负责发现/加载/校验Mod。Steam Workshop集成用于上传/下载/订阅。

### 7.2 IMod接口

```text
/// <summary>
/// Mod基础接口 — 所有Mod必须实现
/// </summary>
public interface IMod
{
    /// <summary>Mod元信息</summary>
    ModInfo Info { get; }

    /// <summary>Mod加载时调用（注册API、初始化）</summary>
    void OnLoad(IModAPI api);

    /// <summary>Mod卸载时调用（清理资源）</summary>
    void OnUnload();

    /// <summary>每帧更新（受时间配额限制）</summary>
    void OnUpdate(float deltaTime);
}

/// <summary>
/// Mod元信息（对应mod_info.json）
/// </summary>
[Serializable]
public class ModInfo
{
    public string Id;                 // 唯一标识: com.example.pwc_more_items
    public string Name;
    public string Author;
    public string Version;            // 语义化版本: "1.0.0"
    public string GameVersion;        // 兼容游戏版本: "1.0.*"
    public string Description;
    public string[] Dependencies;     // 依赖的其他Mod ID
    public int ApiVersion;            // SDK API版本
    public string[] Tags;
    public string PreviewImagePath;
}
```

### 7.3 IModAPI — Mod可调用API

```text
/// <summary>
/// Mod API接口 — 提供给Mod调用的受控API集合
/// </summary>
public interface IModAPI
{
    // ── 数据API ────────────────────────────────────────

    /// <summary>道具数据API</summary>
    IItemModAPI Items { get; }

    /// <summary>祝福数据API</summary>
    IBlessingModAPI Blessings { get; }

    /// <summary>诅咒数据API</summary>
    ICurseModAPI Curses { get; }

    /// <summary>武器数据API</summary>
    IWeaponModAPI Weapons { get; }

    // ── 资源API ────────────────────────────────────────

    /// <summary>精灵图替换API</summary>
    ISpriteModAPI Sprites { get; }

    /// <summary>音效替换API</summary>
    IAudioModAPI Audio { get; }

    /// <summary>UI主题API</summary>
    IUIThemeModAPI UITheme { get; }

    // ── 事件API（只读监听）─────────────────────────────

    /// <summary>订阅游戏事件</summary>
    void SubscribeEvent<T>(Action<T> handler) where T : struct, IEvent;

    /// <summary>取消订阅游戏事件</summary>
    void UnsubscribeEvent<T>(Action<T> handler) where T : struct, IEvent;

    // ── 工具API ────────────────────────────────────────

    /// <summary>日志输出</summary>
    void Log(string message, LogLevel level = LogLevel.Info);

    /// <summary>获取游戏版本</summary>
    string GetGameVersion();

    /// <summary>获取配置目录路径</summary>
    string GetModConfigDirectory(string modId);

    /// <summary>获取当前语言</summary>
    string GetCurrentLanguage();
}

/// <summary>道具Mod API</summary>
public interface IItemModAPI
{
    void RegisterItem(ItemModData itemData);
    void ModifyItem(string itemId, Action<ItemModData> modifier);
    ItemModData GetItemData(string itemId);
    IReadOnlyList<ItemModData> GetAllItems();
}

/// <summary>祝福Mod API</summary>
public interface IBlessingModAPI
{
    void RegisterBlessing(BlessingModData data);
    void ModifyBlessing(string blessingId, Action<BlessingModData> modifier);
}

/// <summary>诅咒Mod API</summary>
public interface ICurseModAPI
{
    void RegisterCurse(CurseModData data);
    void ModifyCurse(string curseId, Action<CurseModData> modifier);
}

/// <summary>武器Mod API</summary>
public interface IWeaponModAPI
{
    void ModifyWeaponStats(string weaponId, WeaponModStats stats);
    WeaponModStats GetWeaponStats(string weaponId);
}

/// <summary>精灵图Mod API</summary>
public interface ISpriteModAPI
{
    void RegisterSprite(string spriteId, Sprite sprite);
    void ReplaceSprite(string originalId, Sprite replacement);
    Sprite GetSprite(string spriteId);
}

/// <summary>音效Mod API</summary>
public interface IAudioModAPI
{
    void ReplaceSFX(string sfxId, AudioClip clip);
    void ReplaceBGM(string bgmId, AudioClip clip);
}

/// <summary>UI主题Mod API</summary>
public interface IUIThemeModAPI
{
    void RegisterTheme(string themeId, UIThemeModData themeData);
    void ApplyTheme(string themeId);
    void ResetToDefault();
}

// Mod数据结构
[Serializable]
public class ItemModData
{
    public string Id;
    public string Name;
    public string Description;
    public string FlavorText;
    public Rarity Rarity;
    public string Category;
    public Dictionary<string, float> Stats;
    public string[] SynergyIds;
    public string IconPath;
    public string EffectType;
}

[Serializable]
public class BlessingModData
{
    public string Id;
    public string Name;
    public string Description;
    public Rarity Rarity;
    public string EffectType;
    public Dictionary<string, float> Stats;
}

[Serializable]
public class CurseModData
{
    public string Id;
    public string Name;
    public string Description;
    public Rarity Rarity;
    public string EffectType;
    public Dictionary<string, float> Stats;
}

[Serializable]
public class WeaponModStats
{
    public float AttackMultiplier = 1.0f;   // ±30%上限
    public float SpeedMultiplier = 1.0f;    // ±20%上限
    public float RangeMultiplier = 1.0f;
    public float CritBonus;
}

[Serializable]
public class UIThemeModData
{
    public string Id;
    public string Name;
    public Color32 PrimaryColor;
    public Color32 SecondaryColor;
    public Color32 BackgroundColor;
    public Color32 TextColor;
    public string PanelSpritePath;
}

public enum LogLevel { Debug, Info, Warning, Error }
```

### 7.4 ModLoader

```text
/// <summary>
/// Mod加载器 — 发现、校验、加载、管理Mod生命周期
/// </summary>
public class ModLoader
{
    private readonly string _modRootDirectory;
    private Dictionary<string, IMod> _loadedMods;            // modId → IMod实例
    private Dictionary<string, ModInfo> _discoveredMods;     // modId → ModInfo
    private Dictionary<string, ModState> _modStates;         // modId → 状态
    private HashSet<string> _enabledMods;
    private IModAPI _modAPI;
    private ModValidator _validator;
    private bool _isModActive;                               // 有非翻译Mod启用

    public ModLoader(string modRootDirectory, IModAPI modAPI);

    // ── 发现与校验 ─────────────────────────────────────

    /// <summary>扫描Mod目录，发现所有Mod</summary>
    public async流程 DiscoverMods(Action<int> onComplete);

    /// <summary>校验Mod（格式、API版本、白名单）</summary>
    public ModValidationResult ValidateMod(string modDirectory);

    /// <summary>获取已发现的Mod列表</summary>
    public IReadOnlyList<ModInfo> GetDiscoveredMods();

    /// <summary>获取已启用的Mod列表</summary>
    public IReadOnlyList<ModInfo> GetEnabledMods();

    // ── 加载与卸载 ─────────────────────────────────────

    /// <summary>加载并启用Mod</summary>
    public async流程 LoadMod(string modId, Action<bool> onComplete);

    /// <summary>卸载Mod</summary>
    public async流程 UnloadMod(string modId, Action<bool> onComplete);

    /// <summary>启用Mod（已加载但未激活）</summary>
    public void EnableMod(string modId);

    /// <summary>禁用Mod</summary>
    public void DisableMod(string modId);

    /// <summary>加载所有已启用Mod</summary>
    public async流程 LoadAllEnabledMods(Action<int> onComplete);

    /// <summary>卸载所有Mod</summary>
    public async流程 UnloadAllMods(Action onComplete);

    // ── 依赖管理 ───────────────────────────────────────

    /// <summary>检查Mod依赖是否满足</summary>
    public bool CheckDependencies(string modId);

    /// <summary>获取依赖解析顺序（拓扑排序）</summary>
    public List<string> ResolveLoadOrder();

    /// <summary>获取Mod冲突列表</summary>
    public List<ModConflict> DetectConflicts();

    // ── 状态 ───────────────────────────────────────────

    /// <summary>获取Mod加载状态</summary>
    public ModState GetModState(string modId);

    /// <summary>是否有非翻译Mod启用</summary>
    public bool IsModActive => _isModActive;

    /// <summary>更新所有已加载Mod</summary>
    public void UpdateMods(float deltaTime);

    // ── Steam Workshop ─────────────────────────────────

    /// <summary>从Workshop下载的Mod目录同步</summary>
    public async流程 SyncWorkshopMods(Action onComplete);

    /// <summary>获取Workshop Mod列表</summary>
    public IReadOnlyList<ModInfo> GetWorkshopMods();

    /// <summary>上传Mod到Workshop</summary>
    public void UploadToWorkshop(string modId, string title, string description,
                                  string[] tags, Action<bool> onComplete);

    // ── 加载实现 ───────────────────────────────────────

    /// <summary>从目录加载Mod程序集</summary>
    private async流程 LoadModAssembly(string modDirectory, Action<IMod> onComplete);

    /// <summary>加载mod_info.json</summary>
    private ModInfo LoadModInfo(string modDirectory);

    /// <summary>更新全局Mod状态标记</summary>
    private void UpdateModActiveFlag();
}

public enum ModState
{
    Discovered,   // 已发现未加载
    Loading,      // 加载中
    Loaded,       // 已加载
    Enabled,      // 已启用
    Error,        // 加载失败
    Disabled      // 已禁用
}

public struct ModValidationResult
{
    public bool IsValid;
    public string[] Errors;
    public string[] Warnings;
    public long FileSizeBytes;
}

public struct ModConflict
{
    public string ModA;
    public string ModB;
    public string ConflictType;    // "same_item_id", "same_sprite_id", etc.
    public string Detail;
}
```

### 7.5 ModValidator

```text
/// <summary>
/// Mod校验器 — 格式校验、白名单检查、恶意代码扫描
/// </summary>
public class ModValidator
{
    private static readonly HashSet<string> ALLOWED_FILE_EXTENSIONS =
        new() { ".json", ".png", ".wav", ".ogg", ".gd" };

    private static readonly HashSet<string> BLOCKED_NAMESPACES =
        new() { "System.IO", "System.Net", "System.Reflection", "System.Diagnostics" };

    private const long MAX_MOD_SIZE_BYTES = 50 * 1024 * 1024;    // 50MB
    private const float MAX_STAT_DEVIATION = 0.5f;                // ±50%

    /// <summary>校验Mod完整性</summary>
    public ModValidationResult Validate(string modDirectory);

    /// <summary>校验mod_info.json</summary>
    public bool ValidateModInfo(ModInfo info, out string[] errors);

    /// <summary>校验文件类型白名单</summary>
    public bool ValidateFileTypes(string modDirectory, out string[] violations);

    /// <summary>校验文件大小</summary>
    public bool ValidateFileSize(string modDirectory, out long totalSize);

    /// <summary>校验数值范围（±50%基准值）</summary>
    public bool ValidateStatRanges(ItemModData item, out string[] violations);

    /// <summary>扫描代码Mod是否调用禁止的命名空间</summary>
    public bool ScanBlockedNamespaces(string assemblyPath, out string[] violations);

    /// <summary>校验API版本兼容性</summary>
    public bool ValidateApiVersion(int modApiVersion, int currentApiVersion);
}
```

---

## 8. Steamworks集成 — 成就/排行榜/云存档封装

### 8.1 概述

Steamworks集成层封装Steam API调用，包括成就系统、排行榜系统、云存档系统、好友系统、Workshop系统。所有Steam API调用通过`SteamworksProvider`单例统一入口，避免各模块直接依赖Steamworks.NET。

### 8.2 SteamworksProvider

```text
/// <summary>
/// Steamworks提供者 — Steam API统一入口，初始化+生命周期管理
/// 单例，挂载于Boot场景
/// </summary>
public class SteamworksProvider : Node
{
    // ── 常量 ───────────────────────────────────────────
    public const uint APP_ID = 1678320;    // Steam App ID

    // ── 单例 ──────────────────────────────────────────
    public static SteamworksProvider Instance { get; private set; }

    // ── 子系统 ─────────────────────────────────────────
    private SteamAchievementManager _achievements;
    private SteamLeaderboardManager _leaderboards;
    private SteamCloudManager _cloud;
    private SteamFriendManager _friends;
    private SteamWorkshopManager _workshop;

    // ── 状态 ───────────────────────────────────────────
    private bool _isInitialized;

    // ── 公有属性 ───────────────────────────────────────
    public bool IsInitialized => _isInitialized;
    public ulong SteamId { get; private set; }
    public string SteamName { get; private set; }
    public SteamAchievementManager Achievements => _achievements;
    public SteamLeaderboardManager Leaderboards => _leaderboards;
    public SteamCloudManager Cloud => _cloud;
    public SteamFriendManager Friends => _friends;
    public SteamWorkshopManager Workshop => _workshop;

    // ── 生命周期 ───────────────────────────────────────
    private void Awake()
    {
        if (Instance != null && Instance != this) { queue_free(); return; }
        Instance = this;
        Autoload常驻;
        InitializeSteam();
    }

    private void Update()
    {
        if (_isInitialized) SteamAPI.RunCallbacks();
    }

    private void On.queue_free()
    {
        if (_isInitialized) SteamAPI.Shutdown();
    }

    // ── 公有方法 ───────────────────────────────────────

    /// <summary>初始化Steam API</summary>
    public void InitializeSteam();

    /// <summary>检查Steam是否可用</summary>
    public bool IsSteamAvailable();

    /// <summary>获取Steam ID</summary>
    public ulong GetSteamId();

    /// <summary>获取Steam显示名</summary>
    public string GetSteamName();

    /// <summary>获取游戏语言（Steam设置）</summary>
    public string GetSteamLanguage();
}
```

### 8.3 SteamAchievementManager

```text
/// <summary>
/// Steam成就管理器 — 解锁/查询/统计
/// </summary>
public class SteamAchievementManager
{
    private Dictionary<string, bool> _achievementCache;
    private Dictionary<string, int> _statCache;
    private bool _isDisabled;       // Mod激活时禁用

    /// <summary>初始化成就缓存</summary>
    public void Initialize();

    /// <summary>解锁成就</summary>
    public bool UnlockAchievement(string achievementId);

    /// <summary>检查成就是否已解锁</summary>
    public bool IsAchievementUnlocked(string achievementId);

    /// <summary>获取成就完成进度(0~100)</summary>
    public int GetAchievementProgress(string achievementId);

    /// <summary>设置统计数据(整数)</summary>
    public bool SetStatInt(string statName, int value);

    /// <summary>增加统计数据(整数)</summary>
    public bool IncrementStatInt(string statName, int delta);

    /// <summary>获取统计数据(整数)</summary>
    public int GetStatInt(string statName);

    /// <summary>设置统计数据(浮点)</summary>
    public bool SetStatFloat(string statName, float value);

    /// <summary>获取统计数据(浮点)</summary>
    public float GetStatFloat(string statName);

    /// <summary>强制提交统计到Steam</summary>
    public void StoreStats();

    /// <summary>重置所有成就（仅调试）</summary>
    public void ResetAllAchievements();

    /// <summary>设置Mod禁用状态</summary>
    public void SetDisabled(bool disabled);

    /// <summary>获取所有成就状态</summary>
    public Dictionary<string, bool> GetAllAchievementStates();
}
```

### 8.4 SteamLeaderboardManager

```text
/// <summary>
/// Steam排行榜管理器 — 查询/提交/排名
/// </summary>
public class SteamLeaderboardManager
{
    private Dictionary<string, SteamLeaderboard_t> _handles;
    private Dictionary<string, LeaderboardEntry_t> _personalBestCache;
    private CallResult<LeaderboardFindResult_t> _findResult;
    private CallResult<LeaderboardScoreUploaded_t> _uploadResult;
    private CallResult<LeaderboardScoresDownloaded_t> _downloadResult;

    /// <summary>初始化（异步获取所有排行榜句柄）</summary>
    public async流程 InitializeAll(string[] leaderboardIds, Action onComplete);

    /// <summary>查找排行榜句柄</summary>
    public void FindLeaderboard(string leaderboardId, Action<SteamLeaderboard_t> onComplete);

    /// <summary>提交分数</summary>
    public void UploadScore(string leaderboardId, int score, int[] details,
                            Action<bool> onComplete);

    /// <summary>下载排行榜条目</summary>
    public void DownloadEntries(string leaderboardId, int start, int end,
                                Action<LeaderboardEntry[]> onComplete);

    /// <summary>下载好友排行榜条目</summary>
    public void DownloadFriendEntries(string leaderboardId,
                                       Action<LeaderboardEntry[]> onComplete);

    /// <summary>获取个人排名</summary>
    public int GetPersonalRank(string leaderboardId);

    /// <summary>获取个人最佳分数</summary>
    public int GetPersonalBest(string leaderboardId);

    /// <summary>将LeaderboardEntry_t转换为自定义结构</summary>
    private LeaderboardEntry ConvertEntry(LeaderboardEntry_t entry, int[] details);
}
```

### 8.5 SteamCloudManager

```text
/// <summary>
/// Steam云存档管理器 — 文件读写/冲突检测/配额查询
/// </summary>
public class SteamCloudManager
{
    private const long REQUESTED_QUOTA_BYTES = 200 * 1024 * 1024;  // 200MB

    /// <summary>检查Steam Cloud是否可用</summary>
    public bool IsCloudEnabled();

    /// <summary>获取云存档配额</summary>
    public CloudQuotaInfo GetQuota();

    /// <summary>上传文件到Steam Cloud</summary>
    public bool FileWrite(string remotePath, byte[] data);

    /// <summary>从Steam Cloud读取文件</summary>
    public byte[] FileRead(string remotePath);

    /// <summary>检查文件是否存在</summary>
    public bool FileExists(string remotePath);

    /// <summary>删除云文件</summary>
    public bool FileDelete(string remotePath);

    /// <summary>获取文件大小</summary>
    public int FileSize(string remotePath);

    /// <summary>获取文件时间戳</summary>
    public DateTime FileTimestamp(string remotePath);

    /// <summary>列出云目录下的所有文件</summary>
    public string[] ListFiles(string remoteDir);

    /// <summary>同步所有存档文件（上传本地→云端）</summary>
    public async流程 SyncAll(string localSaveRoot, Action<CloudSyncResult> onComplete);

    /// <summary>下载所有云文件（云端→本地）</summary>
    public async流程 DownloadAll(string localSaveRoot, Action<CloudSyncResult> onComplete);

    /// <summary>检测本地/云端冲突</summary>
    public List<CloudConflict> DetectConflicts(string localSaveRoot);
}

public struct CloudQuotaInfo
{
    public long TotalBytes;
    public long UsedBytes;
    public long AvailableBytes;
}

public struct CloudConflict
{
    public string FilePath;
    public DateTime LocalTimestamp;
    public DateTime CloudTimestamp;
    public long LocalSize;
    public long CloudSize;
}
```

### 8.6 SteamFriendManager

```text
/// <summary>
/// Steam好友管理器 — 好友列表/在线状态/通知
/// </summary>
public class SteamFriendManager
{
    private List<FriendInfo> _friends;
    private HashSet<ulong> _onlinePlayingFriends;

    /// <summary>初始化好友列表</summary>
    public void Initialize();

    /// <summary>刷新好友列表</summary>
    public void RefreshFriends();

    /// <summary>获取所有好友</summary>
    public IReadOnlyList<FriendInfo> GetAllFriends();

    /// <summary>获取在线好友</summary>
    public IReadOnlyList<FriendInfo> GetOnlineFriends();

    /// <summary>获取正在游戏中的好友</summary>
    public IReadOnlyList<FriendInfo> GetFriendsInGame();

    /// <summary>获取正在游戏中的好友数量</summary>
    public int GetFriendsInGameCount();

    /// <summary>检查是否为好友</summary>
    public bool IsFriend(ulong steamId);

    /// <summary>获取好友Small头像</summary>
    public Sprite GetFriendAvatar(ulong steamId, AvatarSize size);

    /// <summary>邀请好友加入游戏</summary>
    public void InviteToGame(ulong steamId);

    /// <summary>注册好友游戏通知回调</summary>
    public void RegisterGamePlayedCallback(Action<ulong> onFriendStartPlaying);

    /// <summary>注册好友通关通知</summary>
    public void RegisterFriendNotificationCallback(Action<FriendNotification> onNotification);
}

[Serializable]
public struct FriendInfo
{
    public ulong SteamId;
    public string Name;
    public FriendStatus Status;
    public bool IsInThisGame;
}

public enum FriendStatus { Offline, Online, Away, Busy, InGame }

public enum AvatarSize { Small, Medium, Large }

public struct FriendNotification
{
    public ulong SteamId;
    public string PlayerName;
    public NotificationType Type;
    public string Detail;
}

public enum NotificationType { FriendCleared, FriendDied, FriendNewRecord, FriendStartedPlaying }
```

### 8.7 SteamWorkshopManager

```text
/// <summary>
/// Steam Workshop管理器 — Mod/回放上传下载
/// </summary>
public class SteamWorkshopManager
{
    private CallResult<CreateItemResult_t> _createItemResult;
    private CallResult<SubmitItemUpdateResult_t> _submitUpdateResult;
    private Dictionary<PublishedFileId_t, WorkshopItemInfo> _subscribedItems;

    /// <summary>初始化</summary>
    public void Initialize();

    /// <summary>创建Workshop项目</summary>
    public void CreateItem(Action<PublishedFileId_t, bool> onComplete);

    /// <summary>上传Mod到Workshop</summary>
    public async流程 UploadMod(PublishedFileId_t itemId, string modDirectory,
                                  string title, string description, string[] tags,
                                  string previewImagePath, Action<bool> onComplete);

    /// <summary>上传回放到Workshop</summary>
    public async流程 UploadReplay(PublishedFileId_t itemId, string replayFilePath,
                                     string title, string description, string[] tags,
                                     Action<bool> onComplete);

    /// <summary>获取已订阅项目列表</summary>
    public IReadOnlyList<WorkshopItemInfo> GetSubscribedItems();

    /// <summary>下载已订阅项目</summary>
    public async流程 DownloadSubscribedItems(Action<int> onComplete);

    /// <summary>获取项目安装路径</summary>
    public string GetItemInstallPath(PublishedFileId_t itemId);

    /// <summary>取消订阅</summary>
    public void Unsubscribe(PublishedFileId_t itemId);

    /// <summary>查询项目详情</summary>
    public async流程 QueryItemDetails(PublishedFileId_t[] itemIds,
                                         Action<WorkshopItemInfo[]> onComplete);

    /// <summary>搜索Workshop项目</summary>
    public async流程 SearchItems(string searchText, string[] tags, int page,
                                    Action<WorkshopSearchResult> onComplete);
}

[Serializable]
public struct WorkshopItemInfo
{
    public PublishedFileId_t ItemId;
    public string Title;
    public string Description;
    public ulong OwnerSteamId;
    public string PreviewUrl;
    public uint Subscriptions;
    public uint Favorited;
    public float Score;
    public string[] Tags;
    public string InstallPath;
    public bool IsInstalled;
    public bool IsDownloading;
    public float DownloadProgress;
}

public struct WorkshopSearchResult
{
    public WorkshopItemInfo[] Items;
    public int TotalCount;
    public int Page;
}
```

---

## 9. 测试策略 — NUnit + 集成测试 + CI/CD

### 9.1 测试金字塔

```
         ╱╲
        ╱  ╲           E2E测试 (少量)
       ╱    ╲          - 完整通关流程自动化
      ╱──────╲         - 每周1次
     ╱        ╲
    ╱ 集成测试  ╲      - 场景级测试
   ╱ (GUT/gdUnit4) ╲   - 每日CI
  ╱──────────────────╲
 ╱    单元测试        ╲   - RefCounted逻辑测试
╱    (NUnit)          ╲  - 每次提交CI
╱──────────────────────╲
  100+    30+    5~10
```

### 9.2 单元测试（NUnit）

```text
/// <summary>
/// 单元测试示例 — 伤害计算器测试
/// </summary>
[TestFixture]
public class DamageCalculatorTests
{
    [Test]
    public void Calculate_BaseDamage100_CritMultiplier1_5_Returns150();
    [Test]
    public void Calculate_Armor50_Returns50PercentReduction();
    [Test]
    public void Calculate_VoidDamage_IgnoresPhysicalArmor();
    [TestCase(0f, ExpectedResult = 0f)]
    [TestCase(100f, ExpectedResult = 100f)]
    [TestCase(-10f, ExpectedResult = 0f)]
    public float Calculate_NegativeResult_ClampsToZero(float baseDamage);
}

/// <summary>
/// 单元测试示例 — 保底系统测试
/// </summary>
[TestFixture]
public class PityTrackerTests
{
    [Test]
    public void RecordPull_50LegendaryPity_TriggersLegendary();
    [Test]
    public void RecordPull_120MythicPity_TriggersMythic();
    [Test]
    public void GetLegendaryProbability_40Pulls_SoftPityIncreased();
    [Test]
    public void ResetPool_ClearsAllCounters();
}

/// <summary>
/// 单元测试示例 — 存档系统测试
/// </summary>
[TestFixture]
public class SaveManagerTests
{
    [Test]
    public void EncryptDecrypt_Roundtrip_PreservesData();
    [Test]
    public void ValidateSave_TamperedData_FailsValidation();
    [Test]
    public void AtomicWrite_Interrupted_OriginalFileIntact();
    [Test]
    public void RotateBackups_CreatesBackup1And2();
    [Test]
    public void RecoverFromBackup_PrimaryCorrupt_RestoresFromBackup1();
}
```

**必须覆盖的单元测试模块：**

| 模块 | 最低用例数 | 重点测试项 |
|------|-----------|-----------|
| EventBus | 10 | 发布订阅/取消订阅/延迟发布/清除 |
| RNG | 8 | 种子确定性/范围/权重随机 |
| DamageCalculator | 15 | 各伤害类型/暴击/护甲/触发效果 |
| ItemEffectProcessor | 12 | 触发条件/堆叠/联动/移除 |
| SynergyEngine | 10 | 联动激活/条件检测/效果叠加 |
| BlessingManager | 8 | 激活/叠加/移除/冲突 |
| CurseManager | 8 | 接受/效果/净化 |
| TalentTree | 8 | 路径选择/解锁条件/点数计算 |
| DungeonGenerator | 10 | 种子一致性/房间连接/布局合法性 |
| DungeonEconomy | 8 | 金币分配/掉落概率 |
| CurrencyManager | 10 | 增减/上限/乘数 |
| MetaProgression | 8 | 节点解锁/依赖检查 |
| GachaSystem | 12 | 概率分布/保底/重复/碎片 |
| PityTracker | 8 | 软/硬保底/重置 |
| SaveManager | 15 | 加密/校验/原子写入/恢复 |
| AffinitySystem | 8 | 增减/等级/冷却 |
| QuestSystem | 8 | 接受/进度/完成/事件驱动 |
| LocalizationManager | 8 | 键值查找/占位符/语言切换 |
| PoolManager | 8 | 获取/归还/扩容/压缩 |
| ReplayRecorder | 6 | 帧记录/压缩/解压 |

### 9.3 集成测试（GUT / gdUnit4）

```text
/// <summary>
/// 集成测试示例 — 使用GUT / gdUnit4
/// 在实际Godot场景中测试
/// </summary>
[TestFixture]
public class HubIntegrationTests
{
    [GdUnitTest]
    public async流程 HubController_PlayerMovesToArea_TriggersAreaChange();

    [GdUnitTest]
    public async流程 NPCController_PlayerInteracts_StartsConversation();

    [GdUnitTest]
    public async流程 DeathScreen_FullSequence_ReachesReturnButton();
}

[TestFixture]
public class CombatIntegrationTests
{
    [GdUnitTest]
    public async流程 SwordWeapon_FullCombo_DealsFourHits();

    [GdUnitTest]
    public async流程 TimeStop_Activate_FreezesAllEnemies();

    [GdUnitTest]
    public async流程 ItemAcquisition_PickUp_ActivatesSynergy();
}

[TestFixture]
public class SaveIntegrationTests
{
    [GdUnitTest]
    public async流程 SaveAndLoad_FullGameState_PreservesAllData();

    [GdUnitTest]
    public async流程 SteamCloudSync_UploadDownload_MatchesOriginal();
}
```

### 9.4 自动化回放回归测试

```text
/// <summary>
/// 回放回归测试 — 使用历史录像验证版本兼容性
/// </summary>
[TestFixture]
public class ReplayRegressionTests
{
    private const string BASELINE_DIR = "tests/replay_baselines/";

    [Test]
    public void ReplayBaseline_Floor1Clear_MatchesExpected();
    [Test]
    public void ReplayBaseline_FullClear_MatchesExpected();
    [Test]
    public void ReplayBaseline_BossFight_MatchesExpected();

    /// <summary>比较回放结果与基线</summary>
    private void CompareWithBaseline(ReplayResult actual, ReplayBaseline expected)
    {
        // 每帧位置偏差 < 0.1
        // 最终通关状态一致
        // 统计数据一致
    }
}
```

### 9.5 CI/CD流水线

```
GitHub Actions Workflow:

触发条件:
  - push → dev 分支
  - pull_request → dev/main 分支
  - 每日定时 02:00 UTC

流水线步骤:
1. Checkout代码
2. 缓存Godot import cache
3. Godot headless export构建
   - 安装Godot导出模板
   - 执行Editor编译
   - 运行单元测试 (NUnit, ~2分钟)
   - 生成测试报告
4. 代码质量检查
   - SonarQube扫描
   - 检查TODO/FIXME/HACK标记数量
5. 构建结果判定
   - 通过 → 通知团队 + 部署到Beta分支
   - 失败 → 通知提交者 + 阻止合并
6. 每周额外任务:
   - 运行集成测试 (~10分钟)
   - 运行回放回归测试
   - 性能基准测试 (Profiler数据采集)
   - 平衡性模拟 (Python脚本, 1000局自动战斗)

构建产物:
  - Windows x64 Standalone
  - 构建报告 (大小/依赖/Shader编译时间)
  - 测试报告 (通过率/覆盖率)
  - 性能报告 (帧时间/内存)
```

### 9.6 测试覆盖率目标

| 模块类型 | 目标覆盖率 | 说明 |
|---------|-----------|------|
| 核心框架 (EventBus/RNG/Pool) | ≥90% | 高可靠性要求 |
| 战斗系统 (Damage/Hitbox/Combo) | ≥80% | 核心玩法 |
| 数据系统 (Registry/Item/Blessing) | ≥80% | 数据驱动核心 |
| 进度系统 (Meta/Currency/Talent) | ≥75% | 经济平衡 |
| 局外系统 (Hub/NPC/Gacha/Save) | ≥70% | 玩家体验关键 |
| 社交系统 (Leaderboard/Replay) | ≥60% | Steam API依赖 |
| 基础设施 (Audio/Localization) | ≥50% | 引擎集成多 |

---

## 10. 性能预算 — 帧时间16.67ms分配 + 内存2GB + Draw Call 200

### 10.1 帧时间预算（60fps = 16.67ms/帧）

```
帧时间分配 (16.67ms总计):

┌─────────────────────────────────────────────────────────┐
│ 总帧预算: 16.67ms                                       │
├─────────────────────────────────────────────────────────┤
│ 游戏逻辑 (GameLogic)                 3.00ms   18%      │
│ ├── 玩家输入处理                    0.20ms             │
│ ├── 动作系统 (ActionPlayer)         0.50ms             │
│ ├── 伤害计算 + Hitbox检测           0.80ms             │
│ ├── 敌人AI (FSM)                    0.60ms             │
│ ├── 道具效果处理                    0.30ms             │
│ ├── 时间操控逻辑                    0.30ms             │
│ └── 事件总线分发                    0.30ms             │
├─────────────────────────────────────────────────────────┤
│ 物理 (Physics2D)                     1.50ms    9%      │
│ ├── CharacterBody2D更新                 0.80ms             │
│ ├── 碰撞检测                        0.50ms             │
│ └── 触发器检测                      0.20ms             │
├─────────────────────────────────────────────────────────┤
│ 动画 (Animation)                     1.00ms    6%      │
│ ├── AnimationPlayer或AnimationTree更新                    0.60ms             │
│ └── Sprite切换                      0.40ms             │
├─────────────────────────────────────────────────────────┤
│ 粒子/VFX                             1.50ms    9%      │
│ ├── GPUParticles2D更新              1.00ms             │
│ └── Shader特效                      0.50ms             │
├─────────────────────────────────────────────────────────┤
│ UI (Godot Control)                            1.00ms    6%      │
│ ├── HUD更新                         0.40ms             │
│ ├── 伤害数字                        0.30ms             │
│ └── 其他UI元素                      0.30ms             │
├─────────────────────────────────────────────────────────┤
│ 音频 (Godot AudioBus)                          0.50ms    3%      │
│ └── Godot AudioServer更新                 0.50ms             │
├─────────────────────────────────────────────────────────┤
│ 渲染 (Rendering)                     6.67ms   40%      │
│ ├── SRP Batch渲染                   3.00ms             │
│ ├── 透明物体渲染                    1.50ms             │
│ ├── 后处理 (Bloom+ColorGrading)     1.17ms             │
│ └── UI渲染                          1.00ms             │
├─────────────────────────────────────────────────────────┤
│ 余量 (Headroom)                      1.50ms    9%      │
│ └── GC / 临时分配 / 峰值缓冲        1.50ms             │
└─────────────────────────────────────────────────────────┘
```

### 10.2 场景级帧预算

| 场景 | 逻辑(ms) | 物理(ms) | 渲染(ms) | UI(ms) | 总计(ms) |
|------|---------|---------|---------|--------|---------|
| 枢纽(Hub) | 1.5 | 0.5 | 5.0 | 1.0 | 8.0 |
| 地牢-普通房 | 2.5 | 1.0 | 6.0 | 0.8 | 10.3 |
| 地牢-精英房(10敌) | 3.5 | 1.5 | 7.0 | 0.8 | 12.8 |
| Boss战(3阶段) | 3.0 | 1.0 | 8.0 | 0.8 | 12.8 |
| 选择界面(暂停) | 0.5 | 0.0 | 2.0 | 2.0 | 4.5 |
| 死亡画面 | 1.0 | 0.0 | 5.0 | 2.0 | 8.0 |

### 10.3 内存预算（2GB总量）

```
内存分配 (2GB = 2048MB):

┌─────────────────────────────────────────────────────────┐
│ Godot运行时                          150MB    7%       │
│ ├── Managed Heap                    80MB               │
│ └── Native Allocation               70MB               │
├─────────────────────────────────────────────────────────┤
│ 纹理 (Textures)                      600MB   29%       │
│ ├── 角色Sprite Atlas                80MB               │
│ ├── 敌人Sprite Atlas                100MB              │
│ ├── 地牢Tilemap Atlas               120MB              │
│ ├── UI Atlas                        60MB               │
│ ├── VFX Atlas                       40MB               │
│ ├── 道具图标Atlas                   30MB               │
│ └── 动态加载纹理                    170MB              │
├─────────────────────────────────────────────────────────┤
│ 音频 (Audio)                         150MB    7%       │
│ ├── BGM (Godot AudioBus Bank)                 80MB               │
│ ├── SFX (Godot AudioBus Bank)                 50MB               │
│ └── Voice                           20MB               │
├─────────────────────────────────────────────────────────┤
│ 网格/动画 (Mesh/Anim)               100MB    5%       │
│ ├── 角色动画Clip                    40MB               │
│ ├── 敌人动画Clip                    40MB               │
│ └── 特效Mesh                        20MB               │
├─────────────────────────────────────────────────────────┤
│ 字体 (Fonts)                         50MB     2%       │
│ ├── CJK字体 (当前语言)              30MB               │
│ └── Latin字体                       20MB               │
├─────────────────────────────────────────────────────────┤
│ 场景数据 (Scene)                     200MB   10%       │
│ ├── 当前场景+Tilemap                120MB              │
│ └── 预加载资源                      80MB               │
├─────────────────────────────────────────────────────────┤
│ Shader + Material                    50MB     2%       │
├─────────────────────────────────────────────────────────┤
│ 对象池 (Pool)                        100MB    5%       │
│ ├── 敌人池                          40MB               │
│ ├── 弹幕/特效池                     30MB               │
│ ├── 伤害数字池                      10MB               │
│ └── 其他池化对象                    20MB               │
├─────────────────────────────────────────────────────────┤
│ Godot AudioBus运行时                           50MB     2%       │
├─────────────────────────────────────────────────────────┤
│ 资源加载缓存                          200MB   10%       │
├─────────────────────────────────────────────────────────┤
│ 余量 (Headroom)                     398MB   19%       │
│ └── 峰值/GC/DLC预留                 398MB              │
└─────────────────────────────────────────────────────────┘
```

### 10.4 Draw Call预算

| 场景 | Draw Call目标 | SRP Batch | 说明 |
|------|-------------|-----------|------|
| 枢纽 | ≤100 | ≤20 | 静态场景，大量Sprite Atlas |
| 地牢-普通房 | ≤150 | ≤30 | 地形+敌人+特效 |
| 地牢-精英房 | ≤180 | ≤35 | 多敌人+大量弹幕 |
| Boss战 | ≤200 | ≤40 | Boss+特效+阶段切换 |
| 选择界面 | ≤50 | ≤10 | 暂停态，仅UI |
| 死亡画面 | ≤80 | ≤15 | 特效+UI |

**Draw Call优化策略：**
- Sprite Atlas合图（角色/敌人/道具图标/UI各一张大图）
- SRP Batcher兼容材质（相同Shader材质自动批处理）
- 透明物体排序合并（按材质/纹理分组）
- 对象池减少Instantiate/Destroy
- 特效使用GPU粒子（GPUParticles2D）
- Tilemap使用Composite CollisionShape2D

### 10.5 加载时间预算

| 操作 | 目标时间 | 上限 | 优化手段 |
|------|---------|------|---------|
| 冷启动→主菜单 | ≤8秒 | ≤15秒 | 启动场景最小化+异步加载 |
| 主菜单→枢纽 | ≤3秒 | ≤5秒 | ResourceLoader预加载 |
| 枢纽→地牢(出发) | ≤4秒 | ≤6秒 | 转场动画掩盖+预加载 |
| 房间切换 | ≤0.5秒 | ≤1秒 | 对象池+地址缓存 |
| 层级切换 | ≤2秒 | ≤3秒 | 转场动画+预加载下一层 |
| 死亡→枢纽 | ≤3秒 | ≤5秒 | 轻量Hub场景 |
| 语言切换 | ≤2秒 | ≤4秒 | 字体异步加载 |

### 10.6 性能监控与报警

```text
/// <summary>
/// 性能监控器 — 运行时采集帧时间/内存/DrawCall
/// </summary>
public class PerformanceMonitor : Node
{
    // ── 采集指标 ───────────────────────────────────────
    private FrameTimeTracker _frameTimeTracker;
    private MemoryTracker _memoryTracker;
    private int _lastFrameDrawCalls;

    // ── 报警阈值 ───────────────────────────────────────
    private const float FRAME_TIME_WARNING_MS = 22.0f;    // <45fps
    private const float FRAME_TIME_CRITICAL_MS = 33.0f;   // <30fps
    private const long MEMORY_WARNING_MB = 2048L;
    private const long MEMORY_CRITICAL_MB = 2560L;
    private const int DRAW_CALL_WARNING = 200;
    private const int DRAW_CALL_CRITICAL = 300;

    /// <summary>开始监控</summary>
    public void StartMonitoring();

    /// <summary>停止监控</summary>
    public void StopMonitoring();

    /// <summary>获取当前性能快照</summary>
    public PerformanceSnapshot GetSnapshot();

    /// <summary>获取平均帧时间(最近60帧)</summary>
    public float GetAverageFrameTimeMs();

    /// <summary>获取最低帧率(最近60帧)</summary>
    public float GetMinFps();

    /// <summary>获取Draw Call数</summary>
    public int GetDrawCallCount();

    /// <summary>获取内存使用量(MB)</summary>
    public long GetMemoryUsageMB();

    /// <summary>生成性能报告（Run结束时调用）</summary>
    public PerformanceReport GenerateReport();

    /// <summary>上报性能数据到服务器（匿名）</summary>
    public void ReportToServer(PerformanceReport report);

    // ── 内部更新 ───────────────────────────────────────
    private void Update();
    private void CheckThresholds();
    private void OnFrameTimeWarning(float frameTimeMs);
    private void OnFrameTimeCritical(float frameTimeMs);
}

[Serializable]
public struct PerformanceSnapshot
{
    public float FrameTimeMs;
    public float Fps;
    public float AvgFrameTimeMs60;
    public float MinFps60;
    public long MemoryMB;
    public int DrawCalls;
    public int Triangles;
    public int SetPassCalls;
    public string SceneName;
    public float UptimeSeconds;
}

[Serializable]
public class PerformanceReport
{
    public string GameVersion;
    public string GpuModel;
    public string CpuModel;
    public int ScreenResolution;
    public float AvgFps;
    public float MinFps;
    public float MaxFrameTimeMs;
    public long PeakMemoryMB;
    public int MaxDrawCalls;
    public int TotalFrames;
    public float DurationSeconds;
    public Dictionary<string, float> SceneAvgFps;
}
```

### 10.7 GC优化策略

| 策略 | 说明 | 目标 |
|------|------|------|
| 结构体替代类 | DamageInfo/ReplayFrame等使用struct | 减少堆分配 |
| 预分配集合 | List/Array初始化指定Capacity | 避免扩容GC |
| 对象池 | 敌人/特效/伤害数字池化 | 消除Instantiate/Destroy GC |
| 缓存组件引用 | Awake中获取所有GetComponent | 消除Update中查找GC |
| 避免字符串拼接 | StringBuilder或string.Format | 消除临时字符串GC |
| 避免LINQ | 热路径用for循环替代 | 消除委托/迭代器GC |
| 避免热路径临时数组 | 2D物理查询复用数组/对象池 | 降低GDScript分配压力 |
| 事件参数struct | EventBus使用struct事件 | 零GC事件分发 |
| 定时GC.Collect | 场景切换时主动触发 | 避免战斗中突发GC |
| GC目标 | 战斗中每帧GC分配 < 256B | 无可见卡顿 |
