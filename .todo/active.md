# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（空——2026-09-04 深夜 #53/#54 已收口誊写至 `.todo/20260904.md`，待新任务）

---

### #56 [P1] 离底阅读时 live 尾部引发视口小幅来回抖动（阅读锚点补偿链在 cacheExtent 边界震荡）

**主人报障（2026-09-04 深夜）**：live 流式期间上滑看历史，跟随已正确停止，但视口随 live 持续**小幅上下来回抖**；并补充关键观察——**此时列表最底部是「收起态的折叠卡（思考）」，收起态定高，理论上 extent 不该动**，抖得很奇怪。

**探针实证（已做，临时测试已删）**：widget 测试装配 40 条长历史 + `active_stream` 流式，触摸拖拽离底 150px（`userHasScrolled=true, nearBottom=false` 确认进入阅读态），随后 6 轮「4×token（64ms 间隔）+ tool_start + tool_complete」事件流、逐帧（50ms）采样 72 帧 `pixels/maxScrollExtent`——**pixels 全程钉死 2353.50 零位移、reversals=0**。结论：**简单 fixture 复现不了**，抖动需要更真实的条件（见下根因假设的触发要件），主人真机场景包含：live 文本段+工具组多条目、条目高度大（长 markdown）、视口顶部条目恰好「只露一条边」。

**根因假设（源码定位，`chat_message_list.dart`）**：唯一会在离底态动 pixels 的链路 = 阅读锚点补偿 `_maybeRestoreReadingAnchor`（:528，postFrame :1408-1416 在 `_userHasScrolled && !_nearBottom` 时每帧触发）。震荡机制：
1. `_updateReadingAnchor`（:453）选锚规则 = **第一个 `dy + height > 0` 的条目**——即允许「顶部只露 1px 边」的条目当锚点；
2. live 尾部每事件重建 → 视口顶部条目在 cacheExtent(250px) 回收边界**反复进出构建**；条目出树 → 锚点 key 解析失败或跳到下一个条目 → 参照系切换；
3. 顶部条目重新入树时按 ListView 估算高度布局（builder 懒构建下 extent/位置先估后真），`localToGlobal` 测得的 `currentDy` 与 `anchor.topOffset` 出现偏差 → `jumpTo(pixels+diff)` 补偿（:575-580）；下一帧真实高度替换估算 → diff 反号 → 反向补偿——**估算↔真实的反馈循环 = 小幅来回抖**；
4. 折叠卡「定高」不矛盾：抖的不是卡本身，是锚点参照条目在视口**顶部边界**的进出与估算跳动，live 事件只是持续提供「每帧重建」的泵。

**修复方向（实现时按取证定案，允许修正假设）**：
- A. **锚点准入收紧**：`_updateReadingAnchor` 只接受「可见高度 ≥ 阈值（如 24px 或条目高 1/3）」的条目当锚，拒绝贴边一条缝的条目——从源头消除参照切换；
- B. **补偿死区**：`_maybeRestoreReadingAnchor` 的 jump 阈值从 0.5 提到 ~4px，且**同锚点连续补偿方向反转时冻结 N 帧**（防抖锁）；
- C. **锚点稳定性**：锚条目出树时不立即换锚（保留旧 anchor 等它回来，或按 candidateKey 顺序降级到**下一个稳定条目**并同步刷新 topOffset，禁止在两个条目间来回横跳）；
- 三招可组合；实现前先用「真实形状」fixture 复现（长 markdown 条目 + 高度差大的估算场景 + 顶部贴边条目），**复现测试先 RED 再修**（skill 纪律：测「X 后行为」先断言 X 真发生）。
- 复现要件提示：主人场景 live 条目含多段（text 断点+工具组断点交替），条目数与高度方差是关键变量；探针简单版不抖正因条目全等高。

**范围**：`lib/features/chat/widgets/chat_message_list.dart`（锚点记录/恢复链）+ 新建 `test/features/chat/chat_reading_anchor_jitter_test.dart`（真实形状复现 + 修复后 reversals==0 断言 + 锚点贴边准入单测）。**禁碰** tool_call.dart/message_bubble.dart（#55 并行任务同文件域，若必须动列表文件则等 #55 合入后开工基线含 #55）。

**验收**：
1. 复现测试在修复前 RED（帧采样 reversals>0 或锚点条目 id 交替出现）、修复后 GREEN；既有滚动测试（anchor/bottom_bound/image_load/streaming_scroll 四文件）零回归。
2. `C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿。
3. 主人真机复验：live 长回合上滑看历史，视口稳定不抖；上滑/回底/大纲跳转行为不变。

**备注**：与 #55/#54 同文件域（chat_message_list.dart），串行开工（#55 合入后再扇 #56），避免并行冲突。若真机取证发现根因偏离假设（如 Clamping 与别的链互拉），以帧采样数据修正规格再动手，勿按假设硬改。

---

### #57 [P1] 聊天正文 MEDIA 文件链接（如 app-release.apk）点击无反应

**主人报障（2026-09-05）**：助手消息尾部 `MEDIA:` 渲染出的 `📎 app-release.apk` 蓝色链接点击无任何反应。

**根因（实锤）**：`chat_media_parser.dart:101-106` 把非图片 MEDIA 转成 markdown 链接 `[📎 name](url)`，但全仓 `onTapLink` 出现 0 次——三处聊天 MarkdownBody（`message_bubble.dart:221`（用户）、`:336`（助手）、`chat_message_list.dart:2620` `_SafeMarkdownBody`（live 文本段））均未接链接回调，flutter_markdown 默认 onTapLink 为 no-op → 链接可见不可点。

**修复规格**：
1. 新建共享 helper（建议 `chat_media_view.dart` 内 `Future<void> onChatMarkdownLinkTap(BuildContext, WidgetRef? 或 ref 读取器, Uri? link, String? text)`）：
   - `link == null` 直接返回；
   - kind = `MessageAttachment.mediaKindForName(link.toString())`；image → `showAttachmentPreview(isImage: true)`；其余 → `showAttachmentPreview(isImage: false, resolvedUrl: 原样 link, name: 文件名)`（预览页 `_AttachmentDownloadButton` 已有确认框+入队+进度，复用 #53 链路，勿另起炉灶）；
   - http/https 普通网页链接（kind=file 且 scheme http/https 且非 /api/media 场景）→ 走 `url_launcher launchUrl(externalApplication)`；无法启动时 in-app 提示。注意：MEDIA 生成的相对路径/file:// 已被 `ChatMediaResolver.resolveMediaUrl` 转 /api/media URL 的场景在预览页 `_effectiveUrl` 已兜底，链接点击这里同样把原值交给预览页即可。
2. 三处 MarkdownBody 加 `onTapLink: (text, href, title) => handler(...)`；`_SafeMarkdownBody` 需透传该回调。
3. 验收：widget 测试（新文件 `test/features/chat/chat_markdown_link_tap_test.dart`）——pump 含 `MEDIA:<path>.apk` 的助手消息 → tap 链接 → 断言 AttachmentLightbox 出现且下载按钮 key `attachment-download-button` 可点（注入 `createDownloadTestOverrides()`）；普通 https 链接 tap 走 url_launcher mock（`UrlLauncherPlatform`）。

---

### #58 [P1] 回合过程折叠胶囊应在用户气泡下方（现钉在上方）

**主人报障（2026-09-05）**：完成回合的「思考×13, 终端×10…」胶囊卡显示在用户提问气泡**上方**，应改到**下方**（提问气泡 → 胶囊 → 最终答复）。

**根因（实锤）**：`chat_message_list.dart:1816-1836` 折叠分支顺序 = 胶囊行 → userEntry → 最终答复，注释明写「胶囊行置于回合最上方（提问气泡之前）」（#55 当时拍板，现推翻）。

**修复规格**：collapsible 分支 displayItems 顺序改为：1) userEntry（提问气泡常显）→ 2) `_CapsuleListItem` → 3) 最终答复与中间条目（展开态逻辑不变）。非折叠分支不动。

**验收**：`turn_collapse_test.dart` 新增/改断言：胶囊 dy > 用户气泡 dy 且 < 最终文本 dy（getTopLeft 数值化）；其余 7 例语义不变全绿。

---

### #59 [P2] 回合胶囊样式与工具组卡零区分度（同底同框同图标）

**主人指示（2026-09-05 OOB）**：「大回合折叠的样式要和 tools 折叠卡有些差异，不然看起来没区分度」。

**根因（实锤）**：`collapsible_process_capsule.dart:113-118` 与 `tool_call_card.dart:333-339`（ToolCallGroupCard）装饰完全相同：systemGrey6 底 + radius10 + systemGrey4 边框 + fontSize12/w600 + checkmark_circle_fill 绿图标 + chevron 箭头。

**修复规格（区分方向）**：胶囊改为「轻量摘要条」形态，与工具卡拉开层级：
- 去实底：背景透明或极浅（不画 systemGrey6 盒），改左侧 3px 圆角竖条 accent（statusBlue/secondaryLabel 系，resolveFrom）+ 无边框；
- 文字 fontSize 13、常规字重（w400）、secondaryLabel 色，前缀「过程」文案保留 l10n；
- 状态图标缩小为 12 或移除（胶囊只在回合完成态出现，绿勾与工具卡重复）；
- 展开箭头保留但弱化 tertiaryLabel；
- 暗黑模式全部颜色显式 resolveFrom（skill 铁律），对比度扫描过 AA。
- 验收：`contrast_scan_test.dart` 零新增告警；金照若受影响 `--update-goldens`；胶囊 key `collapsible-process-capsule`/`process-capsule-header` 不变（测试依赖）。

---
