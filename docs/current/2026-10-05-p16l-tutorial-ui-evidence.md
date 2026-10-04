# Plane Walker P16L 原生教学 UI 证据

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Native tutorial projection and presentation boundary
- Applies To: TutorialViewModel, TutorialViewState, TutorialPanel and TutorialHintPresenter
- Owner: Project UI implementation lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16f-onboarding-domain-evidence.md`, `docs/current/2026-10-05-p16i-native-tutorial-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native presentation verified; Main routing and training allocation pending

## 已实现

ViewModel 使用实际 34 条教学目录、已验证 Profile 与当前 InputMap，按 authored sequence
投影 10 节课程、6 项训练和 3 档显式引导策略。训练首奖合计 56，不由 UI 发放。查询、回顾和
投影不能修改 Profile。已经完成但没有旧动作计数的迁移课程显示满足目标；已完成课程和
已领取训练奖励必须具有满足目标的计数，未知字段、伪造绑定、乱序和过量计数拒绝。

原生课程面板沿用 DungeonPanelView 的安全区、滚动、焦点、拒绝恢复和版本边界。跳过、
提示开关、引导模式与训练按钮仅发送带 expected_revision 的请求。重绘前按钮、旧版本和
重复按钮不能发布有效领域命令。回顾为只读本地展示。训练仍由正式服务分配原生会话。

提示呈现不抢焦点，只接受严格的已保存提示投影。instant 提示持续 180 个活动 physics
帧，暂停不计时；其他样式由实际上下文清理。重复同一提示不重置计时，旧 revision 拒绝。
新增 33 个中英 UI key，两个翻译源保持一致，Base pack localization integrity 已同步。

## 验证

- ViewModel 缺失 RED：planewalker-tests.9DF4tL；首次 GREEN：planewalker-tests.hgB2tf。
- 原生场景缺失 RED：planewalker-tests.nrlMxs；UI GREEN：planewalker-tests.rUzj68。
- 完成状态缺少真实计数 RED：planewalker-tests.KBqIlk。
- 最终教学回归：planewalker-tests.LUM2eR，5/5 PASS，无脚本错误与泄漏。
- 实际 OpenGL 原生渲染：1/1 PASS；17 张非空截图位于
  `build/visual-evidence/p16-tutorial-ui`，native-final.godot.log 无 ERROR/泄漏。
- 双语、1.0/1.5 字号、640×360、1280×720、1920×1080、3440×1440，控制器遍历、旧版本
  与已释放控件、拒绝后恢复、实际 remap、179/180 帧消失边界和真实 Registry 完整性通过。

截图实际查看确认中文字体正确，小分辨率大字号提示不越过安全区。最终渲染与回归使用
隔离测试目录。编辑器导入完成，但受沙箱限制全局 editor settings 保存拒绝，并有系统 CA
诊断；不能把其退出码单独当作无诊断认证。Godot 行覆盖不可用，本阶段不声称覆盖率通过。

## 剩余边界

Main 路由、Profile 保存后提示投递、真实训练场会话与任务行为、引导策略进入 RunConfig、
打包与完整流程验证需相应集成专项。上述独立呈现证据不代表完整教学或全产品认证。
