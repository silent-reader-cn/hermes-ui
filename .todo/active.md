# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### #43 [P1] 返回动画方向错误 — 进入聊天路由 go 替换栈导致返回变正向转场（问题类）

- 类型：问题类（路由/导航动画方向）。
- 位置：
  - `lib/features/session_list/session_list_page.dart:870` `_openSession`（点击会话行 → `context.go('/chat/...')`）
  - `:701` `_onNewSession`（新建会话 → `context.go('/chat/...')`）
  - `:1065` `_onBranch`（分支新建 → `context.go('/chat/...')`）
  - `lib/features/shared/app_back_button.dart:36-42`（`canPop()==true → context.pop()` / 否则 `context.go(fallback)`）
  - `lib/app/router.dart`（ShellRoute 内顶层路由统一 `HermesPage` 转场）
- 复现：窄屏（手机）点会话进聊天 → 聊天页右滑入；点左上角返回 → 会话列表从右往左盖上来（正向转场），而非聊天页从左往右滑出露出底层列表。
- 现状 vs 预期：
  - 现状：会话列表进 chat 全用 `context.go`（替换整个栈）→ chat 页 `canPop()==false` → `AppBackButton` 走 `context.go(fallback)` → 会话列表当**新 route** 又跑一次**正向转场**（从右滑入）。`HermesPageRoute` 本身 pop 是 iOS 标准（当前页向右滑出），只是从未走 pop。
  - 预期：窄屏（<900）进入聊天用 `context.push` 真入栈 → 返回走 `context.pop()` 反向（聊天页向右滑出、会话列表保持不动）；宽屏（≥900）双栏保持 `go`（不破坏侧栏选中态）。
- 范围：仅 `session_list_page.dart` 三处 `context.go('/chat/...')` 改走新 helper `_openChatRoute`（窄屏 push / 宽屏 go）；`AppBackButton` / 路由表 / `HermesPageRoute` 不动。深链直进 `/chat/:id` 时 `canPop()==false` → `go('/')` 兜底，已有行为覆盖。
- 验收：
  1. 窄屏实机：点会话 → 右滑入；左上角返回 → 聊天页向右滑出（会话列表原地，无「从右滑入」违和）
  2. 宽屏双栏：点会话 → 右侧替换不动画（桌面手感保持）
  3. `flutter analyze` 零告警；`flutter test` 全绿
  4. 新增回归测试 `test/features/session_list/session_open_chat_route_test.dart`：窄屏 390×844 点击会话 → ChatStub 显示 canPop=true（push 入栈）→ 点 AppBackButton pop 返回列表；宽屏 1280×800 → canPop=false（go 替换栈）→ 返回走 go(fallback)
- 备注：根因 2026-08-31 已实锤（reference `router-go-vs-push-transition-direction-2026-08-31.md`，方案 A 推荐窄屏 push）；本次为落地实施，参考 SKILL.md「规格修正裁决模式」——08-28 #17 曾拍板 pop 向左、08-28 晚 #22 改判 iOS 标准向右，本条目与 #22 一致（pop 当前页向右滑出）。

---

### #44 [P2] 后台保活收进「高级设置」二级菜单 + 权限设置引导展开为独立多项（方向类·结构调整）

- 类型：方向类（设置页结构调整，2026-09-02 主人指令：「把设置界面的后台保活单独做成一个高级设置菜单，在二级菜单中把权限设置引导展开成多项，不要四个按钮放在一项」）。
- 位置：
  - `lib/features/settings/settings_page.dart:90`（`_BackgroundKeepAliveSection` sliver 挂载点，通知分组后）
  - `:676-781`（`_BackgroundKeepAliveSection` 全分组：前台服务开关 :689-700、WorkManager 状态 :701-710、HyperOS 引导 tile `settings-bg-hyperos-guide` :711-758 的 `subtitle: Wrap` 内 4 个 `_buildGuideButton`（自启动/省电无限制/联网控制/通知权限），`_buildGuideButton` :763-781）
  - `:302-402`（`_AdvancedSettingsSection`「高级设置」分组：7 个二级入口，统一 `CupertinoListTile` + chevron_right + `Navigator.push(HermesPageRoute(...))` 模式）
  - `lib/features/settings/settings_subpages.dart:288-302`（DesktopSettingsPage 二级页范本：`CupertinoPageScaffold` + `CupertinoNavigationBar(leading: PopBackButton, middle: title)` + `ListView`）
  - `lib/features/notifications/background_keepalive_service.dart:19-32`（`HyperOsSettingType` 4 值：autoStart/batteryOptimization/networkControl/notificationSettings）
  - l10n：`lib/l10n/app_localizations.dart:284-303`（bgKeepAliveSection/bgForegroundService*/bgWorkManager*/bgHyperOsGuidanceTitle/bgGuide*）
  - 测试：`test/features/settings/settings_page_test.dart:1696-1770`（「后台保活设置分组」2 个用例）
- 现状 vs 预期：
  - 现状：后台保活 = 设置主页内联分组（前台服务保活开关 + WorkManager 周期探活 + 「系统保活与权限引导」tile）；4 个引导按钮挤在一个 tile 的 subtitle Wrap 里（窄行难点、观感挤）。
  - 预期：① 主设置页移除 `_BackgroundKeepAliveSection` sliver（:90），改在「高级设置」分组（:302）新增入口行「后台保活」（key `settings-entry-bg-keepalive`，chevron_right，push 二级页）；② 新建二级页 `BackgroundKeepAlivePage`（照 DesktopSettingsPage 范本）：前台服务保活开关（switch）、WorkManager 周期探活（状态行）保留为独立行；③ 「系统保活与权限引导」在二级页内展开为 **4 个独立 CupertinoListTile**（自启动/省电无限制/联网控制/通知权限），每行独立 onTap → `keepalive.openHyperOsSetting(type)`，key 沿用 `settings-bg-guide-*`。
- 范围：仅设置页 UI 结构 + 新二级页 + 测试同步；**不动** `background_keepalive_service.dart` 接口/枚举/保活逻辑、不动通知设置、不新增权限跳转类型（保持 4 项 = `HyperOsSettingType` 全量）；`bg_foreground_service_enabled` 持久化 key 与语义不变。
- 验收：
  1. 设置主页不再显示「后台保活」整块分组；「高级设置」分组内出现「后台保活」入口行（chevron_right）→ tap 后 push 二级页（导航栏标题「后台保活」+ PopBackButton）
  2. 二级页内：前台服务保活（switch 可切、持久化不变）、WorkManager 周期探活（已就绪状态行）各为独立行
  3. 权限设置引导为 4 个**独立行**（自启动/省电无限制/联网控制/通知权限），逐个 tap 触发对应 `HyperOsSettingType` 跳转（FakeBackgroundKeepaliveService 记录调用参数）
  4. `flutter analyze` 零告警；`flutter test` 全绿（「后台保活设置分组」用例改为：主页断言入口行 → tap 入二级页 → 断言开关/WM/4 引导行；设置页金照需 `--update-goldens` 刷新）
- 备注：现有「高级设置」分组（advancedSettingsSection = 高级设置）天然是二级入口容器，后台保活入口归入其中；不改 l10n 现有文案为准。

---

### #45 [P1] 平滑输出五档调速 — 设置页新增「打字机速度」档位选项（方向类 · 主人 2026-09-02 拍板）

- 类型：方向类（设置页新功能 + reveal 参数化）。主人指令：「设置界面应该提供一个速度选项，支持五档调速，每一档预设一些参数，平滑动画开关打开后就显示这个速度选项允许用户调节」；档位表与默认档已 clarify 确认（「按推荐落盘：档位表+默认标准档」）。
- 位置：
  - `lib/features/chat/chat_controller.dart`：`:50-63` 五个 static const（`mergeDelay 16ms` / `revealInterval 48ms` / `maxWordUnitsPerTick 5` / `maxRevealLag 1s` / `maxRevealQueueUnits 2000`）→ 改为读档位预设；`:1487-1493` `_scheduleMerge` 用 mergeDelay；`:1509-1524` `_mergePendingTokens` 用 maxRevealQueueUnits；`:1539-1543` `_startRevealTimerIfNeeded` 用 revealInterval；`:1547-1553` `adaptiveWordUnitsPerTick`（**backlog<5 全吐 = 顺出根因**）；`:1555-1592` `_drainReveal` 消费 + `:1581-1591` maxRevealLag 1s 排空兜底；`:3478-3493` `splitIntoWordUnits` 的 CJK 8 字符硬编码（`:3486` `buffer.length >= 8`）→ 参数化；`:131` `_smoothStreaming` getter（读 `smoothStreamingProvider`）
  - `lib/features/settings/smooth_streaming_settings.dart:10-66`：新增 `SmoothStreamingSpeedPreset` 枚举（五档参数载体）+ `smoothStreamingSpeedProvider`（NotifierProvider，持久化 key `settings.smoothStreamingSpeed`，默认 standard，照 `SmoothStreamingController` 模式）
  - `lib/features/settings/settings_page.dart:207-222`：`settings-smooth-streaming` tile 下方插入速度选择行（key `settings-smooth-streaming-speed`，trailing 当前档名 + chevron，tap → CupertinoActionSheet 五选一）；平滑开关 `smoothStreaming==false` 时该行隐藏（持久化保留，重开恢复）
  - l10n：`lib/l10n/app_localizations.dart` 新增：速度行标签 + 五档名称（逐字/慢/标准/快/极快）+ action sheet 标题
  - 测试：`test/features/chat/chat_lockscreen_reveal_test.dart`（锁屏 5 例，涉及 static const 引用需适配）；`test/features/chat/` 其他 reveal/merge 相关用例（`adaptiveWordUnitsPerTick` 引用）；设置页测试/金照（新增速度行 → `settings_page_test.dart` + golden `--update-goldens`）
- 现状 vs 预期：
  - 现状：三个速度旋钮全静态（48ms tick / backlog<5 每 tick 全吐 / CJK 8 字一刀 / 1s 排空），正常网络下打字机效果几乎不可见 = 「都是顺出」。
  - 预期：设置页五档，每档预设完整参数，重点修复「慢档失效」陷阱——`maxRevealLag` 必须随档位放宽（否则慢档下模型吐得快、backlog 一超 1s 整段排空 = 又变顺出）。档位参数表（已拍板）：
    | 档 | 名称 | tick | 单元/tick | CJK 粒度 | maxRevealLag | 中文体验 |
    |---|---|---|---|---|---|---|
    | 1 | 逐字 | 100ms | 1 | 1 字 | ~8s | ~10字/s，逐字蹦 |
    | 2 | 慢 | 80ms | 1 | 2 字 | ~5s | ~25字/s，明显打字动画 |
    | 3 | **标准（默认）** | 64ms | 2 | 2 字 | ~3s | ~62字/s，有打字感不拖沓 |
    | 4 | 快 | 48ms | 3 | 4 字 | ~2s | ~250字/s，轻快 |
    | 5 | 极快 | 48ms | 5 | 8 字 | 1s | ~833字/s ≈ 原顺出 |
  - 自适应语义：慢档（1-3）**固定**每 tick 单元数（去掉 backlog<5 全吐分支），高积压交给放宽后的 maxRevealLag 排空兜底；快档（4-5）可保留自适应加速（base=档位单元数，上限 32）。
- 范围：仅客户端设置 + reveal 参数化 + 测试。**不动**:SSE 传输层、watchdog 重连、后端、`maxRevealQueueUnits`（2000 硬上限保留，防锁屏积压爆吐）、#20 四条锁屏语义（paused 停止消费 / resumed 铺全文 / 2000 上限 / watchdog 重基线）。切换档位对「正在进行的流式」应生效（controller ref.listen 新 provider → 重启 reveal timer / 下一 tick 用新参数）。
- 验收：
  1. 设置页行为：平滑开关开 → 显示「打字机速度」行 → 点开五档 action sheet → 选中即生效且持久化；开关关 → 行隐藏（重开恢复上次档位）
  2. 实机五档体验：档 1 明显逐字（~10字/s）、档 3（默认）有打字感、档 5 ≈ 原顺出；**慢档加载长文不出现「排空变顺出」**（maxRevealLag 随档生效）
  3. 流式中切换档位：当前流式消息下一 tick 即用新速度（无需等完成）
  4. 回归：#20 锁屏四条语义不回归（锁屏暂停 → 解锁铺全文，不爆吐不重复）；`maxRevealQueueUnits` 上限逻辑保留
  5. `flutter analyze` 零告警；`flutter test` 全绿（更新现有引用 static const 的用例 + 新增：档位参数单测、设置页联动 widget 测试、金照刷新）；发布 Android 验收装新包
- 备注：`adaptiveWordUnitsPerTick` 与 `splitIntoWordUnits` 是 `@visibleForTesting` 静态函数，参数化改造需同步改测试签名；现有测试里直接引用 `ChatController.revealInterval` 等常量处一并用 getter 替换（getter 读档位，保留近现有测试兼容或显式更新）。