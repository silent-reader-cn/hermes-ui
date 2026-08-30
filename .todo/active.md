# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建），标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### [已收口] 看门狗回退 — live 等首 token 频繁重连及文本重复（回归，阈值改回去）

- 已收口：`b7bde6d` — `ChatWatchdogConfig 3/3/8/8/3 → 5/12/18/25/4`，`chat_controller` 注释/transportGap 12s同步，新增`chat_reconnect_dedupe_test` 3项（无seq下fullReconnect去重`Hello world`），`controller/diff_merge`去重加固，`contrast`补`settings|light|推送`

---

### [已收口] 设置通知推送测试 — 三开关下方左选类型右按钮推送（功能）

- 已收口：`b7bde6d` — `settings_page: _NotificationSection`改`ConsumerStatefulWidget`，三开关下方新增`CupertinoListTile(key: settings-notify-push-test)`左`SlidingSegmentedControl<PushTestType>`三选一+右`CupertinoButton.filled`推送，`turnNotificationService`三通道1001/1101/1201直发+`Diagnostics notifications`，`l10n`新增`pushTest*`7项，`settings_page_test`6项（`b7bde6d` 已合但 active 未清，待归档时移除）

---

### [已收口] 工具调用期间假活导致永不重连 — 读取文件一直转圈（问题 · P0 · Q1-Q4 已拍板）

- 类型：问题（看门狗在工具期假活）
- 位置：
  - 看门狗：`lib/features/chat/chat_controller.dart:2836-2893` `_recoverStaleStreamIfNeeded`（`1s心跳` + 双门槛 `progressStale 5s && transportStale 12s → checking` + `force 18s/25s`）、`2893 _hasRunningTools: liveToolCalls.any(!isCompleted)`、`3121 _markProgress`/`3134 _recordTransportActivity`、分发 `1213 _handleSseEvent:1215 _recordTransportActivity` → `1243-1246 ToolStarted/ToolCompleted` 分别 `_appendToolCall/_completeToolCall` 并 `_markProgress`
  - 状态：`lib/features/chat/chat_state.dart:436 liveToolCalls/completedToolCallGroups` + `chat_providers.dart:12-40 ChatWatchdogConfig 5/12/18/25/4`
  - 现象截图：`C:\Users\Admin\AppData\Local\hermes\webui_30002\attachments\6001c63184fd\Screenshot_2026-08-30-09-49-17-244_com.silentreader.hermes_ui.jpg` — 顶栏 `读取文件 ×1, 终端 ×1, Tool ×1` + `运行中`，其中 `读取文件` 单项（Q1）`运行中...` 转圈
  - 测试：`test/features/chat/chat_watchdog_test.dart`、`test/features/chat/chat_controller_test.dart:1212`、`test/helpers/fake_chat_api.dart`
- 范围：工具期 live（`activeStreamId != null && _hasRunningTools==true`，顶栏`运行中`）的全平台；影响工具调用回合（`ToolStarted` 已到但 `ToolCompleted` 迟迟不到，`token/reasoning` 停滞，截图为 `读取文件` 卡死）
- 复现（主人 Q1-Q2 已确认）：
  1. 发起会触发工具调用的对话（`读取文件/终端/搜索` 等），进入 live，观察顶栏 `读取文件 ×1 … 运行中` + 对应工具行 `运行中...`
  2. 模拟工具侧卡死/服务端工具执行超时/弱网（`ToolCompleted` 不到，`token` 亦停），保持 SSE 连接不断但无实质进度，持续 25s+
  3. 现象：看门狗永不重连，一直卡在 `运行中...`（Q1 实为 `读取文件` 在转圈）
  - 根因（已实证 Q2 按“是”）：
    - `ToolStarted` 已 `_markProgress()+_recordTransportActivity`，若服务端/网关在工具执行阶段仍周期性 `heartbeat` 或空 `SSE` 帧，`_recordTransportActivity` 会持续刷新 `lastTransport`，双门槛 `progress 5s && transport 12s` 永不成立；`force` 又因 `_hasRunningTools==true` 被放宽到 `25s`，且同样被 `heartbeat` 刷新，表现为“工具期假活→永不重连”
- 现状 vs 预期（Q2-Q3 已拍板“是”）：
  - 现状：`checking` 双门槛被 `transport` 假活堵住；`force` 在工具期硬 25s 且同样被 `heartbeat` 续命
  - 预期（Q2 是、Q3 是）：
    - 工具期也要能重连：工具已开始但迟迟无 `ToolCompleted` 的僵死要能被识别并重连
    - 重连后工具重放幂等：已见过的 `ToolStarted(stableId)` 去重，仅补新 `Started/Completed`，不重复执行本地工具（与现有 `chat_diff_merge`/`replay_dedupe` 幂等一致）
  - 推荐实现（三选一/组合，验收以不假活为准）：
    - A) `force` 分级收紧：有运行中工具时 `25s→18s`（与无工具一致）或引入“工具僵死阈值”`toolStaleThreshold = 18s`（`lastProgress` 侧，`tool已开始`后无 `ToolCompleted/token` 即计进度停滞，`transport` 侧不受 `heartbeat` 单独刷新影响——`heartbeat` 的 `_recordTransport` 不应覆盖 `progress` 语义，或 `heartbeat` 不刷新 `lastProgress` 的判定保持，仅 `force` 用 `lastTransport` 但缩短）
    - B) `progress` 语义收紧：工具期 `progress` 仅计 `ToolCompleted/token/reasoning`，`ToolStarted` 不算有效 `progress`（或 `ToolStarted` 后启动独立 `toolProgress` 计时），使 `5s && 12s` 更灵敏
    - C) 引入 `lastToolActivity` 独立计时：`_appendToolCall/_completeToolCall` 单独记 `lastToolActivity`，看门狗新增分支 `if (_hasRunningTools && now - lastToolActivity >= 18s) → checking/force`，不受 `heartbeat` 续命
- 验收（Q4 P0）：
  1. 工具期 `ToolStarted` 后 18s 内无 `ToolCompleted/token` 即触发 `checking`（`GET /api/chat/stream/status`），25s 内必触发 `force`（`replayAfterSeq/fullReconnect`），不再 25s+ 卡死
  2. 重连后已见 `ToolStarted(stableId)` 不重复入 `liveToolCalls`，仅新工具补齐；幂等通过 `chat_reconnect_dedupe` 类用例
  3. 无工具期（纯 token）仍为 `5/12/18/25/4`，首 token 5s 内不误判（已回退）
  4. `C:/tmp/f.bat analyze` 零告警；`chat_watchdog`/`chat_controller`/`chat_reconnect_dedupe` 更新，`test 200x` 全绿
- 优先级：P0　批次：单独 worktree（`chat_controller` 独占，阈值已回退到 5/12/18/25/4，本任务在此基线上增量）
- 状态：已收口（`NEXT`，工具期18s checking/25s force不受心跳假活，幂等已固化，2011全绿）
- 备注：截图 `webui_30002` 附件已归档；实现注意 `HeartbeatSseEvent` 的 `_recordTransportActivity` 若保留，需在看门狗侧以 `lastProgress` 而非 `lastTransport` 判工具僵死，避免心跳假活
