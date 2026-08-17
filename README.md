# Hermex Flutter Port

将 Hermex（iOS 原生 SwiftUI 客户端）移植为 Flutter + Cupertino 的全平台客户端
（iOS / Android / Windows / macOS / Linux / Web），API 契约对齐 nesquena/hermes-webui。

- 详细实施计划 → [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- 蓝本：https://github.com/uzairansaruzi/hermex (MIT)
- 服务端：`D:\hermes-webui`（fork of nesquena/hermes-webui，:30002）

> **当前状态**：核心功能里程碑完成（附件上传、离线缓存、Profile、导出、Kanban 拖拽、Android 后台通知）。
> 789 个测试全绿、`flutter analyze` 零告警、Android debug APK 可构建。
> 正式发布前的收尾事项（release 签名、LICENSE、截图等）见 [docs/RELEASE.md](docs/RELEASE.md)。

---

## 项目介绍

**Hermex** 是 hermes-webui 生态中最成熟的移动端控制台——一个 iOS 18+ 原生 SwiftUI App
（MIT 开源，约 6.9 万行业务代码），但它**只支持 iOS**，没有 Android 计划，三个社区移植 PR 均被上游拒绝。

**hermex-flutter** 用 Flutter + Cupertino 把 Hermex 完整重写为跨平台客户端，解决：

- **Android 缺口**：Hermex 覆盖不到的 Android 手机端（主人主要诉求）；
- **桌面统一体验**：Windows / macOS / Linux 一套代码；
- **通知痛点**：Android 后台回合完成通知（Phase 6 已实现，对齐 hermes-android v2.0.1 的思路）；
- **单一代码库**：一套 Dart 逻辑跑六个平台，UI 质感对齐 Hermex（≥90% 视觉还原目标）。

客户端只做「执行平面」的遥控器：所有 Agent 能力仍由服务端
（hermes-webui / Hermes gateway）执行，客户端不做任何服务端逻辑。

## 功能特性

按模块（与 `lib/features/` 一一对应）：

| 模块 | 功能 |
|---|---|
| **会话列表** | 大标题列表、防抖远程搜索、无限滚动分页、会话分区（置顶/今天/昨天/更早）、行快捷操作（pin / archive / branch / delete）、悬浮新建会话按钮 |
| **聊天（核心）** | SSE 流式渲染、9 态聊天状态机（对齐 Hermex ChatViewModel）、思考/工具调用卡片（含错误/警告态）、Markdown + 代码块、流式期间 steer / 停止、模型选择器、新会话/续会话 |
| **任务（Cron）** | 任务列表、创建/编辑/启停/删除、手动触发、输出查看、运行状态徽标（运行中/暂停/停用/出错/需关注/正常） |
| **技能** | 技能浏览、本地搜索过滤、分类分组列表、详情展开（路径/相关技能）、禁用徽标 |
| **记忆** | 只读浏览，按分区展示（我的笔记/用户画像/智能体灵魂/项目上下文），空态占位文案 |
| **设置** | 外观（主题三态：跟随系统/浅色/深色）、服务器（多服务器增删改切换，凭据存 flutter_secure_storage）、模型（默认模型 + 推理强度）、关于 |
| **文件（Workspace）** | 会话工作区文件树浏览、下载、上传入口、文件行操作菜单（下载/重命名/删除）① |
| **Git** | 会话工作区 Git 面板：分支切换、status（已暂存/未暂存分区）、文件 diff 展开、提交表单、fetch / pull / push |
| **看板（Kanban）** | 看板/卡片浏览与操作、跨列长按拖拽（复用 status PATCH）② |
| **统计（Insights）** | 时间范围切换（今天/近 7 天/近 30 天/全部）、指标卡片（会话/消息/令牌/费用）、模型拆分列表、近 14 天令牌柱状图（fl_chart）、峰值活动 |
| **通知（Android）** | 回合完成后台系统通知：前台不发/后台发、点击回跳对应会话、回前台自动清除、预览单行化截断（详见 [docs/RELEASE.md](docs/RELEASE.md) 真机验证清单） |
| **质量基础设施** | fake gateway 契约冒烟、GitHub Actions analyze/test/Android debug 构建、基础 i18n facade、统一无障碍按钮/触觉组件 |
| **连接管理** | 三步向导（Onboarding）配置服务器、多服务器保存/切换、自定义 Header、用户名/密码、API Key 安全存储 |

> ① 文件删除/重命名仍受 hermes-webui 服务端端点限制（当前返回 501），详见 [docs/QA.md](docs/QA.md)。
> ② Kanban 拖拽跨列会调用既有状态 PATCH；服务端目前没有卡片顺序端点，因此未伪造 `reorderWorkspaces` 契约。

## 截图

> [截图待补] —— Android 真机 + Windows 桌面各主要页面截图，发布前补齐。

## 技术栈

| 领域 | 选型 |
|---|---|
| 框架 | Flutter 3.47+ / Dart 3.13+ |
| UI | **Cupertino widgets 全量**（禁止 Material 混入业务 UI，仅 App 壳桥接层除外） |
| 状态管理 | flutter_riverpod 2.x（Notifier / AsyncNotifier / Provider） |
| 网络 | dio 5.x（HTTP）+ 自封装 SSE 客户端 + web_socket_channel（Kanban 事件流） |
| 路由 | go_router 17.x |
| Markdown | flutter_markdown（自定义渲染器） |
| 本地存储 | drift（SQLite）+ flutter_secure_storage（凭据） |
| 图表 | fl_chart |
| 通知 | flutter_local_notifications |
| 测试 | flutter_test + mocktail + fake_async |

## 快速开始

### 环境要求

- **Flutter** 3.47+（stable）—— 开发机实测 3.47.0
- **Dart** 3.13+（随 Flutter SDK）
- **JDK 17**（Android 构建；`compileOptions` 已锁 Java 17）
- **Android SDK** 36（`targetSdk 36`，`compileSdk 37`，minSdk 24 = Android 7.0+）
- **Windows 桌面构建**：Visual Studio Build Tools 2022（含 C++ 桌面工作负载）
- **iOS 构建**：macOS + Xcode（本仓库尚未在 CI/真机验证）

### 安装与运行

```bash
git clone https://github.com/silent-reader-cn/hermex-flutter.git
cd hermex-flutter
flutter pub get

# Android 真机 / 模拟器
flutter run -d <device-id>

# Windows 桌面
flutter run -d windows
```

### 连接你的 hermes-webui 服务器

首次启动进入三步向导（Onboarding），填写：

1. **服务器地址**：`https://your-host:30002`（或局域网 `http://192.168.x.x:30002`）；
2. **认证**：用户名/密码（可选）或自定义 Header（如 API Key，存于 flutter_secure_storage）；
3. 保存后自动进入会话列表；可在「设置 → 服务器」中增删改、切换多台服务器。

## 构建与发布

```bash
# Android release APK（注意：release 签名尚未配置，见 docs/RELEASE.md §Android 签名发布）
flutter build apk --release

# Windows 桌面（产物：build/windows/x64/runner/Release/）
flutter build windows --release

# 其他平台
flutter build ios --release    # 需 macOS + Xcode
flutter build macos --release  # 需 macOS
flutter build linux --release  # 需 Linux + 桌面工具链
flutter build web --release    # PWA
```

- **已验证**：Android（debug APK 可构建、真机运行）；Windows / iOS / macOS / Linux / Web 平台目录均已生成，完整构建链路待验证。
- 完整发布指南（签名、打包、版本号、真机验证清单）→ [docs/RELEASE.md](docs/RELEASE.md)。

## 架构说明

```
lib/
├── main.dart               # 入口（通知 hook 注入）
├── app/                    # 壳：CupertinoApp + 深浅色主题 + go_router 路由表 + 中英本地化
├── core/
│   ├── api/                # ApiClient（dio）+ 10 个域扩展 + endpoints 端点表 + SSE/WS 客户端 + 异常体系
│   ├── models/             # 24 个数据模型文件（手写 fromJson，容错解码，绝不 crash）
│   ├── connections/        # 多服务器连接管理（flutter_secure_storage 持久化）
│   └── utils/              # 工具（lossy JSON、UUID、格式化等）
└── features/               # 业务页面：onboarding / session_list / chat / tasks / skills /
                            # memory / workspace / kanban / git / insights / settings / notifications
```

- 分层原则：**UI（features）→ 状态（Riverpod Providers）→ 服务（core/api）→ 服务器（hermes-webui）**，页面组件不直接持有网络逻辑。
- 规格文档（编码依据，含 API 契约与状态机定义）：
  - [docs/specs/models_spec.md](docs/specs/models_spec.md) —— 145 个模型翻译规格
  - [docs/specs/api_spec.md](docs/specs/api_spec.md) —— 123 端点翻译规格
  - [docs/specs/chat_spec.md](docs/specs/chat_spec.md) —— 9 态聊天状态机规格
  - [docs/specs/app_shell_spec.md](docs/specs/app_shell_spec.md) —— 路由/主题/连接管理/onboarding 规格
- 代码规范：[docs/CODING_STYLE.md](docs/CODING_STYLE.md)（参与开发的强制规范）

## 测试

```bash
flutter test        # 722 个用例 / 60 个文件，全绿
flutter analyze     # 零告警（flutter_lints + 项目追加规则）
```

测试覆盖：全部模型的容错 JSON 解析、各 Controller 状态机（流式追加/错误恢复/重连）、
ApiClient 请求路径与参数（mocktail）、关键页面 widget 测试（会话列表/聊天/任务/设置/工作区/看板）。

## 文档

| 文档 | 内容 |
|---|---|
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | 实施计划、决策记录、进度日志 |
| [docs/RELEASE.md](docs/RELEASE.md) | 发布指南（签名/打包/版本号/真机验证） |
| [docs/QA.md](docs/QA.md) | 无障碍/国际化检查清单与已知待完善项 |
| [docs/CODING_STYLE.md](docs/CODING_STYLE.md) | 代码风格规范 |
| [docs/PROTOCOL_NOTES.md](docs/PROTOCOL_NOTES.md) | SSE 流式协议笔记 |
| [docs/specs/](docs/specs/) | 模块翻译规格（models/api/chat/app_shell） |

## 许可

MIT。本项目是 [Hermex](https://github.com/uzairansaruzi/hermex)（MIT，uzairansaruzi）的 Flutter 全平台移植，
API 契约源于 [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui)（MIT）。
蓝本源码仅作参考（`.reference/hermex-src/`，不进仓库）。

> 注意：仓库暂缺 `LICENSE` 文件，正式发布前需补充（见 [docs/RELEASE.md](docs/RELEASE.md) 发布前检查清单）。
