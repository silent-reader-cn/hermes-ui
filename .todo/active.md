# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#56-#59 已于 2026-09-05 收口誊写至 `.todo/20260905.md`；当前待开工：#60/#61）

---

---

### #60 [P1] live 正文 interim 快照被当新段落重复追加（「先/先」「…重跑/…重跑」叠影）

**主人报障（2026-09-05，会话 9a8c8c50b982）**：Android 端 live 流式正文出现「先」「先」两个独立段、「先验证验证锁屏检测验证锁屏检测命令可用…」滑动窗口式重叠、尾部「跑」。「」「跑」。」重复。服务端存档该回合最终消息（215 号）是干净的单句 → 重复纯属客户端 live 渲染，done 后 transcript 刷新会自愈。

**根因（实锤）**：`chat_controller.dart:1880 _handleInterimAssistant` 只有 `isReplayConnection` 分支做 `deduplicatedReplayText` + `currentContent.contains(append)` 吞段兜底（1891-1913）；**非 replay 的 else 分支（1916）无条件 `append = '\n\n$text'` 整段追加**。agent 侧 interim 回调对同一回合多次触发时携带的是「累积快照」式文本（长度递增），服务端 `_is_visible_output_echo`（streaming.py:7557）只在快照是 token 流尾部子串时标 already_streamed——token 未经 stream_delta 的路径 STREAM_PARTIAL_TEXT 为空，全部快照都以 already_streamed=False 下发 → 客户端把每个快照当独立新段落拼接。官方 WebUI（messages.js:5371）同样 `+= '\n\n'`，但其 anchor/scene 机制按事件覆盖渲染，未暴露此形态。

**修复规格**：非 replay 分支同样加去重防线：① `currentContent.contains(text)` → 整段吞掉；② 否则尝试「快照增量」语义——若 existing content 尾部与 text 头部存在 ≥N 字符重叠（或 text 以已展示内容的前缀开头），只拼接残余部分；③ 短片段（如单字「先」）优先怀疑快照前缀而非新段落。补 widget 测试：连续喂两个递增快照 → 断言渲染文本无重叠段。

---

---

### #61 [P1] 用户消息双气泡：乐观消息与服务端注入行 diff-merge 指纹永不相等

**主人报障（2026-09-05）**：发送带截图的消息后出现两条用户气泡——第一条干净（文本+附件卡），第二条带 `[Workspace::v1: ...]`、`[Attached files: ...]`、`[screenshot]` 原文注入标记。

**根因（实锤）**：本地乐观消息（`chat_controller.dart:986`，id=`local-*`，content=用户原文）与服务端 transcript 权威行（content 被服务端注入 `[Workspace::v1]` 前缀行 + `[Attached files]` 行 + 附件占位符）永不相等；`chat_diff_merge.dart:149` 指纹匹配要求 `localContent == serverContent` 精确相等 → 不匹配 → 服务端行按「缺失项」补入（90 行），乐观消息按「尾部未落库项」保留（102-106 行）→ 双气泡，且第二条暴露注入标记原文。

**修复规格**：`isMessageMatch` 对 user 角色放宽：① 新增归一化函数剥离服务端注入标记（`^\[Workspace::v1: .*\]\n?`、`\[Attached files: .*\]`、`\[screenshot\]`/`\[image\]` 等占位符、trim）；② 归一化后互为前缀/包含 + 时间窗 ≤120s 即匹配；③ 匹配命中后 `_patchMessage` 保留服务端行但 content 用归一化展示文本（勿把注入标记渲染给用户）。补 diff-merge 单测：乐观消息 vs 带注入标记服务端行 → 单条渲染。
