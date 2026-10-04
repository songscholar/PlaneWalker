# Plane Walker P16I 原生教学观察证据

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Committed native Player tutorial observation boundary
- Applies To: TutorialNativeAdapter and native tutorial observation integration tests
- Owner: Project domain implementation lead
- Depends On: `AGENTS.md`, `docs/current/2026-10-05-p16f-onboarding-domain-evidence.md`, `docs/current/2026-10-05-p16h-meta-player-replay-evidence.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native observation focused verification; physical profile service and player-facing UI certification pending

## 已实现边界

TutorialNativeAdapter 绑定实际 RunState、场景树中的真实 Launch/Expansion PlayerController、
经过教学领域验证的 Profile 及活动启动收据。启动运行、种子、角色、武器、时间能力对、
Meta 投影摘要和 Replay owner generation 必须一致。错误来源和损坏投影在访问原生协议前拒绝。
绑定时验证完整 Meta 投影，绑定后比较冻结的全投影；摘要没有改变也不能掩盖字段漂移。

观察仅来自 Player.authoritative_frame_committed。适配器再次核对当前成功帧的
authoritative_frame_intents 和真实优先级仲裁；提前伪造通知、旧帧、失败帧、Replay restore
没有可用的成功输入事实。移动同时需要实际非零移动输入和真实位移；只有击退的位移不能
增加移动教学。冲刺、武器主动作、武器技能和第一时间槽来自实际已接受的 pressed 仲裁。

只有活动地牢阶段可以累计普通局教学；暂停、suspended、Hub 和死亡排除。第一次实际
地牢观察附带 first_dungeon_entry，血量首次下降越过一半附带 health_below_half。
回放时钟倒退或不连续会退休绑定；角色 owner generation 或启动身份变化后旧收据不能确认。

队列最多 64 个脱离原状态的收据，封印包含适配器 owner、成功帧、generation 和收据摘要。
调用者不能改写已签发语义。准备查询与确认查询均不发布提示，服务必须先持久化候选，再
confirm_saved。确认先消费收据，再发布一次 observation_saved，重复确认拒绝。如果已保存
发布回调改变身份，返回 NATIVE_PUBLICATION_PENDING 以及 published=true 和脱离原状态的
已消费收据，要求服务记录恢复；同一收据不能重发。detach 后的实例拒绝再次绑定。

## 验证记录

- 原生适配器缺失 RED：planewalker-tests.lzZfiq。
- 损坏投影协议 RED：planewalker-tests.Yekzy1；现先检查 Variant 类型。
- 真正击退但零输入误计数 RED：planewalker-tests.5mclDW。
- 成功输入投影 GREEN：planewalker-tests.t9NGSw。
- 退休绑定重用和保存回调漂移 RED：planewalker-tests.ynqPvM。
- 生命周期和四类实际动作 GREEN：planewalker-tests.toUJxH。
- 最终实际 World commit 故障和恢复专项：planewalker-tests.frUq9p，1/1 GREEN。
- 复核提出完整投影身份收紧：planewalker-tests.CEXdfc RED；最终
  planewalker-tests.Uz0uOx 1/1 GREEN，涵盖 bind/确认时未改摘要的字段漂移。
- git diff --check：PASS。

专项使用实际内容 Registry、生成 FloorPlan 和配置 Meta 的真实 Player 场景。覆盖三个真实
移动动作、getter 深拷贝与嵌套别名、击退零输入、仍有击退时真实移动、四类实际仲裁动作、
无效帧、暂停、suspended、Hub、真实 Replay restore、时钟退休、owner generation 漂移、
已保存回调 detach 以及不允许重发已消费收据。

真实 WorldPayloadAuthority 提交故障会补偿完整 Player preimage，不发成功帧通知，不保留
可认证的输入记录，也不签发教学收据；去掉故障后同帧恢复只发布一次。该故障探针日志仅有
预期诊断 `ERROR: Fixed-frame event buffer settlement rejected runtime frame 1`；无脚本错误、
解析错误或泄漏。早期测试夹具中的缩进与 Variant 警告已修复，不作为产品行为 RED。
Godot 行覆盖仍不可用，本阶段不声称覆盖率已通过。

## 剩余原生门禁

此专项的持久化确认使用真实纯领域候选模拟成功保存，不证明物理 SaveService 接线。
ProfileRuntimeService 的磁盘保存、保存失败无提示、保存后身份漂移恢复需独立专项。
Main 激活、Hub/训练会话分配、训练场真实行为、其他已编写条件触发、提示和课程原生 UI、
引导策略应用、控制器/双语/多分辨率与打包体验仍分别需要实现和验证。

本阶段没有修改内容、本地化或 pack integrity 字节，没有远程发布或使用外部账户。
通过聚焦本地提交保持可恢复性，不把此观察边界称为完整 P16 或完整游戏认证。
