# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#56-#63 已全部收口誊写至 `.todo/20260905.md`；#64 胶囊方案 E 已收口至 `.todo/20260905.md`；#65-#70、#71、#73、#74、#75 已收口誊写至 `.todo/20260906.md`）

---

---

---

---

---

### #76 [P1] 内置服务 agent 门禁 + 砍 embedded Python（两期，方案已定 · 未开工）

- 位置：
  - 引导页内置 Tab：`lib/features/onboarding/widgets/builtin_tab.dart`（agent 缺失卡 + `:574/:615` 「启动并连接」按钮）
  - 设置页内置服务区：`lib/features/settings/webui_sidecar_section.dart`（开关行）
  - 解释器选择：`webui_sidecar_service.dart:299-314`（三级 venv→.venv→embedded 塌缩为一级）
  - 打包：`scripts/packaging/build_webui_bundle.ps1`（砍 python 下载/裁剪段）、`installer/hermes-ui.iss`（删 `webui\python` 打包行）
- 范围（两期）：
  - **一期（纯客户端门禁）**：未检测到 agent venv（`%LOCALAPPDATA%\hermes\hermes-agent\venv|.venv\Scripts\python.exe` 均不存在）时——① 引导页「启动并连接」置灰 + 引导卡给 Hermes Agent 官方安装文档外链 + 「我装好了，重新检测」按钮（主人拍板：入口可见、点击弹提示+外链）；② 设置页内置服务开关禁开，点击弹「需要先安装 Hermes Agent」+ 前往/重新检测；③ spawn 前 preflight `venv python -c "import yaml, cryptography"`，缺依赖给「解释器缺失/依赖缺失」独立诊断状态，watchdog 重拉失败不无限重试
  - **二期（打包瘦身）**：砍 embedded Python——`build_webui_bundle.ps1` 不再下载/裁剪 Python，`resolvePythonPath` 塌缩为一级（venv→.venv），embedded 兜底分支与对应单测删除；`.iss` 删 `webui\python` 打包行 + 加 `[InstallDelete]` 清存量用户 `webui\python`；`webui/server`（15MB）保留照旧捆绑（主人拍板：webui 仍捆绑安装）
- 现状 vs 预期：现状 = 未装 agent 时引导页仅 agent 检测卡提示、内置 Tab 照常可点，embedded python 33MB 随包分发给每个用户；预期 = agent 缺失即硬门禁不可启用内置服务，安装包 50.6MB → 约 18MB
- 验收：
  1. 全新机（无 agent）走引导页：按钮置灰 + 引导卡外链可达 + 重检按钮工作；装 agent 后重检 → 按钮解禁，一键启动并连接全通
  2. 设置页未装 agent：开关点击弹提示不解开关；装后可开
  3. 二期产物：新装包无 `webui\python`；覆盖安装后旧 `webui\python` 被清；sidecar 以 venv python 起服 + 发收消息正常（venv 内 pyyaml/cryptography 已实测覆盖 webui 依赖）
  4. `C:/tmp/f.bat analyze` 零告警 + `flutter test` 全绿（含解释器选择单测改写）
- 备注：#71（B′ 解释器选择）已收口 @ 9cfbfb5，本条一期沿用其 agent venv 检测逻辑；设置页门禁（①②）与二期均依赖同一检测结果 provider（建议命名 `agentEnvPresent`），一期实现后两处复用。

---

### #77 [P1] 宽屏右侧面板「返回」吞聊天——go 替换栈无来源可回，落空到 EmptyDetailPane

- 复现：宽屏（≥900）点击进入某聊天 → 点侧栏「记忆/定时任务」等模块 → 右侧进入功能页 → 按页面左上角返回 → 落到空面板（EmptyDetailPane），聊天页丢失
- 位置：
  - `lib/app/shell/sidebar_utility_toolbar.dart:132` 宽屏侧栏入口 `context.go(item.path)`（替换栈）
  - `lib/features/shared/app_back_button.dart:36-42` `canPop()`=false → `fallback='/'`
  - `lib/app/shell/adaptive_shell.dart:270-272` 宽屏 `/` 渲染 `EmptyDetailPane`
  - `lib/features/shared/app_navigation.dart:29-36` `openAdaptiveRoute`/`leaveToRoot` 宽屏分支
- 根因：go_router `go` 无历史栈，#51 拍板「宽屏保持 go」后宽屏右侧面板没有「上一页」概念；AppBackButton 无栈可 pop 只能兜底 `/`，宽屏 `/` 即空面板
- 主人裁决（2026-09-06 两轮）：①聊天↔模块/设置双向不得 replace（聊天输入中途去看设置，返回必须回原聊天继续输入，草稿由 #18 会话级草稿兜住）；②最终方案 = **全平台允许 push 积累栈，唯「点进具体聊天」先清栈再进入**
- 探针实证（2026-09-06，go_router 17.5.0，tap 驱动 context.push，等价生产路径）：
  1. ShellRoute 内 push **不复制 shell**——push 页渲染在 shell 内层 Navigator，侧栏单实例存活（#51「宽屏禁 push 防叠 shell」的前提不成立）
  2. push 后旧页 offstage 存活，pop 原样恢复（状态不丢）
  3. push 页上 `go('/chat/:id')` → push 出的页全部丢弃、栈回单层 = **点聊天天然清栈**
  4. shell builder 收到的 `state.matchedLocation` 不跟 push（停在底页）；`currentConfiguration.last.matchedLocation` 才跟——侧栏模块高亮如需跟随需换数据源
  5. 测试坑：裸调 `router.push()` 在 widget 测试环境静默无效，必须 tap 驱动 UI 回调里的 `context.push`
- 修复方案（改动面极小）：
  1. **宽屏模块/设置入口 `go`→`push`**：`sidebar_utility_toolbar.dart:132`、`openAdaptiveRoute` 宽屏分支改 `unawaited(context.push(path))`
  2. **宽屏聊天入口保持 `go`**（`session_list_page.dart` `_openChatRoute` 宽屏分支）= 主人规则「进聊天先清栈」，零改动
  3. **窄屏零改动**：全程 push 现状即主人规则（聊天必经列表中转，返回天然回列表）
  4. `AppBackButton` 零改动：push 层 `canPop=true` 自动走 pop；聊天（go 进）`canPop=false` 走 fallback `/`
  5. `leaveToRoot`（归档/删除会话）保持 `go('/')` 清栈；chat 内部 go 跳转（新会话占位/跳父/分支）保持 go——「聊天=重置点」
  6. 可选增强（验收不强制）：侧栏模块高亮源改读 `currentConfiguration.last.matchedLocation`；Android 系统返回三级分流第②级优先内层 Navigator canPop→pop
- 深度上限：不做（push 页轻量；病态积累需连续切 8+ 模块且从不进聊天/返回，Android 返回键可逐级弹）
- 现状 vs 预期：现状 = 宽屏从聊天进功能页按返回落到空面板；预期 = 模块页返回回原聊天（输入保留），聊天重进即清栈，窄屏不受影响
- 验收：
  1. widget 测试（tap 驱动，参照 session_open_chat_route_test.dart 范式）：宽屏 聊天A→设置→记忆 → 返回×2 依次回设置→聊天A（输入保留）；聊天A→设置→侧栏点聊天B → 栈清空、返回到 `/`；宽屏侧栏点模块后模块页出现、侧栏仍单实例（ShellProbe 计数=1）
  2. 窄屏回归：session_open_chat_route_test 既有两例直接绿（宽屏点会话仍 go，canPop=false 不变）
  3. 深链直进功能页 → fallback 现行行为不变
  4. `C:/tmp/f.bat analyze` 零告警 + 全量 test 绿
- 备注：go_router 17.5；改动面仅 sidebar_utility_toolbar.dart + app_navigation.dart 两个文件的两处 go→push，14 处 AppBackButton 挂点零改动。探针学习已录 skill（hermex-flutter-codebase）。

---

### #78 [P2] 宽屏消息右键菜单改悬浮面板（对齐聊天列表三点菜单形态）

- 现状：`chat_message_list.dart:2167-2169` onSecondaryTapDown/onLongPress → `showMessageActionMenu`（message_action_menu.dart）→ `showCupertinoModalPopup` + CupertinoActionSheet 底部弹出——宽窄屏同一形态
- 主人反馈（2026-09-06）：宽屏右键弹出的是窄屏式底部菜单，不符合桌面 UI；应改为聊天列表对聊天项三点菜单那种悬浮面板
- 方案：宽屏（≥900）右键 → `showCupertinoPopover` 锚定右键位置（项目已有先例：会话列表三点菜单 showCupertinoPopover 按 900 断点分流）；窄屏长按保持 ActionSheet；菜单项与 truncate 确认框逻辑不变
- 验收：宽屏右键弹悬浮面板（贴右键点、屏缘越界翻转）、窄屏长按仍底部 ActionSheet、五项动作全部正常
- 备注：需把 onSecondaryTapDown 的 globalPosition 传入菜单函数；message_action_menu.dart 增加宽屏变体，动作 tag 常量复用

---

### #79 [P1] 「从此处截断」按了不生效——合成 id 反查失配致静默 no-op

- 复现：右键消息 → 从此处截断 → 确认 → 下方消息不消失，无任何报错
- 位置：`chat_message_list.dart` `_showMessageActions` truncate case：`messages.indexWhere((m) => m.id == message.id)` → `if (index >= 0) await controller.truncateAt(index)`；`ChatMessage.id = messageId ?? '$role-$timestamp-$content'`（chat_message.dart:87）
- 根因（代码层定位，置信度高，开工后先实机复核）：UI 层 `entry.message` 与 `state.messages` 元素为不同实例，content 在 fromJson 管线（`_extractThinkingTag` think 剥离/媒体解析/附件 enrich）中可能不一致 → **无 messageId 的消息合成 id 两边不同** → indexWhere=-1 → `if (index >= 0)` 不成立 → 静默 no-op（服务端从未收到请求）
- 修复：索引直传——菜单闭包在 build 处直接携带该消息在 state.messages 的索引（displayItems→messages 坐标换算），废弃 id 反查；兜底：反查失败 setNotice 报错不静默
- 验收：右键截断确认后下方消息消失并刷新；无 messageId（合成 id）消息同样生效；失败有可见提示
- 备注：branch case 同样 id 反查（同款坑），一并修

---

### #80 [P1] 「编辑并重新发送」补截断语义（对齐 WebUI submitEdit）

- 现状：`MessageAction.edit` → `prefillComposer(text)` 仅回填输入框，原消息与后续全部保留；再发送 = 追加新回合、旧消息仍在——名不符实（主人问询确认应含截断语义）
- 参照：webui `ui.js:18117` `submitEdit` = `POST /api/session/truncate` keep_count=被编辑消息绝对索引（**删除被编辑消息及其后全部**）→ 本地 slice → 预填 composer → 发送
- 修复：edit case = truncate（keepCount=index，不含被编辑消息自己）成功后 prefillComposer；失败不清输入、报错可见。与 #79 同域共用索引解析
- 验收：编辑重发确认后原消息及之后消失、输入框预填、发送后新消息取代原位置；失败回滚可见
- 备注：菜单项文案不变；truncateAt 需支持「不含自己」模式（keepCount=index）或直接调 truncateSession

---

### #81 [P1] Windows 下 Ctrl+Enter 发送模式失效——onSubmitted 豁口致裸 Enter 照样发送

- 复现：设置发送快捷键为 Ctrl+Enter 后，裸按 Enter 仍发送（主人 Windows 实机反馈，2026-09-07 复报）
- 实机取证（2026-09-07）：`%APPDATA%\com.silentreader\Hermes\shared_preferences.json` 含 `"flutter.chat_send_shortcut_mode":"ctrlEnter"`——**设置持久化正常**，问题纯在输入栏执行层；两段式未开（prefs 无 composer_two_pane 键），主人走经典单行路径
- 位置一（主豁口，经典路径）：`chat_input_bar.dart:820-830` onSubmitted 守卫 `if (multiline && (isControlPressed || isMetaPressed)) return; unawaited(_submit())`——只拦「带修饰键的 Enter」（防双发），**不拦裸 Enter**；ctrlEnter 模式 maxLines=null，Windows 桌面引擎对 multiline 文本框裸 Enter 仍派发 onSubmitted（TextInputAction.done）→ 守卫放行 → 裸 Enter 照常 _submit
- 位置二（两段式独立豁口）：`_buildTwoPaneComposer`（chat_input_bar.dart:897-903）桌面端 Shortcuts 硬编码 `SingleActivator(enter) → SendIntent`，完全无视 sendMode——两段式 + ctrlEnter 模式下裸 Enter 同样发送
- 现状 vs 预期：现状 = ctrlEnter 模式裸 Enter 仍发送；预期 = ctrlEnter 模式裸 Enter 换行不发送、Ctrl+Enter 才发送
- 修复方向：① 经典路径 onSubmitted 守卫改按模式判定——`if (sendMode == ChatSendShortcutMode.ctrlEnter) return;`（该模式发送只走 Shortcuts 的 SendMessageIntent）；enter 模式行为不变（裸 Enter 提交）；enter 模式下 Ctrl+Enter 双路径（Shortcuts + onSubmitted）防双发需实现时探针定案（桌面端两路是否都触发）；② 两段式路径 Shortcuts 的 Enter→SendIntent 行按 sendMode 条件化（ctrlEnter 时桌面 Enter → InsertNewlineIntent，Ctrl+Enter → SendIntent）
- 验收：Windows 实机 ctrlEnter 模式裸 Enter 换行、Ctrl+Enter 发送；enter 模式裸 Enter 发送不双发；设置切换即时生效
- 备注：twoPane 路径（`_buildTwoPaneComposer`）若有同款 onSubmitted 豁口一并修；实现时先写 key 事件探针测桌面端 onSubmitted/Shortcuts 触发矩阵再动守卫

---

### #82 [P1] 底部跟随模式下组卡内 ToolCallCard 无法展开（点击闪一下回弹）

- 复现：live 底部跟随（流式/自动跟底）中，tools 组卡能展开（状态保持），但组卡内单个 ToolCallCard 点开即闪回收起
- 位置：`tool_call_card.dart` 持久化不对称——`ToolCallGroupCard._expanded`（:261/:274-315）有 PageStorage readState/writeState（identifier `tool-group-expanded-<key>`），重建后恢复；内层 `ToolCallCard._expanded`（:21/:67）**纯内存 setState 无持久化**
- 根因（代码层定位，开工后先探针复核重建源）：底部跟随模式下流式 token/reveal/滚动锚定频繁重建时间线子树，内层 ToolCallCard 被重建 → `_expanded` 复位 false → 视觉「闪一下」；外层组卡因 PageStorage 而幸存——不对称即证据
- 修复：ToolCallCard 复刻 GroupCard 的 PageStorage 模式（identifier `tool-call-expanded-<call.id>`，initState/didChangeDependencies 同步）；若探针发现重建源是 ValueKey(renderId) 变化导致整泡重建，需一并稳定 renderId（以探针为准）
- 验收：底部跟随流式中展开内层 tool 卡保持展开不回弹；历史视图行为不变；组卡收起再展开内层状态按 PageStorage 语义恢复
- 备注：thinking 伪工具行（_ThinkingRow）如无展开态不受影响

---

（当前队列：#76 方案已定 · 未开工、#77 方案已定 · 未开工、#78 P2 待开工、#79 P1 待开工、#80 P1 待开工、#81 P1 待开工、#82 P1 待开工）

