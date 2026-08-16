# hermex-flutter 代码风格规范（CODING STYLE）

> 所有参与本仓库工作的开发者/AI 代理的强制规范。开工前必读。
> 与本规范冲突的写法一律以本规范为准。

## 1. 项目简介

将 Hermex（iOS 原生 SwiftUI，MIT 开源）移植为 Flutter + Cupertino 的全平台客户端。
API 契约对齐 nesquena/hermes-webui（主人 fork 跑在 :30002）。

- 蓝本源码（只读参考，不进仓库）：`.reference/hermex-src/`（uzairansaruzi/hermex 的 HermesMobile 目录）
- 上游 hermes-webui：https://github.com/nesquena/hermes-webui
- 优先平台：Android + Windows；后置：macOS / Linux / Web

## 2. 技术栈（锁死，不得私自更换）

- Flutter 3.x stable + Dart 3.x
- UI：**全部使用 Cupertino widgets**（CupertinoApp / CupertinoPageScaffold / CupertinoListSection / CupertinoListTile / CupertinoNavigationBar / CupertinoTextField / CupertinoSwitch / CupertinoSlider / CupertinoPicker / CupertinoAlertDialog / CupertinoSlidingSegmentedControl / CupertinoActivityIndicator），**禁止 Material widgets 混入业务 UI**（除 App 壳的 MaterialApp 桥接层外）
- 状态管理：flutter_riverpod（Notifier / AsyncNotifier / Provider）
- 网络：dio（HTTP）+ sse_client 自封装（SSE）+ web_socket_channel（WS）
- 路由：go_router
- Markdown：flutter_markdown（自定义渲染器）
- 离线缓存：drift（SQLite）
- 安全存储：flutter_secure_storage
- 图表：fl_chart

## 3. 目录结构

```
lib/
├── main.dart                 # 入口（平台分支）
├── app/                      # 壳：router / theme / 全局初始化
├── core/
│   ├── api/                  # ApiClient / endpoints / sse / ws / errors
│   ├── models/               # 全部数据模型（fromJson 容错解码）
│   ├── cache/                # drift 数据库
│   └── utils/                # 工具
└── features/
    ├── onboarding/  session_list/  chat/  tasks/  skills/
    ├── memory/  workspace/  kanban/  insights/  settings/
    └── shared/               # 跨 feature 复用组件
test/                         # 单元 + widget 测试（镜像 lib/ 结构）
tools/fake_gateway/           # 契约测试用本地模拟服务器
```

## 4. Dart 代码风格（强制）

- 文件：`snake_case.dart`；类/枚举：`PascalCase`；变量/函数：`camelCase`；常量：`lowerCamelCase`
- 每个文件一个主类型；import 顺序：dart: → package: → 相对路径，空行分隔
- 私有成员一律 `_` 前缀；公开 API 必须有 doc comment（`///`）
- `const` 能加就加；`final` 优先于 `var`
- 禁止 `dynamic` 滥用（JSON 解析边界除外）；禁止 `print()` 调试（用 `dart:developer log`）
- 字符串用单引号；格式化用 `dart format`
- 错误处理：业务层抛自定义异常（继承 `ApiException`），UI 层 catch 展示；不吞异常
- 异步：优先 `async/await`，禁止裸 `Future` 忽略（加 `unawaited` 或注释说明）
- analysis_options.yaml 启用 `flutter_lints` + 项目追加规则，`flutter analyze` 必须零告警才算完成

## 5. 模型与 API 约定（对齐 Hermex 容错策略）

- 所有模型手写 `fromJson` / `toJson`（**不用 json_serializable codegen**），保持可控容错
- 容错规则：未知字段忽略；字段缺失/类型不符时给**安全默认值**，绝不 crash；可空字段用 `?`
- `endpoints.dart` 端点表必须与 `.reference/hermex-src/Networking/Endpoints.swift` 一一对应
- 响应形状以真实服务器为准；改动前先跑 `tools/fake_gateway` 契约测试
- API Key 存 flutter_secure_storage，禁止硬编码、禁止进日志

## 6. Riverpod 约定

- 业务状态用 `Notifier`/`AsyncNotifier` + `NotifierProvider`；派生状态用 `Provider`/`FutureProvider`
- Provider 文件与页面同目录（如 `features/chat/chat_providers.dart`）
- 所有 Provider 命名后缀 `Provider`；Notifier 类名后缀 `Controller`
- 页面组件（Widget）不直接持有网络逻辑，一律走 Provider

## 7. 测试要求（必写）

- 每个模型：JSON 解析单测（含**畸形输入**容错用例）
- 每个 Controller：核心状态机单测（流式追加、错误恢复、重连）
- ApiClient 方法：用 mock（mocktail）测请求路径/参数/解析
- 页面：关键交互 widget 测试（会话列表、聊天发送、设置表单）
- `flutter test` 全绿 + `flutter analyze` 零告警 = 完成标准

## 8. Git 规范

- 分支：`feat/<模块>`；提交信息：`<type>(<scope>): <subject>`（type: feat/fix/refactor/test/docs/chore）
- 提交前 `git status` 确认只 add 相关文件；禁止 `git add -A` 混入无关文件
- 合并到 main 前必须：analyze 通过 + 测试通过 + 无 TODO 遗留（有意遗留的 TODO 要标注负责人）

## 9. 参考优先级

1. 本规范（强制，最高优先）
2. `.reference/hermex-src/`（蓝本实现，翻译而非发明）
3. Flutter / Riverpod 官方文档
4. 如与 Hermex 行为冲突：以 Hermex 行为为准（它是产品定义）

## 10. 完成定义（DoD）

- [ ] `flutter analyze` 零告警
- [ ] `flutter test` 全绿（新增代码有测试）
- [ ] 无 Material 组件混入业务 UI
- [ ] 与 Hermex 对应功能行为一致（对照 `.reference/hermex-src`）
- [ ] 提交信息规范、分支正确
