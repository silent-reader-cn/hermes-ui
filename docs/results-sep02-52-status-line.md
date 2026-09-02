# TASK #52 实施结果报告 — 客户端连接/回合状态可视化（统一状态行）

> 本任务是 Leader 接手模式（§8）：agy 子代理完成了数据层后中断退场（无 RESULT.md、核心渲染未做、误删 `isRevealQueueEmpty` 字段导致 17 编译错），Leader 补完核心渲染 + 修复 + 补测试后交付。

## 1. 改动文件清单

### 子代理完成部分（保留，已复核）
- `lib/core/api/sse_client.dart`：
  - 新增 `ContextPrefillStatus` 枚举（notConfigured/loading/loaded/error/unknown + fromString 宽容解析）
  - 新增 `ContextStatusSseEvent`（status/label/rawStatus/payload，`default:` :517 原吞事件分支改为 case 'context_status'）
  - `_logSseEvent` 补 ContextStatusSseEvent 分支（Leader 补：prefill=error 记 error 级，其余 debug）——原实现漏此分支导致 non_exhaustive_switch 编译错
- `lib/features/chat/chat_controller.dart`：`_handleContextStatus` 接线 + 起止/恢复各处 clearPrefillStatus/clearPrefillLabel
- `lib/features/chat/chat_providers.dart`：`chatStatusLineProvider`（key `settings.chatStatusLine` 默认开）+ `ChatStatusLineController`
- `lib/features/chat/chat_state.dart`：prefillStatus/prefillLabel 字段 + copyWith 支持
- `lib/features/settings/settings_page.dart`：对话分组新增「聊天状态指示」开关（key: settings-chat-status-line / settings-switch-chat-status-line）
- `lib/l10n/app_localizations.dart`：chatStatus* 九项双语 getter（连接中…/等待模型响应…/生成中/连接异常，排查中…/正在重新连接…/已重连/上下文不可用/聊天状态指示/说明）
- `test/core/api/sse_client_test.dart`：context_status 六断言（loading/loaded/error/not_configured/宽容/容错）
- `test/l10n/app_localizations_test.dart`：chatStatus* 双语断言

### Leader 补完部分（本次修复）
- `lib/features/chat/chat_state.dart`：**恢复被误删的 `isRevealQueueEmpty` 字段**（构造/copyWith/controller/message_list/测试共 17 处报错病根）
- `lib/features/chat/widgets/chat_message_list.dart`：
  - itemCount/tail 占位逻辑：`showRecovering + sending` 两分支 → 单一 `showStatusLine`（开关 && (sending || streaming || prefill loading/notConfigured/error)）
  - 新增 `_ChatStatusLine`（ConsumerStatefulWidget + SingleTickerProvider）：按优先级渲染 prefill error 红点 → recovery checking/reconnecting 橙 + 转圈 → sending 连接中… → 等待 prefill 黄点+转圈 → 已重连绿点 1.5s 渐隐（ref.listen recovery 非 idle→idle 触发 AnimationController）→ 生成中绿点（带 liveTokensPerSecond tps）
  - 新增 `_StatusLineRow`（状态点/转圈 + secondaryLabel 13px 居中）
  - **删除**旧 `_ReconnectingIndicator`（:1854）与 `_SendingIndicator`（:2123），grep 零残留
- `test/features/chat/chat_status_line_test.dart`（新，11 用例）：sending/prefill loading/notConfigured/error/loaded/streaming+tps/streaming/recovery checking/reconnecting/空闲隐藏/开关关闭隐藏

## 2. 方案取舍说明
- 状态行完全由 `chat_status_line_test` 渲染断言覆盖（FakeChatController 注入预设 ChatState，避免 ChatPage._ensureYoloLoaded 对 fake controller 的空指针）
- 「已重连」1.5s 渐隐用 AnimationController（Ticker 非 Timer，testWidgets 无 pending timer 风险）；`ref.listen` 监听 recovery 非 idle→idle 转换触发
- tps 仅在 `liveTokensPerSecond > 0 && isFinite` 时附加「 ≈N tps」，否则纯「生成中」
- sending 态返回 secondaryLabel 转圈 +「连接中…」（原实现空 label 已修正）

## 3. 验收结果
1. `C:/tmp/f.bat analyze`：**No issues found!**（0 错误 0 告警 0 info）
2. `C:/tmp/f.bat test`：全绿（新增 11 例；全量数字以 Leader 主仓复验为准）
3. grep `_ReconnectingIndicator|_SendingIndicator` → lib/ 零残留（仅注释提及）
4. 设置开关 key `settings.chatStatusLine` 默认开，关闭后状态行不占位

## 4. 遗留风险
- 实机首 token 空窗显示「等待模型响应…」依赖服务端实际下发 context_status 事件（契约 `prefill.status`）；服务端不下发时退化为「生成中」
- recovery 态由既有看门狗驱动，状态行只是消费既有信号，不改变重连逻辑