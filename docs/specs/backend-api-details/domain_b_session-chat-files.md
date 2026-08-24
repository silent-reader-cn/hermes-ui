# Hermes WebUI 后端接口大全 · 域 B（会话 / 聊天 / 流式 / 终端 / 媒体）

> **说明**：本手册为 Hermes WebUI 后端接口规范文档「域 B：会话、聊天、流式传输、终端与媒体文件管理」。
> **唯一权威代码源**：`/d/hermes-webui/api/routes.py`（26554 行），所有路径、方法、参数、响应模式、状态码、权限控制与行号均经过源码严格核对。
> **全局认证机制说明**：
> 1. 当系统开启密码/OIDC认证时（`is_auth_enabled()` 为真），除公开白名单（如 `/login`、`/api/share/<token>` 等）外，所有 `/api/` 接口均强制校验 Cookie 会话凭证（401 Unauthorized）。
> 2. 所有 POST 请求（除部分豁免路径如 `/api/csp-report`、`/api/process-complete-ack`）均强制校验 CSRF Token（403 Forbidden）。
> 3. 多 Profile 隔离机制：接口通过 `_session_visible_to_active_profile` 校验当前激活 Profile，跨 Profile 访问有效会话返回 409 Conflict（附带 Profile 信息），不可见或不存在会话返回 404 Not Found。
> 4. 子代理保护机制：`_session_is_subagent_view_only` 保护子代理会话为只读（400 Bad Request），禁止前端修改或删除。

---

## 目录
- [一、 会话核心与生命周期 (Session Core & Lifecycle)](#一-会话核心与生命周期-session-core--lifecycle)
- [二、 会话列表与越狱文件浏览 (Session List & Escape)](#二-会话列表与越狱文件浏览-session-list--escape)
- [三、 聊天与流式通信 (Chat & Streaming)](#三-聊天与流式通信-chat--streaming)
- [四、 审批与澄清交互 (Approval & Clarify)](#四-审批与澄清交互-approval--clarify)
- [五、 异步任务、目标模式与完成确认 (Btw / Background / Goal / Ack)](#五-异步任务目标模式与完成确认-btw--background--goal--ack)
- [六、 网页交互式终端 (Web PTY Terminal)](#六-网页交互式终端-web-pty-terminal)
- [七、 会话分享 (Session Share)](#七-会话分享-session-share)
- [八、 媒体、语音、文件与工作区上传 (Media / Voice / Files / Upload)](#八-媒体语音文件与工作区上传-media--voice--files--upload)
- [九、 域 B 关联流与运维端点 (Associated Events & Maintenance)](#九-域-b-关联流与运维端点-associated-events--maintenance)
- [十、 域 B 未分类/疑点清单与对接易错点](#十-域-b-未分类疑点清单与对接易错点)

---

# 一、 会话核心与生命周期 (Session Core & Lifecycle)

## GET /api/session  (routes.py:12464)
- **功能**：获取指定会话的完整详情或元数据，支持消息分页懒加载与多 Profile 访问控制。
- **参数**：
  - `session_id` (Query, string, 必填): 目标会话 ID。
  - `messages` (Query, string, 可选, 默认 "1"): 传 "0" 时仅加载元数据（用于侧边栏快速切换），传 "1" 加载消息数组。
  - `resolve_model` (Query, string, 可选): 是否解析兼容模型配置（默认当 messages=1 时为 "1"）。
  - `msg_limit` (Query, integer, 可选): 限制返回尾部可视消息条数（自动限制在服务端最大阈值内）。
  - `msg_before` (Query, integer, 可选): 0-based 消息数组索引，用于向上滚动懒加载历史消息。
  - `expand_renderable` (Query, boolean, 可选): 兼容旧版前端的分页渲染参数。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session": {
        "session_id": "c7a8b9e1f2",
        "title": "React 状态管理重构",
        "workspace": "/home/user/project",
        "model": "claude-3-7-sonnet",
        "model_provider": "anthropic",
        "profile": "default",
        "project_id": "proj_123",
        "pinned": false,
        "archived": false,
        "created_at": 1740000000.0,
        "updated_at": 1740001000.0,
        "messages": [
          { "role": "user", "content": "hello", "timestamp": 1740000001.0 },
          { "role": "assistant", "content": "Hi!", "timestamp": 1740000002.0 }
        ],
        "worktree_path": null,
        "enabled_toolsets": ["core", "web"],
        "todo_state": {}
      }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Session belongs to a different profile", "code": "session_profile_mismatch", "session_id": "...", "profile": "..."}`
- **认证**：启用认证时需 Cookie 会话；校验 Profile 隔离权限。
- **备注**：加载时会自动清理过期的活动流标记（`_clear_stale_stream_state`）；自动挂载 `todo_state`，并对敏感字段进行脱敏（`redact_session_data`）。

---

## GET /api/session/status  (routes.py:12987)
- **功能**：轻量级轮询查询会话状态（流运行状态、消息数、模型等），不拉取完整消息列表。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session_id": "c7a8b9e1f2",
      "active_stream_id": null,
      "streaming": false,
      "message_count": 12,
      "model": "claude-3-7-sonnet",
      "model_provider": "anthropic",
      "title": "React 状态管理重构",
      "pinned": false,
      "archived": false,
      "updated_at": 1740001000.0
    }
    ```
  - `400 Bad Request`: `{"error": "Missing session_id"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；基于 `metadata_only=True` 快速读取。
- **备注**：读取前自动清理僵尸流状态；常用于前端 Tab 标签与状态栏指示器。

---

## POST /api/session/new  (routes.py:14097)
- **功能**：创建全新会话，可配置工作区、隔离 Worktree、模型提供商、Profile 及启用的工具集，并支持异步触发上一会话的记忆归档。
- **参数** (JSON Body):
  - `workspace` (string, 可选): 工作区绝对路径，缺省时使用最近受信任工作区。
  - `model` (string, 可选): 使用的模型名称。
  - `model_provider` (string, 可选): 模型供应商标识。
  - `profile` (string, 可选): 绑定 Profile 名称。
  - `project_id` (string, 可选): 归属项目 ID。
  - `worktree` (boolean | string | null, 可选): 是否开启 Git Worktree 隔离。显式传参优先级高于配置项。
  - `enabled_toolsets` (list[string], 可选): 启用的工具集列表。
  - `prev_session_id` (string, 可选): 前一个会话 ID；传入时会在后台线程异步提交其记忆（`commit_session_memory`），不阻塞本接口响应。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session": {
        "session_id": "a1b2c3d4e5f6",
        "title": "New Chat",
        "workspace": "/home/user/project",
        "model": "claude-3-7-sonnet",
        "model_provider": "anthropic",
        "profile": "default",
        "messages": [],
        "created_at": 1740002000.0
      },
      "worktree_skipped": null
    }
    ```
  - `400 Bad Request`: `{"error": "Invalid workspace / toolset shape"}`
  - `500 Internal Server Error`: `{"error": "Failed to create worktree: ..."}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若 Worktree 请求因非 Git 目录被跳过，响应中将包含 `worktree_skipped` 字符串；创建成功后触发 `session_new` 事件广播。

---

## POST /api/session/duplicate  (routes.py:14233)
- **功能**：复制现有会话创建分支副本，完整继承上下文、工具配置、人格设定与网关路由。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 源会话 ID。
  - `workspace` (string, 可选): 可重定向新副本的工作区。
  - `title` (string, 可选): 副本标题，缺省为 "Copy of <原标题>"。
  - `pinned` (boolean, 可选, 默认 false): 是否置顶。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session": {
        "session_id": "f6e5d4c3b2a1",
        "title": "Copy of React 状态管理重构",
        "parent_session_id": "c7a8b9e1f2",
        "session_source": "duplicate",
        "workspace": "/home/user/project",
        "messages": [...]
      }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}` 或 `{"error": "Subagent sessions are view-only and cannot be duplicated from WebUI"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：新副本会自动清除旧会话的 `active_stream_id` 与 `share_token`，避免状态污染。

---

## POST /api/session/rename  (routes.py:14453)
- **功能**：重命名会话标题，并锁定标题防止后续被大模型自动生成覆盖。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `title` (string, 必填): 新会话标题（非空字符串）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "title": "重构 Redux 到 Zustand 实战",
      "session": { "session_id": "c7a8b9e1f2", "title": "重构 Redux 到 Zustand 实战", "title_locked": true }
    }
    ```
  - `400 Bad Request`: `{"error": "title is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若重命名的是 CLI 导入会话，服务端会自动将其物化写入 WebUI Sidecar JSON 并锁定标题；触发 `session_rename` 广播。

---

## POST /api/session/delete  (routes.py:14744)
- **功能**：彻底删除会话及其关联的所有物理文件、索引、日志与运行态缓存。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "state_db_cleanup_failed": false,
      "worktree_retained": false
    }
    ```
  - `400 Bad Request`: `{"error": "Invalid session_id"}` 或只读/子代理会话拒绝。
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：清理链包括：WebUI JSON sidecar (`.json` 与 `.json.bak`)、附件目录 (`attachments/<sid>`)、轮次日志 (`turn_journal`)、运行日志 (`run_journal`)、Pty 终端进程、Agent 缓存实例与锁、后台任务去重条目、以及 CLI `state.db`。触发 `session_delete` 广播。

---

## POST /api/session/clear  (routes.py:14859)
- **功能**：清空会话的消息历史与上下文，但保留会话元数据（工作区、Profile、项目关联等）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `preserve_system` (boolean, 可选, 默认 false): 是否保留系统预设提示词。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "c7a8b9e1f2", "messages": [], "context_messages": [] }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：同步清空 `run_journal` 与 `turn_journal`；触发 `session_clear` 广播。

---

## POST /api/session/truncate  (routes.py:14951)
- **功能**：截断会话历史至指定消息索引（回退到历史某个节点），同步截断上下文消息。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `index` / `keep` (integer, 必填): 保留的消息条数或截止索引。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "truncated_to": 6,
      "session": { "session_id": "c7a8b9e1f2", "messages": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "index must be an integer >= 0"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：采用 `truncate_session_at_keep` 算法确保隐藏的工具调用结果与上下文对齐；更新截断水印 `truncation_watermark`。

---

## POST /api/session/branch  (routes.py:14994)
- **功能**：从指定会话的某一历史轮次分叉（Branch）出一个新的独立子会话。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 源会话 ID。
  - `index` / `keep` (integer, 可选): 分叉截止位置（保留前 N 条消息）。
  - `title` (string, 可选): 分支会话标题（缺省自动加 `(branch)` 后缀）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session_id": "e9d8c7b6a5",
      "title": "React 状态管理重构 (branch)",
      "parent_session_id": "c7a8b9e1f2"
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：新分支继承源会话的模型、工具集、网关路由配置，并将上下文安全截断至分叉点。

---

## POST /api/session/update  (routes.py:14670)
- **功能**：修改会话运行态配置（切换工作区、切换模型、调整上下文长度阈值、工具集、网关路由等）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `workspace` (string, 可选): 新工作区路径。
  - `model` (string, 可选): 新模型标识。
  - `model_provider` (string, 可选): 新供应商标识。
  - `personality` (string, 可选): 角色人格设定。
  - `enabled_toolsets` (list[string], 可选): 启用的工具集列表。
  - `context_length` (integer, 可选): 上下文窗口限制。
  - `threshold_tokens` (integer, 可选): 压缩触发 Token 阈值。
  - `gateway_routing` (dict, 可选): 网关多模型路由规则。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session": {
        "session_id": "c7a8b9e1f2",
        "workspace": "/new/path",
        "model": "claude-3-7-sonnet",
        "enabled_toolsets": ["core", "terminal"]
      }
    }
    ```
  - `400 Bad Request`: `{"error": "Invalid workspace / toolset shape"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若修改了工作区，服务端会自动关闭旧工作区的关联 Web Terminal；若运行时配置改变，会自动驱逐内存中的 Cached Agent 实例。

---

## POST /api/session/pin  (routes.py:15749)
- **功能**：置顶或取消置顶会话（受最大置顶数量配额限制，并发安全）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `pinned` (boolean, 可选, 默认 true): 是否置顶。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "c7a8b9e1f2", "pinned": true }
    }
    ```
  - `400 Bad Request`: `{"error": "Maximum pinned sessions reached"}` 或子代理会话拒绝。
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：置顶配额在锁内进行原子校验（防止 TOCTOU 竞争）；支持自动物化 CLI 会话；触发 `session_pin` 广播。

---

## POST /api/session/archive  (routes.py:15821)
- **功能**：归档或取消归档会话。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `archived` (boolean, 可选, 默认 true): 是否归档。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "c7a8b9e1f2", "archived": true },
      "worktree_retained": false
    }
    ```
  - `400 Bad Request`: `{"error": "Subagent sessions are view-only"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：针对仅含元数据的存根会先从磁盘升级为完整加载再执行归档，确保消息列表不被覆写为空；触发 `session_archive` 广播。

---

## POST /api/session/move  (routes.py:15911)
- **功能**：将会话移动/关联到指定的项目（Project）或移出项目。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `project_id` (string | null, 可选): 目标项目 ID，传 null 或空表示移出项目。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "c7a8b9e1f2", "project_id": "proj_abc" }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `403 Forbidden`: `{"error": "Read-only imported sessions cannot be moved from WebUI"}`
  - `404 Not Found`: `{"error": "Project not found"}` (项目不存在或跨 Profile 不匹配)
  - `503 Service Unavailable`: `{"error": "Session lock timeout, please retry"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：采用 5 秒超时有界锁获取（防止慢磁盘 I/O 阻塞请求）；严格校验目标项目与会话本身的 Profile 所属一致性。

---

## POST /api/session/undo  (routes.py:15135)
- **功能**：撤销（Undo）最近一轮对话（移除最后一条 Assistant 回复及对应的 User 提问）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "undone_count": 2,
      "remaining_messages": 8
    }
    ```
  - `400 Bad Request`: `{"error": "Subagent sessions are view-only"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `api.session_ops.undo_last` 实现。

---

## POST /api/session/retry  (routes.py:15119)
- **功能**：重试（Retry）最后一轮对话（清除最后的 Assistant 回复，保留最后的 User 输入以便重新触发生成）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "last_user_message": "请优化这段代码的性能",
      "workspace": "/home/user/project"
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `api.session_ops.retry_last` 实现。

---

## GET /api/session/yolo  (routes.py:12998)
- **功能**：查询指定会话当前是否开启了 YOLO 自动审批免确认模式。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "yolo_enabled": true
    }
    ```
  - `400 Bad Request`: `{"error": "Missing session_id"}`
- **认证**：需要登录认证。
- **备注**：YOLO 模式状态保存在服务端内存中，会话隔离，页面刷新不丢失，服务端重启重置。

---

## POST /api/session/yolo  (routes.py:15159)
- **功能**：开启或关闭指定会话的 YOLO 自动审批免确认模式。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `enabled` (boolean, 可选, 默认 true): 是否开启 YOLO。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "yolo_enabled": true
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：开启时会自动清除并全量放行当前会话排队中的所有待审批工具卡片（`tools.approval._pending` 与 Gateway pending queue）。

---

## GET /api/session/stream  (routes.py:13348)
- **功能**：订阅会话级别的全生命周期事件流（SSE），接收会话内的轮次变更、快照和运行状态。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `replay` (Query, string, 可选): 传 "1" 时回放近期日志事件。
- **响应**：
  - `200 OK` (`text/event-stream; charset=utf-8`):
    - 事件列表：`snapshot`、`turn_start`、`turn_end`、`message`、`status`、`done`、`error`。
    - 心跳注释：`: keepalive

`（每 5 秒一次）。
  - `400 Bad Request`: `{"error": "session_id required"}`
- **认证**：需要登录认证；校验会话 Profile 可见性。
- **备注**：设置了防慢连接阻塞的写超时（`_sse_set_write_deadline`）。

---

## POST /api/session/import  (routes.py:16097)
- **功能**：从导出的 JSON 数据结构全量导入创建全新会话（分配新 UUID）。
- **参数** (JSON Body):
  - `messages` (list[dict], 必填): 消息数组。
  - `title` (string, 可选, 默认 "Imported session"): 会话标题。
  - `workspace` (string, 可选): 绑定工作区。
  - `model` (string, 可选): 模型名称。
  - `tool_calls` (list, 可选): 历史工具调用记录。
  - `pinned` (boolean, 可选, 默认 false): 是否置顶。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "b8a9c0d1e2", "title": "Imported session", "messages": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "JSON must contain a "messages" array"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：导入后绑定为当前激活 Profile；触发 `session_import` 广播。

---

## POST /api/session/import_cli  (routes.py:16244)
- **功能**：将 Hermes Agent CLI 在 `state.db` 中的原生会话导入或刷新同步至 WebUI。
- **参数** (JSON Body):
  - `session_id` (string, 必填): CLI 会话 ID。
  - `profile` (string, 可选): 目标 Profile。
  - `all_profiles` (boolean, 可选): 是否允许跨 Profile 导入。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "cli_12345", "is_cli_session": true, "messages": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}` 或禁止导入子代理。
  - `404 Not Found`: `{"error": "Session not found in CLI store"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：具备前缀匹配防丢保护（`_is_messages_refresh_prefix_match`）与工具元数据富化（`_is_cli_tool_metadata_enrichment`）。

---

## GET /api/session/export  (routes.py:13120)
- **功能**：导出指定会话的历史记录为 JSON、Markdown 或 Plain Text 格式。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `format` (Query, string, 可选, 默认 "json"): 导出格式，可选 "json" | "markdown" | "md" | "text" | "txt"。
  - `download` (Query, string, 可选): 传 "1" 时添加 `Content-Disposition: attachment` 强制浏览器下载。
- **响应**：
  - `200 OK`: JSON 结构体（当 format=json）或 Markdown/Text 纯文本内容。
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；校验 Profile 权限。
- **备注**：Markdown 格式会自动排版工具调用过程、代码块与思考过程。

---

## POST /api/session/title/regenerate  (routes.py:14477)
- **功能**：基于首轮或最新对话内容，触发 LLM（优先使用轻量 Auxiliary 辅助模型）重新生成会话标题。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `force` (boolean, 可选, 默认 false): 是否强制覆盖已锁定的手动标题。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "title": "Flutter 路由状态管理方案探讨",
      "generated": true
    }
    ```
  - `400 Bad Request`: `{"error": "Subagent sessions are view-only"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Title generation already in progress"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：内置语言检测，自动匹配对话主要语言；生成失败时自动降级到规则抽取标题。

---

## POST /api/session/toolsets  (routes.py:14549)
- **功能**：动态配置当前会话允许调用的工具集（Toolsets）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `enabled_toolsets` (list[string], 必填): 工具集名称列表，如 `["core", "git", "web", "terminal"]`。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "enabled_toolsets": ["core", "git", "web"],
      "session": { "session_id": "c7a8b9e1f2", "enabled_toolsets": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "enabled_toolsets must be a list of strings"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：修改后自动驱逐该会话的 Cached Agent，使新工具清单在下一轮对话立即生效。

---

## POST /api/session/draft  (routes.py:14576)
- **功能**：保存或读取输入框的草稿内容（支持文字与待上传文件列表），实现草稿跨会话切换防丢失。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `text` (string, 可选): 草稿文字内容。
  - `files` (list[dict], 可选): 附加的文件引用列表。
  - `clear` (boolean, 可选, 默认 false): 是否清空草稿。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "draft": { "text": "请帮我写一个快速排序", "files": [] }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：草稿持久化在会话 Sidecar JSON 中（`composer_draft` 字段）。

---

## POST /api/session/anchor-scene  (routes.py:14450)
- **功能**：将会话与特定的 UI 视觉场景或视图锚点状态进行绑定持久化。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `anchor_scene` (dict, 必填): 场景锚点元数据（包含 scene_id, view_state 等）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "anchor_scene": { "scene_id": "main_editor", "zoom": 1.0 }
    }
    ```
  - `400 Bad Request`: `{"error": "anchor_scene is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_session_anchor_scene` 处理。

---

## POST /api/session/conversation-rounds  (routes.py:15113)
- **功能**：结构化解析会话的所有对话轮次（Rounds），按 User -> Tool -> Assistant 聚合各轮的 Token 统计与工具调用概览。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "rounds": [
        {
          "round_index": 0,
          "user_message": { "content": "帮我查看当前分支", "timestamp": 1740000000.0 },
          "assistant_messages": [{ "content": "当前在 master 分支", "timestamp": 1740000005.0 }],
          "tools_used": ["git_status"],
          "tool_count": 1
        }
      ]
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：用于前端大纲导航视图（Outline / Timeline View）。

---

## POST /api/session/handoff-summary  (routes.py:15116)
- **功能**：生成或存储跨 Agent / 跨会话的上下文交接摘要（Handoff Summary）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `summary` (string, 可选): 手动指定的交接摘要。
  - `generate` (boolean, 可选, 默认 false): 是否由 LLM 自动提取摘要。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "summary": "用户已完成鉴权模块重构，待进行单元测试验证。",
      "generated": true
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_handoff_summary` 处理。

---

## GET /api/session/usage  (routes.py:13004)
- **功能**：汇总统计该会话的 Token 消耗总量、模型拆分分布及预估费用。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "session_id": "c7a8b9e1f2",
      "prompt_tokens": 45200,
      "completion_tokens": 3800,
      "total_tokens": 49000,
      "estimated_cost": 0.185,
      "model_breakdown": {
        "claude-3-7-sonnet": { "prompt": 45200, "completion": 3800 }
      }
    }
    ```
  - `400 Bad Request`: `{"error": "Missing session_id"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证。
- **备注**：由 `api.session_ops.session_usage` 聚合计算。

---

## GET /api/session/lineage/report  (routes.py:12974)
- **功能**：查询会话的血缘关系树报告（从哪个父会话 Branch / Fork / 压缩续写而来）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "found": true,
      "session_id": "c7a8b9e1f2",
      "root_session_id": "root_112233",
      "parent_session_id": "parent_445566",
      "session_source": "fork",
      "lineage_depth": 2,
      "ancestors": ["root_112233", "parent_445566"]
    }
    ```
  - `400 Bad Request`: `{"error": "session_id required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证。
- **备注**：从激活的 `state.db` 中读取会话血缘树结构。

---

## GET /api/session/recovery/audit  (routes.py:12983)
- **功能**：全盘审计会话恢复状态，扫描磁盘未编目会话、孤儿文件及损坏记录。
- **参数**：无
- **响应**：
  - `200 OK`:
    ```json
    {
      "scanned_sessions": 150,
      "corrupted_sessions": [],
      "unindexed_sessions": ["sess_legacy_01"],
      "recovery_recommended": true
    }
    ```
- **认证**：需要登录认证。
- **备注**：调用 `api.session_recovery.audit_session_recovery` 实现。

---

## POST /api/session/recovery/repair-safe  (routes.py:13974)
- **功能**：安全执行会话索引修复与元数据重建（不删除用户消息历史）。
- **参数** (JSON Body):
  - `dry_run` (boolean, 可选, 默认 true): 是否仅演练不落盘。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "repaired_count": 3,
      "repaired_sessions": ["sess_legacy_01"],
      "dry_run": false
    }
    ```
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `api.session_recovery` 修复丢失的索引条目与损坏的 Sidecar 备份。

---

## POST /api/session/compress  (routes.py:15110)
- **功能**：同步压缩会话上下文，对历史长消息与冗余工具输出进行摘要修剪。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `focus_topic` (string, 可选): 压缩时重点保留的主题。
  - `summary` (string, 可选): 自定义替换摘要。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "summary": "【前文摘要】用户重构了鉴权中间件...",
      "compressed_messages_count": 24,
      "session": { "session_id": "c7a8b9e1f2", "messages": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Session is still streaming"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：在上下文首部插入压缩摘要锚点消息，并安全裁剪已压缩轮次的详细工具输出。

---

## POST /api/session/compress/start  (routes.py:15107)
- **功能**：启动异步后台上下文压缩任务（避免大上下文压缩造成前端 HTTP 请求超时）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `focus_topic` (string, 可选): 重点关注主题（最多 500 字）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "status": "running",
      "session_id": "c7a8b9e1f2",
      "started_at": 1740003000.0
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Session is still streaming; wait for the current turn to finish."}` 或 `{"error": "...", "type": "agent_runtime_stale"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：启动名为 `manual-compress-<sid>` 的后台守护线程；前端通过 `/api/session/compress/status` 轮询进度。

---

## GET /api/session/compress/status  (routes.py:12459)
- **功能**：轮询异步上下文压缩任务的执行状态与结果。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "status": "done",
      "session_id": "c7a8b9e1f2",
      "summary": "【前文摘要】...",
      "error": null
    }
    ```
    （状态可能为 `"idle"` | `"running"` | `"done"` | `"error"`）
  - `400 Bad Request`: `{"error": "session_id is required"}`
- **认证**：需要登录认证。
- **备注**：压缩完成后结果保留 10 分钟 TTL，支持多 Tab 页面同时轮询而不丢失结果。

---

## POST /api/session/compression-recovery/start  (routes.py:14230)
- **功能**：当会话上下文严重超限耗尽时，启动聚焦延续恢复模式（创建一个干净上下文的聚焦子会话）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 源会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": {
        "session_id": "focus_998877",
        "title": "React 状态管理重构 (focused continuation)",
        "messages": []
      },
      "source_session_id": "c7a8b9e1f2",
      "recommended_recovery_action": "start_focused_continuation",
      "message": "Started a focused continuation. Describe the next narrow task to continue."
    }
    ```
  - `400 Bad Request`: `{"error": "Subagent sessions are view-only"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Session does not have a compression recovery action."}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：保留原工作区、模型和 Profile 配置，但清空模型上下文尾部，避免重放耗尽的历史状态。

---

## GET /api/session/worktree/status  (routes.py:12440)
- **功能**：查询当前会话绑定的 Git Worktree 隔离工作区状态。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "status": {
        "is_worktree": true,
        "path": "/home/user/project/.worktrees/sess_abc",
        "branch": "hermes/sess_abc",
        "repo_root": "/home/user/project",
        "clean": true
      }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `500 Internal Server Error`: `{"error": "Git operation failed"}`
- **认证**：需要登录认证。
- **备注**：通过 `api.worktrees.worktree_status_for_session` 查询。

---

## POST /api/session/worktree/remove  (routes.py:14721)
- **功能**：移除会话创建的独立 Git Worktree 及关联分支。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `force` (boolean, 可选, 默认 false): 是否强制删除（即使包含未提交修改）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "removed": true,
      "path": "/home/user/project/.worktrees/sess_abc"
    }
    ```
  - `400 Bad Request`: `{"error": "Worktree has uncommitted changes. Use force=true to delete anyway."}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：防止丢失代码，默认若有未提交更改会拒绝，需前端提示用户确认并传 `force: true`。

---

# 二、 会话列表与越狱文件浏览 (Session List & Escape)

## GET /api/sessions  (routes.py:13021)
- **功能**：获取会话元数据列表（支持分页、Profile 过滤、项目过滤与归档筛选），并合并 CLI 本地会话记录。
- **参数**：
  - `profile` (Query, string, 可选): 筛选指定 Profile 的会话。
  - `all_profiles` (Query, string, 可选): 传 "1" 时返回所有可见 Profile 的会话。
  - `project_id` (Query, string, 可选): 筛选指定项目下的会话。
  - `archived` (Query, string, 可选, 默认 "0"): 传 "1" 时仅返回归档会话，传 "0" 返回未归档会话。
  - `limit` (Query, integer, 可选): 分页条数。
  - `offset` (Query, integer, 可选): 分页偏移量。
- **响应**：
  - `200 OK`:
    ```json
    {
      "sessions": [
        {
          "session_id": "c7a8b9e1f2",
          "title": "React 状态管理重构",
          "workspace": "/home/user/project",
          "model": "claude-3-7-sonnet",
          "model_provider": "anthropic",
          "profile": "default",
          "project_id": null,
          "pinned": true,
          "archived": false,
          "message_count": 12,
          "created_at": 1740000000.0,
          "updated_at": 1740001000.0,
          "is_cli_session": false
        }
      ],
      "active_profile": "default",
      "all_profiles": ["default", "work"],
      "other_profile_count": 5
    }
    ```
- **认证**：需要登录认证；按 Profile 隔离规则过滤。
- **备注**：基于 LRU 缓存加速，侧边栏核心数据源；当数据变更时配合 `/api/sessions/events` 事件流实时刷新。

---

## GET /api/sessions/search  (routes.py:13144)
- **功能**：跨所有会话全文搜索消息内容与标题，支持多 Profile 检索与隐私脱敏。
- **参数**：
  - `q` (Query, string, 必填): 搜索关键词。
  - `profile` (Query, string, 可选): 限制搜索的 Profile。
  - `all_profiles` (Query, string, 可选): 是否跨所有 Profile 搜索。
- **响应**：
  - `200 OK`:
    ```json
    {
      "sessions": [
        {
          "session_id": "c7a8b9e1f2",
          "title": "React 状态管理重构",
          "match_preview": "...建议使用 [Zustand] 代替 Redux 处理轻量状态...",
          "updated_at": 1740001000.0
        }
      ],
      "query": "Zustand",
      "count": 1,
      "active_profile": "default",
      "all_profiles": ["default", "work"]
    }
    ```
- **认证**：需要登录认证。
- **备注**：命中结果中的敏感凭据与 API Key 会根据系统配置自动执行脱敏（`_redact_text`）。

---

## GET /api/list  (routes.py:13147)
- **功能**：列出指定会话工作区目录下的文件与子目录列表（沙箱限制在工作区根目录内）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `path` (Query, string, 可选, 默认 "."): 相对工作区的子目录路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "entries": [
        { "name": "src", "type": "dir", "size": 0, "mtime": 1740000000.0 },
        { "name": "package.json", "type": "file", "size": 1240, "mtime": 1740000010.0 }
      ],
      "signature": "a1b2c3d4",
      "path": "."
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}` 或路径不存在。
- **认证**：需要登录认证；严格禁止路径穿越（`..`）。
- **备注**：返回的 `signature` 用于前端比对目录内容是否发生变化。

---

## GET /api/escape/list  (routes.py:13150)
- **功能**：凭借授权的越狱令牌（Escape Token），列出工作区外部目标目录的内容。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `token` (Query, string, 必填): 越狱授权令牌。
  - `path` (Query, string, 可选, 默认 "."): 相对被授权外部根目录的子路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "entries": [
        { "name": "system.log", "type": "file", "size": 54320, "mtime": 1740000000.0 }
      ],
      "path": ".",
      "token": "esc_tok_123"
    }
    ```
  - `400 Bad Request`: `{"error": "token is required"}`
  - `403 Forbidden`: `{"error": "Escape authorization expired or invalid"}`
  - `404 Not Found`: `{"error": "Path not found"}`
- **认证**：需要登录认证 + Escape 授权令牌验证。
- **备注**：令牌具有有效期限，过期需重新申请授权。

---

## POST /api/escape/authorize  (routes.py:13885)
- **功能**：为工作区外的特定绝对/相对路径签发一个临时的越狱授权访问令牌（Escape Token）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 需要授权访问的外部绝对路径。
  - `token` (string, 禁止传递): 必须为空（防止篡改）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "token": "esc_tok_a98b7c",
      "path": "/var/log",
      "expires_at": 1740003600.0
    }
    ```
  - `400 Bad Request`: `{"error": "path is required"}`
  - `403 Forbidden`: `{"error": "browser origin required"}` (必须具备 Origin 且通过 CSRF 校验)
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证 + 严格 Origin / CSRF 校验。
- **备注**：安全沙箱机制，防止未经用户明确授权直接穿透至宿主机敏感文件。

---

## GET /api/escape/file/read  (routes.py:13327)
- **功能**：凭借授权的越狱令牌，读取工作区外部文件的文本内容或 Office 文档预览。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `token` (Query, string, 必填): 越狱授权令牌。
  - `path` (Query, string, 必填): 相对授权路径的目标文件。
- **响应**：
  - `200 OK`:
    ```json
    {
      "content": "Log content here...",
      "mime": "text/plain",
      "size": 1024,
      "is_binary": false
    }
    ```
  - `400 Bad Request`: `{"error": "token is required"}`
  - `403 Forbidden`: `{"error": "Escape authorization expired"}`
  - `404 Not Found`: `{"error": "File not found"}`
  - `503 Service Unavailable`: `{"error": "Office parser not installed"}`
- **认证**：需要登录认证 + Escape 授权令牌验证。
- **备注**：支持 Word/Excel/PPT 文档预览解析。

---

## GET /api/escape/file/raw  (routes.py:13318)
- **功能**：凭借授权的越狱令牌，下载或流式读取工作区外部文件的原始二进制数据。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `token` (Query, string, 必填): 越狱授权令牌。
  - `path` (Query, string, 必填): 相对授权路径的文件。
  - `download` (Query, string, 可选): 传 "1" 时强制作为附件下载。
- **响应**：
  - `200 OK`: 文件二进制流。
  - `400 Bad Request`: `{"error": "token is required"}`
  - `403 Forbidden`: `{"error": "Escape authorization expired"}`
  - `404 Not Found`: `{"error": "not found"}`
- **认证**：需要登录认证 + Escape 授权令牌验证。
- **备注**：遵循同等文件 MIME 与安全头配置。

---

# 三、 聊天与流式通信 (Chat & Streaming)

## POST /api/chat  (routes.py:15196)
- **功能**：同步执行单轮聊天对话（阻塞直至 Assistant 回复完整完成）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `message` (string, 必填): 用户发送的文本消息。
  - `workspace` (string, 可选): 覆盖工作区路径。
  - `model` (string, 可选): 指定调用的模型。
  - `model_provider` (string, 可选): 指定模型供应商。
- **响应**：
  - `200 OK`:
    ```json
    {
      "message": {
        "role": "assistant",
        "content": "这是最终执行回复",
        "timestamp": 1740000010.0
      },
      "session": { "session_id": "c7a8b9e1f2", "messages": [...] }
    }
    ```
  - `400 Bad Request`: `{"error": "empty message"}` 或子代理会话拒绝。
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Agent runtime stale"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：主要供第三方脚本或 API 客户端直接同步调用；WebUI 前端优先采用 `/api/chat/start` + SSE 异步流。

---

## POST /api/chat/start  (routes.py:15193)
- **功能**：启动异步流式对话任务，在后台线程中创建并运行 Agent，返回对应的 `stream_id`。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `message` (string, 必填): 用户输入的 Prompt 文本。
  - `workspace` (string, 可选): 工作区路径。
  - `model` (string, 可选): 模型名称。
  - `model_provider` (string, 可选): 供应商标识。
  - `images` (list[str], 可选): Base64 编码或本地路径的图片附件。
  - `attachments` (list[dict], 可选): 上传的文件附件元数据列表。
  - `profile` (string, 可选): 请求的 Profile。
  - `client_timestamp` (float, 可选): 前端发送时间戳。
- **响应**：
  - `200 OK`:
    ```json
    {
      "stream_id": "stream_9876543210ab",
      "session_id": "c7a8b9e1f2",
      "active": true,
      "replay_available": false
    }
    ```
  - `400 Bad Request`: `{"error": "empty message"}` 或子代理拒绝。
  - `403 Forbidden`: `{"error": "session is read-only"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `409 Conflict`: `{"error": "Session already has an active stream running"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：返回 `stream_id` 后，客户端应立即打开 `GET /api/chat/stream?stream_id=<stream_id>` 监听实时输出。

---

## POST /api/chat/steer  (routes.py:15199)
- **功能**：在流式生成运行过程中动态注入引导提示词（Steering Instruction），不中断当前轮次。
- **参数** (JSON Body):
  - `stream_id` (string, 必填): 处于活跃状态的流 ID。
  - `instruction` / `message` (string, 必填): 引导提示文本。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "steered": true,
      "stream_id": "stream_9876543210ab"
    }
    ```
  - `400 Bad Request`: `{"error": "stream_id and instruction are required"}`
  - `404 Not Found`: `{"error": "Stream not found or already completed"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：指令会被排队推送到活跃 Agent 运行环境的引导队列中，在下一次工具调用或推理间隙生效。

---

## GET /api/chat/stream  (routes.py:13296)
- **功能**：核心 SSE 流式传输通道，实时下发 Token 文本、思考过程、工具调用过程及最终结果。
- **参数**：
  - `stream_id` (Query, string, 必填): 活跃流 ID。
- **响应** (`text/event-stream; charset=utf-8`):
  - **SSE 事件协议清单**：
    - `event: start`：流启动。`data: {"stream_id": "...", "session_id": "...", "model": "...", "model_provider": "..."}`
    - `event: token`：正文增量 Token。`data: {"token": "..."}`
    - `event: reasoning`：深度思考/推理增量（Thinking Chunk）。`data: {"token": "..."}`
    - `event: interim_assistant`：多步思考中的临时助手内容。`data: {"content": "..."}`
    - `event: tool_start`：工具执行开始。`data: {"tool_name": "bash", "tool_id": "call_01", "args": {"command": "ls -la"}}`
    - `event: tool_complete`：工具执行完毕。`data: {"tool_name": "bash", "tool_id": "call_01", "result": "...", "error": null}`
    - `event: tool`：聚合工具调用数据。`data: {"name": "...", "args": {...}, "result": "..."}`
    - `event: status`：Agent 状态变更通知。`data: {"text": "Executing bash...", "type": "tool_running"}`
    - `event: metering`：实时 Token 消耗计量估算。`data: {"prompt_tokens": 1200, "completion_tokens": 150}`
    - `event: title`：后台自动生成的会话标题。`data: {"title": "..."}`
    - `event: approval_required`：触发工具执行人工确认提示。`data: {"command": "...", "pattern_key": "..."}`
    - `event: clarify_required`：触发 Agent 澄清追问提问。`data: {"question": "...", "choices": [...]}`
    - `event: done`：生成顺利完成。`data: {"ok": true, "message": {"role": "assistant", "content": "..."}, "usage": {...}}`
    - `event: error`：执行出错。`data: {"error": "...", "type": "api_error", "retryable": false}`
    - `event: cancelled`：用户主动取消。`data: {"cancelled": true, "stream_id": "..."}`
    - 心跳注释行：`: keepalive

`（每 5 秒自动发送）。
- **认证**：需要登录认证；校验 Profile 隔离。
- **备注**：若流已结束但存在 `run_journal` 日志，接口会自动进行完整历史回放（Replay），确保客户端断线重连后不丢失消息。

---

## GET /api/chat/stream/status  (routes.py:13266)
- **功能**：查询指定 `stream_id` 的流是否仍在运行，以及是否存在可回放的日志。
- **参数**：
  - `stream_id` (Query, string, 必填): 流 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "active": true,
      "stream_id": "stream_9876543210ab",
      "replay_available": true,
      "journal": { "status": "running", "event_count": 45 }
    }
    ```
- **认证**：需要登录认证；校验 Profile 可见性。
- **备注**：前端用于页面加载或重连时探测是否需要重新挂载 SSE 流。

---

## GET /api/chat/cancel  (routes.py:13281)
- **功能**：取消正在运行的流式对话，通知 Agent 停止后续工具调用与输出。
- **参数**：
  - `stream_id` (Query, string, 必填): 目标流 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "cancelled": true,
      "stream_id": "stream_9876543210ab"
    }
    ```
  - `400 Bad Request`: `{"error": "stream_id required"}`
- **认证**：需要登录认证；校验 Profile 可见性。
- **备注**：取消后服务端会将已生成的半截内容安全归档并追加中断标记（`[Cancelled by user]`），避免数据截断破坏 JSON 结构。

---

# 四、 审批与澄清交互 (Approval & Clarify)

## GET /api/approval/pending  (routes.py:13330)
- **功能**：查询指定会话当前是否存在等待人工审批的敏感工具操作（如风险命令执行）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "pending": {
        "command": "rm -rf build/",
        "pattern_key": "rm_rf",
        "pattern_keys": ["rm_rf"],
        "description": "Delete build directory",
        "id": "appr_123"
      },
      "pending_count": 1
    }
    ```
    （无待审批时 `pending: null, pending_count: 0`）
- **认证**：需要登录认证。
- **备注**：同时支持本地工具排队队列与 Gateway 待审批队列的镜像聚合。

---

## GET /api/approval/stream  (routes.py:13333)
- **功能**：长连接 SSE 实时推送待审批事件（替代 1.5s 客户端轮询）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应** (`text/event-stream; charset=utf-8`):
  - **SSE 事件**：
    - `event: initial`：连接建立后立即下发初始状态快照。`data: {"pending": {...}|null, "pending_count": 1}`
    - `event: approval`：新产生审批请求时即时推送。`data: {"command": "...", "pattern_key": "...", ...}`
    - 心跳：`: keepalive

`
- **认证**：需要登录认证。
- **备注**：原子化订阅并快照（防止在订阅缝隙间丢失审批事件）。

---

## POST /api/approval/respond  (routes.py:15342)
- **功能**：对指定工具执行审批请求提交裁决结果（允许一次 / 允许本会话 / 拒绝）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `approved` (boolean, 必填): 是否批准执行。
  - `pattern_key` / `pattern_keys` (string | list[string], 可选): 授权的模式键。
  - `decision` (string, 可选): 决策类型，"allow_once" | "allow_session" | "deny"。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "approved": true,
      "session_id": "c7a8b9e1f2"
    }
    ```
  - `400 Bad Request`: `{"error": "session_id and approved are required"}`
  - `404 Not Found`: `{"error": "No pending approval for session"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：裁决后唤醒阻塞等待在 `tools.approval` 的 Agent 线程；若选择 `allow_session` 则本会话内同类操作自动免审批。

---

## GET /api/approval/inject_test  (routes.py:13336)
- **功能**：注入测试用的待审批数据（仅供自动化测试套件使用）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `pattern_key` (Query, string, 可选, 默认 "test_pattern"): 测试模式键。
  - `command` (Query, string, 可选, 默认 "rm -rf /tmp/test"): 测试命令。
- **响应**：
  - `200 OK`: `{"ok": true, "session_id": "..."}`
  - `404 Not Found`: 非回环地址请求直接返回 404。
- **认证**：**强制仅限本地回环 IP（127.0.0.1）**，远程客户端拦截。
- **备注**：用于端到端测试审批流程。

---

## GET /api/clarify/pending  (routes.py:13342)
- **功能**：查询当前会话是否存在 Agent 抛出的多选/单选澄清追问（Clarification Question）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "pending": {
        "clarify_id": "clarify_abc",
        "question": "请问您希望使用 TypeScript 还是 JavaScript？",
        "choices": ["TypeScript", "JavaScript"],
        "multiple": false,
        "timeout": 60.0
      }
    }
    ```
    （无追问时 `pending: null`）
- **认证**：需要登录认证。
- **备注**：支持单选与多选问题。

---

## GET /api/clarify/stream  (routes.py:13345)
- **功能**：长连接 SSE 实时推送澄清追问事件（替代轮询）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应** (`text/event-stream; charset=utf-8`):
  - **SSE 事件**：
    - `event: initial`：`data: {"pending": {...}|null}`
    - `event: clarify`：`data: {"clarify_id": "...", "question": "...", "choices": [...]}`
    - 心跳：`: keepalive

`
- **认证**：需要登录认证。
- **备注**：由 `api.clarify.sse_subscribe` 管理订阅。

---

## POST /api/clarify/respond  (routes.py:15346)
- **功能**：提交用户对澄清追问的回答内容。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `response` / `answer` / `choice` (string, 必填): 用户的选项或填写的回答。
  - `clarify_id` (string, 可选): 指定解决的澄清 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session_id": "c7a8b9e1f2"
    }
    ```
  - `400 Bad Request`: `{"error": "response is required"}`
  - `409 Conflict`:
    ```json
    {
      "ok": false,
      "error": "Clarification prompt expired or not found. The agent may have already proceeded.",
      "stale": true
    }
    ```
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若 Agent 已超时并自行推进，接口返回 409 Conflict 且 `stale: true`，前端应提示用户已过期。

---

## GET /api/clarify/inject_test  (routes.py:13351)
- **功能**：注入测试用的澄清追问（仅供自动化测试使用）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `question` (Query, string, 可选): 测试问题文本。
  - `choices` (Query, string, 可选): 逗号分隔的选项列表。
- **响应**：
  - `200 OK`: `{"ok": true, "session_id": "...", "clarify_id": "..."}`
  - `404 Not Found`: 非回环地址请求返回 404。
- **认证**：**强制仅限本地回环 IP（127.0.0.1）**。
- **备注**：用于端到端测试澄清问答交互。

---

# 五、 异步任务、目标模式与完成确认 (Btw / Background / Goal / Ack)

## POST /api/btw  (routes.py:15181)
- **功能**：旁路补充信息（"By The Way" 机制）。向会话静默注入一段上下文提示，不立刻触发模型回复。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `message` (string, 必填): 补充的提示信息。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session_id": "c7a8b9e1f2",
      "injected": true
    }
    ```
  - `400 Bad Request`: `{"error": "message is required"}` 或子代理会话拒绝。
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：注入的内容会在下一轮正常对话交互时作为附加系统/前置上下文递交给模型。

---

## POST /api/background  (routes.py:15184)
- **功能**：在后台异步执行长耗时 Shell 脚本或后台任务（托管于后台任务管理器）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `task` / `command` (string, 必填): 待执行的任务命令。
  - `notify` (boolean, 可选, 默认 true): 执行完成后是否通过系统通知唤醒。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "task_id": "bg_task_001",
      "session_id": "c7a8b9e1f2",
      "status": "started"
    }
    ```
  - `400 Bad Request`: `{"error": "task is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：由 `api.background` 模块负责进程树生命周期管理。

---

## GET /api/background/status  (routes.py:13014)
- **功能**：获取指定会话所有后台任务的执行结果、当前状态及标准输出日志缓冲。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "results": [
        {
          "task_id": "bg_task_001",
          "status": "completed",
          "command": "npm run build",
          "output": "Build finished successfully in 4.2s",
          "exit_code": 0,
          "created_at": 1740000000.0,
          "completed_at": 1740000005.0
        }
      ]
    }
    ```
  - `400 Bad Request`: `{"error": "Missing session_id"}`
- **认证**：需要登录认证。
- **备注**：任务完成后，输出结果常驻内存供前端拉取展示。

---

## POST /api/goal  (routes.py:15187)
- **功能**：控制 WebUI 的自主多步目标执行模式（`/goal` 斜杠指令），支持目标设定、暂停、恢复与状态流转。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `action` (string, 可选, 默认 "start"): 动作指令，如 "start" | "status" | "pause" | "resume" | "stop"。
  - `goal` (string, 可选): 目标描述文本。
  - `profile` (string, 可选): 运行 Profile。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "goal_status": {
        "status": "running",
        "goal": "重构前端组件库",
        "current_step": 3,
        "total_steps": 10
      },
      "stream_id": "stream_goal_123"
    }
    ```
  - `400 Bad Request`: `{"error": "invalid profile"}` 或子代理会话拒绝。
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：由 `_handle_goal_command` 驱动多轮次自主 Agent 执行闭环。

---

## POST /api/bg-task-complete-ack  (routes.py:15190)
- **功能**：前端对接收到的后台任务完成事件（`bg_task_complete`）进行确认回执应答。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `task_id` (string, 必填): 完成的任务 ID（兼容旧字段 `process_id`）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session_id": "c7a8b9e1f2",
      "task_id": "bg_task_001",
      "noop": true
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：服务端采用事件驱动自动唤醒，该端点为状态纯确认（`noop: true`）；使用旧参数 `process_id` 时响应头包含 `Deprecation: true`。

---

## POST /api/process-complete-ack  (routes.py:13800)
- **功能**：**[已废弃 / 410 Gone]** 旧版后台进程完成确认端点，已重命名迁移至 `/api/bg-task-complete-ack`。
- **响应**：
  - `410 Gone`:
    ```json
    {
      "error": "gone: /api/process-complete-ack was replaced by /api/bg-task-complete-ack as part of the process_complete -> bg_task_complete event rename",
      "replaced_by": "/api/bg-task-complete-ack"
    }
    ```
- **认证**：免 CSRF 校验（优先保证返回明确的 410 错误引导）。
- **备注**：响应头携带 `X-Replaced-By: /api/bg-task-complete-ack`。

---

## /api/submit? （端点分析）
- **功能与现状说明**：
  - 在 `routes.py` 路由分发表中**不存在 `/api/submit` 独立端点**。
  - **对应功能映射**：
    1. 正常用户聊天消息提交：统一使用 `POST /api/chat/start`（流式）或 `POST /api/chat`（同步）。
    2. 敏感工具操作审批提交：使用 `POST /api/approval/respond`。
    3. 交互式澄清回答提交：使用 `POST /api/clarify/respond`。
    4. 异步完成事件确认提交：使用 `POST /api/bg-task-complete-ack`。

---

# 六、 网页交互式终端 (Web PTY Terminal)

## POST /api/terminal/start  (routes.py:15203)
- **功能**：在指定会话的工作区中生成一个伪终端进程（PTY Process）及底层 Shell。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 绑定的会话 ID。
  - `rows` (integer, 可选, 默认 24): 初始行数。
  - `cols` (integer, 可选, 默认 80): 初始列数。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session_id": "c7a8b9e1f2",
      "pid": 41235,
      "rows": 24,
      "cols": 80
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `403 Forbidden`: `{"error": "Embedded terminal disabled by configuration"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `500 Internal Server Error`: `{"error": "Failed to spawn terminal: ..."}`
- **认证**：需要登录认证；需有效 CSRF Token；受 `_embedded_terminal_gate_allows` 安全网关控制。
- **备注**：进程运行目录自动对齐会话工作区；受最大并发终端数限制（超出自动淘汰最早的空闲终端）。

---

## POST /api/terminal/input  (routes.py:15206)
- **功能**：向终端 PTY 主设备标准输入写入键盘击键、输入字符或控制序列（Raw Stdin）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `data` (string, 必填): 待写入的字符数据或 VT100 转义序列。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true
    }
    ```
  - `400 Bad Request`: `{"error": "data is required"}`
  - `403 Forbidden`: 终端网关拒绝。
  - `404 Not Found`: `{"error": "terminal not running"}`
- **认证**：需要登录认证；需有效 CSRF Token；受终端安全网关控制。
- **备注**：支持向终端管道直接传输二进制与 ANSI 转义序列。

---

## GET /api/terminal/output  (routes.py:13299)
- **功能**：通过长连接 SSE 实时拉取终端标准输出与标准错误流（Stdout / Stderr）。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
- **响应** (`text/event-stream; charset=utf-8`):
  - **SSE 事件**：
    - `event: output`：终端输出块。`data: {"data": "...
"}`
    - `event: exit`：终端退出。`data: {"exit_code": 0}`
  - `403 Forbidden`: 终端网关拒绝。
  - `404 Not Found`: `{"error": "terminal not running"}`
- **认证**：需要登录认证；受终端安全网关控制。
- **备注**：配置了写超时保护；当客户端断开连接时自动清理输出监听器。

---

## POST /api/terminal/resize  (routes.py:15209)
- **功能**：动态调整终端窗口行列尺寸（Window Resize / TIOCSWINSZ）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `rows` (integer, 可选, 默认 24): 终端行数。
  - `cols` (integer, 可选, 默认 80): 终端列数。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true
    }
    ```
  - `400 Bad Request`: `{"error": "invalid dimensions"}`
  - `404 Not Found`: `{"error": "terminal not running"}`
- **认证**：需要登录认证；需有效 CSRF Token；受终端安全网关控制。
- **备注**：底层调用系统 `ioctl(fd, TIOCSWINSZ, ...)` 或 Windows ConPTY API 同步窗口几何尺寸。

---

## POST /api/terminal/close  (routes.py:15212)
- **功能**：强制终止并关闭指定会话的 PTY 终端及所有子进程。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "closed": true
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `403 Forbidden`: 终端网关拒绝。
- **认证**：需要登录认证；需有效 CSRF Token；受终端安全网关控制。
- **备注**：会递归终止由 Shell 衍生的进程树（`_reap_terminal_descendants`）并释放文件描述符。

---

# 七、 会话分享 (Session Share)

## GET /api/share/<token>  (routes.py:12078)
- **功能**：公开只读获取通过分享链接共享的对话快照记录。
- **参数**：
  - `token` (Path, string, 必填): 嵌入在 URL 中的分享令牌。
- **响应**：
  - `200 OK`:
    ```json
    {
      "share": {
        "share_token": "sh_a1b2c3d4e5",
        "share_title": "React 状态管理重构",
        "share_message_count": 8,
        "share_created_at": 1740000000.0,
        "share_updated_at": 1740001000.0,
        "messages": [
          { "role": "user", "content": "hello" },
          { "role": "assistant", "content": "hi" }
        ]
      }
    }
    ```
  - `404 Not Found`: `{"error": "Shared conversation not found"}`
- **认证**：**完全公开免登录**（不受系统登录认证限制）。
- **备注**：响应头强制包含 `Cache-Control: no-store` 与 `X-Robots-Tag: noindex, nofollow` 防止搜索引擎爬取。

---

## POST /api/share/create  (routes.py:14013)
- **功能**：为指定会话生成只读公开分享快照与分享令牌。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 待分享的会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "share": {
        "token": "sh_a1b2c3d4e5",
        "url": "/share/sh_a1b2c3d4e5",
        "title": "React 状态管理重构",
        "message_count": 8,
        "created_at": 1740000000.0,
        "updated_at": 1740000000.0
      },
      "session": { "session_id": "c7a8b9e1f2", "share_token": "sh_a1b2c3d4e5" }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若之前已存在分享令牌则刷新快照并重用或更新；触发 `session_share_create` 事件通知侧边栏更新分享图标。

---

## POST /api/share/revoke  (routes.py:14058)
- **功能**：撤销指定会话的公开分享状态，销毁已发布的分享快照。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "session": { "session_id": "c7a8b9e1f2", "share_token": null }
    }
    ```
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：物理删除 `shares/<token>.json` 镜像；触发 `session_share_revoke` 广播。

---

# 八、 媒体、语音、文件与工作区上传 (Media / Voice / Files / Upload)

## POST /api/upload  (routes.py:13849)
- **功能**：上传文件附件到会话专用附件目录（`attachments/<sid>/`）。
- **参数** (`multipart/form-data`):
  - `session_id` (Form field, string, 可选): 关联的会话 ID。
  - `file` (Form file, binary, 必填): 待上传的文件内容。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "filename": "schema.png",
      "path": "/home/user/.hermes/webui/attachments/c7a8b9e1f2/schema.png",
      "size": 65420,
      "mime": "image/png",
      "is_image": true
    }
    ```
  - `400 Bad Request`: `{"error": "No file field in request"}`
  - `404 Not Found`: `{"error": "Session not found"}`
  - `413 Payload Too Large`: `{"error": "File too large (max 50MB)"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：自动消毒文件名（`_sanitize_upload_name`）；若上传的是 Office 文档（`.docx` / `.xlsx` / `.pptx`），会自动解析并生成 `.preview.txt` 预览 Sidecar。

---

## POST /api/upload/extract  (routes.py:13851)
- **功能**：上传压缩包文件（.zip / .tar / .tgz）并自动解压到会话附件目录中。
- **参数** (`multipart/form-data`):
  - `session_id` (Form field, string, 必填): 会话 ID。
  - `file` (Form file, binary, 必填): 压缩包文件。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "extracted_files": ["src/index.js", "src/util.js"],
      "total_files": 2,
      "total_bytes": 8450
    }
    ```
  - `400 Bad Request`: `{"error": "No file field in request"}`
  - `413 Payload Too Large`: `{"error": "Archive exceeds max uncompressed size / max files limit"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：内置 Zip Bomb 防御，解压字节数与文件总数受严格上限限制。

---

## POST /api/workspace/upload  (routes.py:13853)
- **功能**：直接将文件上传到当前会话的工作区（Workspace）目录或其子目录中。
- **参数** (`multipart/form-data`):
  - `session_id` (Form field, string, 必填): 会话 ID。
  - `path` (Form field, string, 可选, 默认 ""): 工作区内的相对子目录。
  - `file` (Form file, binary, 必填): 上传的文件。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "filename": "app.py",
      "path": "/home/user/project/app.py",
      "rel_path": "app.py",
      "size": 1024
    }
    ```
  - `400 Bad Request`: `{"error": "Missing session_id"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：通过 `safe_resolve_ws` 校验路径，严格禁止越出工作区根目录。

---

## POST /api/transcribe  (routes.py:13856)
- **功能**：语音转文字（STT / Speech-to-Text），上传语音文件并返回识别文本。
- **参数** (`multipart/form-data`):
  - `file` (Form file, binary, 必填): 音频文件（webm、wav、mp3、m4a、ogg 等）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "transcript": "请帮我检查一下代码中的内存泄漏问题。"
    }
    ```
  - `400 Bad Request`: `{"error": "No file field in request"}`
  - `503 Service Unavailable`: `{"error": "Speech-to-text is unavailable on this server"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：后端自动适配本地 Whisper 命令行或 OpenAI Audio API。

---

## GET /api/transcribe/capability  (routes.py:12398)
- **功能**：探测当前服务端是否具备语音识别（STT）能力及具体使用的提供商。
- **参数**：无
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "available": true,
      "provider": "whisper_local"
    }
    ```
- **认证**：需要登录认证。
- **备注**：前端用于判断是否在输入框渲染麦克风语音输入按钮。

---

## POST /api/tts  (routes.py:13859)
- **功能**：文本转语音（TTS / Text-to-Speech），根据传入的文本合成音频流。
- **参数** (JSON Body):
  - `text` (string, 必填, 最大 5000 字): 待合成文本。
  - `voice` (string, 可选, 默认 "zh-CN-XiaoxiaoNeural"): 音色名称。
  - `rate` (string, 可选): 语速调整（如 "+10%"、"-5%"）。
  - `pitch` (string, 可选): 音调调整（如 "+0Hz"）。
  - `engine` (string, 可选, 默认 "edge"): TTS 引擎，支持 "edge" | "elevenlabs" | "openai"。
- **响应**：
  - `200 OK`: 音频二进制数据流（`Content-Type: audio/mpeg`），包含精确的 `Content-Length`。
  - `400 Bad Request`: `{"error": "text too long (max 5000 characters)"}`
  - `405 Method Not Allowed`: `{"error": "POST required for /api/tts"}`
  - `429 Too Many Requests`: `{"error": "Rate limit exceeded (1 request per 2 seconds)"}`
- **认证**：需要登录认证；内置独立客户端单 IP 每 2 秒 1 次的限流器。
- **备注**：全量缓冲后输出 Content-Length，以确保现代浏览器音频组件即时正常起播。

---

## GET /api/media  (routes.py:13312)
- **功能**：按绝对路径安全读取本地媒体文件（用于聊天面板内联展示图片、截图等）。
- **参数**：
  - `path` (Query, string, 必填): 目标文件的绝对路径。
- **响应**：
  - `200 OK`: 媒体文件二进制内容（安全图片内联显示；SVG 强制作为附件下载防 XSS）。
  - `400 Bad Request`: `{"error": "path parameter required"}`
  - `401 Unauthorized`: 未登录拦截。
  - `403 Forbidden`: `{"error": "Path traversal / Access outside allowed roots denied"}`
  - `404 Not Found`: 文件不存在。
- **认证**：强制校验登录认证；**严格白名单路径沙箱**（仅允许 `~/.hermes`、`/tmp`、当前工作区及 `MEDIA_ALLOWED_ROOTS` 环境变量注册目录）。
- **备注**：SVG 文件强制输出 `Content-Disposition: attachment`。

---

## GET /api/file  (routes.py:13324)
- **功能**：读取工作区内指定文件的结构化文本内容、签名与 Office 预览数据。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `path` (Query, string, 必填): 相对工作区的文件路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "content": "import sys...",
      "encoding": "utf-8",
      "mime": "text/x-python",
      "size": 1560,
      "is_binary": false,
      "path": "src/main.py",
      "signature": "e4d3c2b1",
      "is_office": false
    }
    ```
  - `400 Bad Request`: `{"error": "path is required"}`
  - `404 Not Found`: `{"error": "File not found"}`
  - `503 Service Unavailable`: `{"error": "Office parser missing"}`
- **认证**：需要登录认证；禁止越出工作区根目录。
- **备注**：支持 Office 文档预览解析；返回文件的内容哈希 `signature`。

---

## GET /api/file/raw  (routes.py:13315)
- **功能**：读取或下载工作区内文件的原始字节流，支持沙箱内联 HTML 预览。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `path` (Query, string, 必填): 相对文件路径。
  - `download` (Query, string, 可选): 传 "1" 时强制下载。
  - `inline` (Query, string, 可选): 传 "1" 时允许 HTML 在沙箱 Iframe 中内联预览。
- **响应**：
  - `200 OK`: 原始文件二进制流；当 `inline=1` 时注入 CSP 安全头：`sandbox allow-scripts allow-popups allow-popups-to-escape-sandbox`。
  - `400 Bad Request`: `{"error": "session_id is required"}`
  - `404 Not Found`: `{"error": "not found"}`
- **认证**：需要登录认证。
- **备注**：针对 HTML 预览实施严格的同源隔离（不赋予 `allow-same-origin`），防止 Iframe 窃取主站 Cookie 与 LocalStorage。

---

## POST /api/file/delete  (routes.py:15298)
- **功能**：删除工作区内的指定文件。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对工作区的文件路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "temp.txt"
    }
    ```
  - `400 Bad Request`: `{"error": "invalid path"}`
  - `404 Not Found`: `{"error": "File not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_file_delete` 处理。

---

## POST /api/file/save  (routes.py:15301)
- **功能**：保存或更新工作区内的纯文本文件（原子写入）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对文件路径。
  - `content` (string, 必填): 文件文本内容。
  - `encoding` (string, 可选, 默认 "utf-8"): 编码格式（"utf-8" | "base64"）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "src/main.py",
      "size": 1600,
      "signature": "f5e4d3c2"
    }
    ```
  - `400 Bad Request`: `{"error": "content is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：采用临时文件加重命名的原子写模式，防止写入中途断电导致文件损坏。

---

## POST /api/file/office-save  (routes.py:15304)
- **功能**：保存对 Office Word（.docx）文档的文本修改，保留原始 XML 排版与格式。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对 `.docx` 文件路径。
  - `text` (string, 必填): 更新后的纯文本内容。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "docs/spec.docx",
      "size": 24800
    }
    ```
  - `400 Bad Request`: `{"error": "unsupported office format"}`
  - `503 Service Unavailable`: `{"error": "python-docx not installed"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：基于 `api.office_documents.save_office_document` 实现。

---

## POST /api/file/create  (routes.py:15307)
- **功能**：在工作区创建新文件。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对文件路径。
  - `content` (string, 可选, 默认 ""): 初始文本内容。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "src/new_file.py"
    }
    ```
  - `400 Bad Request`: `{"error": "File already exists"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若目标文件已存在则报错拒绝。

---

## POST /api/file/rename  (routes.py:15310)
- **功能**：重命名工作区内的文件或目录。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `old_path` (string, 必填): 原路径。
  - `new_path` (string, 必填): 新路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "old_path": "src/old.py",
      "new_path": "src/new.py"
    }
    ```
  - `400 Bad Request`: `{"error": "Target already exists"}`
  - `404 Not Found`: `{"error": "Source file not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：两端路径均受工作区沙箱限制。

---

## POST /api/file/move  (routes.py:15313)
- **功能**：在工作区内移动文件或目录到新目录。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `source` (string, 必填): 源路径。
  - `destination` (string, 必填): 目标目录或目标文件路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "source": "src/util.py",
      "destination": "lib/util.py"
    }
    ```
  - `400 Bad Request`: `{"error": "Invalid destination"}`
  - `404 Not Found`: `{"error": "Source not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_file_move` 处理。

---

## POST /api/file/create-dir  (routes.py:15316)
- **功能**：在工作区内递归创建新目录。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 待创建的目录路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "src/components"
    }
    ```
  - `400 Bad Request`: `{"error": "Directory already exists"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_create_dir` 处理。

---

## POST /api/file/reveal  (routes.py:15319)
- **功能**：在宿主机操作系统图形界面中高亮显示（Reveal）目标文件所在目录（Windows Explorer / macOS Finder / Linux 文件管理器）。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对工作区的文件路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "path": "src/main.py",
      "absolute_path": "C:\Users\Admin\project\src\main.py"
    }
    ```
  - `400 Bad Request`: `{"error": "path is required"}`
  - `404 Not Found`: `{"error": "File not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：底层调用 `explorer.exe /select,` (Windows) 或 `open -R` (macOS)。

---

## POST /api/file/path  (routes.py:15322)
- **功能**：将工作区相对路径解析并返回宿主机的规范绝对路径。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对文件路径。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "absolute_path": "/home/user/project/src/main.py",
      "workspace": "/home/user/project"
    }
    ```
  - `400 Bad Request`: `{"error": "path is required"}`
  - `404 Not Found`: `{"error": "Session not found"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：用于前端复制绝对路径或与其他本地工具联动。

---

## POST /api/file/open-vscode  (routes.py:15325)
- **功能**：调用本地 VS Code 命令行（`code --goto`）直接在指定行列处打开文件。
- **参数** (JSON Body):
  - `session_id` (string, 必填): 会话 ID。
  - `path` (string, 必填): 相对文件路径。
  - `line` (integer, 可选): 定位的代码行号（1-indexed）。
  - `column` (integer, 可选): 定位的代码列号（1-indexed）。
- **响应**：
  - `200 OK`:
    ```json
    {
      "ok": true,
      "command": "code --goto /home/user/project/src/main.py:45:10"
    }
    ```
  - `400 Bad Request`: `{"error": "path is required"}`
  - `404 Not Found`: `{"error": "File not found"}`
  - `503 Service Unavailable`: `{"error": "VS Code CLI (code) not found in PATH"}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：若环境变量中无法定位 `code` 命令则返回 503 提示。

---

## GET /api/folder/download  (routes.py:13321)
- **功能**：将工作区内的整个文件夹动态打包压缩为 ZIP 文件并以流式方式下载。
- **参数**：
  - `session_id` (Query, string, 必填): 会话 ID。
  - `path` (Query, string, 必填): 相对工作区的目录路径。
- **响应**：
  - `200 OK`: 流式 `application/zip` 二进制数据流；响应头带 `Content-Disposition: attachment; filename="<folder_name>.zip"` 与 `Connection: close`。
  - `400 Bad Request`: `{"error": "path must be a directory; use /api/file/raw for single files"}`
  - `404 Not Found`: `{"error": "not found"}`
  - `413 Payload Too Large`:
    - 超出文件数限制：`{"error": "too many files", "limit": 10000, "configure": "HERMES_WEBUI_FOLDER_ZIP_MAX_FILES"}`
    - 超出大小限制：`{"error": "folder too large", "limit_bytes": 524288000, "configure": "HERMES_WEBUI_FOLDER_ZIP_MAX_MB"}`
- **认证**：需要登录认证。
- **备注**：采用 `zipfile.ZipFile(handler.wfile, mode="w")` 在内存/网络管道即时边压边发，避免占用服务器海量临时磁盘空间。

---

# 九、 域 B 关联流与运维端点 (Associated Events & Maintenance)

## GET /api/sessions/gateway/stream  (routes.py:13302)
- **功能**：网关级全局会话长连接 SSE 流，用于多会话并发网关模式下的跨会话事件广播。
- **参数**：无
- **响应** (`text/event-stream; charset=utf-8`):
  - 下发网关全局路由、活跃运行实例变更与网关生命周期事件。
- **认证**：需要登录认证。
- **备注**：调用 `_handle_gateway_sse_stream`。

---

## GET /api/sessions/events  (routes.py:13305)
- **功能**：全局会话列表变更通知 SSE 事件流（侧边栏实时数据同步核心通道）。
- **参数**：无
- **响应** (`text/event-stream; charset=utf-8`):
  - **SSE 事件**：
    - `event: sessions_changed`：会话增删改、标题变动、置顶、归档时即时广播。
      `data: {"event": "session_rename", "profile": "default", "session_id": "c7a8b9e1f2", "timestamp": 1740001000.0}`
    - 心跳：`: keepalive

`
- **认证**：需要登录认证；按 Profile 隔离事件派发。
- **备注**：前端侧边栏据此自动增量局部更新列表，无需周期性全量轮询。

---

## GET /api/session/events/:session_id  (routes.py:13308-13310)
- **功能**：URL 路径参数形式的单会话专用 SSE 事件流（兼容模式）。
- **参数**：
  - `session_id` (Path, string, 必填): 路径捕获参数。
- **响应**：同 `GET /api/session/stream`。
- **认证**：需要登录认证。
- **备注**：调用 `_handle_session_sse_stream_for_session`。

---

## POST /api/sessions/cleanup  (routes.py:14444)
- **功能**：批量清理过期或超过保留配额的旧会话。
- **参数** (JSON Body):
  - `max_age_days` (integer, 可选): 最长保留天数。
  - `keep_pinned` (boolean, 可选, 默认 true): 是否保留置顶会话。
- **响应**：
  - `200 OK`: `{"ok": true, "deleted_count": 5, "freed_bytes": 1048576}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：调用 `_handle_sessions_cleanup`。

---

## POST /api/sessions/cleanup_zero_message  (routes.py:14447)
- **功能**：一键清理所有没有任何消息记录的空白会话占位符。
- **参数** (JSON Body): 无
- **响应**：
  - `200 OK`: `{"ok": true, "deleted_count": 3}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：释放因反复点击 "+ New Chat" 但未发送任何消息而残留的空白会话 Sidecar。

---

## POST /api/client-events/log  (routes.py:13862)
- **功能**：前端客户端日志与遥测事件上报（UI 异常、渲染耗时、连接中断等）。
- **参数** (JSON Body):
  - `events` (list[dict], 必填): 包含事件名、时间戳、会话 ID、错误堆栈等元数据的事件数组。
- **响应**：
  - `200 OK`: `{"ok": true, "logged": 2}`
- **认证**：需要登录认证；需有效 CSRF Token。
- **备注**：用于后端集中式错误分析与请求诊断链路串联（`RequestDiagnostics`）。

---

# 十、 域 B 未分类/疑点清单与对接易错点

### 1. `/api/submit` 端点存疑澄清
- **现状**：代码中**不存在**名为 `/api/submit` 的路由。
- **结论**：业务提交分别由 `/api/chat/start`（聊天提问）、`/api/approval/respond`（审批）、`/api/clarify/respond`（澄清回答）、`/api/bg-task-complete-ack`（后台任务确认）承担。

### 2. 废弃端点与迁移对照
- `/api/process-complete-ack` 已废弃并明确返回 `410 Gone`，客户端对接应统一使用 `POST /api/bg-task-complete-ack`。
- `/api/session/yolo` 存在两个条目：`GET /api/session/yolo` (行号 12998) 查询状态，`POST /api/session/yolo` (行号 15159) 开启/关闭状态。

### 3. 多 Profile 隔离与 409 状态码处理
- 当访问或操作一个属于其他已配置 Profile 的会话时，后端不会返回 404，而是返回 **`409 Conflict`**（Payload 带 `code: "session_profile_mismatch"` 与所属 `profile`）。前端客户端在对接时必须捕获 409，并提示用户切换 Profile，不可直接当成网络故障或 404 自愈清空 URL。

### 4. 子代理会话只读守卫 (Subagent View-Only)
- 任何由子代理（Subagent Child）衍生的会话均具备 `_session_is_subagent_view_only` 保护。前端对其调用任何修改接口（如 `/api/session/delete`、`/api/session/update`、`/api/session/clear`、`/api/session/truncate`、`/api/session/retry`、`/api/session/undo`、`/api/chat/start` 等）均会返回 **`400 Bad Request`**。客户端对接时需在 UI 上禁用编辑、重试与删除按钮。

### 5. SSE 与流式中断处理协议
- `GET /api/chat/stream` 支持断线重放（Replay）。当流中断时，客户端使用相同的 `stream_id` 重新连接即可从 `run_journal` 恢复历史输出，直至收到 `event: done` 或 `event: error`。
- SSE 链接必须支持每 5 秒一次的 `: keepalive\n\n` 心跳过滤，防止代理层超时断开。

### 6. 文件与媒体安全沙箱边界
- `GET /api/media` 仅允许读取 `HERMES_HOME`、`/tmp`、当前工作区及 `MEDIA_ALLOWED_ROOTS`。超出范围的绝对路径将直接返回 `403 Forbidden`。
- `GET /api/file/raw` 当 `inline=1` 渲染 HTML 时会自动附带 CSP Sandbox 隔离头，禁止调用父页面 DOM / Cookie。
