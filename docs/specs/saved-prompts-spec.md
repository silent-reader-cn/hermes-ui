# 收藏提示词（Saved Prompts）规格 — feat/saved-prompts

> 对齐后端契约：hermes-webui `api/routes.py` 的 `/api/prompts` 三端点。
> UI 对齐 WebUI 的 `static/messages.js` 行为（收藏/列表/插入/删除），但按 Cupertino 规范重做。

## 1. 后端契约（只读，已锁死）

源码：`D:/hermes-webui/api/routes.py`

- 路径工具：
  ```python
  def _saved_prompts_path() -> Path:
      try: from api.profiles import get_active_hermes_home
           return Path(get_active_hermes_home()) / "webui" / "saved_prompts.json"
      except: return Path(os.getenv("HERMES_HOME", "~/.hermes")) / "webui" / "saved_prompts.json"
  def _load_saved_prompts() -> list: # [] if missing/invalid
  def _save_saved_prompts(prompts: list): # mkdir -p + json dump ensure_ascii False
  ```

- **GET /api/prompts**（`_handle_get` L13117）：
  ```json
  {"prompts": [{"id": "abc123def456", "label": "xxx", "text": "full text", "created_at": 1710000000.0}]}
  ```
  无参。始终 200。

- **POST /api/prompts**（`_handle_post` L13998）：
  - 入参：`{"text": string, "label"?: string}` — `text = str(body.get("text") or "").strip()`，`label = str(...) .strip()`
  - 校验：
    - `if not text: bad("text is required")`
    - `if len(text) > 8000: bad("text too long (max 8000 chars)")`
    - `if len(prompts) >= 200: bad("saved prompts limit reached (max 200)")`
  - 创建：`{"id": uuid.uuid4().hex[:12], "label": label or text[:60], "text": text, "created_at": time.time()}`
  - 返回：`{"ok": true, "prompt": new_prompt}`
  - 注意：`text[:60]` 是 Python 切片（按字符），Dart 侧展示时同理；后端 `label` 允许空则回落。

- **DELETE /api/prompts**（`_handle_delete` L16473）：
  - 入参：`{"id": str}` — `pid = str(body.get("id") or "").strip()`
  - 校验：`if not pid: bad("id is required")`
  - 行为：过滤 `p.get("id") != pid`，写回；**幂等**（不存在也 200）
  - 返回：`{"ok": true}`

## 2. 前端参考行为（WebUI messages.js L797-900）

- `insertSavedPromptIntoComposer(text)`: 把 `text` 追加到 `#msg`（composer）：
  ```js
  composer.value = current.trim() ? `${current.replace(/\s+$/,'')}\n\n${text}\n\n` : `${text}\n\n`
  ```
  追加后 `focus()` + `setSelectionRange(end,end)` + `dispatchEvent('input')` + `autoResize()`.
- `_loadSavedPrompts()`: `GET /api/prompts` → `data.prompts` 数组，容错 `[]`
- `toggleSavedPromptsPopup()`: 弹窗渲染 — 空态 `No saved prompts yet.`，每行 `label||text` + 删除按钮(×)，底部 `Save current input` 按钮（POST 当前输入框内容），点击行插入，点击删除调 DELETE 后刷新。

## 3. Flutter 侧设计

### 3.1 目录与文件分区（并行不重叠）

| Agent | 负责文件 | 说明 |
|-------|---------|------|
| A (core) | `lib/core/api/endpoints.dart` (+1 行), `lib/core/models/saved_prompt.dart` (新建), `lib/core/api/api_client_prompts.dart` (新建) | 纯 core，无 UI 依赖 |
| B (state) | `lib/features/prompts/prompts_providers.dart` (新建), `lib/features/prompts/prompts_controller.dart`（可选，与 providers 合并亦可） | Riverpod 状态层，依赖 A 的 model/api |
| C (ui+l10n) | `lib/l10n/app_localizations.dart` (+ ~10 行), `lib/features/prompts/widgets/saved_prompts_sheet.dart` (新建), `lib/features/chat/widgets/chat_input_bar.dart` (改) | UI 集成，依赖 A+B |

### 3.2 模型（A）

`lib/core/models/saved_prompt.dart`

```dart
class SavedPrompt { const SavedPrompt({this.id, this.label, this.text, this.createdAt}); final String? id; final String? label; final String? text; final double? createdAt; factory SavedPrompt.fromJson(Map<String,Object?> json) ...; Map<String,Object?> toJson() ...; }

class SavedPromptsResponse { const SavedPromptsResponse({this.prompts}); final List<SavedPrompt>? prompts; factory SavedPromptsResponse.fromJson(...) ...; }

class SavePromptResponse { const SavePromptResponse({this.ok, this.prompt, this.error}); factory ...; }

class DeletePromptResponse { const DeletePromptResponse({this.ok, this.error}); }
```

- `fromJson` 容错：用 `optString`/`lossyString` + `flexibleDouble`，未知字段忽略，缺失给 null，类型不符不 throw（对齐项目容错规则）。
- `label` 展示回落：`prompt.label?.isNotEmpty == true ? label : (text ?? '')`，UI 侧再 `take(60)` 截断同后端。

### 3.3 端点（A）

`lib/core/api/endpoints.dart` 追加（放在 `// 1.15 skills` 之后，`// 1.16 upload` 之前）：

```dart
// ---------------------------------------------------------------------------
// 1.15b prompts — 3 个（GET/POST/DELETE 同路径，方法区分）
// ---------------------------------------------------------------------------
static const prompts = Endpoint('/api/prompts');
```

与现有 `memory`/`skills` 风格一致（同一路径复用同一 Endpoint，方法由 ApiClient 决定）。

### 3.4 ApiClient 扩展（A）

`lib/core/api/api_client_prompts.dart`

```dart
extension ApiClientPrompts on ApiClient {
  Future<SavedPromptsResponse> fetchPrompts() async {
    final json = await sendJson(Endpoint.prompts);
    return SavedPromptsResponse.fromJson(_asMap(json));
  }
  Future<SavePromptResponse> createPrompt({required String text, String? label}) async {
    final json = await sendJson(Endpoint.prompts, method: 'POST', body: {'text': text, 'label': ?label});
    return SavePromptResponse.fromJson(_asMap(json));
  }
  Future<DeletePromptResponse> deletePrompt(String id) async {
    final json = await sendJson(Endpoint.prompts, method: 'DELETE', body: {'id': id});
    return DeletePromptResponse.fromJson(_asMap(json));
  }
}
Map<String,Object?> _asMap(Object? json) => json is Map<String,Object?> ? json : (json is Map ? Map<String,Object?>.from(json) : const {});
```

- 需处理后端错误：`sendJson` 401 等会 throw `ApiException`（调用方 catch 展示），200 内的业务 bad 已由 `sendJson` 按状态码抛，这里无需额外 `code` 字段判断（与 `memoryWrite` 一致）。

### 3.5 状态层（B）

`lib/features/prompts/prompts_providers.dart`

- `promptsApiProvider` / `savedPromptsControllerProvider` 模式参考 `memory`/`skills` 的 provider（若无则仿 `chat_providers.dart` 的 `chatApiProvider` 形状）。
- 建议：`SavedPromptsController extends AsyncNotifier<List<SavedPrompt>>` 或 `Notifier<AsyncValue<List<SavedPrompt>>>`，提供 `refresh()`, `create(text,label)`, `remove(id)`，内部调 `ApiClientPrompts` 扩展，操作后局部更新或重拉 `fetchPrompts()`。
- `Provider` 命名后缀 `Provider`，`Notifier` 后缀 `Controller`（AGENTS.md §6）。
- 页面不直接持有网络逻辑，一律走 Provider。

### 3.6 UI（C）

- **入口**：`ChatInputBar` 新增一个收藏按钮（书签图标 `CupertinoIcons.bookmark` 或 `bookmark_solid`），`key: chat-saved-prompts-button`，位于附件按钮与输入框之间或输入框右侧（与模型按钮并列）。点击弹 `showCupertinoModalPopup` 的 `CupertinoActionSheet` 或自定义底部 Sheet（参考 `chat_input_bar.dart` 的 `_showModelPicker` 写法）。
- **Sheet**：`lib/features/prompts/widgets/saved_prompts_sheet.dart`
  - 标题：`l10n.savedPrompts`（见 l10n）
  - 列表：`List<SavedPrompt>`，每行 `CupertinoListTile` 显示 `label`（回落 `text` 前 60 字符），副标题 `text` 单行省略，尾部删除按钮（`CupertinoIcons.delete`，红色）。点击行 → 回调 `onInsert(text)` 把文本插入输入框（对齐 WebUI 的追加逻辑：`current.trim().isEmpty ? text : '$current\n\n$text'`），关闭 Sheet。
  - 空态：`l10n.savedPromptsEmpty` + 灰色提示
  - 底部：`CupertinoButton` “保存当前输入”（`l10n.saveCurrentInput`），校验 `controller.text.trim().isEmpty` 则 toast/error，成功后刷新列表并提示 `l10n.promptSaved`。
  - 加载/错误态：`CupertinoActivityIndicator` / `statusRedText` + 重试按钮（对齐其他 feature 的 error 模式：`重试`按钮 + 红字 detail）。
- **插入逻辑**：ChatInputBar 需暴露 `TextEditingController` 文本追加方法（参考 `insertSavedPromptIntoComposer` 的双换行追加 + 光标移到末尾 + `setState` 更新 `_hasText`）。
- **l10n**：`lib/l10n/app_localizations.dart` 在 `// 12. Projects` 之后新增 `// 13. Saved Prompts` 段：
  ```dart
  String get savedPrompts => isEnglish ? 'Saved Prompts' : '收藏提示词';
  String get savedPromptsEmpty => isEnglish ? 'No saved prompts yet.' : '暂无收藏提示词';
  String get savedPromptsDelete => isEnglish ? 'Delete' : '删除';
  String get saveCurrentInput => isEnglish ? 'Save current input' : '收藏当前输入';
  String get promptSaved => isEnglish ? 'Prompt saved' : '已收藏';
  String get promptDeleted => isEnglish ? 'Prompt deleted' : '已删除';
  String get savePromptFailed => isEnglish ? 'Failed to save prompt' : '收藏失败';
  String get deletePromptFailed => isEnglish ? 'Failed to delete prompt' : '删除失败';
  String get savedPromptsSaveCurrent => isEnglish ? 'Save current input' : '收藏当前输入';
  String get savedPromptsEmptyInput => isEnglish ? 'Type a prompt first' : '请先输入提示词';
  String get bookmarkPrompt => isEnglish ? 'Saved prompts' : '收藏提示词';
  ```

### 3.7 关键实现细节（易错）

- **字体**：`MiSans` 已全局注入，无需额外处理。
- **动态色 resolve**：Sheet 背景若用 `CupertinoColors.systemGrey6` 必须 `resolveFrom(context)`，否则暗黑模式白块（见 skill 主文档）。
- **测试可注入性**：Providers 必须支持 override（fake ApiClient），参考 `chatAvailableModelsProvider` 的 `Provider<List<String>>((ref)=>const[])` 可 override 模式；`apiClientProvider` 来自 `connection_providers.dart`，测试用 `ProviderContainer(overrides: [apiClientProvider.overrideWithValue(fake)])`。
- **插入后光标**：`_textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length))` + `setState(() => _hasText = ...)`。
- **并发**：收藏操作（POST/DELETE）期间按钮禁用，避免重复提交。

## 4. 测试要求（必写）

- **模型单测**：`test/core/models/saved_prompt_test.dart` — JSON 解析含畸形输入容错（缺字段、类型错、null、unknown field）
- **ApiClient 方法单测**：`test/core/api/api_client_prompts_test.dart` — mock Dio fake adapter 验路径/方法/参数/解析（参考 `test/features/api_wrappers_regression_test.dart` 的 `FakeAdapter` 模式，需带 `content-type: application/json` header）
- **Controller 单测**：`test/features/prompts/prompts_controller_test.dart` — fetch/创建/删除/错误恢复
- **Widget 测试**：`test/features/prompts/saved_prompts_sheet_test.dart` — 列表渲染、空态、插入回调、删除回调
- **ChatInputBar 集成**：`test/features/chat/chat_input_bar_prompts_test.dart` — 收藏按钮存在、点击弹 sheet、插入文本追加逻辑

## 5. 完成定义

- [ ] `flutter analyze` 零告警
- [ ] `flutter test` 全绿（新增代码有测试）
- [ ] 无 Material 组件混入（全部 Cupertino）
- [ ] 收藏提示词可在会话输入时：收藏当前输入、浏览列表、点击插入、删除
- [ ] 与后端契约一致（GET/POST/DELETE /api/prompts）
