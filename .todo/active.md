1|# Hermes UI TODO — Active（进行中队列 · 完整规格）
2|
3|> **规则**：
4|> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
5|> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
6|> 3. 本文件只保留未收口任务，收口即清出。
7|
8|---
9|
10|
11|
12|---
13|
14|### #56 [P1] 离底阅读时 live 尾部引发视口小幅来回抖动（阅读锚点补偿链在 cacheExtent 边界震荡）
56|
57|**主人报障（2026-09-04 深夜）**：live 流式期间上滑看历史，跟随已正确停止，但视口随 live 持续**小幅上下来回抖**；并补充关键观察——**此时列表最底部是「收起态的折叠卡（思考）」，收起态定高，理论上 extent 不该动**，抖得很奇怪。
58|
59|**探针实证（已做，临时测试已删）**：widget 测试装配 40 条长历史 + `active_stream` 流式，触摸拖拽离底 150px（`userHasScrolled=true, nearBottom=false` 确认进入阅读态），随后 6 轮「4×token（64ms 间隔）+ tool_start + tool_complete」事件流、逐帧（50ms）采样 72 帧 `pixels/maxScrollExtent`——**pixels 全程钉死 2353.50 零位移、reversals=0**。结论：**简单 fixture 复现不了**，抖动需要更真实的条件（见下根因假设的触发要件），主人真机场景包含：live 文本段+工具组多条目、条目高度大（长 markdown）、视口顶部条目恰好「只露一条边」。
60|
61|**根因假设（源码定位，`chat_message_list.dart`）**：唯一会在离底态动 pixels 的链路 = 阅读锚点补偿 `_maybeRestoreReadingAnchor`（:528，postFrame :1408-1416 在 `_userHasScrolled && !_nearBottom` 时每帧触发）。震荡机制：
62|1. `_updateReadingAnchor`（:453）选锚规则 = **第一个 `dy + height > 0` 的条目**——即允许「顶部只露 1px 边」的条目当锚点；
63|2. live 尾部每事件重建 → 视口顶部条目在 cacheExtent(250px) 回收边界**反复进出构建**；条目出树 → 锚点 key 解析失败或跳到下一个条目 → 参照系切换；
64|3. 顶部条目重新入树时按 ListView 估算高度布局（builder 懒构建下 extent/位置先估后真），`localToGlobal` 测得的 `currentDy` 与 `anchor.topOffset` 出现偏差 → `jumpTo(pixels+diff)` 补偿（:575-580）；下一帧真实高度替换估算 → diff 反号 → 反向补偿——**估算↔真实的反馈循环 = 小幅来回抖**；
65|4. 折叠卡「定高」不矛盾：抖的不是卡本身，是锚点参照条目在视口**顶部边界**的进出与估算跳动，live 事件只是持续提供「每帧重建」的泵。
66|
67|**修复方向（实现时按取证定案，允许修正假设）**：
68|- A. **锚点准入收紧**：`_updateReadingAnchor` 只接受「可见高度 ≥ 阈值（如 24px 或条目高 1/3）」的条目当锚，拒绝贴边一条缝的条目——从源头消除参照切换；
69|- B. **补偿死区**：`_maybeRestoreReadingAnchor` 的 jump 阈值从 0.5 提到 ~4px，且**同锚点连续补偿方向反转时冻结 N 帧**（防抖锁）；
70|- C. **锚点稳定性**：锚条目出树时不立即换锚（保留旧 anchor 等它回来，或按 candidateKey 顺序降级到**下一个稳定条目**并同步刷新 topOffset，禁止在两个条目间来回横跳）；
71|- 三招可组合；实现前先用「真实形状」fixture 复现（长 markdown 条目 + 高度差大的估算场景 + 顶部贴边条目），**复现测试先 RED 再修**（skill 纪律：测「X 后行为」先断言 X 真发生）。
72|- 复现要件提示：主人场景 live 条目含多段（text 断点+工具组断点交替），条目数与高度方差是关键变量；探针简单版不抖正因条目全等高。
73|
74|**范围**：`lib/features/chat/widgets/chat_message_list.dart`（锚点记录/恢复链）+ 新建 `test/features/chat/chat_reading_anchor_jitter_test.dart`（真实形状复现 + 修复后 reversals==0 断言 + 锚点贴边准入单测）。**禁碰** tool_call.dart/message_bubble.dart（#55 并行任务同文件域，若必须动列表文件则等 #55 合入后开工基线含 #55）。
75|
76|**验收**：
77|1. 复现测试在修复前 RED（帧采样 reversals>0 或锚点条目 id 交替出现）、修复后 GREEN；既有滚动测试（anchor/bottom_bound/image_load/streaming_scroll 四文件）零回归。
78|2. `C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿。
79|3. 主人真机复验：live 长回合上滑看历史，视口稳定不抖；上滑/回底/大纲跳转行为不变。
80|
81|**备注**：与 #55/#54 同文件域（chat_message_list.dart），串行开工（#55 合入后再扇 #56），避免并行冲突。若真机取证发现根因偏离假设（如 Clamping 与别的链互拉），以帧采样数据修正规格再动手，勿按假设硬改。
82|
83|---
84|