# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit）

---

## #89（取证待复验）Android 保活常驻通知与「正在生成的会话」不同步

- 主人反馈：刷新会话列表后存在正在生成的会话，但前台保活常驻通知仍显示「暂无进行中会话」。
- 现状 vs 预期：预期 = 常驻通知文案与「是否有活跃流式会话」同步（有生成中会话 → 显示进行中）。
- 待办：定位保活通知文案更新链路（flutter_foreground_task + 会话流状态广播），确认为「刷新会话列表」路径上哪一环没触发通知更新（疑似只在流 start/stop 事件更新、列表刷新不重算）。
- 状态：仅登记，未排查。

---

## #90（时序抖动待治理）chat_scroll_bottom_bound_test 全量跑偶发失败

- 现象：`#23 发送消息后滚底不越界…（长会话长短混合）` 在全量套件下偶发失败（600 条懒加载 ListView 像素轨迹时序敏感），单跑恒绿；干净 main 全量亦复现（一次全绿一次挂），与 #87/#88 改动无关（已对照排除）。
- 待办：单独治理（放宽容差/减负载/拆分时序依赖），不阻塞批次。
- 状态：登记，未修。

---

## #92（描述修正）live 流式页面上方区域 y 轴上下抖动

- 主人补充（推翻先前「被拉回」猜测）：划到上方**能保持、不会被拉回**（区别于 #74 PC 滚轮回拉，非同根因）；问题是停留在上方时页面有 y 轴上下滚动抖动。
- 疑因方向（待排查）：流式增量期间 extent 增长与程序化滚动（jumpTo/justify）在用户已上滚后仍对 viewport 施加修正；或 reveal 队列 flush 时 `maxScrollExtent` 估算波动传导。排查入口：`chat_message_list.dart` 手势状态机与「程序化滚动门控」（#74 加的负位移守卫只管回拉，不管页内抖动）。
- 状态：登记待排查。

---

## #94（待排查）已在澄清会话中仍发应用内通知，盖住澄清弹窗

- 主人要求：用户已停留在「需要澄清确认的聊天」页面时，不要发该会话的应用内通知（in-app 通知横幅会盖住上方的澄清确认弹窗）。
- 位置线索：`lib/features/notifications/notification_providers.dart` `turnNotificationHookProvider`（前台 resumed 分支：`active != sessionId` 才发 in-app——澄清通知链路疑似未走该 hook 或判定条件不同）；澄清卡渲染在 `chat_page.dart`。
- 待办：定位澄清事件 → in-app 通知的触发链路，补「当前路由即该会话聊天页」判定（activeSessionId + 当前路由 location 双条件）后静默。
- 状态：登记待排查。

---

## #98 下载自动重试 + 断点续传 [已收口 2026-09-08]

- 交付：main @ 5c19de7（合并 28bdaf8，19 文件 +1960/-208）。自动重试（瞬态错误退避 2s/8s/30s 最多 3 次，403/404 永久错误不重试）+ 断点续传（URL 任务流式写 `.part`，206 校验起点与总长 / 200·416 降级重下，完成后落 Downloads 清 .part）+ 重启恢复续传（有 .part 重置 queued，无 .part 维持 failed）+ Drift v5（temp_path/attempt_count，迁移含真实 v4 库升级测试）+ 下载页「第 N/3 次重试中」「已续传 N MB」提示（l10n 尾部 extension `AppLocalizationsDownloadResume98`）。
- 验收：独立复验 analyze 零告警 + 全库 2554 全绿（首跑挂 #90 已知 flaky，单跑复绿、复跑全量绿）+ 金照 26 绿。架构沉淀 skill references `downloads-auto-retry-resume-2026-09-08.md`。
- 待主人：真机复验（Android 实机下载中断恢复场景）。

---

## #99（已交付 b9df051，待主人真机复验）多会话 watchdog 同步静默 → 连锁强制重连风暴

- 交付：main @ b9df051（7 文件 +476/-30）。T1 重连/探活错峰 jitter（`reconnectJitterMax` 默认 1500ms，jitter=0 确定性同步路径保留；`_forceReconnect` 日志加 `jitterMs`）+ T2 afterSeq=0 全量重连 60s 冷却（命中降级 status 探活，`isThrottledFallback` 防绕过；afterSeq>0 不受限）+ T3 dio cancel 降 `[expected-cancel]` verbose。`ChatWatchdogConfig` 新增 `reconnectJitterMax`/`fullReconnectCooldown`/`random`/`customJitter`/`jitterForAttempt`（测试可 override）。
- 附带修：`e5ea242` 自带回归 `_syncSessionListRename` 无列表 provider 时抛错（补 `ref.exists` 守卫，与四兄弟对齐；`chat_api_client_regression_test` renameSession 全链路复绿）。
- 验收：analyze 零告警 + 全库 2568 全绿 + 金照 26 绿（`--update-goldens` 无意外变更）；`e5ea242` 的 8 用例 mutation 同步测试全绿（回滚事故已修复，sync 调用 10 处完整）。
- 待主人：多会话并发长工具跑 10 分钟，真机看 force reconnect 同秒触发是否归零。
- 收口教训：worktree 存活期间 main 有新合入（e5ea242）时收口整文件 cp 覆盖丢了 sync 功能 → 已回滚 + 逐段移植；以后收口一律先 diff 对照 HEAD 增量。
- 遗留方向（未做）：服务端 journal-only 分支补心跳（主人明确禁动 webui，略）。

---

## #99（多会话放大待取证）watchdog 同步静默 → 连锁强制重连风暴（诊断日志成串）

- 现象（2026-09-08 12:00-12:03 三会话 c131159d210e / 8d1e67593255 / 8e58a33c7584）：多会话并发流式时，WARN stale poll / ERROR force reconnect / ERROR dio cancel 成串出现；12:03:06 三会话 200ms 内同步触发 force reconnect。多会话并发易复现。
- 已证机制（源码行号）：
  - 阈值 5s/12s/18s/25s（chat_providers.dart:75-91），watchdog 判定 chat_controller.dart:3183-3252；任何 SSE 帧（含 `: heartbeat`）经 _handleSseEvent:1292 刷新传输活跃时间。
  - webui 服务端 `/api/chat/stream` 队列空 5s 必写心跳（hermes-webui routes.py:17391-17397）→ 客户端收不到心跳 = 字节未达客户端 = 通道/服务端真停顿，非「上游工具忙」。
  - 纯静默期收不到 id: 帧 → lastEventId 空 → afterSeq=0 → fullReconnect 从 seq 0 全量重放（chat_controller.dart:3133,3148-3151,3164-3169）。
  - dio GET cancel ERROR = _forceReconnect 内 stopStream 副作用（:3147），非人为取消。
- 多会话自放大假设（主嫌疑）：N 会话 N 条 SSE 共享同一服务器/隧道（frp tcpMux 单连接）；任一拥塞同停所有会话 → 看门狗齐触发；afterSeq:0 全量重放突发流量再挤同一通道 → 邻会话心跳被挤停 → 连锁重连（风暴）。
- 待办取证：① 复现时 PC 浏览器连同一服务器对照是否同停（切客户端/通道/服务端）；② 服务端加重连落点+心跳实际写出日志；③ 修复方向：多会话重连错峰 jitter + afterSeq:0 全量重放限频；④ journal-only 分支（routes.py:17352-17371）重放完直接 return 无心跳循环，评估补心跳。
- 验收：≥3 会话并发长工具执行 10 分钟，force reconnect 同秒触发为 0；无正文重复回放；dio cancel 噪音聚合。
- 状态：已登记，待取证后定修复批次。

---

## #101 GitHub Releases 更新检测 + 自动更新开关（0.1.30 发布后立即开工）

- 主人需求（2026-09-08，随 v0.1.30 发布时提出）：应用内检测更新，检测源指向 GitHub Releases（`silent-reader-cn/hermes-ui`），并提供自动更新开关。
- 节奏（主人已拍板）：v0.1.30 先行发布作为检测基线（无基线时检测恒报「已是最新」），随后立即开发，完成后发 0.1.31。
- 方向草案（待细化）：
  - 检测：GitHub API `releases/latest` 比对 `semver`（`version:` vs tag `vX.Y.Z`）；Android 手动下载 APK（沿用下载器确认框+断点续传，装包跳系统安装器）；Windows 下载 setup.exe 或提示用户（Inno 包无静默自更，倾向「提示+打开下载页」或下载后手动运行）。
  - 开关：设置页新增「自动检查更新」三态或开关（默认开：仅启动时静默检查 + 手动「检查更新」按钮；自动下载默认关——下载确认框纪律一致）。
  - 频控：每 24h 至多一次自动检查；手动检查不限。
  - 失败容错：API 限流/断网静默跳过，不打扰。
- 验收：Android/Windows 双端设置页开关生效；检查更新按钮正常报「已是最新」（v0.1.30 基线）或在 v0.1.31 发布后正确提示新版本并可下载。
- 状态：登记待开工（先写规格入库 docs/specs/，再实现）。

---

## #102 Windows 单实例防重开（0.1.31 同批交付）

- 主人需求（2026-09-08）：PC 版禁止双实例——开第二个时直接显示第一个的窗口并 focus。
- 实现（C++ 原生层，`windows/runner/`，全 ASCII）：
  - `single_instance.h`：命名 Mutex `Local\HermesUI.SingleInstance.Mutex` 启动抢占；`ERROR_ALREADY_EXISTS` → `AllowSetForegroundWindow(ASFW_ANY)` + `PostMessage(HWND_BROADCAST, RegisterWindowMessage("HermesUI.SingleInstance.Activate"))` → 第二实例立即 `EXIT_SUCCESS`（进程不落地）。
  - `flutter_window.cpp` MessageHandler：收到注册消息 → `GetWindowPlacement` 还原最小化 → `ShowWindow` → `SetForegroundWindow` → `FlashWindowEx` 兜底（OS 拒绝前台权时任务栏闪烁提示）。内核Mutex 随进程退出自动释放，崩溃无残留锁。
  - `main.cpp`：wWinMain 最前置执行抢占（先于窗口/引擎创建）。
- E2E 真机验证（build Release 实测）：
  - 双开 → 进程数恒为 1（第二实例秒退，PID 未变化）；
  - 第二实例启动后 `GetForegroundWindow()` 归属 PID = 第一实例（35156），窗口标题确认 = Hermes 主窗口；
  - 单实例退出后 Mutex 自动释放（ZERO_LEFT）。
- 验收：`flutter build windows --release` 通过；与 #101 更新检测同批发 0.1.31。
- 状态：已实现并验证，随 0.1.31 发布收口。

---

## #76 二期（待一期真机复验后另批开工）

- 内置服务砍 embedded Python 打包瘦身（方案已定 · 未开工），见 `.todo/20260907.md` #76 条目。
