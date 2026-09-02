# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### #46 [P2] Windows 首次运行自安装引导页 — 一键拉取/配置/部署 agent + webui（方向类 · 主人 2026-09-02 拍板）

- 类型：方向类（Windows 端部署体验新功能）。主人指令：「在 Flutter 应用中提供一个自动安装引导页，帮助 Windows 用户一步一步从 GitHub 拉取、配置和安装部署，不用依赖 webui 才能运行我们的项目」。三个决策点已 clarify 拍板：**webui 仓库 = 官方 upstream（nesquena/hermes-webui，非主人 fork）**；**LLM 配置 = 引导页接管**（步骤向导填 provider/key，走 webui onboarding API）；**优先级 = P2**（排在 #44/#45 之后）。
- 位置（全部为新增，无现有代码可改）：
  - `lib/features/onboarding/` 新增安装引导页（后续确认承接 onboarding_page 还是独立路由）；复用 `ServerConnection{baseUrl,password}` + `ConnectionStore` 自动写入 `http://127.0.0.1:8787` 本地连接并激活
  - Windows 进程中转层（新增 `lib/core/install/`）：Dart `Process` 驱动 PowerShell 调官方 `install.ps1 -Stage <name> -NonInteractive -Json`，逐行解析 JSON 事件帧 → 进度条 + 日志流；`-Manifest` 列 stages、`{ok:false,stage,reason}` 错误帧 → 失败页直接展示
  - webui 部署：官方 upstream clone 后 `python -m pip install -r requirements.txt`（仅 pyyaml+cryptography，超薄）；启动 `server.py` 用 pythonw + DETACHED_PROCESS|CREATE_NO_WINDOW + log 重定向（bootstrap.py:622-658 现成模板语义）；轮询 `/health` 直到 ok（bootstrap.py wait_for_health 语义）
  - LLM 配置向导：走 webui onboarding API（已有 `/api/onboarding` 契约，参考 onboarding-projects 现有 client 能力）
- 现状 vs 预期：
  - 现状：hermes-ui 是纯远程客户端，onboarding 让用户填服务器地址+密码；**没有 webui 服务端就完全不可用**（依赖另装 Hermes Agent + webui 部署），普通 Windows 用户门槛极高。
  - 预期：Windows 首启检测 `%LOCALAPPDATA%\hermes` 不存在 → 引导页「本机部署」入口 → 分步安装（官方 install.ps1 免交互驱动：prereqs → git clone → venv → deps → PATH）→ 部署 webui → 启动 → 健康轮询 → provider 向导 → 自动建 ServerConnection(localhost) → 直接进聊天。已有连接时跳过（检测 `hermes` 命令 / `%LOCALAPPDATA%\hermes\hermes-agent` 存在）。
- 范围：
  - 仅 Windows 平台（Android 不需要自安装——手机连远程服务器是常态；勿扩展到 Android）
  - **不**动 API 契约（仍走同一套 webui /api/*）、不动远程连接模式（保留，多 ServerConnection 并存）、不改现有 10 个 feature
  - **不**重复造安装器轮子：官方 install.ps1 已做 git 拉取/venv/deps/PATH/更新标记，引导页只做「驱动 + 展示 + 联调」
  - webui 用官方 upstream 意味着端口默认 8787（非 fork 30002）——引导页写 localhost 连接一律以实际启动端口为准
- 验收：
  1. 全新 Windows（无 hermes-agent）：首启引导页识别「未安装」→ 点「本机部署」→ 分步安装完成（各 stage 有标题/进度/日志，失败有 stage+reason 错误提示与重试）
  2. 装完自动拉起 webui → /health ok → 自动写入并激活 ServerConnection(baseUrl=http://127.0.0.1:8787) → 进聊天页可对话
  3. provider 配置向导：填 key/选 provider → onboarding API 保存成功 → 模型列表可见
  4. 已安装环境：首启直接进连接页/聊天页，不重复安装
  5. `flutter analyze` 零告警；`flutter test` 全绿（新增安装中转层单测 + 引导页 widget 测试）
- 备注：实现时机在 #44/#45 收口后（现已收口，可启动）；官方 desktop（Electron）已存在同类能力，本项目差异化 = webui 契约 + Flutter 跨端（手机连远程、PC 连本机同一套契约）。可行性已实证：官方 install.ps1（`https://hermes-agent.nousresearch.com/install.ps1`，~245KB）内置 -Stage/-NonInteractive/-Json/-Manifest/-HermesHome 参数，注释明说供 GUI installer 调用。

---

### #50 [P1] Android 后台保活常驻通知重构 — 开关打开即常驻 + 通知显示进行中会话数（方向类 · 主人 2026-09-02 拍板）

- 类型：方向类（后台保活行为重构）。主人指令（原话）：「后台保活开关一旦打开，通知就直接常驻，通知内的文本指示现在有多少会话正在进行中。如果没有会话进行中，这个通知也不要消失。」已 clarify 拍板两项：**前后台都常驻**（通知一直挂着，最贴合「常驻」语义）；**通知文本只显示数量**（`N 个会话正在生成` / `暂无进行中会话`，不列会话标题）。
- 现状（带行号）：
  - FGS 启停由「切后台 + 正在生成」事件驱动：`background_keepalive_service.dart:226-241` `onAppLifecycleChanged` 中 resumed → `stopForegroundService`（:220-225）、切后台且 `isStreaming || activeStreamId` 非空且开关开才 `startForegroundService`（:228-234）；通知文本固定「Hermes 正在生成…」（:267-268）
  - 开关默认关且持久化：`notification_providers.dart:39` `bgForegroundServiceEnabled = false`；key `bg_foreground_service_enabled`（:85）
  - FGS 渠道 `hermes_foreground_service`「后台生成保活」由 flutter_foreground_task 首次 startService 时创建（`background_keepalive_service.dart:163-186` init 仅配置）→ 开关未开/未触发过后台生成 = 系统设置无此渠道
  - 服务端活跃流计数已就绪：`/health?deep=1` 返回 `active_streams`（hermes-webui `routes.py:11354` `_stream_runtime_diagnostics`，`len(STREAMS)`）；客户端 WorkManager 已有 dio 通路（`background_keepalive_service.dart:549-558`）
  - 插件热更能力已具备：flutter_foreground_task 11.0.1 `updateService()`（pub cache 已确认）
- 现状 vs 预期：
  - 现状：开关开 ≠ 通知出现；必须先切后台 + 恰好生成中才出现；回前台立即消失；文本无会话数、固定文案
  - 预期：开关一开 → 常驻通知**立即出现且前后台都常驻**；文本动态显示「N 个会话正在生成」/「暂无进行中会话」；**无会话进行中也不消失**；开关一关 → 立即停止消失
- 方案要点：
  1. FGS 启停挂到开关：`NotificationSettingsNotifier` 监听 `bgForegroundServiceEnabled` 变化 → `startForegroundService`/`stopForegroundService`（移除 `onAppLifecycleChanged` 的 resumed→stop 与后台条件触发逻辑，仅保留流状态上报用于文本更新）
  2. 进行中会话数数据源：前台 = chat_controller 流状态（activeStreamId 起止事件）即时 `updateService`；后台 = WorkManager 周期/加急任务拉 `/health?deep=1` 的 `active_streams` 后 `updateService` 刷新（复用现有 dio 通路）
  3. ⚠️ **Android 14+ 时长限制坑（必做）**：现 manifest 只有 `FOREGROUND_SERVICE_DATA_SYNC`，dataSync 类型 FGS 有 6h/24h 运行总时长限制，「永久常驻」会被系统强停 → FGS type 改 `specialUse`（manifest 加 `FOREGROUND_SERVICE_SPECIAL_USE` 权限 + `android:foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` 声明，自装 APK 无商店审核问题）；flutter_foreground_task `AndroidNotificationOptions` 同步
  4. 渠道随 FGS 启动即建（顺带解决「系统设置看不到常驻渠道」）；无关回合通知四渠道（turns/clarify/errors/downloads，启动预创建，不动）
- 范围：
  - 仅 Android 平台（FGS 不涉及 Windows）
  - 只动 `lib/features/notifications/`：`background_keepalive_service.dart`、`notification_providers.dart`、`background_keepalive_settings_page.dart`（开关文案辅以「开启后常驻通知」说明）、`android/app/src/main/AndroidManifest.xml` + 相关测试；`TurnNotificationService` 不动
  - WorkManager 回合完成兜底（15min 周期 + 加急 one-off + 补发通知）**保留不动**
  - 不改 hermes-webui 后端（`/health?deep=1` 已有 active_streams）
- 验收：
  1. 设置开「前台服务保活」→ 常驻通知立即出现（前台也在），系统设置出现「后台生成保活」渠道；关开关 → 通知立即消失
  2. 1 个会话生成中（前后台均可）→ 文本「1 个会话正在生成」；无会话进行中 → 「暂无进行中会话」且通知不消失
  3. 前台流开始/结束 → 文本即时更新（会话数 0↔1）
  4. 后台常驻 24h+ 仍存活（specialUse 类型，模拟 Doze/锁屏验证不被系统停）
  5. 回合完成/澄清/异常通知功能不受影响仍正常
  6. `flutter analyze` 零告警；`flutter test` 全绿（FakeBackgroundKeepaliveService 同步 + 新增开关直启/文本更新断言）
- 备注：与 #46/#47-#49 无耦合；实现时注意 `TurnNotificationService` 接口扩展的 6-fake 同步坑（漏一个编译挂）。「进行中会话」口径以服务端 `active_streams` 为准（App 被杀后依然准确），前台用本地流状态即时性补偿；客户端为单窗口模型，本地「同时多个流」场景罕见，数量以服务端为真值即可。

---

### #51 [P1] 返回动画全项目对齐 — 列表→工具页入口窄屏 push + 转场两侧统一 300ms（问题类 · 主人 2026-09-02 拍板）

- 类型：问题类（路由/导航动画）。#43 只修了「列表→chat」入口，本轮主人要求全项目排查：会话列表跳 技能/定时任务/设置/记忆/看板/统计/下载 等页面返回动画同样违和；随后追加拍板：**转场 push/pop 两侧统一 300ms（原 400ms 感知偏慢，两侧时长保持一致）**。
- 位置：
  - 新增 `lib/features/shared/app_navigation.dart`：`openAdaptiveRoute(context, path)`（窄屏 push / 宽屏 go）+ `leaveToRoot(context)`（窄屏可 pop 则 pop / 否则 go('/')）
  - `lib/features/session_list/session_list_utility_rows.dart:164`（工具行默认 `context.go(route)` → `openAdaptiveRoute`，7 入口：tasks/kanban/workspaces/skills/insights/memory/downloads）
  - `lib/features/session_list/session_list_page.dart:308`（窄屏头部设置齿轮 `context.go('/settings')` → `openAdaptiveRoute`）
  - `lib/app/widgets/narrow_navigation_dropdown.dart:55-91`（窄屏右上角下拉 7 入口 `context.go` → `unawaited(context.push)`，此组件仅窄屏渲染）
  - `lib/features/chat/chat_page.dart:407`（归档后回列表 → `leaveToRoot`）、`:470`（删除会话后回列表 → `leaveToRoot`）
  - `lib/app/widgets/hermes_page_route.dart`：`transitionDuration`/`reverseTransitionDuration` 400→**300ms**；`reverseCurve: Curves.easeOut → Curves.easeIn`（探针实锤：easeOut 反向播放变「先慢后快」开头拖沓，easeIn 与 push 对称「先快后慢」）
  - 测试：`test/features/session_list/session_tool_entry_route_test.dart`（新，#51 回归 2 例：窄屏头部下拉→技能 push canPop=true / 窄屏设置齿轮 push）；`test/app/hermes_page_route_test.dart`（pop 深帧采样 360ms→280ms 适配 300ms）
  - settings 测试缺陷修复：`test/features/settings/settings_page_test.dart:1899` 注入 `_FakeTurnNotificationService`——真实服务 `areNotificationsEnabled` 触发 DiagnosticsService 500ms 防抖 timer，原 400ms 动画恰好排空，300ms 后残留 Timer pending（stash 对照实证）
- 复现：窄屏点会话列表右上角下拉选技能/任务，或点头部设置齿轮 → 页面右滑入；点左上角返回 → 工具页不是向左让开，而是列表从右盖上来。返回动画整体比进入慢一拍。
- 现状 vs 预期：
  - 现状：工具页入口全 `context.go` 替换栈 → `AppBackButton` canPop=false → `go(fallback)` 正向转场（#43 同根因）；且 HermesPageRoute 两侧 400ms 但 reverseCurve=easeOut 反向播放变先慢后快，感知拖沓。
  - 预期：窄屏进入工具页 `push` 入栈 → 返回 `pop()` 当前页向右滑出、列表原地；宽屏双栏 `go` 替换；push/pop 两侧 300ms 且速度曲线对称（先快后慢）。
- 范围：仅前**往**工具页的入口（窄屏 push）；chat 内部 chat→chat 替换（新会话占位/跳父/分支）保持 `go` 不叠加栈；empty_detail_pane（宽屏双栏新建）、sidebar_utility_toolbar（宽屏侧栏）、onboarding/adaptive_shell（登录/系统返回）保持 `go`。
- 验收：
  1. 窄屏实机：列表→技能/任务/设置/记忆/看板/统计/下载 任一入口 → 右滑入；返回 → 工具页向右滑出，列表原地，无「列表从右滑入」违和
  2. 进入与返回动画节奏一致、同为 300ms 量级
  3. 宽屏双栏：侧栏切页不动画、右侧替换（桌面手感保持）
  4. chat 归档/删除会话后：窄屏 pop 回列表、宽屏 go 回列表
  5. `flutter analyze` 零告警；`flutter test` 全绿（2121，含 #51 回归 2 例 + settings timer 修复）
- 备注：根因链条与 #43 相同（go 替换栈 → 无 pop 可走 → 正向转场），本轮扩大到全部列表→工具页入口并用共享 helper 统一；duration 同步为 300ms 是主人实机感知拍板（非代码不一致——两侧原本都是 400ms，是 reverseCurve 造成的感知差异，一并对齐）。