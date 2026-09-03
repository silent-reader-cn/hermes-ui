# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

## [2026-09-03] 状态行文案删除末尾省略号「…」

**类型**：问题类（UI 文案优化）

**位置**：
- `lib/l10n/app_localizations.dart:1397-1403` — `chatStatusConnecting` / `chatStatusWaitingResponse` / `chatStatusInvestigating` / `chatStatusReconnecting` 四个 getter，中英文均带「…」
- `lib/features/chat/widgets/chat_message_list.dart:1942-1970` — `_ChatStatusLineState.build` 各状态分支 label 拼装；workSuffix 在 `:1932-1934`，格式「 · 已工作 MM:SS」

**范围**：仅聊天状态行 4 条状态文案（中英文同步）：
| 状态 | 中文 | 英文 |
|---|---|---|
| sending | 连接中 | Connecting |
| 等待 prefill | 等待模型响应 | Waiting for model response |
| 连接异常排查 | 连接异常，排查中 | Connection anomaly, investigating |
| 重新连接 | 正在重新连接 | Reconnecting |

不带省略号的（生成中 / 已重连 / 上下文不可用）不动；其它界面（加载中…/思考中…/发送中…/运行中…等）不在本次范围。

**复现**：聊天进入 prefill loading / sending / recovery checking / reconnecting 任一状态时，状态行显示「等待模型响应… · 已工作 01:05」，「… · 」连排形成视觉噪点；且状态行本身已带转圈动画，省略号的「进行中」语义冗余。

**现状 vs 预期**：
- 现状：「等待模型响应… · 已工作 01:05」（4 条状态文案末尾均有 …）
- 预期：「等待模型响应 · 已工作 01:05」（删除 …，转圈动画保留，其余不变）

**验收**：
1. `app_localizations.dart` 四 getter 中英文均去掉「…」
2. 同步更新 `test/features/chat/chat_status_line_test.dart`（含「…」断言约 10 处，`:108-291` 区间，如 `'等待模型响应…'` → `'等待模型响应'`、`'等待模型响应… · 已工作 00:00'` → `'等待模型响应 · 已工作 00:00'`）及 `test/l10n/app_localizations_test.dart:561`（`'等待模型响应…'` → `'等待模型响应'`）
3. `flutter analyze` 零告警
4. `flutter test` 全绿
5. 实机状态行 UI 确认：各状态不再显示「…」，转圈动画保留

---

## [2026-09-03] 聊天右上角菜单新增「Git 页面 / 工作区页面」跳转入口

**类型**：方向类（功能补充）

**位置**：
- `lib/features/chat/chat_page.dart:271-286` — 右上角 ellipsis 按钮（`chat-session-actions`）
- `lib/features/chat/chat_page.dart:386-484` — `_showSessionActions` 菜单项组装
- 复用路由：`/git/:sessionId` → GitPage（`lib/app/router.dart:178-187`）、`/workspace/:sessionId` → WorkspacePage（`lib/app/router.dart:144-163`），均 `context.push` 从右滑入

**范围**：仅聊天会话（sessionId 非空，空的会走 `_showSessionActions` 首行 `if (sessionId.isEmpty) return;` 自然禁用）。新增 2 个纯导航菜单项，不动其它会话操作。

**现状 vs 预期**：
- 现状：菜单只有重命名/置顶/归档/压缩/撤销/重试/YOLO/分支/导出/删除
- 预期：菜单增加「工作区文件」「Git 工作区」两个跳转入口 → `push('/workspace/$sessionId')`、`push('/git/$sessionId')`，跳转后返回聊天状态保留

**验收**：
1. 菜单出现「工作区文件」「Git 工作区」两项
2. 点击分别跳转会话对应工作区页 / Git 页，返回聊天不丢状态
3. `flutter analyze` 零告警、`flutter test` 全绿
4. 菜单文案与插入位置定稿（主人已确认按推荐）：文案 = 「工作区文件」（复用 `workspaceFilesTitle` 键，`app_localizations.dart:804`）+ 「Git 工作区」（/ Git Workspace，需新增键）；插入位置 = 分支/导出之前（操作项前），位于 `chat_page.dart:443`「创建分支」之前

---

## [2026-09-03] 窄屏快捷导航下拉按钮位置统一（右上角 → 大标题旁边）

**类型**：问题类（UI 一致性）

**位置**：
- `lib/app/widgets/adaptive_sliver_navigation_bar.dart:89-104` — 共享导航栏组件：窄屏下默认把 `NarrowNavigationDropdownButton` 塞进 `CupertinoSliverNavigationBar.trailing`（靠右上角），并 `Row` 拼到页面自带操作按钮前
- 受影响页面（均复用该组件且未 `showNarrowNavigationDropdown:false`）：tasks / kanban / workspace_manager / workspace / skills / insights / memory / settings / git（约 9 页）
- 参考基准：`lib/features/session_list/session_list_header.dart:270-276` + `session_list_page.dart:150-152`（`titleTrailing`）——会话列表按钮紧贴大标题正右方，`trailingLeft = 20 + 标题宽 + 4`

**范围**：窄屏（width < 900）下，上述大标题页右上角的「快捷导航下拉（▾）按钮」位置调整；宽屏不受影响（宽屏走 `SidebarUtilityToolbar`，`adaptive_sliver_navigation_bar.dart:76-87` 返回 44pt 紧凑条，无 dropdown）。

**复现**：手机/窄窗进入任务/看板/工作区/技能/统计/记忆/设置/git 任一页，顶部右上角出现 ▾ 按钮（与页面操作按钮挤一排）；而会话列表把 ▾ 贴在大标题「会话」右侧，两者不一致。

**现状 vs 预期**：
- 现状：非会话页的 ▾ 在导航栏右上角（trailing）
- 预期：与会话列表一致，▾ 贴在大标题右侧（随展开/收起平滑过渡）

**实现取向（主人已确认）**：改 `AdaptiveSliverNavigationBar` 共享组件——窄屏下将 dropdown 从 trailing 移到「大标题右侧」布局，一处改动 9 页全生效；不做逐页复制。

**验收**：
1. 窄屏下任务/看板/工作区/技能/统计/记忆/设置/git 各页 ▾ 均在大标题右侧，与会话列表观感一致
2. 宽屏无回归（仍走紧凑条 + 侧栏工具条）
3. `flutter analyze` 零告警、`flutter test` 全绿
4. 既有 `AdaptiveSliverNavigationBar` 相关测试同步更新（如有位置/结构断言）

---

## [2026-09-03] 会话列表筛选弹层 UI 风格对齐 iOS + 归档/全部改 checkbox

**类型**：问题类（UI 风格 / 交互控件）

**位置**：
- `lib/features/session_list/session_list_page.dart:1527-1801` — `_SessionFilterSheet`（筛选底部弹层）
- `:1550` — 圆角仅 `BorderRadius.vertical(top: Radius.circular(12))`（只顶部、视觉偏方角）
- `:1612-1712` — 「显示 subagent」区 + 「全部/归档/清除筛选」区
- `:1684-1710` — 全部 / 已归档 / 清除筛选 三行，`_SheetOptionRow` 渲染
- `:1748-1782` — projects 区
- `:1808-1845` — `_SheetOptionRow` 共用行组件：选中态 = 右侧蓝色 checkmark（`check_mark`，`:1835-1841`）

**范围**：仅会话列表筛选弹层（`_SessionFilterSheet`）这一个界面。深色/浅色均覆盖。

**主人反馈（2026-09-03 截图确认）**：
1. 界面「一点也不 iOS」——具体：弹窗是**方角**（对比其它弹层如 `adaptive_popover.dart:383` 14pt、`popover_dropdown.dart:25` 8pt，本弹层仅顶部 12pt 且无完整卡角观感）、列表**没边框**、底色**灰灰的**（深色模式下 `secondarySystemGroupedBackground` 与页面底对比度不足，卡片与背景糊成一片）
2. 「归档 / 全部」只有两个选项 → 建议改成 **checkbox** 样式（多选暗示但维持单选语义，视觉用左侧 checkbox 勾选代替右侧 checkmark）
3. projects 区「做成选项就没问题」→ **保持现状**（checkmark 单选）不动

**现状 vs 预期**：
- 现状：弹层顶部 12pt 圆角偏方、分组卡片无边框、选中态为右侧蓝色 checkmark；「全部/已归档」也是 checkmark
- 预期：弹层对齐 iOS 底部弹层观感（圆角完整/与其它弹层一致、分组卡片带合适边框或更高对比底色、层次清晰）；「全部」「已归档」两行改为左侧 **checkbox 勾选**（保持单选互斥语义，选中的那个打勾）；projects 区维持 checkmark 单选

**验收**：
1. 弹层圆角/卡片边框/底色观感对齐 iOS 与项目其它弹层，深色模式不再「灰糊一片」
2. 「全部」「已归档」显示为 checkbox 样式，且单选互斥（选中项打勾，另一项空框），切换正常；归档计数 `(N)` 后缀保留
3. projects 区、渠道区、清除筛选逻辑不受影响（仍 checkmark 单选）
4. `flutter analyze` 零告警、`flutter test` 全绿
5. 实机深色/浅色截图确认

