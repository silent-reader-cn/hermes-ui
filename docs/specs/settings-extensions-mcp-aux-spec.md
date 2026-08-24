# 设置页三板块对接规格：Extensions 生态 / MCP 服务器 / 辅助模型（2026-08-21）

> 状态：规格定稿（Leader 依据后端 routes.py 源码 + domain_a 卡片精读）
> 后端权威：`api/routes.py` 行号见各端点 ｜ 详细卡片：`docs/specs/backend-api-details/domain_a_system-auth-config.md`
> 进度：已对接 75/255 端点；本规格新增 13 端点（3 域），全部属「后端有、客户端无」差距清单 P0/P1
> 强制约束：Cupertino 全量、Riverpod 后缀规范、模型手写容错 fromJson（未知字段忽略/缺失给安全默认/可空用 `?`）、`flutter analyze` 零告警、`flutter test` 全绿、API Key 禁进日志

---

## 0. 目标

在设置页新增三个板块（沿用现有 `CupertinoListSection` 组织模式，见 `settings_page.dart` 的 `_ModelSection`）：

1. **Extensions 生态**：已装扩展列表 + 启停开关 + 卸载 + 安装（registry）+ sidecar 授权开关
2. **MCP 服务器管理**：服务器列表 + 启停 + 删除 + 新增/编辑（command/args/env）+ 工具清单查看
3. **辅助模型（Auxiliary Models）**：11 个 task slot 各绑定 provider/model + 查看高级信息 + 「全部重置 auto」

---

## 1. 新增端点（endpoints.dart — 13 个）

### 1.1 Extensions（6 个，`routes.py` 行号佐证）

| Dart 常量 | 方法 | 路径 | Body | 响应类型 |
|---|---|---|---|---|
| `extensionsStatus` | GET | `/api/extensions/status` | — | `ExtensionsStatusResponse` |
| `extensionsRegistry` | GET | `/api/extensions/registry` | — | `ExtensionsRegistryResponse` |
| `extensionToggle` | POST | `/api/extensions/toggle` | `{id, enabled}` | `ExtensionToggleResponse` |
| `extensionInstall` | POST | `/api/extensions/install` | `{id, download_url, sha256}` | `ExtensionInstallResponse` |
| `extensionUninstall` | POST | `/api/extensions/uninstall` | `{id}` | `ExtensionUninstallResponse` |
| `extensionSidecarProxyConsent` | POST | `/api/extensions/sidecar-proxy-consent` | `{id, approved}` | `ExtensionConsentResponse` |

### 1.2 MCP（5 个）

| Dart 常量 | 方法 | 路径 | Body/Query | 响应类型 |
|---|---|---|---|---|
| `mcpServers` | GET | `/api/mcp/servers` | — | `McpServersResponse` |
| `mcpTools` | GET | `/api/mcp/tools` | — | `McpToolsResponse` |
| `mcpServerUpdate(String name)` | PUT | `/api/mcp/servers/{name}` | `{command, args, env, enabled}` | `McpServerWriteResponse` |
| `mcpServerToggle(String name)` | PATCH | `/api/mcp/servers/{name}` | `{enabled}` | `McpServerToggleResponse` |
| `mcpServerDelete(String name)` | DELETE | `/api/mcp/servers/{name}` | — | `McpServerDeleteResponse` |

> MCP `{name}` 路径段用 `encodePathSegment`（同 kanban slug 规则，复用 `Endpoint.encodePathSegment`）；新增 mcpServerEdit 与 mcpServerDelete 可共用同一 Endpoint 构造（不同 HTTP 方法）。

### 1.3 辅助模型（2 个）

| Dart 常量 | 方法 | 路径 | Body | 响应类型 |
|---|---|---|---|---|
| `auxiliaryModels` | GET | `/api/model/auxiliary` | — | `AuxiliaryModelsResponse` |
| `modelSet` | POST | `/api/model/set` | `{scope, task, provider, model, advanced?}` | `ModelSetResponse` |

---

## 2. 响应模型（lib/core/models/，手写容错 fromJson）

### 2.1 `extensions.dart`

```dart
class ExtensionInfo {
  final String id;            // 缺失给 ''
  final String name;          // 缺失给 id（fallback 不为空串）
  final bool enabled;         // 缺失给 false
  final bool sidecarActive;   // 缺失给 false
  final bool sidecarProxyConsent; // 缺失给 false
}
class ExtensionsStatusResponse {
  final bool enabled;         // 系统扩展开关
  final List<ExtensionInfo> extensions; // 缺失给 []
}
class ExtensionRegistryItem {
  final String id; final String name; final String version;
  final String downloadUrl; final String sha256; // 全部缺失给 ''
}
class ExtensionsRegistryResponse { final List<ExtensionRegistryItem> registry; }
// 以下写响应：ok(bool), 冗余辅助字段, fromJson 容错
class ExtensionToggleResponse { final bool ok; final String id; final bool enabled; }
class ExtensionInstallResponse { final bool ok; final String installed; }
class ExtensionUninstallResponse { final bool ok; final String uninstalled; }
class ExtensionConsentResponse { final bool ok; final String id; final bool sidecarProxyConsent; }
```

### 2.2 `mcp.dart`

```dart
class McpServer {
  final String name;          // 缺失给 ''
  final String command;       // 缺失给 ''
  final List<String> args;    // 缺失给 []
  final bool enabled;         // 缺失给 false
  final String status;        // connected / disconnected / error... 缺失给 ''
}
class McpServersResponse { final List<McpServer> servers; }
class McpTool {
  final String name; final String server; final String description;
  final Map<String, dynamic> parameters; // JSON Schema，缺失给 const {}
}
class McpToolsResponse { final List<McpTool> tools; }
class McpServerWriteResponse { final bool ok; final McpServer? server; }
class McpServerToggleResponse { final bool ok; final String name; final bool enabled; }
class McpServerDeleteResponse { final bool ok; final String deleted; }
```

> 注意：`McpServerWriteResponse.server` 是**嵌套对象**（PUT 返回 `{ok, server: {...}}`），server 字段再做 `McpServer.fromJson`，不是裸 map 兜底。

### 2.3 `auxiliary_model.dart`

```dart
/// 11 个 canonical task（后端 config.py AUXILIARY_TASK_CATALOG）：
/// vision / web_extract / compression / approval / mcp / title_generation /
/// skills_hub / curator / kanban_decomposer / profile_describer / triage_specifier
class AuxiliaryTaskRow {
  final String task;          // 缺失给 ''
  final String provider;      // 默认 'auto'
  final String model;         // 缺失给 ''
  final String baseUrl;       // 缺失给 ''
  final String timeout;       // 缺失给 ''
  final String downloadTimeout;
  final String maxConcurrency;
  final Map<String, dynamic> extraBody; // 缺失给 const {}
  final bool apiKeySet;       // 缺失给 false
  final String label;         // 缺失给 ''
  final String description;   // 缺失给 ''
}
class AuxiliaryModelsResponse {
  final List<AuxiliaryTaskRow> tasks;   // 缺失给 []
  final AuxMainModel main;              // 缺失给 const
}
class AuxMainModel {
  final String provider; final String model;
  final bool supportsFastTier; final String serviceTier;
  final Map<String, dynamic> advanced; // 缺失给 const {}
}
class ModelSetResponse { final bool ok; final String task; final String provider; final String model; }
```

> 字数注意：timeout/max_concurrency 后端可能给 int 或 str，用 `lossyString` 语义（num→toString，其他→''），参考现有 `core/utils/lossy_json.dart` 工具。

---

## 3. ApiClient 扩展（lib/core/api/）

新建两个扩展文件 + 辅助模型方法挂到 `api_client_server_panels.dart`（它已负责 models/reasoning 域）：

### 3.1 `api_client_extensions.dart`

```dart
extension ApiClientExtensions on ApiClient {
  Future<ExtensionsStatusResponse> extensionsStatus() async { ... sendJson(Endpoint.extensionsStatus) ... }
  Future<ExtensionsRegistryResponse> extensionsRegistry() async { ... }
  Future<ExtensionToggleResponse> toggleExtension(String id, bool enabled) async { ... }
  Future<ExtensionInstallResponse> installExtension({required String id, required String downloadUrl, required String sha256}) async { ... }
  Future<ExtensionUninstallResponse> uninstallExtension(String id) async { ... }
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(String id, bool approved) async { ... }
}
```

### 3.2 `api_client_mcp.dart`

```dart
extension ApiClientMcp on ApiClient {
  Future<McpServersResponse> mcpServers() async { ... }
  Future<McpToolsResponse> mcpTools() async { ... }
  Future<McpServerWriteResponse> saveMcpServer(String name, {required String command, required List<String> args, Map<String, String>? env, bool enabled = true}) async { ... }
  Future<McpServerToggleResponse> toggleMcpServer(String name, bool enabled) async { ... }
  Future<McpServerDeleteResponse> deleteMcpServer(String name) async { ... }
}
```

### 3.3 `api_client_server_panels.dart` 追加

```dart
  Future<AuxiliaryModelsResponse> auxiliaryModels() async { ... }
  Future<ModelSetResponse> setAuxiliaryModel({required String task, required String provider, required String model, Map<String, dynamic>? advanced}) async { ... }
```

> `Endpoint.modelSet` 构造统一 `{scope:'auxiliary', task, provider, model, advanced?}`；scope 恒为 auxiliary（主模型已有 default-model 端点，不重复）。

---

## 4. Settings 接口抽象（features/settings/settings_providers.dart 或拆分文件）

沿用现有 `SettingsApi` interface + `SettingsApiFactory` 注入模式：

```dart
abstract interface class SettingsApi {
  // ...现有 4 方法不动...
  // 新增：
  Future<ExtensionsStatusResponse> extensionsStatus();
  Future<ExtensionsRegistryResponse> extensionsRegistry();
  Future<ExtensionToggleResponse> toggleExtension(String id, bool enabled);
  Future<ExtensionInstallResponse> installExtension({required String id, required String downloadUrl, required String sha256});
  Future<ExtensionUninstallResponse> uninstallExtension(String id);
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(String id, bool approved);
  Future<McpServersResponse> mcpServers();
  Future<McpToolsResponse> mcpTools();
  Future<McpServerWriteResponse> saveMcpServer(String name, {required String command, required List<String> args, Map<String, String>? env, bool enabled = true});
  Future<McpServerToggleResponse> toggleMcpServer(String name, bool enabled);
  Future<McpServerDeleteResponse> deleteMcpServer(String name);
  Future<AuxiliaryModelsResponse> auxiliaryModels();
  Future<ModelSetResponse> setAuxiliaryModel({required String task, required String provider, required String model});
}
```

⚠️ 透传铁律（2026-08 实锤）：包装层方法一律 `_client.xxx()` 直接透传 typed 结果，**严禁** `fromJson(_asMap(...))` 二次解析。

状态管理：三个互不干扰的 AsyncNotifier（不合并进现有 settingsController 以免互相拖累刷新）：
- `extensionsControllerProvider`（AsyncNotifierProvider<ExtensionsController, ExtensionsState>）— state: {status, registry, error}
- `mcpControllerProvider`（McpController）— state: {servers, tools, error}
- `auxiliaryModelsControllerProvider`（AuxiliaryModelsController）— state: {tasks, main, error}

每个 Controller 提供 `refresh()`、以及对应写操作后重新 `refresh()`。

---

## 5. UI（settings_page.dart + 3 个新 section widget）

### 5.1 Extensions 板块（`_ExtensionsSection`，key: `settings-extensions-section`）

- `CupertinoListSection(header: '扩展 (Extensions)')`
- 系统开关 todo：`extensionsStatus.enabled` 只读展示不提供切换（后端无写端点）
- 每个已装扩展一个 `CupertinoListTile`：
  - title: name；subtitle: id + sidecar 状态
  - trailing: `CupertinoSwitch`（key `extension-toggle-<id>`）→ toggleExtension
  - onTap: 扩展详情 action sheet（启用/停用、sidecar 授权开关 `extension-sidecar-<id>`、卸载 `extension-uninstall-<id>`）
- 底部行：`安装扩展`（key `settings-extension-install`）→ 弹输入 sheet（id/download_url/sha256 三项，来自 registry 可选）→ installExtension
- 空态：`暂无安装扩展`；错误态沿用 `_describeError` 模式

### 5.2 MCP 板块（`_McpSection`，key: `settings-mcp-section`）

- 每个 `McpServer` 一个 `CupertinoListTile`：
  - title: name；subtitle：`command args` 摘要 + status（`statusGreenText` 给 connected / `statusGreyText` 其他）
  - trailing: `CupertinoSwitch`（key `mcp-toggle-<name>`）→ toggleMcpServer
  - onTap: 详情页/菜单（编辑、查看工具、删除 `mcp-delete-<name>`）
- `添加 MCP 服务器`（key `settings-mcp-add`）→ 表单页（name/command/args 多行/env JSON/启用开关）→ saveMcpServer
- 工具查看：点工具体现当前 servers 的 tools 列表（或单独 `查看工具` action sheet）

### 5.3 辅助模型板块（`_AuxiliaryModelsSection`，key: `settings-auxiliary-section`）

- 每 task 一个 `CupertinoListTile`：
  - title: label；subtitle: `provider / model`（auto 显示「自动」）
  - trailing: chevron → `_AuxTaskPickerPage`（复用 `_ModelPickerPage` 的分组模型选择模式，从 `state.modelGroups`/models 列表选 provider+model，选中即调 setAuxiliaryModel 并刷新）
- 顶部一行：`全部重置为自动`（key `settings-aux-reset`）→ setAuxiliaryModel(task: '__reset__', provider: 'auto', model: '')
- 只读信息：`main` 显示；`apiKeySet` 显示 🔑 已配置 标记（不显示 key 本身）

### 5.4 页面装配

`SettingsPage.build` 的 ListView 里追加三个 section（顺序建议：...模型 → 辅助模型 → MCP → 扩展 → 关于）。

### 5.5 l10n（lib/l10n/app_localizations.dart 新增段 `// 14. Settings · Extensions/MCP/Auxiliary`）

~20 条：extensionsSection、mcpSection、auxiliaryModelsSection、installedExtensions、noExtensions、installExtension、uninstall、extensionSidecar、addMcpServer、editMcpServer、deleteMcpServer、mcpTools、auto、resetAuxiliary、apiKeyConfigured、mcpsEmpty、auxTaskPickerTitle 等，中英双文案，命名沿用现有 `l10n.xxx` 风格。

---

## 6. 测试要求

每模型：JSON 解析单测（畸形输入容错：缺字段/类型错/空数组）
每 Controller：核心状态机单测（加载、刷新、写操作后刷新、错误）
SettingsApi 包装层：mocktail 或假 Dio adapter 验证透传（**必须绕开 Fake 注入**，测真实 client + 假 adapter 回放 JSON，防二次解析回归）
Widget：三板块在设置页渲染测试（fake SettingsApi 注入）、关键交互（toggle/卸载/安装表单/添加服务器/辅助任务选择）
对比度/无障碍：新文本用现有 color tokens（statusGreenText/statusGreyText/secondaryText），不引入裸 system 色文字

## 7. 验收命令

```bash
/c/tmp/f.bat analyze   # 零告警含 info
/c/tmp/f.bat test      # 全绿（新增用例绿 + 原有 1082 不回归）
```

## 8. 文件级分区（AGY 任务书用）

- **区 A（core 层）**：`lib/core/api/endpoints.dart`、`lib/core/api/api_client_extensions.dart`（新）、`lib/core/api/api_client_mcp.dart`（新）、`lib/core/api/api_client_server_panels.dart`（追加 2 方法）、`lib/core/models/extensions.dart`（新）、`lib/core/models/mcp.dart`（新）、`lib/core/models/auxiliary_model.dart`（新）+ 对应单测（test/core/ 下）
- **区 B（settings 层）**：`lib/features/settings/settings_page.dart`、`lib/features/settings/settings_providers.dart`、新建 `lib/features/settings/extensions_section.dart`、`mcp_section.dart`、`auxiliary_models_section.dart`（或按需并入 settings_page）、`lib/l10n/app_localizations.dart` + settings 相关 widget/controller 测试

> 两区仅通过 §4 的 `SettingsApi` 接口签名耦合；规格已定死，A/B 可并行。A 先建模型与 client 方法，B 按规格写 UI，编译冲突由 Leader 最终统一解决。