# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（空——2026-09-04 深夜 #53/#54 已收口誊写至 `.todo/20260904.md`，待新任务）

---

### #55 [P1] 完成回合顶部折叠按钮：默认只露最终文本（过程折叠胶囊回归·增强版）

**主人拍板（2026-09-04）**：「如果存在最终文本的话，就应该在本轮次最上方提供折叠按钮，默认折叠隐蔽掉本轮除了最终文本之外的其他内容」+ 两点推荐裁决均按推荐执行（1A 提问常显、2A 失败回合不折）。

**一句话**：回合完成且有最终文本 → 回合顶部一行折叠胶囊，默认收起本轮全部过程内容（中间文本/思考卡/工具卡），只露「胶囊行 + 主人提问 + 最终答复」。8/30 代 `CollapsibleProcessCapsule`（856b13d 撤销移除）的复活增强版：当年只收 think/tool，本次连中间过程文本一起收。

**规格**：
1. **触发条件**（全部满足才出现胶囊行）：
   - 回合已完成（流式中不出现；transcript 不含 streaming 消息，天然满足，但回合完成瞬间按钮出现需无跳变）；
   - 回合内存在**最终文本** = 最后一条带可见 content 的 assistant 消息（末条 content 为空但更早有助手文本时，取最末有文本者为最终文本；纯工具无文本回合 → 不折叠不显示按钮）；
   - 回合内**无失败项**（任一 ToolCall isError / 消息 error 态 → 整回合不折叠、不显示按钮——错误不该被默认藏起来，主人拍板 2A）。
2. **折叠态布局**（自上而下）：
   - 胶囊摘要行（chevron + 「思考 ×N, 终端 ×N, 中间文本 ×N」计数，复用 adaptiveActivityTitle 风格计数逻辑，l10n 新段 `turn55*` 尾部追加）；
   - 主人提问气泡（user 消息，**常显不受折叠影响**，主人拍板 1A）；
   - 最终答复文本（常显）；
   - 收起时隐藏：中间 assistant 文本、全部思考卡/工具卡（即 #54 时间线卡位内容整体收纳）。
3. **展开态**：胶囊行点按 → 展开显示全部过程内容，顺序仍按 #54 事件时间线语义渲染（回合级折叠包在 transcript 逐条气泡外层，两层语义不打架）；再点收起。
4. **展开记忆**：会话内记忆（widget 层 Set<turnKey>，翻页/切会话不重置，不持久化——对齐旧胶囊「首次折叠、不跨会话记忆」与 `_expandedNoticeIds` 模式）。
5. **设置开关**：`settings.turnCollapse`（默认**开**；关闭 = 完全维持现状逐条平铺）。放「对话」分区，与工具聚合开关同组。
6. **回合归属**：用 `TranscriptTurnClassifier.assistantTurnKeysByAnchorID`（turn:user:<idx> 键）分组 transcript；user 消息开启新回合；无 user 前导的孤儿 assistant 归入其自身隐式回合。
7. **多轮连续折叠**：每个满足条件的回合独立胶囊行，互不影响。

**范围（分区）**：
- `lib/features/chat/widgets/collapsible_process_capsule.dart`（新建，git 考古 `467fcfa:lib/...同名文件` 复活改造：children 从「仅卡」扩为「中间文本+卡」，摘要计数含中间文本数）
- `lib/features/chat/widgets/chat_message_list.dart`（itemBuilder 主循环 :1598 处按回合分组包装；展开态 Set 状态）
- `lib/features/settings/`（turnCollapse 开关 provider + 设置页行，模式照抄 toolGroupCoalesce）
- `lib/l10n/app_localizations.dart`（尾部追加 `turn55*` 段：胶囊摘要/展开收起语义文案，中英双语）
- 测试：新建 `test/features/chat/turn_collapse_test.dart`（触发条件三态/最终文本判定含末条空文本回退/失败不折/开关关平铺/展开收起切换/提问常显）+ settings 开关测试；金照 `--update-goldens`（chat 页默认折叠观感变化）

**现状 vs 预期**：现状完成回合逐条气泡全平铺（856b13d 回退后无任何回合级折叠），长回合刷屏；预期默认只见「胶囊行+提问+最终答复」三段式，一点展开看全过程。

**验收口径**：
1. `C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿。
2. 金照更新后目检：多工具回合默认折叠态 = 计数胶囊 + 提问 + 最终答复；展开态内容顺序符合 #54 时间线。
3. 边界：纯工具回合（无最终文本）不出现按钮；含失败工具回合不折叠；流式中无按钮、完成瞬间出现且不闪烁跳位；开关关闭 = 与 main 现状逐像素一致。
4. 滚动跟随/大纲跳转/搜索高亮（`_itemKeys`/`_highlightKey` 机制）不回归——折叠后 renderId 分组变化需保持 key 查找兼容。

**备注**：与 #54 同域（chat 渲染层），开工基线必须含 f2fd2b6；旧胶囊的 noticeCount/injectedExpanded 联动（注入通知卡）本次不恢复，注入卡归入「过程内容」随折叠收纳。

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
