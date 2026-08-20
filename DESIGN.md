# DESIGN.md — 自适应宽屏双栏外壳设计方案

## 1. 架构选型：GoRouter 单 Navigator ShellRoute

采用 GoRouter 的 `ShellRoute`（单 Navigator）包裹所有已连接业务路由，`/onboarding` 作为顶层独立 `GoRoute` 不进壳。

### 选型对比与决策
- **ShellRoute（选定）**：全局共用单一 Navigator 栈，URL 路径与浏览器/桌面端历史无缝映射。`context.go()` 与 `AppBackButton`（`canPop` / `go('/')`）语义完全保持现有规范；在窄屏下直接返回 `child`，实现 100% 行为零回归；在宽屏下通过组合包裹实现双栏。
- **StatefulShellRoute / 双 Navigator（否决）**：将左栏与右栏分别割裂为独立分支 Navigator 会导致 URL 参数同步困难、`AppBackButton` 栈混乱，且可能破坏既有深链与路由守卫。

## 2. 宽度阈值（Breakpoint）取值与依据

- **阈值取值**：`900.0 px`（定义为 `kAdaptiveBreakpoint = 900.0`）
- **判定方式**：`MediaQuery.sizeOf(context).width >= 900.0`
- **取值依据**：
  1. **避开 Flutter 测试默认视口（800×600）**：现有 960+ 测试中大量 widget 测试直接 `pumpWidget` 单页面并在 800×600 默认视口下断言。阈值设定在 900px，确保全量现有单测与页面测试稳定运行于窄屏单栈分支，避免全项目测试大面积误报。
  2. **人体工学与空间分配**：左侧栏固定宽度为 320px（对齐 iOS 原生 `min: 280, ideal: 340`），在 900px 视口下右侧内容区仍拥有 580px 宽度，保障聊天消息气泡、看板卡片与设置表单具有充裕的排版与交互空间。

## 3. 布局结构与渲染逻辑

### 3.1 窄屏模式（width < 900）
`AdaptiveShell` 直接返回 `child`，表现为标准的单栈全屏页面切换（与改造前完全一致）。

### 3.2 宽屏模式（width >= 900）
`AdaptiveShell` 渲染水平 `Row`：
- **左侧常驻栏 (`SessionSidebar`，宽度 320px)**：
  - **顶部工具入口条 (`SidebarUtilityToolbar`)**：Cupertino 风格横向工具行，包含定时任务 (`/tasks`)、看板 (`/kanban`)、技能 (`/skills`)、记忆 (`/memory`)、用量统计 (`/insights`) 及设置 (`/settings`)，支持当前激活路由高亮。
  - **下方会话列表**：直接复用完整 `SessionListPage`，保留搜索、筛选、分区、新建、多选及长按操作等全部功能，不作任何功能阉割。
  - **右侧边框**：1px `CupertinoColors.separator` 纵向分割线。
- **右侧内容区 (`Expanded`)**：
  - 若当前路由为 `/`（主列表）：展示 `EmptyDetailPane`（对齐 iOS 蓝本 `regularWidthDetail` 空态，显示会话图标、引导文案及“新建会话”按钮）。
  - 若当前路由为各二级业务页（`/chat/...`, `/tasks`, `/kanban`, `/skills`, `/memory`, `/insights`, `/settings`, `/workspace/...`, `/git/...`）：直接渲染 `child`。

## 4. 路由进壳与不进壳划分

- **不进壳（顶层 GoRoute）**：
  - `/onboarding`：未连接或向导流程，始终全屏，无侧栏干扰。
- **进壳（ShellRoute 内部子路由）**：
  - `/` (SessionListPage)
  - `/chat` 及 `/chat/:sessionId` (ChatPage)
  - `/settings` (SettingsPage)
  - `/tasks` (TasksPage)
  - `/skills` (SkillsPage)
  - `/memory` (MemoryPage)
  - `/workspace/:sessionId` (WorkspacePage)
  - `/kanban` (KanbanPage)
  - `/git/:sessionId` (GitPage)
  - `/insights` (InsightsPage)

## 5. 对现有守卫与 Deep-link 影响分析

- **路由重定向守卫 (redirect)**：
  守卫逻辑依据 `state.matchedLocation` 判断是否为 `/onboarding` 及 `activeConnectionProvider` 状态。纳入 `ShellRoute` 后，各子路由的 `matchedLocation` 保持不变，守卫拦截与放行逻辑语义 100% 不变。
- **深链解析 (Deep Link)**：
  `lib/app/deep_link.dart` 的 `resolveInitialRoute` 基于入参 URL 正则解析出标准目标路径（如 `/chat/xxx?q=yyy`），GoRouter 命中对应子路由后由 `ShellRoute` 包装，深链定位与高亮逻辑不受任何影响。
