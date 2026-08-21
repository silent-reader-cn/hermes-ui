# 工作区管理（Workspace Manager）功能规格

> 版本：1.0（2026-08-21）
> 范围：hermex-flutter 客户端「工作区管理」功能预研 —— 后端 API 契约、认证机制、WebUI 交互行为、Flutter 端现状盘点、数据模型/端点/页面/schema 建议。
> 后端事实来源：主人 fork 的 nesquena/hermes-webui（本机 `D:/hermes-webui`，运行于 `http://localhost:30002`）。
> 证据规则：所有 API 形状均来自**后端源码行号引用**或 **curl 实测输出摘录**，禁止凭空猜测；凡标注 `实测` 的为登录态 curl 直连 :30002 的真实响应，标注 `源码` 的为 `D:/hermes-webui` 内指定文件行号。

---

## 0. 一页结论（TL;DR）

- 工作区管理 = **两类端点**：① 工作区注册表 CRUD（`/api/workspaces` 家族，6 个，**与 session 无关**，操作的是 `state_dir/workspaces.json`）；② 单会话工作区的文件浏览/内容/下载（`/api/list`、`/api/file`、`/api/file/raw` 等，**必须带 `session_id`**，以该会话的 `workspace` 为根）。
- 认证：所有工作区端点都走 **cookie 会话**（`hermes_session=<token>.<hmac>`），服务器开启密码登录时未认证一律 `{"error":"Authentication required"}`（HTTP 401）；无 API key。Flutter 端 `ApiClient` 已内置完整 cookie 会话 + 自动重登机制，可零改动复用。
- 实测：`GET /api/workspaces` 带 cookie 返回 `{"workspaces":[{"path","name"}...],"last":"D:\\projects\\hermex-flutter","terminal_remote_backend":false}`。
- Flutter 现状：模型层（`workspace.dart`）与 API 层（`api_client_workspace.dart` + `workspace_api.dart`）**已覆盖两端点全族**，但缺 `terminal_remote_backend`、`signature`、`mtime_ns`（现状读的是不存在的 `modified`）、symlink 字段；UI 层只有**文件浏览页**（`workspace_page.dart`），**没有**工作区列表/管理页，也没有文件内容预览页。
- 交付建议：新增 `WorkspaceManagerController`（AsyncNotifier，family 无需 session）+ `WorkspaceManagerPage`（Cupertino 列表页）+ 新建/重命名弹窗（带 `/api/workspaces/suggest` 补全）+ 文件预览页（文本用 `/api/file`，图片/媒体用 `/api/file/raw`）。
- ⚠️ 实测坑：后端 worker 池（128 线程）满载时**任何端点**返回裸 `HTTP/1.1 503` + `Connection: close` + 空 body（`server.py:124-129`），客户端必须把「传输级 503」当可重试错误（与 JSON body 的 503 语义不同）。

---

## 1. 后端端点全表（method / path / 参数 / 响应形状）

### 1.0 路由分发位置（源码证据）

- GET 分发：`api/routes.py` 的 `handle_get` 大 if-链（`/api/workspaces` L13123、`/api/workspaces/suggest` L13133、`/api/list` L13147、`/api/file/raw` L13315、`/api/file` L13324、`/api/folder/download` L13321）。
- POST 分发：同文件 `handle_post`（文件操作 L15298-15326、工作区注册表 L15329-15339、上传 L13849-13853）。
- 认证门卫：`server.py:382`（GET）与 `server.py:410`（POST）在进入 handler 前统一 `check_auth(self, parsed)`。

### 1.1 工作区注册表域（6 个）—— 会话无关

#### GET `/api/workspaces` — 列出所有工作区

| 项 | 值 |
|---|---|
| 请求参数 | 无 |
| 响应 JSON | `{"workspaces": [{"path": str, "name": str}, ...], "last": str, "terminal_remote_backend": bool}` |
| 源码 | `routes.py:13123-13131`；`load_workspaces()`：`workspace.py:337-367`；`get_last_workspace()`：`workspace.py:415` |
| 实测 | 登录态 curl 返回（节选）：`{"workspaces":[{"path":"C:\\Users\\Admin\\workspace","name":"Home"},{"path":"D:\\projects\\hermex-flutter","name":"HERMEX"},…共 9 项],"last":"D:\\projects\\hermex-flutter","terminal_remote_backend":false}` |

- `workspaces.json` 持久化路径：`STATE_DIR/workspaces.json`（`config.py:86`；本机 `C:\Users\Admin\AppData\Local\hermes\webui_30002\workspaces.json`）。条目**恒为 `{path, name}` 对象**（实测与文件一致）；早期版本可能存裸字符串，Flutter 模型已兼容（见 §4.1）。
- 无任何配置文件时不建文件，返回单条默认 `[{"path": <profile default>, "name": "Home"}]`（`workspace.py:351/367`）。

#### GET `/api/workspaces/suggest?prefix=` — 工作区路径补全

| 项 | 值 |
|---|---|
| 请求参数 | `prefix`（query，可空，默认 `""`） |
| 响应 JSON | `{"suggestions": [str, ...], "prefix": str}` |
| 源码 | `routes.py:13133-13142`；`list_workspace_suggestions()`：`workspace.py:695-807` |
| 语义 | 只扫描「可信根」（Home 目录 / 启动默认工作区 / 已保存工作区根，`workspace.py:698-705`）；任意系统前缀返回空数组而非报错；每项**最多 12 条**（`limit=12` 默认）；`~` 前缀保留为 `~/...` 形式 |

#### POST `/api/workspaces/add` — 添加（可创建目录）

| 项 | 值 |
|---|---|
| 请求体 JSON | `{"path": str, "name"?: str, "create"?: bool}`；`path` 首尾成对引号会被剥除（`routes.py:23517`） |
| 响应 JSON | `{"ok": true, "workspaces": [{"path","name"},...]}`（变更后全量列表） |
| 源码 | `_handle_workspace_add`：`routes.py:23510-23560` |
| 错误 | 400 `path is required`；400 `Path points to a system directory: <path>`（系统根被封，家目录例外）；400 `Could not create directory: ...`（create 失败）；400 `Workspace already in list`（重复）；路径校验 `validate_workspace_to_add`（`workspace.py:903-941`：只挡不存在路径/非目录/已知系统根；**它信任用户显式意图**，比使用期校验宽松） |
| 语义 | `create=true` 时先 `mkdir(parents=True, exist_ok=True)`；`name` 缺省回退 `path` 的 basename |

#### POST `/api/workspaces/remove` — 移除（不删磁盘文件）

| 项 | 值 |
|---|---|
| 请求体 JSON | `{"path": str}`（必须与列表中的 `path` 精确匹配） |
| 响应 JSON | `{"ok": true, "workspaces": [...]}` |
| 源码 | `_handle_workspace_remove`：`routes.py:23563-23570` |
| 语义 | 只是从 `workspaces.json` 过滤掉该 entry；**不删任何磁盘内容**。路径不存在也返回 `ok:true`（幂等） |

#### POST `/api/workspaces/rename` — 重命名（仅改显示名）

| 项 | 值 |
|---|---|
| 请求体 JSON | `{"path": str, "name": str}` |
| 响应 JSON | `{"ok": true, "workspaces": [...]}` |
| 源码 | `_handle_workspace_rename`：`routes.py:23573-23586` |
| 错误 | 400 `path and name are required`；404 `Workspace not found` |
| 语义 | 只改 `name` 字段，**不改 `path`**（WebUI 编辑表单里 path 只读，见 §3.1） |

#### POST `/api/workspaces/reorder` — 排序

| 项 | 值 |
|---|---|
| 请求体 JSON | `{"paths": [str, ...]}`（顺序即新顺序；未提及的条目追加到末尾） |
| 响应 JSON | `{"ok": true, "workspaces": [...]}` |
| 源码 | `_handle_workspace_reorder`：`routes.py:23589-23614` |

### 1.2 会话工作区文件浏览域（核心 3 个 GET + 文件操作 POST）

> **共同语义**：`session_id` 定位会话 → 会话的 `workspace` 字段为根；`path` 均为**工作区相对路径**（`/` 分隔，`.` = 根）；一切路径解析走 `safe_resolve_ws`（`workspace.py:943-957`），`..` 穿越与符号链接逃逸一律 `ValueError` → 400；会话不存在的三种回退顺序：WebUI 内存 SESSIONS → CLI 会话列表（`routes.py:16800-16815`）。
> ⚠️ Windows 服务器上 entry 的 `path` 是**反斜杠绝对路径显示**（`list_dir` 用 `rel + '/' + name` 拼 POSIX 相对路径，实测可见 `"path": "docs/specs/..."` 形式），而 `/api/workspaces` 的 `path` 是磁盘绝对路径（`C:\...` / `D:\...`）——两类 path 语义不同，客户端不得混用。

#### GET `/api/list?session_id=&path=` — 目录条目列表

| 项 | 值 |
|---|---|
| 请求参数 | `session_id`（必填）、`path`（可空，默认 `"."`） |
| 响应 JSON | `{"entries": [Entry...], "signature": str(sha256 hex), "path": str}` |
| 源码 | `_handle_list_dir`：`routes.py:16795-16828`；`list_dir()`：`workspace.py:1234-1336`；`dir_signature()`：`workspace.py:1433-1455` |
| 错误 | 404 `Session not found` / `Not a directory: <path>`；400 `invalid path` |

**Entry 字段（精确蛇形命名，`workspace.py:1247-1336`）**：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | str | 条目名（仅末段，不含父路径） |
| `path` | str | 工作区相对路径（`rel/name`，根下级即 `name`），**客户端用它作为后续请求的 path 参数** |
| `type` | str | `"dir"` / `"file"` / `"symlink"` |
| `size` | int \| null | 文件字节数（目录/symlink 为 null） |
| `mtime_ns` | int \| null | **纳秒**时间戳（`os.stat` 的 `st_mtime_ns`）；普通文件/目录都有 |
| `is_dir` | bool | **仅 symlink 条目出现**（其解析目标是否为目录） |
| `target` | str | 仅 symlink 且未逃逸工作区时出现（解析后的绝对路径） |
| `target_outside_workspace` | bool | 仅 symlink 出现；`true` = 指向工作区外（**只展示不可读写**，`workspace.py:1285-1299` 只发 4 个安全字段） |

- `signature`：基于条目元数据（name/path/type/is_dir/size/mtime_ns/target/target_outside_workspace）的 SHA-256，**不含文件内容**；WebUI 用它做目录缓存失效（客户端可选做，不强制）。
- 排序：目录在前、文件在后，各自按名称排序（`list_dir` 尾部 sort；实测 `docs` 等目录排在文件前）。
- 实测（2026-08-21 截图节选，200 OK）：`GET /api/list?session_id=<webui会话>&path=.` →
  ```json
  {
    "entries": [
      {"name": ".dart_tool", "path": ".dart_tool", "type": "dir", "size": null, "mtime_ns": 1787179911828507100},
      {"name": ".git", "path": ".git", "type": "dir", "size": null, "mtime_ns": 1787267345565716500},
      ...
    ],
    "path": ".",
    "signature": "567213e156933a5e704208427bc7681f..."
  }
  ```
  （32 条 entries；`keys: entries/path/signature` 与源码完全一致，`size:null` 用于目录，`mtime_ns` 为纳秒 int。）
- ⚠️ 探测期间后端 worker 池满载时该端点返回裸 503（见 §0 坑）；恢复后正常 200（以上实测即恢复后捕获）。

#### GET `/api/file?session_id=&path=` — 文本内容 / 预览（JSON）

| 项 | 值 |
|---|---|
| 请求参数 | `session_id`（必填）、`path`（必填，非空） |
| 响应 JSON | 普通文本：`{"path": str, "content": str, "size": int, "lines": int}`；Office（.docx/.xlsx/.pptx）走 `preview_office_document`：`{"path","content","size","lines","preview_kind","office_format","render_mode","editable", 可选 "edit_blocked_reason","truncated"}` |
| 源码 | `_handle_file_read`：`routes.py:19203-19220`；`read_file_content()`：`workspace.py:1458-1479`；office：`office_documents.py:555-586` |
| 错误 | 404 `Not a file: <path>`；400 `path is required`；503（office 依赖缺失时）|
| 语义 | UTF-8 解码（`errors='replace'`，坏字节不报错）；> `MAX_FILE_BYTES` 的文件直接 400 `File too large`（长度上限见 `workspace.py:1471-1473`）；`content.count('\n')+1` 为行数 |
| 实测 | 200 OK（`path=pubspec.yaml`）：`{"content": "name: hermex_flutter\\r\\n...", "lines": 105, "path": "pubspec.yaml", "size": 4011}` —— `keys: content/lines/path/size` 与源码一致 |

#### GET `/api/file/raw?session_id=&path=[&download=1][&inline=1]` — 原始字节（下载 / 图片 / 媒体）

| 项 | 值 |
|---|---|
| 请求参数 | `session_id`（必填）、`path`（必填）、`download=1`（强制 attachment）、`inline=1`（仅对 `text/html` 放行沙箱预览） |
| 响应 | 二进制流；`Content-Type` 按扩展名（MIME_MAP，未知为 `application/octet-stream`）；危险 MIME（`text/html`/`application/xhtml+xml`/`image/svg+xml`）**默认强制 attachment** 防 XSS（`routes.py:19184-19187`） |
| 源码 | `_handle_file_raw`：`routes.py:19163-19200`；`_file_raw_target`（同文件 19174 行调用，路径解析+大小上限同 `/api/file`） |
| 错误 | 404 `{"error":"not found"}`；400 `session_id is required`；400 `invalid path`；超大文件 400 |
| 客户端用途 | 图片预览（`<img>`）、音视频/PDF 内嵌、下载落盘——**Flutter 端 `rawFileData` 已封装** |
| 实测 | 200 OK（`path=pubspec.yaml`）：body 4011 字节原始文件；headers `Content-Type: application/octet-stream`（yaml 不在 MIME_MAP → 兜底）、`Content-Disposition: inline; filename="pubspec.yaml"; filename*=UTF-8''pubspec.yaml`、`X-Content-Type-Options: nosniff` |

#### GET `/api/folder/download?session_id=&path=` — 目录打包下载（zip 流）

| 项 | 值 |
|---|---|
| 请求参数 | `session_id`、`path`（必须是目录） |
| 响应 | `application/zip` 流（`Content-Disposition: attachment; filename="<dirname>.zip"`），无 Content-Length，`Connection: close` |
| 源码 | `_handle_folder_download`：`routes.py:19066-19160` |
| 错误 | 400 `path must be a directory; use /api/file/raw for single files`；413 `{"error":"folder too large","limit_bytes":N,"configure":"HERMES_WEBUI_FOLDER_ZIP_MAX_MB"}` / `{"error":"too many files","limit":N,...}`（预检后才发包体） |
| 备注 | 可选高级能力；symlink 逃逸条目跳过；空目录返回合法空 zip |

#### POST `/api/file/delete` — 删除文件/目录

- 请求体：`{"session_id", "path", "recursive"?: bool}`（目录必须 `recursive=true`，否则 400）
- 成功响应：`{"ok": true, "path": "<请求时 path>"}`
- 错误：400 `File not found`→404、`Set recursive=true to delete directories`、`Cannot delete a symlinked entry`（后两者 400）
- 源码：`_handle_file_delete`：`routes.py:23067-23096`

#### POST `/api/file/rename` — 重命名文件/目录

- 请求体：`{"session_id", "path", "new_name"}`（`new_name` 仅末段，含 `/`、`\`、`..` 或空 → 400 `Invalid file name`）
- 成功响应：`{"ok": true, "old_path": "<请求时 path>", "new_path": "<新相对路径>"}`
- 错误：404 `File not found`、400 `A file named "<new_name>" already exists`、400 `Cannot rename a symlinked entry`
- 源码：`_handle_file_rename`：`routes.py:23192-23224`（Flutter 端模型 `FileRenameResponse` 已对齐 `old_path`/`new_path`，`workspace.dart:401-439`）

#### POST `/api/file/create` / `/api/file/create-dir` — 新建文件 / 目录

- 请求体：`{"session_id", "path", "content"?: str}`（create 文件；content 默认空串）
- 成功响应：`{"ok": true, "path": "<规范化相对路径>"}`
- 错误：400 `File already exists`/`Path already exists`（create 用 `O_EXCL` 原子防重）
- 源码：`_handle_file_create`：`routes.py:23165-23189`；`_handle_create_dir`：`routes.py:23325-23344`

#### POST `/api/file/move` — 移动（跨目录）

- 请求体：`{"session_id", "path", "dest_dir"}`（目标目录相对路径；`..` 段被拒）
- 成功响应：`{"ok": true, "old_path", "new_path"}`
- 错误：400 `Cannot move a folder into itself or its subfolder`、404 `Destination folder not found`
- 源码：`_handle_file_move`：`routes.py:23227-23322`

#### POST `/api/file/save` / `/api/file/office-save` — 保存编辑后的文本 / Office

- 请求体：`{"session_id", "path", "content"}`；`.docx/.xlsx/.pptx` 必须走 `/api/file/office-save`（普通 save 对其 400 `Use /api/file/office-save for Office documents`）
- 成功响应：`{"ok": true, "path", "size": int}`（office-save 附带 preview 字段：`preview_kind/office_format/render_mode/editable` 等）
- 源码：`routes.py:23099-23127`（save）、`routes.py:23130-23162`（office-save）
- 备注：文件预览页若做「编辑保存」，需按扩展名选择 save 路由（WebUI 同款逻辑 `workspace.js:984-990`）

#### POST `/api/file/path` / `/api/file/reveal` / `/api/file/open-vscode` — 平台集成（可选）

- `file/path`：`{"session_id","path"}` → `{"ok":true,"path":"<服务器绝对路径>"}`（目标可不存在；`routes.py:23395-23421`，用于「复制绝对路径」）
- `file/reveal`：在服务器文件管理器里选中（Windows 调 `explorer.exe /select,`；`routes.py:23347-23392`）
- `file/open-vscode`：服务器侧用 `code` 打开（需服务器装 VS Code CLI 或 `vscode.command` 配置；`routes.py:23424-23507`）
- 移动端无意义，列为可选。

### 1.3 上传域（2 个，注意区别）

#### POST `/api/workspace/upload` — ⭐ WebUI 实际使用的上传端点（推荐 Flutter 迁移至此）

- multipart form：文本字段 `session_id`、`path`（目标子目录，默认工作区根）、文件字段 `file`（**可多文件**）
- 成功响应：单文件 → 对象；多文件 → `{"files": [对象...], "count": N}`
  - 普通文件对象：`{"filename", "path", "size", "mime", "is_image", "extracted": false, 可选 "sidecar"/"sidecar_error"}`
  - 归档（.zip/.tar/.tar.gz/.tgz/.tar.bz2/.tbz2/.tar.xz/.txz）：**自动解压**到 `path/<stem>`，删除归档：`{"filename","path","size","is_image":false,"extracted":true,"extracted_files":[...],"extracted_count":N}`；解压失败：`{"filename","path","size","mime","is_image":false,"extracted":false,"extract_error":str}`
- 重名去重：自动追加 `-1`、`-2` 后缀（`upload.py:660-672`）
- 错误：400 `Missing session_id` / `No file field in request`；404 `Session not found`；403 `Upload target escapes workspace`；409 `Upload destination already exists`；413 `File too large (max NMB)`（`MAX_UPLOAD_BYTES` 上限）
- 源码：`handle_workspace_upload`：`api/upload.py:592-767`

#### POST `/api/upload` — Flutter 当前实现（聊天附件同款，单文件）

- multipart form：`session_id` + `file`（单文件）；**无 path 参数**（固定落到工作区根）
- 成功响应：`{"filename", "path", "size", "mime", "is_image"}`（`path` 是**绝对路径**）
- 源码：`handle_upload`：`api/upload.py:206-241`
- 结论：聊天附件用 `/api/upload` 无妨，但**工作区上传应改用 `/api/workspace/upload`**（支持目标子目录、多文件、归档解压、去重）。

---

## 2. 认证机制（实现必读）

### 2.1 机制总述

- **纯 cookie 会话认证，无 API key**。cookie 名 `hermes_session`（`auth.py:61`，可用 `HERMES_WEBUI_SESSION_COOKIE_NAME` env 覆盖；30002 fork 未覆盖）。
- cookie 值格式：`<token>.<sig>`，token = `secrets.token_hex(32)`，sig = `HMAC-SHA256(.signing_key, token)`（`auth.py:579-597`）。`.signing_key` 存在 state_dir（本机 `webui_30002/.signing_key`）。
- 会话有效期默认 30 天（`HERMES_WEBUI_SESSION_TTL` 可调）；服务端 token 表持久化在 `state_dir/.sessions.json`，过期自动剔除（`auth.py:600-608`）。
- 认证门卫：`server.py:382`（GET）/ `server.py:410`（POST）在路由前执行 `check_auth`；未登录 → `{"error":"Authentication required"}`（HTTP 401）。
- 实测：`curl http://localhost:30002/api/workspaces`（无 cookie）→ `{"error":"Authentication required"}`；带合法 cookie → 200 全量 JSON（§1.1 实测）。
- 线上 auth 状态（实测 `/api/auth/status`）：`auth_enabled: true, logged_in: false, password_auth_enabled: true`（未带 cookie 时）；登录用 `POST /api/auth/login {"password": "<pw>"}` → 成功 `{"ok": true}` 并 Set-Cookie（`api_client.dart:510-515`）。

### 2.2 Flutter 端现状（零改动复用）

- `ApiClient`（`lib/core/api/api_client.dart`）已实现：登录后 cookie 自动注入/落库（`CookieStore`，L365-389）、401 归一化为 `UnauthorizedException`、同域/跨域下载自动分流（L262 区）。
- 自动重登：`auto_reauth_spec.md` 已落地 —— 数据端点 401 时用连接里保存的密码重登并重试一次（lie in `session_list_providers.dart` 的 `_tryAutoReauth`；后续要推广到所有 401 场景，工作区管理页可直接沿用同一 `apiClientProvider`）。
- 因此工作区所有端点**无需新增任何认证代码**，直接把端点接到 `ApiClient` 的 `sendJson`/`sendData` 即可。

### 2.3 需要留意的两点

1. **profile 绑定**：cookie 可带 `bound_profile`，一个登录会话可能绑定到某 profile；工作区列表/文件浏览是 profile 作用域的（`workspaces.json` 按 profile 分开）。Flutter 端沿用现有连接（同一 cookie）即可，不必特殊处理。
2. **502/503 过载**：worker 池（128 线程）满载时返回裸 503 空 body（`server.py:124-129` `_OVERFLOW_RESPONSE`），与 JSON 503 语义不同——客户端应把「传输错误/空 body 503」统一视为可重试（指数退避重试 1-2 次）。

---

## 3. Hermes WebUI 前端交互行为（移植蓝本）

源码：`D:/hermes-webui/static/`（`panels.js` = 工作区注册表面板；`workspace.js` = 会话文件树/预览；`ui.js` = 文件右键菜单）。

### 3.1 工作区注册表面板（panels.js）

- **列表**：`loadWorkspaceList()`（`panels.js:5672-5681`）`api('/api/workspaces')` 缓存 `_workspaceList`；每行 = 友好名（`getWorkspaceFriendlyName`：查找 `name`，无则取 path 末段，L5623-5630）+ 完整路径副行。
- **当前工作区**：`syncWorkspaceDisplays()`（L5632-5670）根据「激活会话的 workspace」或 profile 默认工作区显示 chip（侧栏 + 底栏 composer）；点击 chip 打开下拉切换（`switchToWorkspace(path, name)`）。
- **新建**：`openWorkspaceCreate()`（L6135-6140）→ 表单模式（L6149-6183）：
  - `Name` 可选 + `Path` 必填；输入 path 时 120ms 防抖请求 `/api/workspaces/suggest?prefix=`（L5596-5621）以内联建议列表补全（滚动键盘上下选中，mousedown 直选）。
  - 提交 `saveWorkspaceForm()`（L6196-6236）：先 `POST /api/workspaces/add {"path"}`，若填了 name 再 `POST /api/workspaces/rename {"path","name"}`；成功后刷新列表并打开该工作区详情。
- **编辑/重命名**：`editCurrentWorkspace()`（L6142-6147）→ 同一表单，**path 只读**（`disabled` + "Path cannot be changed. Rename only."，L6155-6157）；提交 `rename` 后刷新。
- **删除**：`deleteCurrentWorkspace()`（L6121-6133）：确认对话框（danger 样式，文案强调「只注销路径，不删文件」）→ `POST /api/workspaces/remove {"path"}`。
- **排序**：拖拽行 → `POST /api/workspaces/reorder {"paths":[...]}`（L6000 附近）；mutation 在途时禁用 move/delete 防竞态（Swift 版同款：`WorkspaceManagerView.swift:57-58`）。
- 「激活」即切换会话工作区，**不修改注册表**——是 `POST /api/session/update {"session_id","workspace"}` 或新建会话带 `workspace` 的动作，与注册表 CRUD 分离（Swift `WorkspaceRegistryViewModel` 同）。

### 3.2 会话文件树 + 预览（workspace.js / ui.js）

- **树**：`loadDir(dir)` 请求 `/api/list?session_id=&path=`（`workspace.js:608`、1234-1336 区渲染）；目录行点击展开/进入（维护展开状态 + `_dirCache` 缓存）；响应序号守卫防串流（`_wsTreeGen`，L654-666）；**路径一律工作区相对**，展示时剥掉工作区绝对前缀（L616-622）。
- **预览路由**（`openFile`，L1070-1200）：扩展名分流 ——
  - 图片：`/api/file/raw` 作 `<img src>`（带 `_=<timestamp>` 缓存击穿）；
  - 音频/视频：`/api/file/raw?inline=1` 内嵌播放器；
  - PDF：`/api/file/raw?inline=1` 塞 iframe；
  - HTML：`/api/file/raw?inline=1` 塞沙箱 iframe（`sandbox="allow-scripts"`，无 allow-same-origin，L1143-1158）；
  - Markdown/CSV/代码：`/api/file` 取文本 → 渲染（CSV 表格化、markdown 富渲染；CSV 太大/二进制标记退回下载）；
  - `DOWNLOAD_EXTS` 黑名单（zip 等二进制）直接触发下载（L1078-1081）。
- **下载**：`downloadFile(path)`（L1202-1212）→ 构造 `/api/file/raw?...&download=1` 塞临时 `<a download>` 点击。
- **上传**：`uploadToWorkspace(file, dir)`（L1313-1347）→ `FormData{session_id, path: dir, file}` 发 `/api/workspace/upload`（120s 超时）；归档自动解压；`data.error` / `data.extract_error` / 每文件 `extract_error` 都作为错误 toast。
- **右键菜单**（`ui.js:19600-19938`）：新文件 / 新文件夹 / 重命名（`_inlineRenameFileItem` L19940-19975：**预填旧名且只选中主干(stem)、保留扩展名**，目录则全选）/ 删除（确认对话框 `deleteWorkspaceFile` L19977-19992）/ 复制绝对路径（`/api/file/path`）/ 在文件管理器中显示（`/api/file/reveal`）/ 用 VS Code 打开（`/api/file/open-vscode`）；只读 symlink 逃逸条目（`target_outside_workspace`）只保留查看/下载，隐藏写操作（L19922 的 `isReadOnlyEscape` 判断）。
- **保存编辑**：预览内编辑 → `POST /api/file/save`；office 文档预览 `preview_kind==='office'` 时切 `/api/file/office-save`（`workspace.js:984-990, 1180-1186`）。

### 3.3 对 Flutter 移植的要点提炼

1. 工作区注册表 UI 与文件浏览 UI 是**两个独立页面/入口**（注册表更像「设置」子页，文件浏览是会话级入口）。
2. 新建表单 = 名称(可选) + 路径(必填) + 补全列表 + 「不存在则创建」开关（Swift 另有 `createIfMissing` Toggle，`WorkspaceAddSheet.swift` L237）。
3. 删除确认文案必须说清「不删除磁盘文件」。
4. 重命名预填：选中主干保留扩展名（iOS 习惯）。

---

## 4. Flutter 端现状盘点（可复用清单）

### 4.1 模型层 `lib/core/models/workspace.dart`（450 行，已较完整）

| 现有模型 | 状态 | 与真实后端对照 |
|---|---|---|
| `WorkspacesResponse{workspaces?, last?}` | ✅ 已用 | ⚠️ 缺 `terminal_remote_backend`（实测响应有，直接忽略无碍但建议补） |
| `WorkspaceSuggestionsResponse{suggestions?, prefix?}` | ✅ 已用 | 与 `/api/workspaces/suggest` 完全对齐 |
| `WorkspaceRoot{path?, name?}` | ✅ 已用 | **兼容裸字符串**（`fromJson` L66-88）；实测后端发 `{path,name}` 对象 |
| `WorkspaceMutationResponse{ok?, workspaces?, error?}` | ✅ 已用 | 与 4 个注册表 mutation 对齐 |
| `AddWorkspaceRequest{path, name?, create?}` | ✅ 已用 | JSON 键 `path/name/create` 精确对齐 |
| `RemoveWorkspaceRequest{path}` / `RenameWorkspaceRequest{path,name}` / `ReorderWorkspacesRequest{paths}` | ✅ 已用 | 对齐 |
| `DirectoryListResponse{entries?, path?, workspace?, error?}` | ✅ 已用 | ⚠️ 缺 `signature`；后端不发 `workspace` 键（保留无害） |
| `WorkspaceEntry{name?, path?, type?, size?, modified?, isDirectory?}` | ✅ 已用 | ⚠️ **`modified` 是 double(epoch 秒)，后端发的是 `mtime_ns`（int 纳秒）→ 实际填不上**；缺 `is_dir` 之外的 `target` / `target_outside_workspace`。当前 `isBrowsableDirectory` = `isDirectory==true || type=='dir'`，对普通目录 OK，对外部 symlink 会误判（type=='symlink' 不浏览，正确） |
| `FileResponse{content?, path?, name?, language?, size?, lines?, error?}` | ✅ 已用 | 与 `/api/file` 文本形状对齐；⚠️ 缺 office 预览字段（`preview_kind`/`office_format`/`render_mode`/`editable`/`edit_blocked_reason`/`truncated`）与 `binary` 标记 |
| `FileDeleteResponse{ok?, path?, error?}` | ✅ 已用 | 精确对齐 `/api/file/delete` |
| `FileRenameResponse{ok?, oldPath?, newPath?, error?}` | ✅ 已用 | 兼容 `old_path`/`new_path` 与驼峰双键 |
| `WorkspaceUploadResult{filename?, path?, size?, mime?, isImage?, error?}` | ✅ 已用 | 对齐 `/api/upload` 单文件形状；⚠️ `/api/workspace/upload` 返回 `extracted/extracted_files/extracted_count/extract_error/sidecar` 等键未建模；多文件信封 `{files,count}` 未建模 |

### 4.2 API 层（可零改动复用）

- `lib/core/api/api_client_workspace.dart`（extension `ApiClientWorkspace`，10 方法）：`workspaces()` / `workspaceSuggestions(prefix)` / `addWorkspace` / `removeWorkspace` / `renameWorkspace` / `reorderWorkspaces` / `directoryList(sessionId, path?)` / `file(sessionId, path)` / `rawFileData(sessionId, path)` / `deleteFile` / `renameFile` / `mediaData` —— **注册表 6 端点 + 文件核心 4 端点全部封装完毕**。
- `lib/features/workspace/workspace_api.dart`：`WorkspaceApi` 接口（`fetchDirectory` / `uploadFile` / `downloadFile` / `deleteFile` / `renameFile`）+ 生产实现 `WorkspaceApiClient`（透传，绕开 `_asMap` 双层解析坑，符合 skill 记录的正确范式）。测试注入 `FakeWorkspaceApi`（`test/helpers/fake_workspace_api.dart`）。
- `lib/core/api/endpoints.dart` L298-347 已有 12 个 workspace 端点条目（`/api/workspaces` 家族 + `directoryList`/`rawFile`/`media`）。
- 上传现状：走 `/api/upload`（聊天附件同款）；**建议新增 `/api/workspace/upload` 封装**（`path` 字段 + 多文件 + 归档语义）。

### 4.3 UI 层（现状 = 只有文件浏览页）

- `lib/features/workspace/workspace_page.dart`（885 行）：会话文件浏览页 —— 面包屑头 + 下拉刷新 + 列表（目录行进入、文件行弹操作菜单：下载/重命名/删除）+ 上传入口（filePicker 未注入时提示平台通道后置）+ 加载/错误/空态三态；`formatWorkspaceFileSize` / `formatWorkspaceModifiedTime` 工具已在（`modified` 因后端键名填不上，见 4.1）。
- `lib/features/workspace/workspace_providers.dart`（471 行）：`WorkspaceController`（family by sessionId，AsyncNotifier）—— `refresh`/`navigateTo`/`navigateUp`/`navigateToRoot`/`retryLastLoad`/`uploadFile`/`download`/`delete`/`rename` + `clearActionError`/`clearNotice`；`WorkspaceState`（entries/currentPath/isRefreshing/isUploading/busyPaths/actionError/notice）+ `breadcrumbs`/`parentPath`/`displayPath` 派生。**状态机成熟，工作区管理页可直接复用其「AsyncData 携带 actionError/notice」模式**。
- 测试：`test/features/workspace/workspace_page_test.dart`、`workspace_controller_test.dart`、`test/core/models/workspace_test.dart`、golden `workspace_light/dark` 均已存在。
- **缺口清单**（本次要补的）：
  1. 工作区**列表/管理页**（注册表 CRUD UI）——完全不存在；
  2. 新建/重命名**弹窗**（带 suggest 补全）——不存在；
  3. 文件**内容/预览页**（调 `/api/file` 与 `/api/file/raw` 展示文本/图片/媒体）——未接入 UI（`file()` 方法已封装）；
  4. 下载落盘（平台通道后置，当前只提示字节数）——规格里给出方案选项；
  5. 「激活工作区」入口（切会话 workspace）——依赖会话域，建议独立小任务。

---

## 5. 建议的新数据模型（字段名 + JSON 键名）

> 命名约定：Dart 字段 camelCase，JSON 键 snake_case（线上键名一律蛇形，`api_spec.md` L407）。全部手写 `fromJson` 容错解码（安全默认值）。

```dart
// lib/core/models/workspace.dart 增量修改（不改破坏性字段）

/// GET /api/workspaces 信封：补 terminal_remote_backend。
class WorkspacesResponse {
  // ...现有 workspaces / last ...
  final bool? terminalRemoteBackend; // json: 'terminal_remote_backend'
  // fromJson 增加 optBool(json, 'terminal_remote_backend')
}

/// 目录条目：对齐服务器真实键名（mtime_ns 纳秒；symlink 字段）。
class WorkspaceEntry {
  // ...现有 name/path/type/size ...
  final int? mtimeNs;        // json: 'mtime_ns'  ← 替换 modified(double) 的使用
                              //   （保留 modified 字段避免破坏现有引用？建议直接新增 mtimeNs，
                              //    UI 层 formatWorkspaceModifiedTime 改收纳秒）
  final bool? isDir;         // json: 'is_dir'（仅 symlink 出现；与现有 'is_directory' 都容忍）
  final String? target;      // json: 'target'（symlink 解析目标绝对路径）
  final bool? targetOutsideWorkspace; // json: 'target_outside_workspace'
  // isBrowsableDirectory 增强：targetOutsideWorkspace==true 视为不可浏览；
  // 展示 helper: isSymlink => type=='symlink'
}

/// GET /api/list 信封：补 signature。
class DirectoryListResponse {
  // ...现有 entries/path/workspace/error ...
  final String? signature;   // json: 'signature'（sha256 hex，缓存失效用）
}

/// GET /api/file 文本响应：补 office 预览字段与 binary 标记。
class FileResponse {
  // ...现有 content/path/name/language/size/lines/error ...
  final String? previewKind;        // json: 'preview_kind'（office 时为 'office'）
  final String? officeFormat;       // json: 'office_format'（docx/xlsx/pptx）
  final String? renderMode;         // json: 'render_mode'
  final bool? editable;             // json: 'editable'
  final bool? truncated;            // json: 'truncated'
  final bool? isBinary;             // json: 'binary'（前端防御性检查，服务器常规不发）
}

/// 新增：POST /api/workspace/upload 响应（单文件对象）。
class WorkspaceUploadEntry {
  final String? filename;    // json: 'filename'
  final String? path;        // json: 'path'（绝对路径）
  final int? size;           // json: 'size'
  final String? mime;        // json: 'mime'
  final bool? isImage;       // json: 'is_image'
  final bool? extracted;     // json: 'extracted'（true = 归档已自动解压）
  final List<String>? extractedFiles; // json: 'extracted_files'
  final int? extractedCount; // json: 'extracted_count'
  final String? extractError;// json: 'extract_error'
  final Map<String, Object?>? sidecar; // json: 'sidecar'
}

/// 新增：POST /api/workspace/upload 信封（多文件时）。
class WorkspaceUploadListResponse {
  final List<WorkspaceUploadEntry>? files; // json: 'files'
  final int? count;                        // json: 'count'
  // fromJson：对象 → 单元素列表；{files,count} → 列表
}
```

新增「工作区管理器」状态（`lib/features/workspace_manager/workspace_manager_providers.dart`，新 feature 目录）：

```dart
/// 工作区注册表状态（与文件浏览 WorkspaceState 分离）。
class WorkspaceManagerState {
  final List<WorkspaceRoot> workspaces;  // 服务端顺序
  final String? last;                    // 上次激活工作区（json 'last'）
  final bool isLoading;
  final bool isMutating;                 // 任一 mutation 在途（防并发竞态，对齐 Swift isMutating）
  final String? actionError;             // 行操作错误（UI 弹窗后 clear）
  final String? notice;                  // 成功提示
}

final workspaceManagerControllerProvider =
    AsyncNotifierProvider<WorkspaceManagerController, WorkspaceManagerState>(
      WorkspaceManagerController.new);

class WorkspaceManagerController extends AsyncNotifier<WorkspaceManagerState> {
  // build(): GET /api/workspaces
  // addWorkspace({path, name?, create?})   → POST /api/workspaces/add
  // renameWorkspace({path, name})          → POST /api/workspaces/rename
  // removeWorkspace(path)                  → POST /api/workspaces/remove
  // reorderWorkspaces(paths)               → POST /api/workspaces/reorder
  // loadSuggestions(prefix)                → GET /api/workspaces/suggest（新建弹窗内防抖调用）
  // 每次 mutation 成功后用响应里的 workspaces 直接替换本地列表（省一次 GET）
}
```

---

## 6. 端点表（对齐 `lib/core/api/endpoints.dart` 风格）

### 6.1 已存在（零改动，第 4.2 节引用）

`workspaces` / `workspaceSuggestions(prefix)` / `workspaceAdd` / `workspaceRemove` / `workspaceRename` / `workspaceReorder` / `directoryList(sessionId, path?)` / `file(sessionId, path)` / `rawFile(sessionId, path)` / `media(sessionId, path)` / `fileDelete` / `fileRename`。

### 6.2 建议新增（加到 `1.7 workspace` 段，保持同风格）

```dart
// 1.7 workspace — 新增
/// GET /api/workspace/upload（multipart：session_id + path? + file*）。
/// 用 Endpoint('/api/workspace/upload')；multipart 不走 sendJson，
/// 在 ApiClient 上新增 sendForm 系列（参照 api_client_upload.dart 现有做法）。
static const workspaceUpload = Endpoint('/api/workspace/upload');

/// POST /api/file/create {session_id, path, content?} → {ok, path}。
static const fileCreate = Endpoint('/api/file/create');

/// POST /api/file/create-dir {session_id, path} → {ok, path}。
static const fileCreateDir = Endpoint('/api/file/create-dir');

/// POST /api/file/move {session_id, path, dest_dir} → {ok, old_path, new_path}。
static const fileMove = Endpoint('/api/file/move');

/// POST /api/file/save {session_id, path, content} → {ok, path, size}。
static const fileSave = Endpoint('/api/file/save');

/// POST /api/file/office-save（.docx/.xlsx/.pptx 专用）。
static const fileOfficeSave = Endpoint('/api/file/office-save');

/// GET /api/folder/download?session_id=&path=（目录 zip 下载；可选）。
static Endpoint folderDownload({required String sessionId, String? path}) =>
    Endpoint('/api/folder/download',
        query: [QueryParam('session_id', sessionId), if (path != null) QueryParam('path', path)]);

/// POST /api/file/path {session_id, path} → {ok, path: 绝对路径}（复制路径；可选）。
static const filePath = Endpoint('/api/file/path');
```

对应 `ApiClientWorkspace` 扩展追加方法：`workspaceUpload(...)`（multipart + 结果双形状解码）、`createFile` / `createDir` / `moveFile`（`WorkspaceMutationResponse` 风格或专用小模型）、`saveFile`（可选）。

---

## 7. Cupertino 页面结构建议

### 7.1 工作区列表页 `WorkspaceManagerPage`（新，入口放设置页或侧栏）

```
CupertinoPageScaffold
└─ CupertinoNavigationBar（大标题「工作区」；trailing：+ 新建按钮）
└─ 状态三态（加载 CupertinoActivityIndicator / 错误态（statusRedText 细节 + 重试）/
    空态「还没有工作区，点右上角 + 添加」）
└─ CupertinoListSection（分组列表）
   └─ 每行 CupertinoListTile：
        标题 = name ?? path 末段（粗体，label）
        副行 = path（secondaryText，2 行截断）
        trailing = 当前激活标记（last == path 时显示「当前」徽标）
   └─ footer: 「移除工作区只是从列表注销路径，不会删除磁盘上的文件。」
```

- **交互**：
  - 行长按 → `CupertinoContextMenu`：`重命名` / `移除`（红色 statusRedText）；Cupertino 无系统自带滑动操作，长按菜单是最贴近 iOS 的免费方案（也匹配 WebUI 右键语义）。
  - 排序：Cupertino 无原生 ReorderableListView；方案 A（推荐，最轻）行内「上移/下移」按钮（对齐 web 拖拽的等价能力）；方案 B 用 `ReorderableListView`（Material 组件，违反「禁止 Material 混入业务 UI」约定，不推荐）。**建议明确不做拖拽排序（Android/Windows 优先平台下拖拽成本高），reorder 端点留接口即可**。
  - `+ 新建` → 弹层（见 7.3）。
- **状态管理**：`WorkspaceManagerController`（§5），mutation 在途 `isMutating=true` 禁用列表操作（防竞态，对齐 Swift `moveDisabled/deleteDisabled`）。

### 7.2 文件浏览 / 预览 / 下载页（扩展现有 `workspace_page.dart`）

现状已具备目录浏览 + 行操作（下载/重命名/删除）三态与面包屑。**本批补两块**：

1. **文件预览页 `FilePreviewPage`**（push 进入，参数 `{sessionId, entry}`）：
   - 文本（`.txt/.md/.dart/.json/...`）：`GET /api/file` → `CupertinoPageScaffold` + `SelectableText.rich`（monospace）或 `flutter_markdown`（`.md`，沿用 chat 的 MiSans theme 化样式 `MarkdownStyleSheet.fromCupertinoTheme`），内容超长自然滚动；顶部栏显示 `path` + 大小/行数。
   - 图片：`GET /api/file/raw` → `Image.memory(bytes)`（Cupertino 无自带 viewer；尺寸自适应 + 点击全屏 `InteractiveViewer`）。
   - 音视频/PDF：`GET /api/file/raw` → 平台播放器/`pdf` 包预览（可选后置）。
   - 下载按钮（导航栏 trailing）：调 `rawFileData` → 平台通道完成落盘（见 7.4）；Windows 优先平台可先用「保存对话框」或直接写下载目录。
   - 文件类型判定：按扩展名白名单（镜像 WebUI `IMAGE_EXTS/AUDIO_EXTS/VIDEO_EXTS/PDF_EXTS/MD_EXTS/DOWNLOAD_EXTS`，`workspace.js:811-820`）；黑名单（zip 等）不预览，点击直接触发下载。
2. **上传改造**：`uploadFile` 从 `/api/upload` 迁移到 `/api/workspace/upload`（带当前目录 `path`），响应兼容双形状（§5 `WorkspaceUploadEntry`）；归档解压/去重行为直接获得。

### 7.3 新建 / 重命名弹窗

- **重命名**：`CupertinoAlertDialog` + `CupertinoTextField`（预填当前 name；对齐 iOS 习惯**选中主干保留扩展名**——需要在 `initState` 里对 TextEditingController 设置 selection）。「保存/取消」两键；保存中 `isMutating` 禁用。
- **新建（Add Workspace）**：推荐 `showCupertinoModalPopup` 全高 sheet（可键盘避让）：
  - `CupertinoTextField` 路径（必填，`autocapitalization: none`，`autocorrect: false`——对齐 Swift `textInputAutocapitalization(.never)` + WebUI `autocomplete="off"`）；
  - `CupertinoTextField` 名称（可选）；
  - `CupertinoSwitch` 「目录不存在时自动创建」（`create: true`）；
  - 路径输入 250ms 防抖 → `workspaceSuggestions(prefix)` → 内联 `CupertinoListSection` 建议列表（点击填入）；
  - 底部「添加」按钮，path 空白时禁用；错误（400/403 消息）以 statusRedText 内联展示（不弹窗打断）。
- 两端点表单都**不做**「编辑 path」能力（对齐 WebUI 只读 hint）。

### 7.4 下载落盘方案（平台通道后置，规格只给方向）

优先平台 Windows/Android：`file_picker` 或 `path_provider` + 自写 `Uint8List` 到「下载目录」；Android 需 SAF；`WorkspaceFilePicker` 已有注入位（`workspace_page.dart:16-24`）可同构扩展 `WorkspaceFileSaver` 回调接口，测试注入 fake。

---

## 8. 容错点（实现时对照）

1. **path 语义分离**：`/api/workspaces` 的 `path` = 磁盘绝对路径（Windows 反斜杠）；`/api/list`、`/api/file*`、`/api/workspace/upload` 的 `path` = 工作区相对路径（`/` 分隔，`.`=根）。**绝对路径绝不能当作相对 path 传给文件端点**（会 400 `Path traversal blocked` 或 404）。
2. **服务器 503 裸响应**：worker 池满载时任何端点返回空 body 503（`server.py:124-129`）——`ApiClient` 需把「非 2xx 且无 JSON body 的 503」识别为可重试（区别于 `{"error":...}` 的 503，如 updates/office 依赖缺失）。建议指数退避重试 1-2 次后再抛给 UI。
3. **`mtime_ns` 键名/单位**：服务器发纳秒 int；现状 `modified`(double 秒) 永远解析不到 → 列表副行时间显示「—」。新增 `mtimeNs` 字段并按纳秒格式化（`formatWorkspaceModifiedTime` 收 int 纳秒）。
4. **symlink 条目**：`type=='symlink'` 且 `target_outside_workspace==true` 时**只读**（不提供重命名/删除/移动/上传目标，预览只读版本放行——对齐 WebUI `isReadOnlyEscape`）；`isBrowsableDirectory` 必须把外部 symlink 判为不可进入。
5. **删除目录必须 `recursive: true`**；否则 400。工作中状态机已处理（`entry.isDirectory ?? false`），工作区管理涉及文件删除时同样注意。
6. **Office/大文件**：`/api/file` 对 >MAX 文件、office 缺依赖返回 400/503；预览页对 `error` 字段要给出「改用下载」兜底（镜像 WebUI：二进制/失败 → 下载）。
7. **并发 mutation**：注册表 4 个 mutation 都可能被快速连点；`isMutating` 期间禁用所有列表操作（Swift/WebUI 同款），memory + server 无并发保护。
8. **401 自动重登**：工作区页 401 时沿用现有 auto-reauth 机制；重登失败再展示错误（链接 `auto_reauth_spec.md`）。
9. **空工作区列表**：服务器冷启动无文件时返回单条 `Home`（`workspace.py:351/367`），不要依赖「至少一条」假设，UI 仍要支持空态。
10. **`last` 为空**：`last` 可能空串（无会话激活过）；激活徽标判断用 `last != null && last == path`。
11. **Windows 路径大小写/反斜杠**：`/api/workspaces` 对比（remove/rename/reorder 的 path 匹配）是**字面字符串相等**，客户端必须原样回传服务器给的 `path`，不要规范化。

---

## 9. 证据附录

### 9.1 curl 实测摘录（2026-08-21，:30002，登录态 cookie）

```
$ curl -s http://localhost:30002/api/auth/status
{"auth_enabled": true, "logged_in": false, "oidc_enabled": false,
 "password_auth_enabled": true, "passwordless_enabled": false,
 "passkeys_enabled": false, "passkeys_count": 0, ...}

$ curl -s http://localhost:30002/api/workspaces            # 无 cookie
{"error":"Authentication required"}

$ curl -s -b "hermes_session=<valid cookie>" http://localhost:30002/api/workspaces
{"workspaces":[
  {"path":"C:\\Users\\Admin\\workspace","name":"Home"},
  {"path":"D:\\projects\\末世生存小队","name":"末世生存小队"},
  {"path":"D:\\projects\\hermex-flutter","name":"HERMEX"}, …共 9 项],
 "last":"D:\\projects\\hermex-flutter","terminal_remote_backend":false}

$ curl -s -b "hermes_session=<valid cookie>" "http://localhost:30002/api/sessions"
（会话列表，含 session_id/title/workspace；首条 workspace = "D:\\projects\\hermex-flutter"）

# 文件浏览三端点（服务器恢复后补测，均为 200）
$ curl -s -b cookie "http://localhost:30002/api/list?session_id=<webui会话>&path=."
→ {"entries":[{"name":".dart_tool","path":".dart_tool","type":"dir","size":null,"mtime_ns":1787179911828507100},…共32条],
   "path":".","signature":"567213e156933a5e704208427bc7681f..."}

$ curl -s -b cookie "http://localhost:30002/api/file?session_id=<webui会话>&path=pubspec.yaml"
→ {"content":"name: hermex_flutter\\r\\n…","lines":105,"path":"pubspec.yaml","size":4011}

$ curl -s -b cookie -D - -o /dev/null "http://localhost:30002/api/file/raw?session_id=<webui会话>&path=pubspec.yaml"
→ HTTP/1.1 200 · Content-Type: application/octet-stream · Content-Disposition: inline; filename="pubspec.yaml" · 4011 字节
```

> 注：本机服务器在探测期间 worker 池曾长期满载（连 `/health` 都返回裸 503，`server.py:124-129` 溢出响应）；恢复后上述文件三端点已补测到 200 实测体，与源码形状逐一印证（`workspace.py:1234-1336/1458-1479` + `routes.py:16795-16828/19203-19220/19163-19200`）。

### 9.2 后端源码引用清单（D:/hermes-webui）

| 文件:行 | 内容 |
|---|---|
| `api/routes.py:13123-13131` | GET /api/workspaces 响应组装（workspaces/last/terminal_remote_backend） |
| `api/routes.py:13133-13142` | GET /api/workspaces/suggest（{suggestions, prefix}） |
| `api/routes.py:13147-13148`、`16795-16828` | GET /api/list 分发与处理（entries/signature/path；session_id 必填、path 默认 `.`） |
| `api/routes.py:13315-13316`、`19163-19200` | GET /api/file/raw（download=1 / inline=1；危险 MIME 强制附件） |
| `api/routes.py:13324-13325`、`19203-19220` | GET /api/file（文本内容） |
| `api/routes.py:13321-13322`、`19066-19160` | GET /api/folder/download（zip 流；413 预检） |
| `api/routes.py:15298-15326` | POST 文件操作分发 |
| `api/routes.py:15329-15339` | POST 工作区注册表分发 |
| `api/routes.py:23067-23096` | POST /api/file/delete |
| `api/routes.py:23099-23127` | POST /api/file/save |
| `api/routes.py:23130-23162` | POST /api/file/office-save |
| `api/routes.py:23165-23189` | POST /api/file/create |
| `api/routes.py:23192-23224` | POST /api/file/rename |
| `api/routes.py:23227-23322` | POST /api/file/move |
| `api/routes.py:23325-23344` | POST /api/file/create-dir |
| `api/routes.py:23347-23392` | POST /api/file/reveal |
| `api/routes.py:23395-23421` | POST /api/file/path（绝对路径解析） |
| `api/routes.py:23424-23507` | POST /api/file/open-vscode |
| `api/routes.py:23510-23560` | POST /api/workspaces/add（引号剥除/create/去重） |
| `api/routes.py:23563-23570` | POST /api/workspaces/remove |
| `api/routes.py:23573-23586` | POST /api/workspaces/rename |
| `api/routes.py:23589-23614` | POST /api/workspaces/reorder |
| `api/workspace.py:337-373` | load_workspaces / save_workspaces（workspaces.json） |
| `api/workspace.py:415-431` | get_last_workspace（last_workspace.txt） |
| `api/workspace.py:695-807` | list_workspace_suggestions（可信根/`~`/12 条上限） |
| `api/workspace.py:903-941` | validate_workspace_to_add（只挡不存在/系统根） |
| `api/workspace.py:943-957` | safe_resolve_ws（路径穿越/符号链接逃逸封锁） |
| `api/workspace.py:1234-1336` | list_dir **entry 字段构造（name/path/type/size/mtime_ns + symlink 字段）** |
| `api/workspace.py:1433-1455` | dir_signature（SHA-256，纯元数据） |
| `api/workspace.py:1458-1479` | read_file_content（{path,content,size,lines}；office 分支） |
| `api/config.py:86-90` | WORKSPACES_FILE / LAST_WORKSPACE_FILE 常量 |
| `api/upload.py:206-241` | POST /api/upload（{filename,path,size,mime,is_image}） |
| `api/upload.py:592-767` | POST /api/workspace/upload（path 字段/多文件/去重/归档解压/双形状响应） |
| `api/office_documents.py:555-586` | preview_office_document（preview_kind/office_format/render_mode/editable/…） |
| `api/auth.py:61` | COOKIE_NAME = 'hermes_session' |
| `api/auth.py:579-632` | create_session（token.sig 签名 cookie）/ verify_session |
| `server.py:124-129` | worker 溢出 503 裸响应（连接关闭、空 body） |
| `server.py:382,410` | GET/POST 统一 check_auth 门卫 |
| `static/panels.js:5672-5681, 6121-6236` | WebUI 注册表：列表/删除/新建/编辑表单与建议 |
| `static/workspace.js:1070-1212, 1313-1347` | WebUI 预览路由 / 下载 / 上传（/api/workspace/upload） |
| `static/ui.js:19600-20049` | WebUI 文件右键菜单（重命名/删除/新建/移动等） |

### 9.3 参考

- `docs/specs/api_spec.md` §1.7（既有 10 端点表）、§4（上传形状）、§2.4（path 编码规则）
- `.reference/hermex-src/Features/Workspace/WorkspaceManagerView.swift`（iOS 蓝本管理页/新建 sheet 结构）
- `.reference/hermex-src/Features/Workspace/WorkspaceRegistryViewModel.swift`（isMutating/竞态守卫语义）
- `docs/specs/auto_reauth_spec.md`（401 自动重登机制）
- skill `hermex-flutter-codebase` references/workspace-file-ops-2026-08.md（delete/rename 既有契约）