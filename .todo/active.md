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