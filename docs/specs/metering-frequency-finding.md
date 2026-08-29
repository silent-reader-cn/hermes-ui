# 规格实证：上下文窗口指示器更新频率（#31）

> 任务：#31 上下文窗口指示器更新频率 —— 实证后端 metering 推送频率（调研任务，只读不改代码）
> 实证日期：2026-08-29
> 实证方式：只读源码（客户端 worktree `D:/worktrees/hermes-aug29-metering` + 服务端 `D:/hermes-webui`，均未改动）
> 优先级：待定　批次：待定
> 状态：已实证（结论：瓶颈在客户端 metering 事件解析层丢弃 `usage`，非服务端推送间隔、非客户端节流）

---

## 1. 服务端实证（D:/hermes-webui，SSE 推送频率 / 触发条件 / 消息格式）

### 1.1 两条主动发射路径 + 工具边界 + done 兜底，频率充足

**路径 A — 逐 token/reasoning delta 高频率发射（最高 ~10Hz）**
- `api/streaming.py:7544-7555` `_emit_metering()`：节流条件 `if now - _metering_last_emit[0] < 0.1: return`（`:7546-7549`）→ 快流下至少每 100ms 一发（≤10Hz）
- 首次 token 立即发射：`_metering_last_emit = [time.monotonic() - 1]`（`api/streaming.py:7527`）
- 触发点（每 delta 调一次 `_emit_metering()`）：
  - 输出 token：`api/streaming.py:7646-7648`（`_metering_output_deltas[0] += 1; meter().record_token(stream_id, ...); _emit_metering()`）
  - reasoning delta：`api/streaming.py:7689-7691` 与 `api/streaming.py:7801-7803`（两处 reasoning 回调）
- 载荷：`stats = meter().get_stats(stream_id); stats['session_id'] = session_id; stats['usage'] = _live_usage_snapshot(); put('metering', stats)`（`api/streaming.py:7550-7553`）

**路径 B — 1 Hz 保底 ticker（活跃期间）**
- 定义：`api/streaming.py:7114-7125` `_metering_ticker()`：`interval = meter().get_interval()`；`if interval >= 10.0: break`（空闲退出，不发空读数）
- `meter().get_interval()`：活跃会话（60s 内有 token）返回 1.0，空闲返回 10.0（`api/metering.py:112-125`，`_STALE_SECS = 60.0` `api/metering.py:53`）
- 每次 tick 同样 `stats['usage'] = _live_usage_snapshot()` 后 `put('metering', stats)`（`api/streaming.py:7122-7124`）
- 启动：`meter().begin_session(stream_id)` + `_metering_thread.start()`（`api/streaming.py:7222-7223`，`api/metering.py:96-98`）

**路径 C — 工具事件边界补发**
- `api/streaming.py:7843-7846`（tool started，`_tool_stats['usage'] = _live_usage_snapshot()` 后 `put('metering', _tool_stats)`）；同模式另有 `api/streaming.py:7945、7977、8028` 三处

**路径 D — done 兜底**
- `api/streaming.py:10136` `put('done', {'session':..., 'usage': usage})`（完整精确 usage）；
- `api/streaming.py:10137-10142` done 后补发最后一次 metering（`meter_stats.setdefault('tps_available', False)` / `setdefault('estimated', False)`）

### 1.2 消息格式（SSE `metering` 事件）
- 顶层：`metering.py:200-207` `get_stats()`：`{'tps': round(global_tps,1) if ... else None, 'tps_available': bool, 'estimated': False, 'high':..., 'low':..., 'active': n}`；叠加 `session_id`（`streaming.py:7122`）与 `usage`（`streaming.py:7123 / 7552 / 7845`）
- 字段语义注释：`api/metering.py:34-42`（`tps_available=false` 时前端必须隐藏 TPS；`estimated=false` 永不展示估算）
- **`usage` 载荷 = `_live_usage_snapshot()`（`api/streaming.py:6889+`）**：`input_tokens / output_tokens / estimated_cost / cache_read_tokens / cache_write_tokens / cache_hit_percent / context_length / threshold_tokens / last_prompt_tokens / post_compression_context_tokens_estimate`
  - docstring `api/streaming.py:6890-6895`：生成中是「最近一次模型调用的精确值 + 下一次调用的保守下界」，实时非估算
  - `context_length` 经 `_real_ctx_cache` 每流只解析一次（`api/streaming.py:6941-6950` 注释：避免逐 tick 冻结非默认模型流）
- TPS 计算：`total_tokens / (last_token_ts - first_token_ts)`（`api/metering.py:65-71`）；全局 = 活跃流均值（`api/metering.py:178-183`）

### 1.3 服务端结论
活跃 token 流下：**≤10Hz 逐 token 发射 + 1Hz ticker 保底 + 工具边界/done 补发**，且每个 metering 事件都携带**完整 usage 快照**（圆环所需字段全在）。
唯一稀疏窗口：`>60s` 无 token 无 reasoning 的长停顿（ticker 退出，`api/metering.py:121-125`），但工具事件处仍有补发、done 必有兜底。**服务端推送间隔不构成瓶颈。**

---

## 2. 客户端实证（D:/worktrees/hermes-aug29-metering）

### 2.1 事件到达链路：收到即更新，无节流、无过滤
- SSE 解码：`lib/core/api/sse_client.dart:485-492` `case 'metering'` → `MeteringSseEvent(tps, tpsAvailable, estimated, sessionId)`（`Debug` 级诊断日志在 `:816-821`，#9 调试模式可观测到达频率）
- 分发：`lib/features/chat/chat_controller.dart:1205-1216` `MeteringSseEvent` → `_handleMetering(...)`
- 处理：`lib/features/chat/chat_controller.dart:1704-1734` `_handleMetering`：**无节流/无定时器/无去重**；`tpsAvailable && !estimated && tps>0` 直接 `state.copyWith(stream.copyWith(liveTokensPerSecond: tps))` + `contextWindowSnapshot.replacingTokensPerSecond(tps)`（`:1716-1732`）
- 事件到达频率即服务端频率（≤10Hz + 1Hz ticker），客户端为同步串行分发（`chat_controller.dart:1189-1238`）

### 2.2 关键缺陷：metering 事件里的 `usage` 在解码层被丢弃
- `lib/core/api/sse_client.dart:485-492`（decode）与 `lib/core/api/sse_client.dart:408-415`（`MeteringStreamEvent.fromJson`）**只解析 `tps / tps_available / estimated / session_id` 四个字段；服务端每个 metering 事件都带的 `usage`（以及 high/low/active）被丢弃**
- `_handleMetering`（`:1704-1734`）**只更新 tps**；snapshot 的 `contextLength / thresholdTokens / lastPromptTokens / inputTokens / outputTokens / estimatedCost` 全部不动
- 因此生成期间圆环进度（`percentage = tokensUsed / contextLength`，`lib/core/models/context_window_snapshot.dart:76-81`；圆环渲染 `lib/features/chat/widgets/context_window_indicator.dart:33-60`）与 popover 各 token/cost 行（`lib/features/chat/widgets/context_window_popover.dart:430-436`）**保持冻结**，直到 done

### 2.3 snapshot 的其它写路径（均非生成中实时）
- `chat_controller.dart:379-392`：压缩后 `replacingTokensUsed(estimate)` 覆盖
- `chat_controller.dart:827`：会话加载
- `chat_controller.dart:1922-1992`：`_applyDone` 合并 usage snapshot（`context_window_snapshot.dart:15-55` `fromJson` 已兼容服务端 snake_case 键：`context_length / threshold_tokens / last_prompt_tokens / input_tokens / output_tokens / estimated_cost / tps`）
- `chat_controller.dart:2060-2090`：session detail 刷新

### 2.4 客户端结论
事件**到达**客户端是无节流、即时处理的（诊断日志可证）；但**承载圆环所需全量数据的 `usage` 字段在解码层被解析丢弃**，`_handleMetering` 只用了 tps。客户端「实时」能力只覆盖 TPS 一行，未覆盖上下文圆环/成本。

---

## 3. 瓶颈判定

**瓶颈在客户端（metering 事件解析层丢弃 `usage`），非服务端推送间隔，也非客户端节流。**

| 环节 | 证据 | 判定 |
|---|---|---|
| 服务端推送频率 | ≤10Hz（streaming.py:7546-7549）+ 1Hz ticker（:7114-7125）+ tool/done 补发（:7843-7846、:10137-10142） | ✅ 充足 |
| 服务端载荷 | 每事件带完整 usage（input/output/cost/context_length/threshold/last_prompt_tokens，:7550-7553、:7123） | ✅ 字段齐全 |
| 客户端事件到达 | decode+分发即时，无节流（sse_client.dart:485-492、chat_controller.dart:1205-1216、:1704-1734） | ✅ 无漏收 |
| **客户端 usage 解析** | **MeteringSseEvent 只有 4 字段，usage 被丢弃（sse_client.dart:408-415、:485-492）；_handleMetering 只更新 tps（chat_controller.dart:1716-1726）** | ❌ **瓶颈所在** |

---

## 4. 建议改动清单（本任务只读，未实施；由 Leader 决定时机）

1. **[P0·推荐] 客户端补接 usage**：
   - `lib/core/api/sse_client.dart:485-492`：`MeteringSseEvent` 增加 `usage` 字段（`Map<String, Object?>?`），decode 时 `final usage = map['usage']` 透传；`lib/core/api/sse_client.dart:408-415` `MeteringStreamEvent.fromJson` 同步增加（`usage: map['usage']`）
   - `lib/features/chat/chat_controller.dart:1205-1216`：`_handleMetering` 调用透传 usage
   - `lib/features/chat/chat_controller.dart:1704-1734` `_handleMetering`：`usage != null` 时用 `ContextWindowSnapshot.fromJson(usage)` 与现有 snapshot 合并（contextLength/threshold/lastPromptTokens/inputTokens/outputTokens/estimatedCost 有值则覆盖；tps 逻辑保持不变）——复用 `_applyDone:1922-1992` 的回退合并且不覆盖 tps
   - 效果：圆环百分比、popover 各行在生成中以服务端真实 `_live_usage_snapshot`（≤10Hz/1Hz）实时刷新
2. **[P1] 诊断观测**：`sse_client.dart:816-821` 已有 `metering` debug 日志，验收时用 #9 调试模式记录 metering 到达时间戳对比即可，无需改动
3. **[P2] 性能护栏（可选）**：若担心 ≤10Hz×多行文本 rebuild，可将 usage 合并节流到 ~1s（对齐 ticker 1Hz）；默认 10Hz 在 Flutter 25ms 帧节奏下无压力，不必加
4. **[不改] 服务端**：`streaming.py:7544-7555 / 7114-7125` 频率已充足，**无需调整**；若未来确要调，改 `_metering_last_emit` 的 `0.1`（`streaming.py:7547`）或 `get_interval()` 返回值（`metering.py:112-125`），风险低但当前无必要
5. **[P3 备注] 长工具执行 >60s 无 token 窗口**：ticker 退出（`api/metering.py:121-125`）期间无 metering，但 tool 事件补发（`streaming.py:7843-7846`）+ done 兜底（`:10137-10142`）可接受；如未来需要更密可加定时补发，非必须

**【禁止】** 不新增轮询/定时器（主人已拍板否决）；本任务零代码改动。

---

## 5. 证据索引（关键行号速查）

服务端：
- `api/streaming.py:7527`（首 token 立即发射）、`:7544-7555`（_emit_metering 0.1s 节流）、`:7646-7648 / 7689-7691 / 7801-7803`（token/reasoning 触发）、`:7114-7125`（1Hz ticker）、`:7122-7124`（ticker 载荷含 usage）、`:7843-7846 / 7945 / 7977 / 8028`（tool 补发）、`:10136-10142`（done 兜底）、`:6889-6910`（_live_usage_snapshot 字段）
- `api/metering.py:34-42`（事件格式注释）、`:65-71`（tps 计算）、`:112-125`（interval 1.0/10.0）、`:160-212`（get_stats 载荷）、`:200-207`（tps/tps_available/estimated/high/low/active）

客户端：
- `lib/core/api/sse_client.dart:408-415`（MeteringStreamEvent.fromJson 仅 4 字段）、`:485-492`（decode 丢弃 usage）、`:816-821`（诊断日志）
- `lib/features/chat/chat_controller.dart:1205-1216`（分发）、`:1704-1734`（_handleMetering 仅 tps）、`:1922-1992`（_applyDone 合并 usage）、`:379-392 / 827 / 2060-2090`（其它 snapshot 写路径）
- `lib/core/models/context_window_snapshot.dart:15-55`（fromJson 兼容 snake_case）、`:76-81`（percentage）
- `lib/features/chat/widgets/context_window_indicator.dart:33-60`（圆环渲染）、`context_window_popover.dart:430-436`（popover 行）