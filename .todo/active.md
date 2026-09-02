# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。

> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
>
> 3. 本文件只保留未收口任务，收口即清出。

---

## #37 [问题类·实时性] live 流式上下文指示器读数实时更新（客户端轮询口径）

- 类型：问题类（实时性增强——《相对 WebUI 现状为新行为》）。
- 位置：
  - 指示器：`lib/features/chat/widgets/context_window_indicator.dart`（纯渲染，snapshot 驱动；环形百分比/阈值色）
  - snapshot 状态与挂载：`lib/features/chat/chat_state.dart`（ChatState.contextWindowSnapshot）；`lib/features/chat/widgets/chat_input_bar.dart:581-583`（watch snapshot 渲染）、:536-557（弹层打开时 read 一次）
  - snapshot **现有 4 处更新点**（现状底）：`lib/features/chat/chat_controller.dart` :838-848（会话详情/开始）、:391-397（压缩后）、:1939-1948（metering 仅刷 tps）、:2307-2311（回合 done 服务端详情整体刷新）
  - SSE 协议现状：`lib/core/api/sse_client.dart:199-210`（MeteringSseEvent=tps/tps_available/estimated/session_id，无 usage）；服务端 metering 载荷无 usage（`D:\hermes-webui\api\metering.py:34-42`）；done/compressed 事件才带 usage（sse_client.dart:423-434 `DoneStreamEvent.usage`）
- 复现：长回答生成中，环形百分比/token 数停在回合开始值，仅 cost/tps 行随 metering 轻动（done 后跳变到终值）.
（主人实测反馈）
- 现状 vs预期：
  -现状：#37 前 Flutter 与 WebUI **一致**（WebUI 亦仅 done/compressed/会话元数据事件时 `_syncCtxIndicator`，messages.js:5834 、:6085 、:6106-1111 守卫）；live 期间 token 读数不更新是设计现状。
  -预期（主人已拍板口径）：**客户端轮询**——live 活跃期间每 N 秒拉一次会话/usage 接口，更新 snapshot 读数；**不动服务端契约**。
  -**未决（实施时定）**：轮询频率 N（建议 2s）；轮询端点（候选：现有会话详情 / 新轻量 usage 端点，需实机确认响应体与开销）；轮询起止条件（建议仅 isStreaming 活跃时轮询，done/空闲即停）；轮询与流式渲染互不干扰（无 jank）
- 验收口径（待实施规格补全后拍死）：
  1. live 期间环形百分比随轮询**单调更新**（可观测变化）
  2. done 后读数与终值一致（无跳变/收敛）
  3. 轮询不干扰流式渲染（无卡顿）；空闲/非 live 零请求

---

## #40 [问题类·样式/主题适配] 澄清/审批选项面板（_PendingPromptCard）样式不齐——字号突兀、按钮/输入框高度不平齐

- 类型：问题类（样式统一，对齐项目紧凑风格）。
- 位置：
  - 渲染面板本体：`lib/features/chat/chat_page.dart:284-285`（`state.pendingAction.hasPendingPrompt` 时挂载 `_PendingPromptCard`）
  - 澄清分支（Clarification）：`:869-989`（标题 13pt :887-893、倒计时 13pt :900-906、问题 14pt :929-932、提示 12pt :981-984、选项按钮 `CupertinoButton.filled(padding h14/v8)` :942-951、输入框+提交按钮 Row :956-977）
  - 审批分支（Approval）：`:823-861`（标题 13pt colored :836-840、问题 14pt :844、选项按钮 `CupertinoButton.filled` 默认样式 :851-855）
  - 状态：`chat_controller.dart:1974-1999`（`_applyClarificationUpdate` 写 `pendingAction.clarificationPrompt`）；作答 `respondToClarification` :912-928
- 复现：（主人实测）聊天中收到 agent 澄清/审批请求时，卡片内按钮/输入框文字明显大于卡片内其他文字（~17-20 vs 12-14），与聊天界面整体风格不协调；输入框与提交按钮高度不平齐。
- 现状 vs 预期：
  -现状：卡片内文字阶梯混乱——标题 13 / 问题 14 / 提示 12，但**按钮（`CupertinoButton.filled`）与**输入框（`CupertinoTextField`）未指定字号，走 Cupertino **系统默认**（~17-20）→ 视觉突兀；输入框+按钮于 :956-977 **Row 直接排列无统一高度约束**（TextField 默认高 vs 按钮 `v8 padding` 高，像素级不平齐）。触发时同组件 _PendingPromptCard 的审批分支同款问题（:851-855）。
  -预期（主人已拍板）：
    1. **字号向项目聊天区现有紧凑字号阶梯对齐**（卡片内 12/13/14 阶梯，按钮/输入框文字收敛到该范围，与聊天界面/其他 UI 统一）
    2. **澄清与审批两分支一起统一**（同组件同规格）
    3. 按钮与输入框**高度平齐**（统一高度约束/对齐基线，如 Row 内 IntrinsicHeight 或统一 minHeight）
    4. 符合 iOS 设计观感（圆角/填充/间距延续现有 Cupertino 体系，不引入新组件风格）
- 待实施时定：具体字号落点（按钮 13？输入框 13？标题 13/问题 14 是否保留）、按钮/输入框统一高度具体值（建议 36-38，对齐输入区其他控件）。
- 验收口径：
  1. 澄清/审批卡片内所有文字统一在紧凑阶梯内（无系统默认大字号突兀）
  2. 输入框与提交按钮高度视觉平齐（同主题深浅色下均齐）
  3. 卡片样式与聊天区其他 UI（输入栏、工具卡）风格一致（字号/圆角/间距）
    4. `flutter analyze` 零告警；`flutter test` 全绿

  ---

## #41 [方向类·手势状态机] 聊天底部跟随取消时机重构——触摸即解锁，松手按方向/按压前状态定夺

  - 类型：方向类（行为状态机重构）+ 问题类（现状「一碰就丢跟随」）。
  - 位置：
    - 消息列表状态：`lib/features/chat/widgets/chat_message_list.dart`（`ChatMessageListState`：跟随态 `_userHasScrolled` :159、`_nearBottom` :153、`_isUserInteracting` :160；贴底阈值 `_nearBottomThreshold=80` :150-151）
    - 手势/滚动通知链：`NotificationListener<ScrollNotification>` :1390-1463（ScrollStart+dragDetails→interacting :1392-1395；UserScroll **forward=取消** :1404-1416；ScrollUpdate 拖拽 `delta.dy>0`/`scrollDelta<0` **=取消** :1425-1438；非拖拽 `scrollDelta<-1.0`**=取消** :1441-1456；ScrollEnd→interacting=false :1459-1461）
    -位置离底取消：`_onScroll` :375-388；恢复：:363-374
    -相位跟随复位：`_phaseSub` :213-236（sending/streaming 启用相位强制复位跟随 :217-233、:293-309）
    -steered 相位：`chat_state.dart:20-21`；steer accepted → 置 steered：`chat_controller.dart:1070-1072`
  - **术语约定（主人 2026-09-01 拍死，防再搞反）**：一律以**内容方向**命名——**「向上滑」** = 手指从**上往下**滑，内容相对视口**向上**移动（滚动**朝底部/新内容**方向，pixels 增大）；**「向下滑」** = 手指从**下往上**滑，内容相对视口**向下**移动（滚动**朝顶部/历史**方向（pixels 减小）。下方「现状/预期/验收」所有方向词均指此约定。
- 现状（取消跟随全清单——主人所问「现在都在什么时机被取消」）：（注：下述「向底部方向」= 主人术语「向上滑」；「向顶部/历史方向」=「向下滑」）
    1. `_onScroll` 位置离底 >80px 且（交互中或已离底）→ 置 `_userHasScrolled=true`（:378-383），**无方向判断**（任何方式离开底 80px 都算「用户上滚」）
    2. `UserScrollNotification.direction==forward`（= 滚动**向底部**方向 = 术语「向上滑」）→ 直接取消（:1404-1416）——**向底部方向滑反而取消跟随**
    3. `ScrollUpdateNotification` 拖拽 `dragDetails.delta.dy>0`（= 内容向上= 向底部）或 `scrollDelta<0` → 取消（:1425-1438）
    4. 非拖拽惯性滚动 `scrollDelta<-1.0` → 取消（:1441-1456）
    5. 恢复跟随仅三条路：滚回离底 <80px 且非交互中（:363-374）；sending/streaming 相位复位（:217-233）；换 session（:263）
    6. `_isUserInteracting` 有接线（ScrollStart+dragDetails→true :1394；UserScroll idle→false :1398、非 idle→true :1400；ScrollUpdate dragDetails→true :1421；ScrollEnd→false :1460）但**无「按压前跟随态」记录、无「松手方向恢复」**
  - 根因：现有逻辑「位置+方向」混合且**方向判断自相矛盾**（**向底部方向滑也触发取消**，:1404、:1425：即主人术语「向上滑」也会被砍），无「按压前跟随态」、无「松手恢复」——任何一滑（哪怕朝底部方向）都砍跟随，砍了不回头（除非滚回 80px 内）。
  - 预期（主人已拍板全口径）：
    **新状态机（两段式：拖动开始解锁 → 松手按方向/按压前状态定夺）**：
    1. **触摸判定**：**按下并拖动才算**（ScrollStart+dragDetails 系），拖动阈值**调敏感**（排除轻点）；拖动开始即置取消（解锁自由滚动，不滚到离底不算用户离开）
    2. **方向判定**：= 整个手势**累计位移**（起止方向，非松手瞬时速度）：
       - 累计**向上滑**（= 内容向上 = 滚动朝底部/新内容：手指从上往下滑）——按压前**跟随中** → **恢复跟随**（继续跟）；按压前**不跟随** → 若松手位置接近底部超 **80px 阈值** → **进入跟随**；否则保持不跟随
       - 累计**向下滑**（= 内容向下 = 滚动朝顶部/历史：手指从下往上滑）→ **一定取消跟随**
       - **无位移**（轻点已排除）→ 状态**回到按压前**（不改变）
    3. **其他任何操作都不得取消跟随**：除触摸手势外的任何来源（新消息到达、键盘/输入栏高度挤压、窗口 resize、程序滚动等）一律不得置 `_userHasScrolled=true`（需防 `_onScroll` :375-388 把布局挤压/程序滚动误判为用户离底——现注释 :376-377 仅防键盘/新气泡，需扩到全「其他操作」）
    4. **例外**：大纲跳转 `outlineJumpTo` / 高亮搜索定位 `scrollToHighlight` = 用户**主动导航**，算「用户主动取消」（离底即不跟随）
    5. **发送/Steer**（OOB）：
       - 普通发送新消息后 → **自动跟随**（维持现状相位复位 :217-233）
       - **Steer 发送**（时机 = **steer 请求发出时**，非 steered 相位）→ **不打开自动跟随**（不进跟随）
       - **若先前已跟随 → 不故意取消**（steer 保持当前跟随态原样）
  - 待实施时定：拖动起始阈值具体值（建议 ~4-8px 或 touchSlop 基准）；「按压前跟随态」记录字段（建议新增 `_pressFollowed` 等，勿覆盖 `_userHasScrolled`）。
  - 验收口径：
    1. 跟随中：**向上拖动**（= 内容向上 = 朝底部，松手仍近底）→ 保持跟随；**向下拖动**（= 内容向下 = 朝顶部）→ 取消
    2. 不跟随中：**向上拖动**接近底部（= 内容向上，松手 <80px）→ 恢复跟随；否则保持不跟随；轻点/无位移 → 状态不变
    3. 新消息/键盘/布局挤压/窗口 resize/程序滚动 → 不取消跟随
    4. 大纲跳转/高亮定位 → 离底不跟随（主动导航例外）
    5. 发送新消息 → 进跟随；steer 请求发出 → 不进跟随、先前已跟随则保持
    6. `flutter analyze` 零告警；`flutter test` 全绿（跟随状态机单测同步更新（现测 nearBottom/userHasScrolled 系）

  ---

## #42 [问题类·配色一致性] Fork 会话「分支」图标颜色同步——聊天标题 badge vs 会话列表副标题

  - 类型：问题类（配色/主题一致性）。
  - 位置：
    - 聊天标题「分支」badge：`lib/features/chat/chat_page.dart:233-258`（`parentSessionId != null` 时显示；图标 `CupertinoIcons.arrow_2_squarepath` :243-247，**固定 `CupertinoColors.secondaryLabel`**（未 resolveFrom），size 12）
    - 会话列表副标题「分支」图标：`lib/features/session_list/session_list_page.dart:1316-1324`（`isBranched = parentSessionId != null` :1313；图标同 `arrow_2_squarepath`，**`color: secondaryColor`**（:1311 = `secondaryText.resolveFrom(context)` 项目动态主题色），size 10）
  - 复现：（主人实测）Fork 会话进入聊天页后，标题下方「分支」badge 图标颜色与会话列表项副标题「分支」图标颜色不同。
  - 现状 vs 预期：
    -现状：两处**同一图标**（`arrow_2_squarepath`）但**着色源不同**：聊天标题 = `CupertinoColors.secondaryLabel`（Cupertino 内置动态色，未走项目主题 resolve）；列表副标题 = `secondaryText.resolveFrom(context)`（项目自定义 secondary 色）→ 渲染结果（尤其暗色/自定义主题下）色相/透明度不一致；另 **size 不一致**（12 vs 10）。
    -预期：两处「分支」图标**颜色同步**（统一走 `secondaryText.resolveFrom(context)` 或同一主题解析路径）；顺带统一 size（建议 10 或 12 二选一，实施时定）。
  - 验收口径：
    1. Fork 会话：聊天标题 badge 图标与会话列表副标题图标颜色一致（浅色/暗色均齐）
    2. （可选）size 统一（10 或 12）
    3. `flutter analyze` 零告警；`flutter test` 全绿
