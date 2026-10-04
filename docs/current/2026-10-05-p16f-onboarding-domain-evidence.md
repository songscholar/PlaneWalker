# Plane Walker P16F 教学领域证据

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Tutorial domain and current-input projection boundary
- Applies To: TutorialCatalog, TutorialProgress, TutorialRuntime and TutorialProjector
- Owner: Project domain implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/current/2026-10-04-p16b-authoritative-content-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Pure domain focused verification; native scenes and full checkout certification pending

## 已实现边界

运行时读取实际 34 条定义：十课、十五提示、六项训练和三种明确选择的引导局策略。
封闭目录校验嵌套动作与上下文、课程零奖励、训练首次奖励、前序课程依赖、精确助攻预算和
默认关闭助攻。错误配置会清空旧运行时，不能继续使用过时目录。

Meta Profile 根结构和 tutorial_state 保持既有结构。目标计数使用 completed_command_ids 中
可替换的 onboarding-progress 标记。normal_run、hub、training_drill 各保留最多一个
onboarding-watermark；引导局完成另有一个可替换水位。训练领取固定为六个
training-claim:T-01..T-06。公开命令不能分配这些保留命名空间。重复练习替换水位，
不积累永久逐动作历史。

严格解码拒绝未知目标、非规范数字、重复水位、超过作者上限的计数、缺失上下文水位、
完整计数没有完成标记、部分计数与已完成状态矛盾、未满足前序依赖、完成与跳过重叠。
旧完成目标没有原生计数时仍视为已满足；旧已见提示没有次数标记时视为耗尽，避免迁移后
重新显示用户已经看过的提示。

准备观察不会改变传入 Profile；即使收据序号存在间隔，也只计入一次真实语义动作，返回
脱离原状态并规范化整数的候选快照。普通局收据绑定 active launch 的运行与序号；Hub 与
训练要求没有活动生产局且 run_id 为空。新认证会话从动作一开始；旧会话和重复动作拒绝。
后续原生服务必须持久化分配并认证会话，以及真实动作和提示条件的发生。

六项训练只在首次完成发放 3/5/5/8/15/20 碎片，合计 56；普通课程和提示不发货币。
跳过清除部分课程计数，不开启助攻。抑制提示不消耗未见提示次数。课程回顾只返回内容，
不改变 Profile，也不发奖励。

普通模式立即可用。三次显式助攻的伤害/前摇比例精确为 0.80/1.25、0.90/1.10、1.0/1.0，
全部排除排名资格。完成引导局只接受没有活动局时的 last_settlement_receipt，严格匹配
运行、launch sequence 和终局原因；active launch 不具有终局证明，提前提交拒绝。
引导序号必须是下一次，且同一终局不能伪装成后续引导局；第四次助攻拒绝。原生结算服务
可在真实结算候选上合并引导完成；它仍必须核对启动时冻结的显式助攻策略。

TutorialProjector 使用 InputRemapService.binding_labels，读取当前 InputMap。
输出键鼠或手柄的实际绑定，移动包含四方向；time_slot_1 同时携带选中的能力身份。
Boss 转换等服务事实不虚构输入键。测试实际修改键盘和手柄 InputMap，验证提示同步。

## 验证记录

- 缺少运行时 RED：planewalker-tests.SxAXGL。
- 引导局 JSON 序号查询 RED：planewalker-tests.qWOe9g。
- 缺少投影器 RED、运行时 GREEN：planewalker-tests.1ccXyA。
- 损坏引导序号类型 RED：planewalker-tests.jMx0Ht；现先校验类型，再转换序号。
- 活动局提前完成 RED：planewalker-tests.xabm07；现仅认证已结算终局。
- 最终 Godot 专项：planewalker-tests.9vu4wG，2/2 场景 GREEN，日志无引擎错误、
  脚本错误或泄漏警告。
- 既有 Hub/教学权威 Python 合同：9/9 GREEN。
- git diff --check：PASS。

测试到达全部十课、十五提示精确次数上限、六项首次训练奖励和三次已结算引导完成。
覆盖真实 JSON、过期/重复收据、其他运行/退休会话、序号间隔、损坏或矛盾计数、错误
嵌套内容、货币溢出、抑制、跳过、回顾和实际 InputMap 重映射。运行时独立复核无其他
阻断发现；集成负责人复核提出的提前完成问题已通过 RED/GREEN 修复。
Godot 行覆盖仍不可用，本阶段不声称覆盖率已通过。

## 剩余原生门禁

本阶段尚未把教学激活到 Main，没有认证真实训练场、安装教学呈现器、应用引导局伤害或
前摇倍率，也没有持久化认证 Hub/训练会话。后续服务必须先保存候选，再发布提示；绑定
真实 Player 动作和场景条件；冻结启动助攻与结果资格；排除训练的生产结算和统计。
原生 UI、手柄焦点、双语布局、多分辨率、存档失败补偿和打包游戏需要独立集成证据。

本阶段没有修改内容、本地化或 pack integrity 字节。文件可通过聚焦本地提交恢复，
没有远程发布或使用外部账户。
