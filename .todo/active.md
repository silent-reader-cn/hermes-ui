# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#56-#63 已全部收口誊写至 `.todo/20260905.md`；#64 胶囊方案 E 已收口至 `.todo/20260905.md`；#65-#70、#71、#73、#74、#75 已收口誊写至 `.todo/20260906.md`；#76一期/#77/#78-#82 已收口誊写至 `.todo/20260907.md`；#83/#84/#85 已收口誊写至 `.todo/20260907.md` @77bdc49；#86 live 上下文指示器 0 已判定为后端行为不改码，记录在 20260907.md）

---

## #87 消息 meta 行时间出现条件与 tok/s 对齐（不独立出现）

- 主人要求：tok/s 不出现时时间也不能独立出现；时间只在 tok/s 旁追加，不把时间到处乱加（#83 实施跑偏为「有 timestamp 就显示」）。
- 位置：`lib/features/chat/widgets/message_bubble.dart` `_AssistantContent.build` meta 行（#83 后 380-390 行区域）。
- 复现：任一完成的 assistant 消息末尾均显示「14:30」等时间戳，时间到处都是。
- 现状 vs 预期：现状 = meta 行按 turnTps 与 timestamp 各自独立渲染；预期 = 整行由 `turnTps != null` 门控，时间为 tok/s 的尾缀（`18.5 tok/s · 14:30`），无速率数据整行不渲染。
- 根因：#83（77bdc49）规格原意「同车追加」被实施成「独立出现」；`turnTps` 仅回合结束落到末条 assistant 消息，故时间应只在回合末条出现。
- 实施：metaSpans 收集嵌套进 `if (message.turnTps != null)` 块；仅 timestamp 场景整行不渲染。
- 验收：①有 turnTps+timestamp → 「xx.x tok/s · HH:mm」；②仅 turnTps → 仅 tok/s；③仅 timestamp → 整行不渲染；④均无 → 不渲染 ✅ 单测 8/8（含改判的「仅 timestamp 不显示」）
- 状态：代码+测试已落地，待全量复验后随批次 commit。

---

## #88 工作区文件浏览页 Android 系统返回 = 目录级返回（非根目录返回上一级）

- 主人要求：工作区页浏览文件树时按安卓系统返回，未到根目录应返回上一级目录；到根目录后再按返回才退出页面（pop 回列表）。
- 位置：`lib/features/workspace/workspace_page.dart`（页面）、`lib/app/shell/adaptive_shell.dart:169` `_handleAndroidBack`（分流入口）。
- 复现：进入 `/workspace/:sid` → 点进子目录 → 按系统返回 → 页面直接 pop 回会话列表，目录层级丢失。
- 现状 vs 预期：现状 = 系统返回只有 shell 四级分流（弹层/Navigator pop/go('/')/双击退出），目录导航不参与；预期 = 页面非根目录时返回被页面消费（navigateUp），根目录时放行走原有 pop。
- 根因（架构实锤）：Android 上系统返回事件只达 shell 的 PopScope（root navigator 单页 + `canPop:!isAndroid` + onPopInvokedWithResult 接管）；页面内包 PopScope 收不到事件，且 shell 第 2 步 `Navigator.pop` 绕过一切 PopScope → 必须由 shell 集中询问页面级拦截器。
- 实施：
  1. 新增 `lib/app/shell/android_back_interceptor.dart`：LIFO 注册表，`handle()` 任一处理器返回 true 即消费（dispose 期间遍历安全）。
  2. `adaptive_shell.dart`：`_handleAndroidBack` 在「弹层关闭」与「Navigator pop」之间插 1.5 步 `AndroidBackInterceptorRegistry.handle()`。
  3. `workspace_page.dart`：initState 注册 / dispose 注销 `_handleAndroidBack`——`ModalRoute.isCurrent` 自证顶层（文件预览页/弹窗覆盖时不抢）、`valueOrNull` 就绪、非 `isAtRoot` 才消费并 `navigateUp()`。
- 验收：①非根目录 handle 消费且列表回上一级；②根目录 handle 放行；③dispose 注销无残留；④注册表 LIFO/注销/自注销语义 7 例单测 ✅；页面行为 3 例 ✅（39 例相关全绿）
- 范围外说明：FilePreviewPage 依赖系统返回自然 pop（Navigator 栈覆盖在 workspace 页上方，`isCurrent` 为 false 页面不抢），无需单独处理。
- 状态：代码+测试已落地，待全量复验后随批次 commit。

---

## #89（取证待复验）Android 保活常驻通知与「正在生成的会话」不同步

- 主人反馈：刷新会话列表后存在正在生成的会话，但前台保活常驻通知仍显示「暂无进行中会话」。
- 现状 vs 预期：预期 = 常驻通知文案与「是否有活跃流式会话」同步（有生成中会话 → 显示进行中）。
- 待办：定位保活通知文案更新链路（flutter_foreground_task + 会话流状态广播），确认为「刷新会话列表」路径上哪一环没触发通知更新（疑似只在流 start/stop 事件更新、列表刷新不重算）。
- 状态：仅登记，未排查。

---

## #90（时序抖动待治理）chat_scroll_bottom_bound_test 全量跑偶发失败

- 现象：`#23 发送消息后滚底不越界…（长会话长短混合）` 在全量套件下偶发失败（600 条懒加载 ListView 像素轨迹时序敏感），单跑恒绿；干净 main 全量亦复现（一次全绿一次挂），与 #87/#88 改动无关（已对照排除）。
- 待办：单独治理（放宽容差/减负载/拆分时序依赖），不阻塞本批次。
- 状态：登记，未修。

---

## #91 聊天 Markdown 图片块级化（不与文字同行镶嵌，避免撑高行高）

- 主人要求：聊天里图片渲染总是另起一行（前方已是换行/图片在行首则不重复另起），不要 inline 镶嵌在文字里撑高文字行；「其实就是不要 inline 以后图像组件全部 block」。
- 位置：`lib/features/chat/widgets/markdown_styles.dart`（builders 工厂 + 新增 `ImgBlockElementBuilder`）；接线 `message_bubble.dart`（user/assistant 两处 MarkdownBody）、`chat_message_list.dart`（`_SafeMarkdownBody` live 路径）。
- 现状 vs 预期：现状 = flutter_markdown `img` 非 block 标签，图片 widget 进段落 `Wrap(crossAxisAlignment: center)` 与文字同行，图片高度撑高整行；预期 = 图片独立成块（文本块 / 图片块 / 文本块），图片不参与文字行内排版。
- 根因（包内机制实锤，flutter_markdown 0.7.7+1 `builder.dart`）：`_kBlockTags` 不含 `img`；段内图片走 `else if (tag == 'img')` inline 分支加入 `current.children`，段落收口 `_mergeInlineChildren` + `Wrap` 同行混排。包支持自定义 builder `isBlockElement() => true` 注册为块级：进入图片前 `_addAnonymousBlockIfNeeded()` 先把已累积 inline 文本 flush 成独立块 → 图片单独成块 → 后续文本再起块。行首图片（前面无 inline）不产生空块 → 不重复另起行，天然满足主人「避免重复行」要求。
- 实施：
  1. 新增 `ImgBlockElementBuilder`（持有与 MarkdownBody 同源的 `imageBuilder` 回调，`visitElementAfterWithContext` 用 `element.attributes['src'/'alt'/'title']` 生成同一 `ChatInlineMediaWidget`，媒体卡片/门控/预览逻辑不变）。
  2. `createMarkdownElementBuilders` 增加可选 `imageBuilder` 参数，**仅在传入时注册 `'img'` builder**（memory_page / file_preview_page 两处未接媒体链路，保持包默认渲染不回归）。
  3. `createAssistantMarkdownBuilders` / `createUserMarkdownBuilders` 透传 `imageBuilder`；聊天三处调用点（bubble assistant/user + live list）把现有 imageBuilder 闭包同源传入。
- 范围外：流式纯文本路径（`isStreaming` 时用 `Text`）不含图片，无需处理；user 气泡同款 block 化。
- 测试：`markdown_image_block_test.dart` 4/4（行中图片前后文字拆独立块 / 行首图片无空文本块 / 连续两图独立纵向排列 / 未传 imageBuilder 不注册 img）。
- 验收：analyze 零告警 ✅；test/features/chat 591 全绿 ✅；金照 22/22 ✅（金照不覆盖含图 markdown）。
- 状态：已实施，随批次 commit，待主人真机复验。

---

## #93 下载进度常驻通知（Android 状态栏显示下载进度）

- 主人要求：手机端下载进行中在状态栏常驻显示下载进度通知；下载完成/失败/取消后消失。
- 位置：`lib/features/notifications/turn_notification_service.dart`（接口 + 生产实现）、`lib/features/downloads/download_controller.dart`（进度同步钩子）、`lib/l10n/app_localizations.dart`（尾部 extension）。
- 实施：
  1. 接口新增 `updateDownloadProgress({fileName, receivedBytes, expectedBytes, queuedCount})` 与 `clearDownloadProgress()`；
  2. 生产实现：Android-only（`androidPlatformOverride` 测试钩子 + `Platform.isAndroid`，Windows 空转）；通知 ID **1401**（复用 downloads 渠道），`showProgress + maxProgress:100 + progress + ongoing:true + onlyAlertOnce + importance:low`（进度条静默更新不响铃）；总大小未知（expectedBytes≤0）→ `indeterminate`；正文 = 「文件名 (已收/总量) · 还有 N 个排队」；标题 l10n `notifDownloading`（正在下载/Downloading）；
  3. `DownloadController`：下载开始与 onProgress 节流回调后 `_syncProgressNotification`（fire-and-forget）；完成（发 1301 完成通知后）、失败、worker finally 兜底均 `clearDownloadProgress`；
  4. 7 处测试 fake 补桩。
- 测试：service 4 例（Android show 参数组装/indeterminate 分支/非 Android 空转/cancel 1401）+ controller 3 例（进度调用与完成清除/失败清除/取消清除）。
- 验收：analyze 零告警 ✅；全量 2530 例仅 #90 已登记抖动测试失败（与本改动无关，单跑恒绿）✅。
- 状态：已实施，随批次 commit，待主人真机复验。

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

（当前队列：#91 已实施待收口 commit；#92 登记待排查；#89 保活通知不同步登记待排查；#90 滚动抖动登记待治理）
