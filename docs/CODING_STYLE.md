# hermex-flutter 代码风格规范（CODING STYLE）

> 所有参与本仓库工作的开发者/AI 代理的强制规范。开工前必读。
> 与本规范冲突的写法一律以 `AGENTS.md` 为准（同源，`AGENTS.md` 为权威）。

## 1. 项目简介

将 Hermex（iOS 原生 SwiftUI，MIT 开源）移植为 Flutter + Cupertino 的全平台客户端。
API 契约对齐 nesquena/hermes-webui（主人 fork 跑在 :30002）。

- 蓝本源码（只读参考，不进仓库）：`.reference/hermex-src/`（uzairansaruzi/hermex 的 HermesMobile 目录）
- 上游 hermes-webui：https://github.com/nesquena/hermes-webui
- 优先平台：Android + Windows；后置：macOS / Linux / Web

## 2. 技术栈（锁死，不得私自更换）

| 领域 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x stable + Dart 3.x (`sdk: ^3.13.0`) | 六平台单代码库 |
| UI | **全部 Cupertino widgets** | 禁止 Material 混入业务 UI（仅 App 壳桥接例外） |
| 状态管理 | flutter_riverpod 2.6.x | Notifier / AsyncNotifier / Provider |
| 网络 | dio + sse_client 自封装 + web_socket_channel | HTTP / SSE / WS |
| 路由 | go_router 17.5.x | ShellRoute 单 Navigator |
| Markdown | flutter_markdown 0.7.x | 自定义渲染器 |
| 离线缓存 | drift 2.34.x + drift_flutter | SQLite |
| 安全存储 | flutter_secure_storage 11.x | API Key 凭据 |
| 桌面能力 | window_manager / tray_manager / hotkey_manager | 窗口/托盘/快捷键 |
| 通知 | flutter_local_notifications 22.3.x | Android 后台通知 |
| 图表 | fl_chart 1.2.x | Insights |
| 字体 | MiSans Regular/Medium | 见 `AGENTS.md` §5 |

完整依赖以 `pubspec.yaml` 为准；新增依赖需对齐选型。

## 3. 目录结构（以实盘为准）

```
lib/
├── main.dart / driver_main.dart / l10n/
├── app/         # app.dart / router.dart / deep_link.dart / shell/* / theme/*
├── core/        # api/ / models/ / cache/ / connections/ / providers/ / utils/
└── features/    # onboarding/session_list/chat/tasks/skills/memory/workspace*/kanban/insights/settings/git/prompts/projects/notifications/desktop/shared
test/            # 镜像 lib/ 结构
assets/branding/ + assets/fonts/
tools/fake_gateway/ + tools/icon_pipeline/
docs/specs/ + docs/PROTOCOL_NOTES.md 等
```

## 4. Dart 代码风格（强制）

- 文件：`snake_case.dart`；类/枚举：`PascalCase`；变量/函数：`camelCase`；常量：`lowerCamelCase`
- 每个文件一个主类型；import 顺序：dart: → package: → 相对路径，空行分隔
- 私有成员一律 `_` 前缀；公开 API 必须有 doc comment（`///`）
- `const` 能加就加；`final` 优先于 `var`
- 禁止 `dynamic` 滥用（JSON 解析边界除外）；禁止 `print()` 调试（用 `dart:developer log`）
- 字符串用单引号；格式化用 `dart format`（跟随 flutter_lints 默认）
- 错误处理：业务层抛自定义异常（继承 `ApiException`），UI 层 catch 展示；不吞异常
- 异步：优先 `async/await`，禁止裸 `Future` 忽略（加 `unawaited` 或注释说明）
- `analysis_options.yaml` 启用 `package:flutter_lints/flutter.yaml` + 追加规则，`flutter analyze` 必须零告警才算完成

追加 lint：`avoid_print` / `prefer_single_quotes` / `prefer_final_locals` / `prefer_const_constructors` / `always_declare_return_types` / `unawaited_futures` / `discarded_futures`；`avoid_dynamic_calls: false`（容错解码放宽）。

## 5. 样式规范（摘要）

- 主题：`cupertino_theme.dart` → `buildCupertinoTheme`，主色 `0xFF007AFF`，字体 `MiSans`，`barBackgroundColor` 跟随 scaffold 不透明
- 状态色：`status_colors.dart` 全部 `CupertinoDynamicColor` 且 WCAG AA ≥4.5:1（statusGreen/Orange/Blue/Grey/Teal/Red + secondaryText），禁直接用 systemGreen/Orange/Red 作文字色
- 外壳：`DESIGN.md` 定义 `kAdaptiveBreakpoint = 900`，宽屏 320px 侧栏 + 1px separator；详见 `AGENTS.md` §5 与 `DESIGN.md`

## 6. 模型与 API 约定（对齐 Hermex 容错策略）

- 所有模型手写 `fromJson` / `toJson`（**不用 codegen**），容错解码
- 未知字段忽略；缺失/类型不符给安全默认值，绝不 crash；可空用 `?`
- `endpoints.dart` 与 `.reference/.../Endpoints.swift` 一一对应
- 响应形状以真实服务器为准；改动前跑 `tools/fake_gateway` 契约测试
- API Key 存 flutter_secure_storage，禁硬编码、禁进日志

## 7. Riverpod 约定

- 业务状态用 `Notifier`/`AsyncNotifier` + `NotifierProvider`；派生用 `Provider`/`FutureProvider`
- Provider 文件与页面同目录；命名后缀 `Provider`；Notifier 后缀 `Controller`
- 页面不直接持有网络逻辑，一律走 Provider

## 8. 测试要求与流水线

- 必写：模型畸形输入容错、Controller 状态机（流式/错误/重连）、ApiClient mock、关键 widget 交互、对比度/无障碍专项
- 本地：`flutter analyze` 零告警 + `flutter test` 全绿 + `python tools/fake_gateway/smoke_test.py`
- CI：`.github/workflows/ci.yml` 三 job（analyze-test / android-debug / fake-gateway），合并前必须全绿
- 完成标准：`flutter test` 全绿 + `flutter analyze` 零告警 + 无 Material 混入 + 与 Hermex 行为一致

## 9. Git 规范

- 分支：`feat/<模块>`；提交：`<type>(<scope>): <subject>`（feat/fix/refactor/test/docs/chore）
- 提交前 `git status` 仅 add 相关文件，禁 `git add -A`
- 合并前：analyze + test 通过，无 TODO 遗留（有意遗留标注负责人）

## 10. 并行治理（摘要）

本仓库由柚子担任 Leader，通过 AGY 并行子代理推进，固定五步闭环：规格先行 → 编码并行（文件级分区）→ 盯场 steer → 独立复验（analyze+test 全量重跑）→ 统一提交。子代理任务书自包含、禁止自行 commit、模型固定 `gemini-3.7-flash-high`，Windows 下 flutter 走封装 bat。完整规范见 `AGENTS.md` §12。
