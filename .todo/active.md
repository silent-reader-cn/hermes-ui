# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（空——#56-#61 已全部收口誊写至 `.todo/20260905.md`，待新任务）

---

---


---

### #62 [P1] live 中连续工具卡不被空白 text 段聚合（「连续四张 tools 折叠卡」）

**主人报障（2026-09-05）**：聚合开关开启下，live 回合出现「执行代码×8,思考×5,终端×3,搜索文件×2」「执行代码×5,思考×3,读取文件×2,终端×2」「执行代码×3,思考×2,视觉分析×1」「执行代码×1,思考×1」四张相邻工具卡，卡间无任何可见文本，应并为一张。

**根因（实锤）**：`chat_providers.dart` liveTimelineProvider 的 text case 对**每个 text 断点**无条件 `flushBlock()` 切卡；但模型在工具间隙常吐 `'\n\n'`/空格 token（及 interim 分隔符残留），产生「零高度隐形文本段」照样切。对照组：transcript 路径 `coalescingAdjacent` 已判 `trim().isNotEmpty`（tool_call.dart:732），故历史回看是一张卡、仅 live 裂开。

**修复**：text case 改为「仅可见文本段才 flush + 渲染」；空白段跳过（textIndex 照常推进保持对齐）。coalesce=true 路径本不受影响（仅末尾 flush）。

**验收**：新文件 `live_timeline_blank_text_test.dart` 3 例（空白不切卡/可见文本仍切卡穿插/coalesce=true merged 不回归）先 RED 后 GREEN；live_timeline 系列既有 20 例零回归；全量 + analyze 绿。

---

### #63 [P1] 发送途中退页 → 输入栏 await 后用 ref 抛 StateError（platform_error 报告）

**主人报障（2026-09-05 OOB）**：`Bad state: Cannot use "ref" after the widget was disposed @ chat_input_bar.dart:265`。

**根因（实锤）**：`_submit()` 在 `await send(...)` 之后继续 `ref.read(...)` 清附件/草稿（成功分支）及回填输入框（失败分支）；发送在途切会话/退页 → widget dispose → `ref` 与 `_textController` 均不可触碰。

**修复**：await 前一次性捕获全部 notifier（三 provider 均无 autoDispose，随容器常驻，捕获安全）；await 后一律用捕获引用；失败分支 UI 回填加 `mounted` 守卫（草稿回填为数据层操作照常）。

**验收**：新文件 `chat_input_bar_disposed_ref_test.dart` 2 例（成功/失败路径 × 在途退页），stash 验证旧代码 RED → 修复 GREEN；全量 + analyze 绿。
