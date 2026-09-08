# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit）

---


## #98 下载自动重试 + 断点续传 [已收口 2026-09-08]

- 交付：main @ 5c19de7（合并 28bdaf8，19 文件 +1960/-208）。自动重试（瞬态错误退避 2s/8s/30s 最多 3 次，403/404 永久错误不重试）+ 断点续传（URL 任务流式写 `.part`，206 校验起点与总长 / 200·416 降级重下，完成后落 Downloads 清 .part）+ 重启恢复续传（有 .part 重置 queued，无 .part 维持 failed）+ Drift v5（temp_path/attempt_count，迁移含真实 v4 库升级测试）+ 下载页「第 N/3 次重试中」「已续传 N MB」提示（l10n 尾部 extension `AppLocalizationsDownloadResume98`）。
- 验收：独立复验 analyze 零告警 + 全库 2554 全绿（首跑挂 #90 已知 flaky，单跑复绿、复跑全量绿）+ 金照 26 绿。架构沉淀 skill references `downloads-auto-retry-resume-2026-09-08.md`。
- 待主人：真机复验（Android 实机下载中断恢复场景）。

---

## #99（已交付 b9df051，待主人真机复验）多会话 watchdog 同步静默 → 连锁强制重连风暴

- 交付：main @ b9df051（7 文件 +476/-30）。T1 重连/探活错峰 jitter（`reconnectJitterMax` 默认 1500ms，jitter=0 确定性同步路径保留；`_forceReconnect` 日志加 `jitterMs`）+ T2 afterSeq=0 全量重连 60s 冷却（命中降级 status 探活，`isThrottledFallback` 防绕过；afterSeq>0 不受限）+ T3 dio cancel 降 `[expected-cancel]` verbose。`ChatWatchdogConfig` 新增 `reconnectJitterMax`/`fullReconnectCooldown`/`random`/`customJitter`/`jitterForAttempt`（测试可 override）。
- 附带修：`e5ea242` 自带回归 `_syncSessionListRename` 无列表 provider 时抛错（补 `ref.exists` 守卫，与四兄弟对齐；`chat_api_client_regression_test` renameSession 全链路复绿）。
- 验收：analyze 零告警 + 全库 2568 全绿 + 金照 26 绿（`--update-goldens` 无意外变更）；`e5ea242` 的 8 用例 mutation 同步测试全绿（回滚事故已修复，sync 调用 10 处完整）。
- 待主人：多会话并发长工具跑 10 分钟，真机看 force reconnect 同秒触发是否归零。
- 收口教训：worktree 存活期间 main 有新合入（e5ea242）时收口整文件 cp 覆盖丢了 sync 功能 → 已回滚 + 逐段移植；以后收口一律先 diff 对照 HEAD 增量。
- 遗留方向（未做）：服务端 journal-only 分支补心跳（主人明确禁动 webui，略）。

---

## #99（多会话放大待取证）watchdog 同步静默 → 连锁强制重连风暴（诊断日志成串）

- 现象（2026-09-08 12:00-12:03 三会话 c131159d210e / 8d1e67593255 / 8e58a33c7584）：多会话并发流式时，WARN stale poll / ERROR force reconnect / ERROR dio cancel 成串出现；12:03:06 三会话 200ms 内同步触发 force reconnect。多会话并发易复现。
- 已证机制（源码行号）：
  - 阈值 5s/12s/18s/25s（chat_providers.dart:75-91），watchdog 判定 chat_controller.dart:3183-3252；任何 SSE 帧（含 `: heartbeat`）经 _handleSseEvent:1292 刷新传输活跃时间。
  - webui 服务端 `/api/chat/stream` 队列空 5s 必写心跳（hermes-webui routes.py:17391-17397）→ 客户端收不到心跳 = 字节未达客户端 = 通道/服务端真停顿，非「上游工具忙」。
  - 纯静默期收不到 id: 帧 → lastEventId 空 → afterSeq=0 → fullReconnect 从 seq 0 全量重放（chat_controller.dart:3133,3148-3151,3164-3169）。
  - dio GET cancel ERROR = _forceReconnect 内 stopStream 副作用（:3147），非人为取消。
- 多会话自放大假设（主嫌疑）：N 会话 N 条 SSE 共享同一服务器/隧道（frp tcpMux 单连接）；任一拥塞同停所有会话 → 看门狗齐触发；afterSeq:0 全量重放突发流量再挤同一通道 → 邻会话心跳被挤停 → 连锁重连（风暴）。
- 待办取证：① 复现时 PC 浏览器连同一服务器对照是否同停（切客户端/通道/服务端）；② 服务端加重连落点+心跳实际写出日志；③ 修复方向：多会话重连错峰 jitter + afterSeq:0 全量重放限频；④ journal-only 分支（routes.py:17352-17371）重放完直接 return 无心跳循环，评估补心跳。
- 验收：≥3 会话并发长工具执行 10 分钟，force reconnect 同秒触发为 0；无正文重复回放；dio cancel 噪音聚合。
- 状态：已登记，待取证后定修复批次。

---



## #76 二期（待一期真机复验后另批开工）

- 内置服务砍 embedded Python 打包瘦身（方案已定 · 未开工），见 `.todo/20260907.md` #76 条目。
