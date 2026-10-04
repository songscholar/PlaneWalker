# Plane Walker P16M 正式目录激活证据

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: ContentRegistry activation and native domain catalog boundary
- Applies To: Base pack, ContentRegistry, HubDistrictDefinition, P16ContentCatalog and MetaCatalogFactory
- Owner: Project content integration lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`, `docs/current/2026-10-05-p16l-tutorial-ui-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Authored content activation verified; complete native product certification pending

## 已激活目录

Base pack 从 211 条扩为 431 条已验证记录，26 个内容源、49 个已声明资源和策略文件、
1 个翻译源共 76 个完整性摘要。新增目录仅对 LAUNCH/EXPANSION 可查询，M1 语义保持隔离。

| 类别 | 精确数量 |
|---|---:|
| Meta 节点 | 42 |
| Hub 区域 | 3，合计 9 个功能 |
| 锻造定义 | 20，5 武器和 15 附魔偏好 |
| 叙事定义 | 57 |
| 原生叙事来源 | 13 |
| 教学定义 | 34 |
| 普通敌人定义 | 22 |
| Boss 定义 | 5 |
| 召唤定义 | 9 |
| 精英词缀定义 | 10 |
| Launch 遭遇 Profile | 5，合计 40 个配方 |

P16 每行使用封闭字段和本地化校验，整组使用现有 Meta、Forge、Narrative、Tutorial 领域
解析器校验精确数量、先决条件、引用和奖励政策。Hub 原生解析器拒绝未知嵌套字段、重复
功能、错误 NPC、非法位置和修复阶段，并验证实际 scene namespace、身份与文件存在。
NPC 默认驻地与功能接待区允许 authored 内容中的不同位置，例如 Phia 的 Gallery 接待。

P15 使用已有 Enemy/Boss/Summon/Affix/Encounter 严格原生解析器，并核对完整五类数量、
实际 floor、Boss、actor 引用和嵌套房间模板引用。Required pack 失败返回零条记录，普通
类别也不残留；optional pack 失败只隔离自身。新增 P16 目录是完整冻结包，部分拆包拒绝。

get_catalog_entries 返回去除 pack_id/pack_version 的深拷贝，严格领域不接收存储元数据。
MetaCatalogFactory.from_registry 只接受正式 Registry API 与 LAUNCH/EXPANSION，生成的
生产 Meta fingerprint 与 load_base 离线适配路径一致。Main 五个状态文案补齐双语，CSV
一致，localization digest 同步并完成实际翻译导入。

当前四张 Hub PNG、生成来源 manifest、十二个已编写敌人 scene/PNG/manifest 和材料
政策已纳入 pack integrity。Hub scene 仍位于 res://scenes/hub，pack 相对路径合同不能
直接声明外部 scene；此处只验证文件身份与存在，不声称该外部 scene 的摘要由 pack 验证。

## 验证

- 缺少目录与正式 Factory API 的有效 RED：planewalker-tests.S0S9c9。
- 完整原生 activation GREEN：planewalker-tests.kBNqkT，1/1。
- 加入完整 composite fixture 正控制、嵌套叙事、非法教学计数和缺少敌人探针后 GREEN：
  planewalker-tests.sUkzo8，1/1。
- 最终内容回归 planewalker-tests.ptY8W7，19/19 PASS，无 ERROR、脚本错误和泄漏。
- MetaCatalogFactory 回归 planewalker-tests.8b08Kw，1/1 PASS。
- P14/P15/P16 Python 内容契约 54/54 PASS；localization contract PASS。
- 全部 76 个声明文件 byte digest 核对一致；git diff --check PASS。
- 实际编辑器导入完成，无脚本错误或泄漏；系统 CA 与全局 editor settings 保存拒绝为
  环境诊断。已存在的 workspace portable editor 被系统以 137 终止，未作为认证证据。

Godot 行覆盖不可用，本阶段没有覆盖率声明。当前原生敌人实现与五 Boss 完整行为、Main
营地全流程和三平台导出仍有独立门禁；目录可用不等于这些运行时和完整产品已经认证。
