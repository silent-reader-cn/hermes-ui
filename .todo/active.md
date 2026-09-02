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