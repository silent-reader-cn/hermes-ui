# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。



## [待实施] 意见4a：图片加载后滚动条被顶上去（进入已滚底，图一加载又回顶）

- **位置/范围**：`lib/features/chat/widgets/chat_message_list.dart` `_onScroll`（:369-410）+ 图片异步加载对 extent 的影响联动；`chat_media_view.dart`（只读参考，不改控制权看实现）
- **复现**：进入一个**含图片消息**的会话 → 初始 `_settleToBottom` 已滚到底部 → 图片异步下载/解码完成后撑高 item，`maxScrollExtent` 增大 → `distFromBottom` 变大 → `_onScroll` 里 `nearBottom`（`distFromBottom < _nearBottomThreshold`）变 false → 走 else 分支 `_nearBottom = false`（:399）→ 后续不再触发滚底跟随，视觉上滚动条被顶回中部/顶部。
- **根因**：`_onScroll` 把**非用户主动滚动导致的 extent 增长**（图片异步加载、布局高度变化）误判为「用户离开底部」，把 `_nearBottom` 置 false 且无后续恢复。注释（:395-397）已声明「任何非触摸手势不得置 `_userHasScrolled`」，但 `_nearBottom` 仍受影响。
- **现状vs预期**：
  - 现状：图片加载撑高 → `_nearBottom` 被误置 false → 不再跟随底部，滚动条上移。
  - 预期：用户未主动滚动（`!_userHasScrolled` && `!_isUserInteracting`）时，extent 增长（图片/未知高度加载）不应把进入时的底部跟随打断；应保持贴底跟随并回到底部。只有用户**真正手势上滚**才取消跟随。
- **改动要点**：修正 `_onScroll` 对 `_nearBottom` 的维护——非用户交互（`!_isUserInteracting` && `!_userHasScrolled`）下的 extent 增长时，`_nearBottom` 应保持 true 且（若原本贴底）滚动回底部；或对图片加载导致的布局变化走专门的 `_nearBottom=true` 保持路径。需读 `chat_media_view.dart` 确认图片加载如何影响列表布局（是否 AnimatedSize/frameBuilder），配合 §20/§21 教训（媒体占位防抖、extent 单帧跳变打断跟随）。恢复 session 滚动位置的场景（`_restoringOlderPosition`）不应被破坏。
- **验收**：
  - `C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿
  - 新增/调整 widget 测试：构造含异步图片消息的会话，pump 触发图片加载撑高 extent，断言滚动位置仍贴底（`position.pixels == maxScrollExtent` 附近）且 `_nearBottom == true`；用户手势上滚后不再跟随（保持现有语义）
  - 实机：进入含图会话 → 图片加载 → 滚动条**不再被顶上去**，始终贴底跟随

