# 05 地牢生成系统开发文档

> **文档版本**：v1.0  
> **最后更新**：2026-04-22  
> **适用项目**：《Plane Walker: Chronicles of Collapse》  
> **引擎**：Godot 4.x + GDScript 2.0  
> **架构依赖**：EventBus Autoload, ServiceRegistry, StateMachine, Registry  
> **参考**：Dead Cells关卡结构 + Hades房间选择 + Binding of Isaac地牢生成  

> **Godot迁移约束**：房间模板使用 `.tscn` + `RoomTemplateData(.tres/json)`；地图使用 `TileMapLayer/TileSet`；运行时实例化使用 `PackedScene.instantiate()`。历史伪代码中的实体、PackedScene、配置数据分别映射为 Node、PackedScene、Resource。

> **v1.1实现约束**：首发地牢固定按5层、每层6-9房间、单局30-45分钟实现。任何10层、7/9层天赋节奏、额外层级经济曲线或扩展Boss路线只作为后续扩展，不进入首发默认生成器和平衡表。

---

## 5.1 地牢生成架构

### 5.1.1 三层混合生成架构

```
┌───────────────────────────────────────────────────────────────┐
│                    地牢生成架构                                │
│                                                               │
│  第一层：宏观布局 (DungeonGraphGenerator)                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 图论拓扑 → 房间节点图 → 主路径 + 分支 → 房间类型标记    │ │
│  └───────────────────────┬─────────────────────────────────┘ │
│                          ▼                                    │
│  第二层：空间映射 (BSPPartitioner + RoomPlacer)               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ BSP递归分区 → 叶节点 → 房间矩形放置 → 拓扑映射         │ │
│  └───────────────────────┬─────────────────────────────────┘ │
│                          ▼                                    │
│  第三层：微观填充 (CorridorBuilder + RoomInstantiator)        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 走廊连接(MST+额外边) → 模板实例化 → 内容填充           │ │
│  └───────────────────────┬─────────────────────────────────┘ │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 验证与修正：可达性BFS / 最短路径 / 特殊房间保底         │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### 5.1.2 核心类职责

| 类 | 职责 |
|----|------|
| `DungeonGenerator` | 地牢生成主控制器，协调三层算法流程 |
| `DungeonGraphGenerator` | 第一层：图论拓扑生成，创建房间节点图 |
| `BSPPartitioner` | 第二层：BSP空间分区 |
| `RoomPlacer` | 第二层：房间矩形放置 |
| `CorridorBuilder` | 第三层：走廊连接（MST+额外边） |
| `RoomInstantiator` | 第三层：房间模板实例化 |
| `RoomContentGenerator` | 第三层：房间内容（敌人/奖励）生成 |
| `SeededRNG` | 确定性随机数生成器 |
| `DifficultyManager` | 难度曲线管理 |
| `DungeonEconomy` | 地牢内经济系统 |
| `MiniMapRenderer` | 小地图渲染 |
| `EventManager` | 事件房系统 |
| `DungeonData` | 生成结果数据结构 |

### 5.1.3 DungeonGenerator主控

```text
public class DungeonGenerator : Node
{
    [Header("生成参数")]
     private RoomTemplateDatabase templateDatabase;
     private EnemyDatabase enemyDatabase;
     private EventDatabase eventDatabase;
    
    private DungeonGraphGenerator _graphGenerator;
    private BSPPartitioner _bspPartitioner;
    private RoomPlacer _roomPlacer;
    private CorridorBuilder _corridorBuilder;
    private RoomInstantiator _roomInstantiator;
    private RoomContentGenerator _contentGenerator;
    private DifficultyManager _difficultyManager;
    
    public DungeonData CurrentDungeon { get; private set; }
    
    private void Awake()
    {
        _graphGenerator = new DungeonGraphGenerator();
        _bspPartitioner = new BSPPartitioner();
        _roomPlacer = new RoomPlacer();
        _corridorBuilder = new CorridorBuilder();
        _roomInstantiator = new RoomInstantiator(templateDatabase);
        _contentGenerator = new RoomContentGenerator(enemyDatabase);
        _difficultyManager = ServiceRegistry.Get<DifficultyManager>();
    }
    
    /// <summary>
    /// 生成地牢主入口
    /// </summary>
    public DungeonData Generate(int globalSeed, int floorIndex)
    {
        // 层种子派生
        int floorSeed = SeededRNG.DeriveSeed(globalSeed, floorIndex);
        var rng = new SeededRNG(floorSeed);
        var floorParams = FloorParams.Get(floorIndex);
        
        int maxRetries = 10;
        for (int attempt = 0; attempt < maxRetries; attempt++)
        {
            var dungeon = GenerateInternal(rng, floorIndex, floorParams);
            if (Validate(dungeon, floorParams))
            {
                CurrentDungeon = dungeon;
                EventBus.Publish(new DungeonGeneratedEvent(dungeon, floorIndex));
                return dungeon;
            }
            // 验证失败，换种子重试
            rng = new SeededRNG(SeededRNG.DeriveSeed(floorSeed, attempt + 1));
        }
        
        Debug.LogError($"Dungeon generation failed after {maxRetries} attempts for floor {floorIndex}");
        return null;
    }
    
    private DungeonData GenerateInternal(SeededRNG rng, int floorIndex, FloorParams params_)
    {
        var dungeon = new DungeonData(floorIndex);
        
        // === 第一层：图论拓扑 ===
        var graph = _graphGenerator.Generate(rng, params_, floorIndex);
        dungeon.Graph = graph;
        
        // === 第二层：BSP空间映射 ===
        var bspRoot = _bspPartitioner.Partition(rng, 
            new Rect(0, 0, 200, 200), 0, CalcBSPDepth(graph.RoomCount));
        var roomRects = _roomPlacer.Place(rng, bspRoot, graph);
        dungeon.RoomRects = roomRects;
        
        // === 第三层：走廊与实例化 ===
        var corridors = _corridorBuilder.Build(rng, graph, roomRects, floorIndex);
        dungeon.Corridors = corridors;
        
        // 实例化房间
        _roomInstantiator.Instantiate(graph, roomRects, floorIndex, dungeon);
        
        // 填充内容
        foreach (var room in dungeon.Rooms)
        {
            _contentGenerator.Populate(rng, room, floorIndex);
        }
        
        return dungeon;
    }
    
    /// <summary>
    /// 验证地牢数据
    /// </summary>
    private bool Validate(DungeonData dungeon, FloorParams params_)
    {
        // 1. 全局可达性
        var reachable = BFSReachable(dungeon, dungeon.StartRoom);
        if (reachable.Count != dungeon.RoomCount) return false;
        
        // 2. 最短路径检查
        int shortestPath = BFSShortestPath(dungeon, dungeon.StartRoom, dungeon.BossRoom);
        int minAcceptable = math.Max(3, (int)(dungeon.RoomCount * 0.4f));
        int maxAcceptable = (int)(dungeon.RoomCount * 0.7f);
        if (shortestPath < minAcceptable || shortestPath > maxAcceptable) return false;
        
        // 3. 特殊房间保底
        foreach (var kvp in params_.SpecialRoomMin)
        {
            int actual = dungeon.CountRooms(kvp.Key);
            if (actual < kvp.Value) return false;
        }
        
        // 4. Boss房唯一且在末端
        if (dungeon.CountRooms(RoomType.BOSS) != 1) return false;
        
        return true;
    }
    
    private int CalcBSPDepth(int roomCount)
    {
        return math.CeilToInt(math.Log(roomCount, 2)) + 1;
    }
    
    private HashSet<RoomNode> BFSReachable(DungeonData dungeon, RoomNode start)
    {
        var visited = new HashSet<RoomNode>();
        var queue = new Queue<RoomNode>();
        queue.Enqueue(start);
        visited.Add(start);
        
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            foreach (var neighbor in dungeon.Graph.GetNeighbors(current))
            {
                if (visited.Add(neighbor))
                    queue.Enqueue(neighbor);
            }
        }
        
        return visited;
    }
    
    private int BFSShortestPath(DungeonData dungeon, RoomNode start, RoomNode end)
    {
        var visited = new HashSet<RoomNode> { start };
        var queue = new Queue<(RoomNode node, int dist)>();
        queue.Enqueue((start, 0));
        
        while (queue.Count > 0)
        {
            var (current, dist) = queue.Dequeue();
            if (current == end) return dist;
            
            foreach (var neighbor in dungeon.Graph.GetNeighbors(current))
            {
                if (visited.Add(neighbor))
                    queue.Enqueue((neighbor, dist + 1));
            }
        }
        
        return int.MaxValue;
    }
}
```

---

## 5.2 种子系统

### 5.2.1 SeededRNG 确定性随机

```text
public class SeededRNG
{
    private ulong _state0;
    private ulong _state1;
    
    public SeededRNG(int seed)
    {
        _state0 = (ulong)seed;
        _state1 = (ulong)seed ^ 0xDEADBEEFDEADBEEF;
        // 预热：丢弃前10个值
        for (int i = 0; i < 10; i++) Next();
    }
    
    /// <summary>
    /// xorshift128+ 核心
    /// </summary>
    private ulong Next()
    {
        ulong s1 = _state0;
        ulong s0 = _state1;
        ulong result = s0 + s1;
        _state0 = s0;
        s1 ^= s1 << 23;
        _state1 = s1 ^ s0 ^ (s1 >> 18) ^ (s0 >> 5);
        return result & 0x7FFFFFFFFFFFFFFF;
    }
    
    /// <summary>
    /// 种子派生：用于从全局种子派生层/房间/内容种子
    /// </summary>
    public static int DeriveSeed(int parentSeed, int index)
    {
        // 使用FNV-1a哈希
        unchecked
        {
            uint hash = 2166136261u;
            byte[] bytes = System.BitConverter.GetBytes(parentSeed * 31 + index * 17);
            foreach (byte b in bytes)
            {
                hash ^= b;
                hash *= 16777619u;
            }
            return (int)hash;
        }
    }
    
    /// <summary>
    /// [min, max] 范围整数
    /// </summary>
    public int IntRange(int min, int max)
    {
        if (min >= max) return min;
        return min + (int)(Next() % (ulong)(max - min + 1));
    }
    
    /// <summary>
    /// [min, max) 范围浮点
    /// </summary>
    public float FloatRange(float min, float max)
    {
        return min + (float)(Next() / (double)ulong.MaxValue) * (max - min);
    }
    
    /// <summary>
    /// 概率判定
    /// </summary>
    public bool Chance(float probability)
    {
        return FloatRange(0f, 1f) < probability;
    }
    
    /// <summary>
    /// 从列表中随机选择
    /// </summary>
    public T Choice<T>(IList<T> list)
    {
        if (list.Count == 0) throw new System.ArgumentException("List is empty");
        return list[IntRange(0, list.Count - 1)];
    }
    
    /// <summary>
    /// 加权随机选择
    /// </summary>
    public T WeightedChoice<T>(IList<(T item, float weight)> weightedList)
    {
        float total = 0f;
        foreach (var (_, w) in weightedList) total += w;
        
        float roll = FloatRange(0f, total);
        float cumulative = 0f;
        foreach (var (item, weight) in weightedList)
        {
            cumulative += weight;
            if (roll < cumulative) return item;
        }
        return weightedList[weightedList.Count - 1].item;
    }
    
    /// <summary>
    /// Fisher-Yates洗牌
    /// </summary>
    public void Shuffle<T>(IList<T> list)
    {
        for (int i = list.Count - 1; i > 0; i--)
        {
            int j = IntRange(0, i);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }
    
    /// <summary>
    /// 不重复采样
    /// </summary>
    public List<T> Sample<T>(IList<T> source, int count)
    {
        var shuffled = new List<T>(source);
        Shuffle(shuffled);
        return shuffled.GetRange(0, math.Min(count, shuffled.Count));
    }
}
```

---

## 5.3 图论拓扑生成

### 5.3.1 DungeonGraphGenerator

```text
public class DungeonGraphGenerator
{
    public RoomGraph Generate(SeededRNG rng, FloorParams floorParams, int floorIndex)
    {
        int roomCount = rng.IntRange(floorParams.RoomCountMin, floorParams.RoomCountMax);
        float branchRate = floorParams.BranchRate;
        
        var graph = new RoomGraph();
        
        // 创建起点和Boss
        var startNode = graph.AddRoom(RoomType.START, 0);
        var bossNode = graph.AddRoom(RoomType.BOSS, roomCount - 1);
        
        // 主路径长度
        int mainPathLen = math.Max(3, (int)(roomCount * (1f - branchRate)));
        
        // 创建主路径
        var prev = startNode;
        var mainPathNodes = new List<RoomNode> { startNode };
        
        for (int i = 1; i < mainPathLen - 1; i++)
        {
            RoomType type = (i % 3 == 0) ? RoomType.ELITE : RoomType.COMBAT;
            var node = graph.AddRoom(type, graph.NextId());
            graph.AddEdge(prev, node);
            mainPathNodes.Add(node);
            prev = node;
        }
        
        graph.AddEdge(prev, bossNode);
        mainPathNodes.Add(bossNode);
        
        // 生成分支
        int remaining = roomCount - mainPathLen;
        int branchCount = 0;
        var mainNodesForBranch = mainPathNodes
            .Skip(1)    // 不从起点分出
            .Take(mainPathNodes.Count - 2) // 不从Boss分出
            .ToList();
        
        rng.Shuffle(mainNodesForBranch);
        
        while (remaining > 0 && branchCount < mainPathNodes.Count - 2)
        {
            var anchor = mainNodesForBranch[branchCount % mainNodesForBranch.Count];
            int branchLen = math.Min(rng.IntRange(1, 3), remaining);
            
            var prevBranch = anchor;
            for (int j = 0; j < branchLen; j++)
            {
                var branchType = PickBranchRoomType(rng, floorParams, graph, floorIndex);
                var node = graph.AddRoom(branchType, graph.NextId());
                graph.AddEdge(prevBranch, node);
                prevBranch = node;
                remaining--;
            }
            branchCount++;
        }
        
        // 保底特殊房间
        EnsureSpecialRooms(rng, graph, floorParams);
        
        // 休息房放置在Boss前2-3个位置
        EnsureRestBeforeBoss(graph, floorIndex);
        
        return graph;
    }
    
    private RoomType PickBranchRoomType(SeededRNG rng, FloorParams params_, RoomGraph graph, int floorIndex)
    {
        // 分支末端倾向宝藏/事件
        var typeWeights = new List<(RoomType type, float weight)>
        {
            (RoomType.COMBAT, 40f),
            (RoomType.TREASURE, 25f),
            (RoomType.EVENT, 20f),
            (RoomType.ELITE, 10f),
            (RoomType.SHOP, 5f),
        };
        
        return rng.WeightedChoice(typeWeights);
    }
    
    private void EnsureSpecialRooms(SeededRNG rng, RoomGraph graph, FloorParams params_)
    {
        foreach (var kvp in params_.SpecialRoomMin)
        {
            RoomType type = kvp.Key;
            int minCount = kvp.Value;
            int currentCount = graph.CountRooms(type);
            
            while (currentCount < minCount)
            {
                // 找一个普通战斗房替换
                var combatRooms = graph.GetRoomsOfType(RoomType.COMBAT);
                if (combatRooms.Count > 0)
                {
                    var target = rng.Choice(combatRooms);
                    target.Type = type;
                    currentCount++;
                }
                else
                {
                    break; // 无法替换，放弃
                }
            }
        }
    }
    
    private void EnsureRestBeforeBoss(RoomGraph graph, int floorIndex)
    {
        if (floorIndex == 5) return; // 层5无休息房
        
        if (graph.CountRooms(RoomType.REST) > 0) return; // 已有
        
        var boss = graph.GetRoomsOfType(RoomType.BOSS).FirstOrDefault();
        if (boss == null) return;
        
        // BFS从Boss回溯2-3步
        var pathToStart = graph.FindPathTo(graph.GetRoomsOfType(RoomType.START).First(), boss);
        if (pathToStart != null && pathToStart.Count >= 3)
        {
            int restIndex = math.Max(1, pathToStart.Count - 3);
            if (pathToStart[restIndex].Type == RoomType.COMBAT)
            {
                pathToStart[restIndex].Type = RoomType.REST;
            }
        }
    }
}
```

### 5.3.2 RoomGraph数据结构

```text
public class RoomGraph
{
    private readonly List<RoomNode> _nodes = new();
    private readonly List<RoomEdge> _edges = new();
    private readonly Dictionary<int, List<int>> _adjacency = new();
    private int _nextId = 0;
    
    public IReadOnlyList<RoomNode> Nodes => _nodes;
    public IReadOnlyList<RoomEdge> Edges => _edges;
    public int RoomCount => _nodes.Count;
    
    public RoomNode AddRoom(RoomType type, int? id = null)
    {
        int nodeId = id ?? _nextId++;
        var node = new RoomNode(nodeId, type);
        _nodes.Add(node);
        _adjacency[nodeId] = new List<int>();
        if (id.HasValue) _nextId = math.Max(_nextId, id.Value + 1);
        return node;
    }
    
    public void AddEdge(RoomNode a, RoomNode b)
    {
        _edges.Add(new RoomEdge(a.Id, b.Id));
        _adjacency[a.Id].Add(b.Id);
        _adjacency[b.Id].Add(a.Id);
    }
    
    public int NextId() => _nextId++;
    
    public IEnumerable<RoomNode> GetNeighbors(RoomNode node)
    {
        foreach (var neighborId in _adjacency[node.Id])
        {
            yield return _nodes.First(n => n.Id == neighborId);
        }
    }
    
    public List<RoomNode> GetRoomsOfType(RoomType type)
    {
        return _nodes.Where(n => n.Type == type).ToList();
    }
    
    public int CountRooms(RoomType type)
    {
        return _nodes.Count(n => n.Type == type);
    }
    
    public List<RoomNode> FindPathTo(RoomNode from, RoomNode to)
    {
        var visited = new HashSet<int> { from.Id };
        var queue = new Queue<(RoomNode node, List<RoomNode> path)>();
        queue.Enqueue((from, new List<RoomNode> { from }));
        
        while (queue.Count > 0)
        {
            var (current, path) = queue.Dequeue();
            if (current == to) return path;
            
            foreach (var neighbor in GetNeighbors(current))
            {
                if (visited.Add(neighbor.Id))
                {
                    var newPath = new List<RoomNode>(path) { neighbor };
                    queue.Enqueue((neighbor, newPath));
                }
            }
        }
        
        return null;
    }
}

public class RoomNode
{
    public int Id { get; }
    public RoomType Type { get; set; }
    public Vector2Int GridPosition { get; set; }
    public Rect RoomRect { get; set; }
    
    public RoomNode(int id, RoomType type) { Id = id; Type = type; }
}

public readonly struct RoomEdge
{
    public readonly int A;
    public readonly int B;
    public RoomEdge(int a, int b) => (A, B) = (a, b);
}

public enum RoomType { START, COMBAT, ELITE, TREASURE, SHOP, EVENT, REST, BOSS }
```

### 5.3.3 FloorParams 层参数

```text
public class FloorParams
{
    public int RoomCountMin { get; }
    public int RoomCountMax { get; }
    public float BranchRate { get; }
    public Dictionary<RoomType, int> SpecialRoomMin { get; }
    
    private static readonly FloorParams[] FLOORS = {
        new(8, 10, 0.3f, new() { { RoomType.SHOP, 1 }, { RoomType.TREASURE, 1 }, { RoomType.EVENT, 1 }, { RoomType.REST, 1 } }),
        new(9, 11, 0.35f, new() { { RoomType.SHOP, 1 }, { RoomType.TREASURE, 1 }, { RoomType.EVENT, 1 }, { RoomType.REST, 1 } }),
        new(10, 12, 0.4f, new() { { RoomType.SHOP, 1 }, { RoomType.TREASURE, 1 }, { RoomType.EVENT, 2 }, { RoomType.REST, 1 } }),
        new(10, 13, 0.45f, new() { { RoomType.SHOP, 1 }, { RoomType.TREASURE, 2 }, { RoomType.EVENT, 1 }, { RoomType.REST, 1 } }),
        new(8, 10, 0.2f, new() { { RoomType.SHOP, 1 }, { RoomType.TREASURE, 1 }, { RoomType.EVENT, 1 }, { RoomType.REST, 0 } }),
    };
    
    public static FloorParams Get(int floorIndex) => FLOORS[math.Clamp(floorIndex - 1, 0, 4)];
    
    private FloorParams(int min, int max, float branch, Dictionary<RoomType, int> special)
    {
        RoomCountMin = min; RoomCountMax = max; BranchRate = branch; SpecialRoomMin = special;
    }
}
```

---

## 5.4 BSP分区算法

### 5.4.1 BSPPartitioner

```text
public class BSPPartitioner
{
    private const float MIN_ROOM_AREA = 12f * 12f; // 最小房间面积
    
    public BSPNode Partition(SeededRNG rng, Rect area, int depth, int maxDepth)
    {
        var node = new BSPNode(area);
        
        if (depth >= maxDepth || area.width * area.height < MIN_ROOM_AREA * 2f)
        {
            return node; // 叶节点
        }
        
        // 选择分割方向
        SplitDirection dir;
        if (area.width > area.height * 1.25f)
            dir = SplitDirection.VERTICAL;
        else if (area.height > area.width * 1.25f)
            dir = SplitDirection.HORIZONTAL;
        else
            dir = rng.Chance(0.5f) ? SplitDirection.VERTICAL : SplitDirection.HORIZONTAL;
        
        // 分割比例 [0.35, 0.65]
        float splitRatio = rng.FloatRange(0.35f, 0.65f);
        
        Rect rectA, rectB;
        if (dir == SplitDirection.VERTICAL)
        {
            float splitX = area.x + area.width * splitRatio;
            rectA = new Rect(area.x, area.y, splitX - area.x, area.height);
            rectB = new Rect(splitX, area.y, area.xMax - splitX, area.height);
        }
        else
        {
            float splitY = area.y + area.height * splitRatio;
            rectA = new Rect(area.x, area.y, area.width, splitY - area.y);
            rectB = new Rect(area.x, splitY, area.width, area.yMax - splitY);
        }
        
        node.Left = Partition(rng, rectA, depth + 1, maxDepth);
        node.Right = Partition(rng, rectB, depth + 1, maxDepth);
        
        return node;
    }
}

public enum SplitDirection { VERTICAL, HORIZONTAL }

public class BSPNode
{
    public Rect Area { get; }
    public BSPNode Left { get; set; }
    public BSPNode Right { get; set; }
    public bool IsLeaf => Left == null && Right == null;
    
    public BSPNode(Rect area) => Area = area;
    
    public List<BSPNode> GetLeaves()
    {
        var leaves = new List<BSPNode>();
        CollectLeaves(this, leaves);
        return leaves;
    }
    
    private static void CollectLeaves(BSPNode node, List<BSPNode> leaves)
    {
        if (node.IsLeaf)
        {
            leaves.Add(node);
        }
        else
        {
            if (node.Left != null) CollectLeaves(node.Left, leaves);
            if (node.Right != null) CollectLeaves(node.Right, leaves);
        }
    }
}
```

### 5.4.2 RoomPlacer

```text
public class RoomPlacer
{
    private const int MARGIN = 2; // 房间与分区边缘的最小间距
    
    public Dictionary<int, Rect> Place(SeededRNG rng, BSPNode bspRoot, RoomGraph graph)
    {
        var leaves = bspRoot.GetLeaves();
        rng.Shuffle(leaves);
        
        var roomRects = new Dictionary<int, Rect>();
        var nodes = graph.Nodes.ToList();
        
        // 排序：起点靠左下，Boss靠右上
        var startNode = nodes.First(n => n.Type == RoomType.START);
        var bossNode = nodes.First(n => n.Type == RoomType.BOSS);
        var otherNodes = nodes.Where(n => n != startNode && n != bossNode).ToList();
        rng.Shuffle(otherNodes);
        
        var orderedNodes = new List<RoomNode> { startNode };
        orderedNodes.AddRange(otherNodes);
        orderedNodes.Add(bossNode);
        
        // 按叶节点面积排序（大房间给Boss/精英）
        var sortedLeaves = leaves.OrderBy(l => l.Area.width * l.Area.height).ToList();
        
        for (int i = 0; i < math.Min(orderedNodes.Count, sortedLeaves.Count); i++)
        {
            var node = orderedNodes[i];
            var leaf = sortedLeaves[i];
            
            var roomSize = GetRoomSize(rng, node.Type, leaf.Area);
            float roomX = leaf.Area.x + rng.IntRange(MARGIN, 
                math.Max(MARGIN, (int)(leaf.Area.width - roomSize.x - MARGIN)));
            float roomY = leaf.Area.y + rng.IntRange(MARGIN, 
                math.Max(MARGIN, (int)(leaf.Area.height - roomSize.y - MARGIN)));
            
            var rect = new Rect(roomX, roomY, roomSize.x, roomSize.y);
            node.RoomRect = rect;
            roomRects[node.Id] = rect;
        }
        
        // 起点映射到最左下，Boss映射到最右上
        if (roomRects.ContainsKey(startNode.Id) && roomRects.ContainsKey(bossNode.Id))
        {
            var startRect = roomRects[startNode.Id];
            var bossRect = roomRects[bossNode.Id];
            
            // 如果起点的x+y > Boss的x+y，交换矩形
            if (startRect.center.x + startRect.center.y > bossRect.center.x + bossRect.center.y)
            {
                var temp = startNode.RoomRect;
                startNode.RoomRect = bossNode.RoomRect;
                bossNode.RoomRect = temp;
                roomRects[startNode.Id] = startNode.RoomRect;
                roomRects[bossNode.Id] = bossNode.RoomRect;
            }
        }
        
        return roomRects;
    }
    
    private Vector2 GetRoomSize(SeededRNG rng, RoomType type, Rect leafArea)
    {
        var sizeRange = RoomSizeConstants.GetSizeRange(type);
        
        float width = rng.IntRange(
            math.Max(sizeRange.minW, (int)leafArea.width - 2 * MARGIN),
            math.Min(sizeRange.maxW, (int)leafArea.width - MARGIN));
        
        float height = rng.IntRange(
            math.Max(sizeRange.minH, (int)leafArea.height - 2 * MARGIN),
            math.Min(sizeRange.maxH, (int)leafArea.height - MARGIN));
        
        return new Vector2(width, height);
    }
}

public static class RoomSizeConstants
{
    public static (int minW, int minH, int maxW, int maxH) GetSizeRange(RoomType type) => type switch
    {
        RoomType.COMBAT => (12, 12, 20, 20),
        RoomType.ELITE => (16, 16, 22, 22),
        RoomType.BOSS => (24, 24, 32, 32),
        RoomType.TREASURE => (10, 10, 14, 14),
        RoomType.SHOP => (10, 10, 14, 12),
        RoomType.EVENT => (10, 10, 16, 14),
        RoomType.REST => (10, 10, 14, 12),
        RoomType.START => (10, 10, 14, 14),
        _ => (12, 12, 18, 18)
    };
}
```

---

## 5.5 走廊连接算法

### 5.5.1 CorridorBuilder

```text
public class CorridorBuilder
{
    public List<Corridor> Build(SeededRNG rng, RoomGraph graph, 
        Dictionary<int, Rect> roomRects, int floorIndex)
    {
        var corridors = new List<Corridor>();
        var edges = graph.Edges.ToList();
        
        // === 第一步：基于MST确保所有房间连通 ===
        var mstEdges = KruskalMST(edges, roomRects);
        
        // === 第二步：额外添加边增加多路径 ===
        var extraEdges = edges.Except(mstEdges).ToList();
        int extraCount = math.CeilToInt(mstEdges.Count * 0.15f); // 额外15%的边
        rng.Shuffle(extraEdges);
        
        var finalEdges = new List<RoomEdge>(mstEdges);
        for (int i = 0; i < math.Min(extraCount, extraEdges.Count); i++)
        {
            finalEdges.Add(extraEdges[i]);
        }
        
        // === 第三步：为每条边生成走廊 ===
        int corridorWidth = floorIndex >= 4 ? 3 : 2;
        
        foreach (var edge in finalEdges)
        {
            var rectA = roomRects[edge.A];
            var rectB = roomRects[edge.B];
            
            var (doorA, doorB) = FindClosestDoors(rectA, rectB);
            
            // L型走廊
            if (rng.Chance(0.5f))
            {
                // 先水平后垂直
                var mid = new Vector2(doorB.x, doorA.y);
                corridors.Add(new Corridor(doorA, mid, corridorWidth, SplitDirection.HORIZONTAL));
                corridors.Add(new Corridor(mid, doorB, corridorWidth, SplitDirection.VERTICAL));
            }
            else
            {
                // 先垂直后水平
                var mid = new Vector2(doorA.x, doorB.y);
                corridors.Add(new Corridor(doorA, mid, corridorWidth, SplitDirection.VERTICAL));
                corridors.Add(new Corridor(mid, doorB, corridorWidth, SplitDirection.HORIZONTAL));
            }
        }
        
        return corridors;
    }
    
    /// <summary>
    /// Kruskal最小生成树
    /// </summary>
    private List<RoomEdge> KruskalMST(List<RoomEdge> edges, Dictionary<int, Rect> roomRects)
    {
        var sorted = edges
            .OrderBy(e => RectDistance(roomRects[e.A], roomRects[e.B]))
            .ToList();
        
        var parent = new Dictionary<int, int>();
        foreach (var key in roomRects.Keys) parent[key] = key;
        
        int Find(int x) => parent[x] == x ? x : parent[x] = Find(parent[x]);
        void Union(int a, int b) => parent[Find(a)] = Find(b);
        
        var mst = new List<RoomEdge>();
        foreach (var edge in sorted)
        {
            if (Find(edge.A) != Find(edge.B))
            {
                mst.Add(edge);
                Union(edge.A, edge.B);
                if (mst.Count == roomRects.Count - 1) break;
            }
        }
        
        return mst;
    }
    
    private (Vector2 doorA, Vector2 doorB) FindClosestDoors(Rect rectA, Rect rectB)
    {
        // 找两房间最近的边界点
        float ax = math.Clamp(rectB.center.x, rectA.xMin, rectA.xMax);
        float ay = math.Clamp(rectB.center.y, rectA.yMin, rectA.yMax);
        float bx = math.Clamp(rectA.center.x, rectB.xMin, rectB.xMax);
        float by = math.Clamp(rectA.center.y, rectB.yMin, rectB.yMax);
        
        return (new Vector2(ax, ay), new Vector2(bx, by));
    }
    
    private float RectDistance(Rect a, Rect b)
    {
        float dx = math.Max(0, math.Abs(a.center.x - b.center.x) - (a.width + b.width) / 2);
        float dy = math.Max(0, math.Abs(a.center.y - b.center.y) - (a.height + b.height) / 2);
        return math.Sqrt(dx * dx + dy * dy);
    }
}

public class Corridor
{
    public Vector2 Start { get; }
    public Vector2 End { get; }
    public int Width { get; }
    public SplitDirection Direction { get; }
    
    public Corridor(Vector2 start, Vector2 end, int width, SplitDirection dir)
        => (Start, End, Width, Direction) = (start, end, width, dir);
}
```

---

## 5.6 房间实例化

### 5.6.1 RoomInstantiator

```text
public class RoomInstantiator
{
    private readonly RoomTemplateDatabase _templateDB;
    
    public RoomInstantiator(RoomTemplateDatabase templateDB)
    {
        _templateDB = templateDB;
    }
    
    public void Instantiate(RoomGraph graph, Dictionary<int, Rect> roomRects, 
        int floorIndex, DungeonData dungeon)
    {
        foreach (var node in graph.Nodes)
        {
            if (!roomRects.TryGetValue(node.Id, out var rect)) continue;
            
            var room = new RoomController
            {
                RoomId = node.Id,
                RoomType = node.Type,
                RoomRect = rect,
                FloorIndex = floorIndex
            };
            
            // 选择模板
            var template = SelectTemplate(node.Type, floorIndex, rect);
            room.Template = template;
            
            // 创建Node
            var roomGO = new Node($"Room_{node.Id}_{node.Type}");
            roomGO.transform.SetParent(dungeon.transform);
            roomGO.transform.position = new Vector3(rect.center.x, 0, rect.center.y);
            room.Node = roomGO;
            
            // 实例化模板内容
            if (template != null)
            {
                InstantiateTemplateContent(roomGO, template, floorIndex);
            }
            
            // 创建门
            CreateDoors(room, graph, node);
            
            dungeon.Rooms.Add(room);
        }
    }
    
    private RoomTemplateData SelectTemplate(RoomType type, int floorIndex, Rect rect)
    {
        var candidates = _templateDB.GetTemplates(type, floorIndex)
            .Where(t => t.Width <= rect.width && t.Height <= rect.height)
            .ToList();
        
        if (candidates.Count == 0)
        {
            // 无合适模板，使用默认
            return _templateDB.GetDefaultTemplate(type);
        }
        
        // 简单随机选择（可替换为加权）
        return candidates[Godot.Random.Range(0, candidates.Count)];
    }
    
    private void InstantiateTemplateContent(Node roomGO, RoomTemplateData template, int floorIndex)
    {
        // 墙壁
        foreach (var wall in template.Walls)
        {
            var wallGO = Node.CreatePrimitive(PrimitiveType.Cube);
            wallGO.transform.SetParent(roomGO.transform);
            wallGO.transform.localPosition = new Vector3(wall.x, 1f, wall.y);
            wallGO.transform.localScale = new Vector3(wall.width, 2f, wall.height);
            wallGO.GetComponent<Renderer>().material = GetFloorMaterial(floorIndex);
        }
        
        // 灯光
        foreach (var light in template.Lights)
        {
            var lightObj = new Node("Light");
            lightObj.transform.SetParent(roomGO.transform);
            lightObj.transform.localPosition = new Vector3(light.x, 3f, light.y);
            var pointLight = lightObj.AddComponent<Light>();
            pointLight.type = LightType.Point;
            pointLight.color = light.color;
            pointLight.intensity = light.intensity;
            pointLight.range = light.range;
        }
        
        // 敌人生成点标记
        foreach (var spawnPoint in template.EnemySpawnPoints)
        {
            var marker = new Node($"SpawnPoint_{spawnPoint.id}");
            marker.transform.SetParent(roomGO.transform);
            marker.transform.localPosition = new Vector3(spawnPoint.x, 0, spawnPoint.y);
            marker.AddComponent<EnemySpawnMarker>().Initialize(spawnPoint.id, spawnPoint.delay);
        }
    }
    
    private void CreateDoors(RoomController room, RoomGraph graph, RoomNode node)
    {
        foreach (var neighbor in graph.GetNeighbors(node))
        {
            var door = new DoorData
            {
                ConnectedRoomId = neighbor.Id,
                IsOpen = false, // 战斗房门默认关闭
                Position = CalculateDoorPosition(room.RoomRect, neighbor.RoomRect)
            };
            room.Doors.Add(door);
        }
    }
    
    private Vector3 CalculateDoorPosition(Rect fromRect, Rect toRect)
    {
        // 朝向邻居房间方向的边界中点
        Vector2 dir = (toRect.center - fromRect.center).normalized;
        float angle = math.Atan2(dir.y, dir.x);
        
        if (math.Abs(angle) < math.PI / 4) // 右
            return new Vector3(fromRect.xMax, 0, fromRect.center.y);
        if (math.Abs(angle) > 3 * math.PI / 4) // 左
            return new Vector3(fromRect.xMin, 0, fromRect.center.y);
        if (angle > 0) // 上
            return new Vector3(fromRect.center.x, 0, fromRect.yMax);
        // 下
        return new Vector3(fromRect.center.x, 0, fromRect.yMin);
    }
    
    private Material GetFloorMaterial(int floorIndex)
    {
        // 根据楼层主题返回对应材质
        // 实际由ResourceLoader加载
        return null;
    }
}
```

### 5.6.2 RoomController

```text
public class RoomController
{
    public int RoomId { get; set; }
    public RoomType RoomType { get; set; }
    public Rect RoomRect { get; set; }
    public int FloorIndex { get; set; }
    public RoomTemplateData Template { get; set; }
    public Node Node { get; set; }
    public List<DoorData> Doors { get; } = new();
    public List<WaveData> Waves { get; set; } = new();
    public bool IsCleared { get; set; }
    public bool IsExplored { get; set; }
    public RoomReward Reward { get; set; }
}

public class DoorData
{
    public int ConnectedRoomId { get; set; }
    public bool IsOpen { get; set; }
    public Vector3 Position { get; set; }
}

public class WaveData
{
    public List<EnemySpawnData> Enemies { get; } = new();
    public bool IsSpawned { get; set; }
    public bool IsCleared { get; set; }
}

public class EnemySpawnMarker : Node
{
    public int SpawnId { get; private set; }
    public float SpawnDelay { get; private set; }
    
    public void Initialize(int id, float delay)
    {
        SpawnId = id;
        SpawnDelay = delay;
    }
}
```

---

## 5.7 房间内容生成

### 5.7.1 RoomContentGenerator

```text
public class RoomContentGenerator
{
    private readonly EnemyDatabase _enemyDB;
    
    // 基础参数
    private static readonly int[] COMBAT_BASE_COUNT = { 3, 4, 5, 5, 4 };
    private static readonly int[] ENEMY_BASE_HP = { 30, 50, 75, 110, 150 };
    private static readonly int[] ENEMY_BASE_ATK = { 8, 12, 18, 25, 35 };
    
    // 波次概率表
    private static readonly float[,] WAVE_TABLE = {
        { 0.70f, 0.30f, 0.00f }, // 层1
        { 0.50f, 0.40f, 0.10f }, // 层2
        { 0.30f, 0.45f, 0.25f }, // 层3
        { 0.20f, 0.50f, 0.30f }, // 层4
        { 0.25f, 0.45f, 0.30f }, // 层5
    };
    
    public RoomContentGenerator(EnemyDatabase enemyDB)
    {
        _enemyDB = enemyDB;
    }
    
    public void Populate(SeededRNG rng, RoomController room, int floorIndex)
    {
        switch (room.RoomType)
        {
            case RoomType.COMBAT:
                PopulateCombat(rng, room, floorIndex);
                break;
            case RoomType.ELITE:
                PopulateElite(rng, room, floorIndex);
                break;
            case RoomType.BOSS:
                PopulateBoss(rng, room, floorIndex);
                break;
            case RoomType.TREASURE:
                PopulateTreasure(rng, room, floorIndex);
                break;
            // SHOP/EVENT/REST 由模板交互定义，无需额外生成
        }
    }
    
    private void PopulateCombat(SeededRNG rng, RoomController room, int floorIndex)
    {
        int idx = math.Clamp(floorIndex - 1, 0, 4);
        
        // 确定敌人数量
        int baseCount = COMBAT_BASE_COUNT[idx];
        int variance = rng.IntRange(-1, 2);
        int enemyCount = math.Max(2, baseCount + variance);
        
        // 确定敌人组合
        var enemies = new List<EnemySpawnData>();
        var enemyPool = _enemyDB.GetPool(floorIndex);
        
        for (int i = 0; i < enemyCount; i++)
        {
            var enemyType = rng.WeightedChoice(enemyPool);
            var spawnData = CreateEnemy(rng, enemyType, floorIndex);
            enemies.Add(spawnData);
        }
        
        // 确定波次数
        int waveCount = DetermineWaveCount(rng, floorIndex);
        room.Waves = SplitIntoWaves(rng, enemies, waveCount);
    }
    
    private void PopulateElite(SeededRNG rng, RoomController room, int floorIndex)
    {
        var waves = new List<WaveData>();
        
        // 第一波：精英 + 小怪
        var wave1 = new WaveData();
        wave1.Enemies.Add(CreateEnemy(rng, EnemyType.ELITE, floorIndex));
        
        int minionCount = rng.IntRange(2, 4);
        for (int i = 0; i < minionCount; i++)
        {
            wave1.Enemies.Add(CreateEnemy(rng, EnemyType.NORMAL, floorIndex));
        }
        waves.Add(wave1);
        
        // 部分精英房有第二波
        if (rng.Chance(0.4f))
        {
            var wave2 = new WaveData();
            int wave2Count = rng.IntRange(2, 3);
            for (int i = 0; i < wave2Count; i++)
            {
                wave2.Enemies.Add(CreateEnemy(rng, rng.Choice(new[] { EnemyType.NORMAL, EnemyType.FAST }), floorIndex));
            }
            waves.Add(wave2);
        }
        
        room.Waves = waves;
    }
    
    private void PopulateBoss(SeededRNG rng, RoomController room, int floorIndex)
    {
        var bossData = BossStats.Get(floorIndex);
        var wave = new WaveData();
        wave.Enemies.Add(new EnemySpawnData
        {
            EnemyId = bossData.enemyId,
            Type = EnemyType.ELITE,
            Hp = bossData.hp,
            Atk = bossData.atk,
            SpawnDelay = bossData.spawnDelay,
            Position = new Vector3(room.RoomRect.center.x, 0, room.RoomRect.yMax - 4)
        });
        room.Waves = new List<WaveData> { wave };
    }
    
    private void PopulateTreasure(SeededRNG rng, RoomController room, int floorIndex)
    {
        // 宝藏房奖励由ItemPool系统生成
        room.Reward = new RoomReward
        {
            Gold = math.RoundToInt(new[] { 50, 70, 90, 120, 150 }[floorIndex - 1] * rng.FloatRange(0.9f, 1.1f)),
            HasItemChoice = true,
            ChoiceCount = 3
        };
    }
    
    private int DetermineWaveCount(SeededRNG rng, int floorIndex)
    {
        int idx = math.Clamp(floorIndex - 1, 0, 4);
        float roll = rng.FloatRange(0f, 1f);
        
        float cumulative = 0f;
        for (int w = 0; w < 3; w++)
        {
            cumulative += WAVE_TABLE[idx, w];
            if (roll < cumulative) return w + 1;
        }
        return 1;
    }
    
    private List<WaveData> SplitIntoWaves(SeededRNG rng, List<EnemySpawnData> enemies, int waveCount)
    {
        if (waveCount == 1)
        {
            return new List<WaveData> { new WaveData { Enemies = enemies } };
        }
        
        rng.Shuffle(enemies);
        
        int firstWaveSize = math.Max(2, (int)(enemies.Count * 0.4f));
        var waves = new List<WaveData>();
        
        // 第一波
        waves.Add(new WaveData { Enemies = enemies.GetRange(0, firstWaveSize) });
        
        var remaining = enemies.Skip(firstWaveSize).ToList();
        int perWave = remaining.Count / (waveCount - 1);
        
        for (int w = 1; w < waveCount; w++)
        {
            int start = (w - 1) * perWave;
            int end = w < waveCount - 1 ? start + perWave : remaining.Count;
            waves.Add(new WaveData { Enemies = remaining.GetRange(start, end - start) });
        }
        
        return waves;
    }
    
    private EnemySpawnData CreateEnemy(SeededRNG rng, EnemyType type, int floorIndex)
    {
        int idx = math.Clamp(floorIndex - 1, 0, 4);
        
        float hpVariance = rng.FloatRange(0.85f, 1.15f);
        float atkVariance = rng.FloatRange(0.85f, 1.15f);
        
        var typeMultipliers = GetTypeMultipliers(type);
        
        return new EnemySpawnData
        {
            Type = type,
            Hp = math.RoundToInt(ENEMY_BASE_HP[idx] * hpVariance * typeMultipliers.hpMult),
            Atk = math.RoundToInt(ENEMY_BASE_ATK[idx] * atkVariance * typeMultipliers.atkMult),
            Speed = typeMultipliers.speed,
            EnemyId = _enemyDB.GetRandomEnemyId(type, floorIndex),
            SpawnDelay = rng.FloatRange(0f, 2f)
        };
    }
    
    private (float hpMult, float atkMult, float speed) GetTypeMultipliers(EnemyType type) => type switch
    {
        EnemyType.NORMAL => (1.0f, 1.0f, 1.0f),
        EnemyType.FAST => (0.7f, 0.8f, 1.5f),
        EnemyType.RANGED => (0.6f, 1.3f, 0.8f),
        EnemyType.TANK => (2.0f, 0.7f, 0.7f),
        EnemyType.ELITE => (3.5f, 1.5f, 1.0f),
        _ => (1.0f, 1.0f, 1.0f)
    };
}

public enum EnemyType { NORMAL, FAST, RANGED, TANK, ELITE }

[Serializable]
public class EnemySpawnData
{
    public string EnemyId;
    public EnemyType Type;
    public int Hp;
    public int Atk;
    public float Speed = 1f;
    public float SpawnDelay;
    public Vector3 Position;
}

public static class BossStats
{
    public static (string enemyId, int hp, int atk, float spawnDelay) Get(int floor) => floor switch
    {
        1 => ("boss_ruins_king", 800, 35, 2f),
        2 => ("boss_void_tree_mother", 1200, 45, 1.5f),
        3 => ("boss_time_lord", 1600, 55, 1f),
        4 => ("boss_forge_heart", 2200, 70, 1.5f),
        5 => ("boss_void_king", 3000, 90, 3f),
        _ => ("boss_default", 800, 35, 2f)
    };
}
```

---

## 5.8 事件房系统

### 5.8.1 EventManager

```text
public class EventManager
{
    private readonly EventDatabase _eventDB;
    private readonly HashSet<string> _seenEvents = new();
    
    public EventManager(EventDatabase eventDB)
    {
        _eventDB = eventDB;
    }
    
    /// <summary>
    /// 生成事件房内容
    /// </summary>
    public EventData SelectEvent(SeededRNG rng, int floorIndex, PlayerState playerState)
    {
        // 优先检查特殊事件
        var specialEvent = CheckSpecialEvents(rng, playerState);
        if (specialEvent != null) return specialEvent;
        
        // 构建可用事件池
        var pool = new List<(EventData data, float weight)>();
        foreach (var evt in _eventDB.GetAllEvents())
        {
            if (!IsAvailable(evt, floorIndex, playerState)) continue;
            pool.Add((evt, evt.appearWeight));
        }
        
        if (pool.Count == 0) return _eventDB.GetFallbackEvent();
        
        return rng.WeightedChoice(pool);
    }
    
    private bool IsAvailable(EventData evt, int floorIndex, PlayerState state)
    {
        // 层限制
        if (floorIndex < evt.minFloor || floorIndex > evt.maxFloor) return false;
        // 不重复
        if (_seenEvents.Contains(evt.eventId)) return false;
        return true;
    }
    
    /// <summary>
    /// 处理事件选择
    /// </summary>
    public EventResult ProcessChoice(EventData evt, int choiceIndex, PlayerState playerState)
    {
        _seenEvents.Add(evt.eventId);
        
        var choice = evt.choices[choiceIndex];
        var result = new EventResult
        {
            EventId = evt.eventId,
            ChoiceIndex = choiceIndex,
            Description = choice.resultDescription
        };
        
        // 应用后果
        foreach (var effect in choice.effects)
        {
            ApplyEventEffect(effect, result, playerState);
        }
        
        // 概率后果
        if (choice.probabilisticEffects != null && choice.probabilisticEffects.Length > 0)
        {
            float roll = Godot.Random.Range(0f, 1f);
            float cumulative = 0f;
            foreach (var probEffect in choice.probabilisticEffects)
            {
                cumulative += probEffect.probability;
                if (roll < cumulative)
                {
                    foreach (var effect in probEffect.effects)
                        ApplyEventEffect(effect, result, playerState);
                    break;
                }
            }
        }
        
        EventBus.Publish(new EventRoomCompletedEvent(evt.eventId, choiceIndex));
        return result;
    }
    
    private void ApplyEventEffect(EventEffect effect, EventResult result, PlayerState state)
    {
        switch (effect.type)
        {
            case EventEffectType.HEAL:
                ServiceRegistry.Get<PlayerStats>()?.Heal(effect.value);
                result.HealAmount += effect.value;
                break;
            case EventEffectType.DAMAGE:
                ServiceRegistry.Get<PlayerStats>()?.TakeDirectDamage(effect.value, DamageType.PHYSICAL);
                result.DamageTaken += effect.value;
                break;
            case EventEffectType.GAIN_GOLD:
                var economy = ServiceRegistry.Get<PlayerEconomy>();
                economy?.EarnGold(math.RoundToInt(effect.value));
                result.GoldGained += math.RoundToInt(effect.value);
                break;
            case EventEffectType.GAIN_ITEM:
                var itemPool = ServiceRegistry.Get<ItemPool>();
                var item = itemPool?.RollSpecificItem(
                    new SeededRNG(System.DateTime.Now.Millisecond), 
                    effect.itemRarity, state.CurrentWeaponType);
                if (item != null)
                {
                    ServiceRegistry.Get<Inventory>()?.TryAddPassiveItem(item, out _);
                    result.ItemsGained.Add(item.itemId);
                }
                break;
            case EventEffectType.GAIN_BLESSING:
                ServiceRegistry.Get<BlessingManager>()?.AcquireBlessing(effect.blessingData);
                result.BlessingsGained.Add(effect.blessingData.blessingId);
                break;
            case EventEffectType.GAIN_CURSE:
                ServiceRegistry.Get<CurseManager>()?.AcceptCurse(effect.curseData);
                result.CursesGained.Add(effect.curseData.curseId);
                break;
            case EventEffectType.CONSUME_HP_PERCENT:
                float hpCost = ServiceRegistry.Get<PlayerStats>().GetStat(StatType.HP) * effect.value;
                ServiceRegistry.Get<PlayerStats>()?.TakeDirectDamage(hpCost, DamageType.PHYSICAL);
                result.DamageTaken += hpCost;
                break;
            case EventEffectType.CONSUME_TIME_FRAGMENT:
                ServiceRegistry.Get<PlayerEconomy>()?.SpendTimeFragments((int)effect.value);
                result.FragmentsSpent += (int)effect.value;
                break;
            case EventEffectType.REVEAL_MAP:
                result.MapRevealed = true;
                break;
            case EventEffectType.TRIGGER_COMBAT:
                result.TriggerCombat = true;
                result.CombatEnemyTier = (int)effect.value;
                break;
            case EventEffectType.TELEPORT_SKIP:
                result.SkipRooms = (int)effect.value;
                break;
            case EventEffectType.APPLY_DEBUFF:
                DebuffSystem.ApplyDebuff(ServiceRegistry.Get<PlayerStats>().Entity, 
                    effect.debuffId, effect.value, effect.duration);
                result.DebuffsApplied.Add(effect.debuffId);
                break;
        }
    }
    
    /// <summary>
    /// 检查特殊事件触发条件
    /// </summary>
    private EventData CheckSpecialEvents(SeededRNG rng, PlayerState state)
    {
        // S1: 虚无低语 — >=3个诅咒
        if (state.CurseCount >= 3 && rng.Chance(0.5f))
        {
            return _eventDB.GetSpecialEvent("S1");
        }
        
        // S2: 完美回溯 — 未死亡且层3+
        if (!state.HasDiedThisRun && state.CurrentFloor >= 3 && rng.Chance(0.1f))
        {
            return _eventDB.GetSpecialEvent("S2");
        }
        
        // S3: 旧日重逢 — 通关3局+，层2-4
        if (state.TotalSuccessfulRuns >= 3 && state.CurrentFloor >= 2 && state.CurrentFloor <= 4 && rng.Chance(0.05f))
        {
            return _eventDB.GetSpecialEvent("S3");
        }
        
        return null;
    }
}

// ===== 事件数据结构 =====

[CreateAssetMenu(fileName = "EventData_", menuName = "PlaneWalker/EventData")]
public class EventData : Resource
{
    public string eventId;
    public string description;
    public int minFloor;
    public int maxFloor;
    public float appearWeight;
    public EventChoice[] choices;
}

[Serializable]
public class EventChoice
{
    public string description;
    public string resultDescription;
    public EventEffect[] effects;
    public ProbabilisticEffect[] probabilisticEffects;
}

[Serializable]
public class EventEffect
{
    public EventEffectType type;
    public float value;
    public ItemRarity itemRarity;
    public BlessingData blessingData;
    public CurseData curseData;
    public string debuffId;
    public float duration;
}

public enum EventEffectType
{
    HEAL, DAMAGE, GAIN_GOLD, GAIN_ITEM, GAIN_BLESSING, GAIN_CURSE,
    CONSUME_HP_PERCENT, CONSUME_TIME_FRAGMENT, REVEAL_MAP,
    TRIGGER_COMBAT, TELEPORT_SKIP, APPLY_DEBUFF
}

[Serializable]
public class ProbabilisticEffect
{
    public float probability;
    public EventEffect[] effects;
}

public class EventResult
{
    public string EventId;
    public int ChoiceIndex;
    public string Description;
    public float HealAmount;
    public float DamageTaken;
    public int GoldGained;
    public List<string> ItemsGained = new();
    public List<string> BlessingsGained = new();
    public List<string> CursesGained = new();
    public int FragmentsSpent;
    public bool MapRevealed;
    public bool TriggerCombat;
    public int CombatEnemyTier;
    public int SkipRooms;
    public List<string> DebuffsApplied = new();
}

public class PlayerState
{
    public int CurrentFloor;
    public WeaponType CurrentWeaponType;
    public int CurseCount;
    public bool HasDiedThisRun;
    public int TotalSuccessfulRuns;
}
```

---

## 5.9 难度曲线管理

### 5.9.1 DifficultyManager

```text
public class DifficultyManager
{
    // 层基础难度
    private static readonly float[] BASE_DIFFICULTY = { 1.0f, 1.5f, 2.2f, 3.0f, 4.0f };
    
    // 困难/噩梦修正
    private static readonly DifficultyModifier HARD_MOD = new()
    {
        enemyHpMult = 1.3f, enemyAtkMult = 1.2f, enemySpeedMult = 1.15f,
        goldDropMult = 0.8f, healMult = 0.7f, badOutcomeChance = 1.3f, xpMult = 1.5f
    };
    
    private static readonly DifficultyModifier NIGHTMARE_MOD = new()
    {
        enemyHpMult = 1.6f, enemyAtkMult = 1.5f, enemySpeedMult = 1.3f,
        goldDropMult = 0.6f, healMult = 0.5f, badOutcomeChance = 1.6f,
        noRestRooms = true, timePressure = true, xpMult = 2.5f
    };
    
    private DifficultyMode _mode;
    private float _floorTimeElapsed;
    private int _roomsClearedThisFloor;
    
    public DifficultyMode CurrentMode => _mode;
    
    public void SetMode(DifficultyMode mode) => _mode = mode;
    
    /// <summary>
    /// 计算有效难度
    /// </summary>
    public float GetEffectiveDifficulty(int floorIndex)
    {
        int idx = math.Clamp(floorIndex - 1, 0, 4);
        float baseDiff = BASE_DIFFICULTY[idx];
        
        // 房间深度系数
        float depthMult = 1f + (_roomsClearedThisFloor / 10f) * 0.3f;
        
        // 时间系数（每10分钟+15%，封顶45%）
        float timeMult = 1f + math.Min(_floorTimeElapsed / 600f * 0.15f, 0.45f);
        
        return baseDiff * depthMult * timeMult;
    }
    
    /// <summary>
    /// 获取敌人缩放属性
    /// </summary>
    public EnemyScaledStats GetScaledEnemyStats(int floorIndex, int roomsCleared)
    {
        int idx = math.Clamp(floorIndex - 1, 0, 4);
        int baseHp = new[] { 30, 50, 75, 110, 150 }[idx];
        int baseAtk = new[] { 8, 12, 18, 25, 35 }[idx];
        
        float hpScale = 1f + 0.05f * roomsCleared;
        float atkScale = 1f + 0.03f * roomsCleared;
        
        // 难度修正
        var mod = GetModifier();
        
        return new EnemyScaledStats
        {
            Hp = math.RoundToInt(baseHp * hpScale * mod.enemyHpMult),
            Atk = math.RoundToInt(baseAtk * atkScale * mod.enemyAtkMult),
            Speed = 1f * mod.enemySpeedMult * (1f + 0.01f * roomsCleared)
        };
    }
    
    /// <summary>
    /// 获取Boss缩放属性
    /// </summary>
    public (int hp, int atk) GetScaledBossStats(int floorIndex)
    {
        var boss = BossStats.Get(floorIndex);
        var mod = GetModifier();
        return (math.RoundToInt(boss.hp * mod.enemyHpMult), math.RoundToInt(boss.atk * mod.enemyAtkMult));
    }
    
    /// <summary>
    /// 新手保护检查
    /// </summary>
    public void ApplyBeginnerProtection(PlayerStats playerStats, int totalRuns, int consecutiveDeaths)
    {
        // 首次减免
        if (totalRuns == 0)
        {
            playerStats.SetDamageTakenMultiplier(0.8f); // 受伤-20%
        }
        
        // 三连败保护
        if (consecutiveDeaths >= 3)
        {
            playerStats.SetShopPriceMultiplier(0.85f); // 商店-15%
        }
        
        // 通关1次后保护降为50%
        // 由外部RunTracker统计控制
    }
    
    private DifficultyModifier GetModifier()
    {
        return _mode switch
        {
            DifficultyMode.HARD => HARD_MOD,
            DifficultyMode.NIGHTMARE => NIGHTMARE_MOD,
            _ => new DifficultyModifier() // NORMAL，所有系数1.0
        };
    }
    
    public void Update(float deltaTime)
    {
        _floorTimeElapsed += deltaTime;
    }
    
    public void OnRoomCleared()
    {
        _roomsClearedThisFloor++;
    }
    
    public void OnFloorChanged()
    {
        _floorTimeElapsed = 0f;
        _roomsClearedThisFloor = 0;
    }
}

public enum DifficultyMode { NORMAL, HARD, NIGHTMARE }

public struct DifficultyModifier
{
    public float enemyHpMult;
    public float enemyAtkMult;
    public float enemySpeedMult;
    public float goldDropMult;
    public float healMult;
    public float badOutcomeChance;
    public float xpMult;
    public bool noRestRooms;
    public bool timePressure;
}

public struct EnemyScaledStats
{
    public int Hp;
    public int Atk;
    public float Speed;
}
```

---

## 5.10 经济系统实现

### 5.10.1 DungeonEconomy

```text
public class DungeonEconomy
{
    private readonly int _floorIndex;
    private readonly DifficultyMode _difficultyMode;
    private int _itemsSoldThisRun;
    private float _goldFloorAccumulator;
    
    public DungeonEconomy(int floorIndex, DifficultyMode mode)
    {
        _floorIndex = floorIndex;
        _difficultyMode = mode;
    }
    
    /// <summary>
    /// 计算击杀金币
    /// </summary>
    public int CalculateKillGold(EnemyType enemyType, SeededRNG rng)
    {
        int[] baseGoldKill = { 3, 4, 6, 8, 10 };
        int idx = math.Clamp(_floorIndex - 1, 0, 4);
        float baseGold = baseGoldKill[idx];
        
        // 敌人等级修正
        float tierMult = enemyType switch
        {
            EnemyType.NORMAL => 1f,
            EnemyType.FAST => 1f + 0.1f,
            EnemyType.RANGED => 1f + 0.1f,
            EnemyType.TANK => 1f + 0.2f,
            EnemyType.ELITE => 1f + 0.3f,
            _ => 1f
        };
        
        // 随机波动
        float variance = rng.FloatRange(0.8f, 1.2f);
        
        // 难度修正
        float diffMult = _difficultyMode switch
        {
            DifficultyMode.HARD => 0.8f,
            DifficultyMode.NIGHTMARE => 0.6f,
            _ => 1f
        };
        
        // 金币动态调整
        float adjustment = GetGoldAdjustment();
        
        return math.RoundToInt(baseGold * tierMult * variance * diffMult * adjustment);
    }
    
    /// <summary>
    /// 计算宝箱金币
    /// </summary>
    public int CalculateChestGold(SeededRNG rng)
    {
        int[] baseChestGold = { 50, 70, 90, 120, 150 };
        int idx = math.Clamp(_floorIndex - 1, 0, 4);
        float baseGold = baseChestGold[idx];
        float variance = rng.FloatRange(0.9f, 1.1f);
        float adjustment = GetGoldAdjustment();
        
        return math.RoundToInt(baseGold * variance * adjustment);
    }
    
    /// <summary>
    /// 计算房间清除奖励
    /// </summary>
    public int CalculateRoomClearGold(RoomType roomType, float clearTimeSeconds, SeededRNG rng)
    {
        int[] baseGoldPerFloor = { 15, 20, 28, 35, 45 };
        int idx = math.Clamp(_floorIndex - 1, 0, 4);
        float baseGold = baseGoldPerFloor[idx];
        
        // 速度奖励
        float timeBonus = clearTimeSeconds < 60 ? 1.5f : 1f;
        
        // 房间类型倍率
        float typeMult = roomType switch
        {
            RoomType.COMBAT => 1f,
            RoomType.ELITE => 2f,
            RoomType.BOSS => 5f,
            _ => 1f
        };
        
        float variance = rng.FloatRange(0.8f, 1.2f);
        return math.RoundToInt(baseGold * timeBonus * typeMult * variance);
    }
    
    /// <summary>
    /// 计算道具出售价格
    /// </summary>
    public int CalculateSellPrice(ItemData item)
    {
        float baseValue = item.shopBasePrice * 0.4f; // 40%回收率
        
        // 出售衰减：每出售1件后-5%，最低20%
        float decayMultiplier = math.Max(0.2f, 1f - _itemsSoldThisRun * 0.05f);
        _itemsSoldThisRun++;
        
        return math.RoundToInt(baseValue * decayMultiplier);
    }
    
    /// <summary>
    /// 金币上限检查
    /// </summary>
    public int ApplyGoldCap(int currentGold)
    {
        int cap = 500 + _floorIndex * 200; // 层1:700, 层5:1500
        if (currentGold > cap)
        {
            int excess = currentGold - cap;
            return cap + math.RoundToInt(excess * 0.5f); // 超出部分衰减50%
        }
        return currentGold;
    }
    
    /// <summary>
    /// 动态金币调整（防通胀/防赤字）
    /// </summary>
    private float GetGoldAdjustment()
    {
        var economy = ServiceRegistry.Get<PlayerEconomy>();
        if (economy == null) return 1f;
        
        int cap = 500 + _floorIndex * 200;
        float ratio = (float)economy.CurrentGold / cap;
        
        if (ratio > 0.8f) return 0.7f;  // 过多 → 收益-30%
        if (ratio < 0.2f) return 1.3f;  // 过少 → 收益+30%
        return 1f;
    }
}
```

---

## 5.11 小地图系统

### 5.11.1 MiniMapRenderer

```text
public class MiniMapRenderer : Node
{
    [Header("显示参数")]
     private Vector2 mapSize = new(200, 150); // 像素
     private float roomIconSize = 12f;
     private float bossIconSize = 16f;
     private Control mapRoot;
    
    [Header("颜色配置")]
     private Color combatColor = new(0.8f, 0.8f, 0.8f);      // #CCCCCC
     private Color eliteColor = new(0.67f, 0.27f, 1f);        // #AA44FF
     private Color treasureColor = new(1f, 0.84f, 0f);        // #FFD700
     private Color shopColor = new(0.27f, 1f, 0.27f);         // #44FF44
     private Color eventColor = new(0.27f, 0.53f, 1f);        // #4488FF
     private Color restColor = new(1f, 0.53f, 0.27f);         // #FF8844
     private Color bossColor = new(1f, 0.27f, 0.27f);         // #FF4444
     private Color startColor = Color.white;
     private Color unexploredColor = new(0.33f, 0.33f, 0.33f); // #555555
     private Color currentColor = new(1f, 0.84f, 0f);         // #FFD700
     private Color corridorColor = new(0.67f, 0.67f, 0.67f);  // #AAAAAA
    
    private DungeonData _dungeon;
    private int _currentRoomId;
    private readonly Dictionary<int, Control> _roomIcons = new();
    private readonly Dictionary<int, bool> _exploredRooms = new();
    
    /// <summary>
    /// 初始化小地图
    /// </summary>
    public void Initialize(DungeonData dungeon)
    {
        _dungeon = dungeon;
        _exploredRooms.Clear();
        foreach (var room in dungeon.Rooms)
        {
            _exploredRooms[room.RoomId] = false;
        }
        
        RenderMap();
    }
    
    /// <summary>
    /// 玩家进入新房间时更新
    /// </summary>
    public void OnRoomEntered(int roomId)
    {
        _currentRoomId = roomId;
        
        // 标记为已探索
        if (_exploredRooms.ContainsKey(roomId))
            _exploredRooms[roomId] = true;
        
        // 标记相邻房间为可见(未探索)
        var currentRoom = _dungeon.Rooms.FirstOrDefault(r => r.RoomId == roomId);
        if (currentRoom != null)
        {
            foreach (var door in currentRoom.Doors)
            {
                if (!_exploredRooms.ContainsKey(door.ConnectedRoomId))
                    _exploredRooms[door.ConnectedRoomId] = false;
            }
        }
        
        RefreshMap();
    }
    
    /// <summary>
    /// 渲染完整地图
    /// </summary>
    private void RenderMap()
    {
        if (_dungeon == null) return;
        
        // 清空
        foreach (Node2D child in mapRoot) child.gameObject.queue_free();
        _roomIcons.Clear();
        
        // 计算缩放
        var bounds = CalculateDungeonBounds();
        float scale = math.Min(mapSize.x / bounds.width, mapSize.y / bounds.height) * 0.8f;
        
        // 渲染走廊
        foreach (var corridor in _dungeon.Corridors)
        {
            DrawCorridor(corridor, scale, bounds);
        }
        
        // 渲染房间
        foreach (var room in _dungeon.Rooms)
        {
            DrawRoom(room, scale, bounds);
        }
    }
    
    private void RefreshMap()
    {
        foreach (var room in _dungeon.Rooms)
        {
            if (!_roomIcons.TryGetValue(room.RoomId, out var icon)) continue;
            
            bool explored = _exploredRooms.GetValueOrDefault(room.RoomId);
            bool isCurrent = room.RoomId == _currentRoomId;
            
            // 更新图标状态
            if (!explored && !IsAdjacentToExplored(room.RoomId))
            {
                icon.gameObject.SetActive(false); // 不显示
            }
            else
            {
                icon.gameObject.SetActive(true);
                var img = icon.GetComponent<TextureRect>();
                
                if (isCurrent)
                {
                    img.color = currentColor;
                    // 脉冲动画
                    icon.localScale = Vector3.one * 1.2f;
                }
                else if (explored)
                {
                    img.color = GetRoomColor(room.RoomType);
                    // 已清除的房间图标变暗
                    if (room.IsCleared)
                        img.color *= 0.5f;
                }
                else
                {
                    img.color = unexploredColor;
                }
            }
        }
    }
    
    private void DrawRoom(RoomController room, float scale, Bounds bounds)
    {
        var icon = new Node($"RoomIcon_{room.RoomId}");
        icon.transform.SetParent(mapRoot, false);
        
        var rectNode2D = icon.AddComponent<Control>();
        float size = room.RoomType == RoomType.BOSS ? bossIconSize : roomIconSize;
        rectNode2D.sizeDelta = new Vector2(size, size);
        
        Vector2 pos = WorldToMapPos(room.RoomRect.center, scale, bounds);
        rectNode2D.anchoredPosition = pos;
        
        var image = icon.AddComponent<TextureRect>();
        image.sprite = GetRoomIconSprite(room.RoomType);
        image.color = unexploredColor;
        
        _roomIcons[room.RoomId] = rectNode2D;
    }
    
    private void DrawCorridor(Corridor corridor, float scale, Bounds bounds)
    {
        var line = new Node("Corridor");
        line.transform.SetParent(mapRoot, false);
        
        var img = line.AddComponent<TextureRect>();
        img.color = corridorColor;
        
        var rt = line.GetComponent<Control>();
        Vector2 start = WorldToMapPos(corridor.Start, scale, bounds);
        Vector2 end = WorldToMapPos(corridor.End, scale, bounds);
        
        Vector2 delta = end - start;
        float length = delta.magnitude;
        float angle = math.Atan2(delta.y, delta.x) * math.Rad2Deg;
        
        rt.sizeDelta = new Vector2(length, 2);
        rt.anchoredPosition = (start + end) / 2;
        rt.localRotation = Quaternion.Euler(0, 0, angle);
    }
    
    private Vector2 WorldToMapPos(Vector2 worldPos, float scale, Bounds bounds)
    {
        return new Vector2(
            (worldPos.x - bounds.center.x) * scale,
            (worldPos.y - bounds.center.z) * scale
        );
    }
    
    private bool IsAdjacentToExplored(int roomId)
    {
        var room = _dungeon.Rooms.FirstOrDefault(r => r.RoomId == roomId);
        if (room == null) return false;
        
        foreach (var door in room.Doors)
        {
            if (_exploredRooms.GetValueOrDefault(door.ConnectedRoomId))
                return true;
        }
        return false;
    }
    
    private Color GetRoomColor(RoomType type) => type switch
    {
        RoomType.COMBAT => combatColor,
        RoomType.ELITE => eliteColor,
        RoomType.TREASURE => treasureColor,
        RoomType.SHOP => shopColor,
        RoomType.EVENT => eventColor,
        RoomType.REST => restColor,
        RoomType.BOSS => bossColor,
        RoomType.START => startColor,
        _ => Color.gray
    };
    
    private Sprite GetRoomIconSprite(RoomType type)
    {
        // 从资源加载对应图标
        // 实际由ResourceLoader加载
        return null;
    }
    
    private Bounds CalculateDungeonBounds()
    {
        if (_dungeon == null || _dungeon.Rooms.Count == 0)
            return new Bounds(Vector3.zero, Vector3.one);
        
        float minX = float.MaxValue, minZ = float.MaxValue;
        float maxX = float.MinValue, maxZ = float.MinValue;
        
        foreach (var room in _dungeon.Rooms)
        {
            minX = math.Min(minX, room.RoomRect.xMin);
            minZ = math.Min(minZ, room.RoomRect.yMin);
            maxX = math.Max(maxX, room.RoomRect.xMax);
            maxZ = math.Max(maxZ, room.RoomRect.yMax);
        }
        
        return new Bounds(
            new Vector3((minX + maxX) / 2, 0, (minZ + maxZ) / 2),
            new Vector3(maxX - minX, 0, maxZ - minZ)
        );
    }
}
```

---

## 5.12 房间模板数据结构

### 5.12.1 RoomTemplateData Resource

```text
[CreateAssetMenu(fileName = "RoomTemplate_", menuName = "PlaneWalker/RoomTemplate")]
public class RoomTemplateData : Resource
{
    [Header("模板信息")]
    public string templateId;          // 如 "COMBAT_01", "BOSS_01"
    public RoomType roomType;
    public int width;                  // 网格宽度
    public int height;                 // 网格高度
    public int[] applicableFloors;     // 适用层（空=全部）
    
    [Header("墙壁与碰撞")]
    public WallData[] walls;
    public CoverData[] covers;
    public PitData[] pits;
    
    [Header("装饰")]
    public DecorationData[] decorations;
    
    [Header("敌人生成点")]
    public SpawnPointData[] enemySpawnPoints;
    
    [Header("灯光")]
    public LightData[] lights;
    
    [Header("环境交互物")]
    public InteractableData[] interactables;
    
    [Header("环境危险")]
    public EnvironmentHazardData[] hazards;
}

[Serializable]
public class WallData
{
    public float x, y;          // 网格坐标
    public float width, height; // 尺寸
    public WallType type;       // WALL, PIT, COVER, DECO
}

public enum WallType { WALL, PIT, COVER, DECO }

[Serializable]
public class CoverData
{
    public float x, y;
    public float width, height;
    public bool isArc;           // 是否为弧形掩体
    public float arcAngle;       // 弧度角度
}

[Serializable]
public class PitData
{
    public float x, y;
    public float width, height;
    public bool isCircular;
    public float radius;
}

[Serializable]
public class DecorationData
{
    public float x, y;
    public string scene_id;
    public DecorationCategory category;
}

public enum DecorationCategory { TORCH, BANNER, FLAG, FURNITURE, CRATE, VASE, MUSHROOM, CRYSTAL, OTHER }

[Serializable]
public class SpawnPointData
{
    public int id;
    public float x, y;
    public float facing;         // 朝向角度
    public float spawnDelay;     // 出场延迟
}

[Serializable]
public class LightData
{
    public float x, y;
    public Color color;
    public float intensity;
    public float range;
    public LightType type;       // POINT, SPOT, AMBIENT
    public bool isFlickering;
    public float flickerSpeed;
}

public enum LightType { POINT, SPOT, AMBIENT }

[Serializable]
public class InteractableData
{
    public float x, y;
    public InteractableType type;
    public string customId;
}

public enum InteractableType { CHEST, SHRINE, WISHING_WELL, FORGE, MIRROR, ALTAR, NPC, CUSTOM }

[Serializable]
public class EnvironmentHazardData
{
    public float x, y;
    public HazardType type;
    public float damagePerTick;
    public float tickInterval;
    public float radius;
    public float triggerProbability;
}

public enum HazardType
{
    COLLAPSE_FLOOR,    // 塌陷地板
    POISON_FOG,        // 毒雾
    VINE_TRAP,         // 藤蔓
    TIME_SLOW_ZONE,    // 时间减速区
    TIME_REWIND_TRAP,  // 回溯陷阱
    TIME_RIFT,         // 时空裂隙
    LAVA_RIVER,        // 熔岩河
    STEAM_VENT,        // 蒸汽喷口
    FORGE_HAMMER,      // 锻造锤
    VOID_EROSION,      // 虚无侵蚀
    GRAVITY_ANOMALY    // 重力异常
}
```

### 5.12.2 RoomTemplateDatabase

```text
[CreateAssetMenu(fileName = "RoomTemplateDB", menuName = "PlaneWalker/RoomTemplateDB")]
public class RoomTemplateDatabase : Resource
{
     private RoomTemplateData[] templates;
    
    private Dictionary<RoomType, List<RoomTemplateData>> _templatesByType;
    private RoomTemplateData _defaultCombatTemplate;
    
    public void Initialize()
    {
        _templatesByType = new Dictionary<RoomType, List<RoomTemplateData>>();
        foreach (var t in templates)
        {
            if (!_templatesByType.ContainsKey(t.roomType))
                _templatesByType[t.roomType] = new List<RoomTemplateData>();
            _templatesByType[t.roomType].Add(t);
        }
        
        _defaultCombatTemplate = templates.FirstOrDefault(t => t.templateId == "COMBAT_01");
    }
    
    public List<RoomTemplateData> GetTemplates(RoomType type, int floorIndex)
    {
        if (_templatesByType == null) Initialize();
        
        if (!_templatesByType.TryGetValue(type, out var list)) return new();
        
        // 根据楼层过滤
        if (floorIndex > 0)
        {
            var filtered = list.Where(t => 
                t.applicableFloors == null || 
                t.applicableFloors.Length == 0 || 
                t.applicableFloors.Contains(floorIndex)).ToList();
            return filtered.Count > 0 ? filtered : list;
        }
        
        return list;
    }
    
    public RoomTemplateData GetDefaultTemplate(RoomType type)
    {
        if (_templatesByType == null) Initialize();
        return _templatesByType.GetValueOrDefault(type)?.FirstOrDefault() ?? _defaultCombatTemplate;
    }
}
```

---

## 5.13 测试计划

### 5.13.1 单元测试

| 测试ID | 测试目标 | 测试内容 | 预期结果 |
|--------|---------|---------|---------|
| UT-RNG-01 | SeededRNG确定性 | 相同种子生成2次 | 结果完全一致 |
| UT-RNG-02 | 种子派生 | DeriveSeed(100, 1) vs DeriveSeed(100, 2) | 不同种子 |
| UT-RNG-03 | IntRange边界 | IntRange(0, 10) × 10000次 | 结果∈[0,10]，分布均匀 |
| UT-RNG-04 | Chance精度 | Chance(0.5) × 10000次 | 约50%概率 |
| UT-GRAPH-01 | 图论生成-房间数 | floorIndex=1 | 房间数∈[8,10] |
| UT-GRAPH-02 | 图论生成-主路径 | 生成后检查 | 起点到Boss有路径 |
| UT-GRAPH-03 | 图论生成-特殊房保底 | floorIndex=1 | 商店≥1, 宝藏≥1 |
| UT-GRAPH-04 | 图论生成-无环 | 检查邻接矩阵 | 无循环引用 |
| UT-BSP-01 | BSP分区-叶节点数 | depth=3 | 叶节点数∈[4,8] |
| UT-BSP-02 | BSP分区-最小面积 | 所有叶节点 | 面积≥MIN_ROOM_AREA |
| UT-CORR-01 | 走廊-MST连通 | 生成后BFS | 所有房间可达 |
| UT-CORR-02 | 走廊-额外边 | 检查最终边数 | > MST边数 |
| UT-PLACE-01 | 房间放置-不重叠 | 所有房间矩形 | 无交集 |
| UT-PLACE-02 | 房间放置-起点Boss位置 | 起点x+y < Boss x+y | 起点靠左下 |
| UT-CONT-01 | 内容生成-敌人数量 | floorIndex=1 | ∈[2,7] |
| UT-CONT-02 | 内容生成-波次数 | floorIndex=1 | 70%单波 |
| UT-ECON-01 | 金币计算 | 击杀普通怪层1 | 约3金币 |
| UT-ECON-02 | 出售衰减 | 连续出售3件 | 价格逐次-5% |
| UT-DIFF-01 | 难度曲线 | floorIndex=3, base_diff | 2.2 |
| UT-DIFF-02 | 困难模式修正 | HARD模式 | HP×1.3, ATK×1.2 |

### 5.13.2 集成测试

| 测试ID | 测试场景 | 验证内容 |
|--------|---------|---------|
| IT-DUN-01 | 完整生成流程(层1-5) | 每层均通过验证 |
| IT-DUN-02 | 种子可复现性 | 同一全局种子生成2次，结果一致 |
| IT-DUN-03 | 1000次随机生成 | 全部通过验证，无死循环 |
| IT-DUN-04 | 不同种子多样性 | 10个不同种子的房间布局差异度>70% |
| IT-DUN-05 | 极端参数 | branchRate=0.9, roomCount=15 | 仍能生成有效地牢 |
| IT-EVT-01 | 事件选择(全15个) | 逐一触发，后果正确应用 |
| IT-EVT-02 | 特殊事件S1 | 3诅咒时触发虚无低语 |
| IT-EVT-03 | 事件不重复 | 同局中同一事件仅出现1次 |
| IT-MAP-01 | 小地图渲染 | 进入房间后地图正确更新 |
| IT-MAP-02 | 小地图未探索 | 未探索房间显示灰色轮廓 |
| IT-MAP-03 | 小地图路径提示 | Boss路径高亮显示 |

### 5.13.3 性能测试

| 测试项 | 标准 | 测试方法 |
|--------|------|---------|
| 完整地牢生成(层1) | <100ms | 计时Generate()调用 |
| 完整地牢生成(层5, 最大房间数) | <200ms | 计时Generate()调用 |
| BSP分区(深度5) | <10ms | 计时Partition() |
| MST构建(20节点) | <5ms | 计时KruskalMST |
| 房间实例化(10房间) | <50ms | 计时Instantiate() |
| 小地图刷新 | <2ms/帧 | Profiler检测RefreshMap() |
| SeededRNG 100万次调用 | <50ms | 循环计时 |

### 5.13.4 边界条件测试

| 测试场景 | 输入 | 预期行为 |
|---------|------|---------|
| 种子=0 | globalSeed=0 | 正常生成，不崩溃 |
| 种子=Int32.MaxValue | 最大种子值 | 正常生成 |
| 层6(超出范围) | floorIndex=6 | 使用层5参数(Clamp) |
| 房间数=1 | roomCount=1 | 至少生成起点+Boss |
| 全战斗房 | branchRate=0 | 线性路径，全战斗 |
| 全分支 | branchRate=0.9 | 大量短分支 |

### 5.13.5 每日种子测试

| 测试项 | 内容 |
|--------|------|
| 日期种子一致性 | 同一天生成结果相同 |
| 不同日期差异 | 不同日期生成结果不同 |
| 排行榜种子 | 使用daily_seed=hash(YYYYMMDD) |

---

> **文档结束**  
> 本文档为《Plane Walker: Chronicles of Collapse》地牢生成系统的完整开发文档。实现目标为Godot 4.x + GDScript，遵循已有EventBus Autoload/ServiceRegistry/StateMachine/Registry架构。核心设计原则：**程序化保证变化性，模板化保证品质感，种子化保证可复现。**
