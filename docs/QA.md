# 无障碍 / 国际化检查清单（QA）

> 状态：**持续维护清单**。本文件汇总当前代码中的已知占位、TODO 与待完善项，
> 供后续迭代排期；所有条目均可从代码定位（文件:行）。
> 更新日期：2026-08-17

## 1. 无障碍（Accessibility）

| # | 项目 | 现状 | 定位 |
|---|---|---|---|
| 1 | 语义标签（Semantics） | 新增可复用 `AccessibleButton`；既有页面仍需逐步迁移图标按钮 | `lib/core/utils/accessibility.dart` |
| 2 | 字体缩放适配 | 未专项验证（动态字号下布局是否溢出） | 全局 |
| 3 | 对比度/深色模式 | 主题已支持深浅色三态，但未做对比度审计 | `lib/app/theme/` |
| 4 | 触觉反馈（HapticFeedback） | 新增统一 `AccessibleButton` 与 haptic helpers；既有按钮仍需逐步迁移 | `lib/core/utils/accessibility.dart` |
| 5 | 动画手感 | 未逐条对齐 SwiftUI Spring 参数（Phase 6 打磨项后置） | 全局 |

## 2. 国际化（i18n）

| # | 项目 | 现状 | 定位 |
|---|---|---|---|
| 1 | 框架层本地化 | 已配置：`supportedLocales: en/zh` + Cupertino/Material/Widgets delegates + `AppLocalizationsDelegate` | `lib/app/app.dart`, `lib/l10n/` |
| 2 | 业务文案 | 已建立中英基础 facade；完整业务文案 ARB 抽离仍待后续迭代 | `lib/l10n/app_localizations.dart` |
| 3 | 日期/数字格式化 | 已用本地化格式（`yyyy-MM-dd HH:mm` 等），但文案拼接未走 l10n | `lib/core/utils/`、workspace_page |

## 3. 已知占位 / TODO 清单（从代码汇总）

> 全部为「不阻塞 v0.1.0 功能验收」的已知项；`TODO(merge)` 为多分支合并期遗留标记，
> 均已评估为低风险（对应域方法返回 `Object?`，解析为 JSON 透传，测试覆盖）。

### 3.1 功能占位（用户可见）

| # | 项目 | 行为 | 定位 |
|---|---|---|---|
| 1 | 聊天附件上传 | **已完成**：file picker、20MB 预检、上传状态、成功/失败提示 | `chat_input_bar.dart`, `core/utils/file_picker.dart` |
| 2 | 工作区文件上传 | **已完成**：路由生产注入 picker；删除/重命名仍受服务端限制 | `router.dart`, `workspace_page.dart` |
| 3 | 工作区文件删除/重命名 | 服务端（hermes-webui）尚无删除/重命名端点，生产实现抛 HTTP 501（Not Implemented），UI 弹「操作失败」 | `workspace_api.dart:90-152`（§api_spec 1.7 workspace 域 10 端点无此能力） |
| 4 | 看板拖拽 | **已完成跨列拖拽**；服务端暂无卡片顺序端点，当前拖拽映射为状态 PATCH | `kanban_page.dart`, `kanban_providers.dart` |

### 3.2 类型化待合并（TODO(merge)，全部为 API 返回类型占位）

| # | 位置 | 说明 |
|---|---|---|
| 1 | `api_client.dart:428` 及 server/cron/git/kanban/memory_skills/server_panels/sessions/workspace/upload 各域扩展 | 返回类型暂为 `Object?`（解码后 JSON 透传），模型就绪后改为类型化响应 |
| 2 | `sse_client.dart:226,234,375,378` | approval / clarify / context window / session detail 待类型化 |
| 3 | `ws_client.dart:49` | `List<KanbanEvent>` 待类型化（现为 `List<Map<String, Object?>>`） |
| 4 | `cookie_store.dart:89` | Cookie 持久化待接入 dio_cookie_jar / flutter_secure_storage |
| 5 | `custom_header.dart` | 已增加 `persist/restore` 安全存储 API；设置页接线仍可继续完善 |

### 3.3 发布相关（见 docs/RELEASE.md）

- Android release 签名仍用 debug keystore（`android/app/build.gradle.kts:37` TODO）
- 仓库缺 LICENSE 文件；README 截图待补；pubspec 版本 `1.0.0+1` 与 CHANGELOG v0.1.0 未对齐
- macOS / Linux / Web 平台目录已生成，构建链路未验证；无 CI workflows（.github/ 为空）
- `tools/fake_gateway`（CODING_STYLE.md 提及的契约测试模拟服务器）尚未创建

## 4. 迭代建议（按优先级）

1. 工作区删除/重命名：等待上游 hermes-webui 补端点；
2. 业务文案完整 ARB 抽离与逐页迁移；
3. 将 `AccessibleButton` 迁移到全部图标按钮并完成动态字号审计；
4. 接入真实持久化缓存 provider，并补充真机断网验收；
5. 服务端提供卡片顺序端点后，再补 Kanban 同列排序同步。
