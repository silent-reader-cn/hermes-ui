# Hermes WebUI 后端接口大全参考目录（hermes-webui fork @ :30002）

> 最后更新：2026-08-21 ｜ 生成方式：4×AGY(gemini-3.7-flash-high) 并行静态审计后端 + 客户端 + Leader(routes.py 行号) 独立抽查
> 后端权威源：`D:\hermes-webui\api\routes.py`（26554 行单文件分发）+ `api/` 下 65 个模块 ｜ dispatch 区：routes.py L11982–L16506
> 详细卡片：`docs/specs/backend-api-details/`（domain_a/b/c 全端点卡片 + client-bound-endpoints 客户端三层链路）
> 用途：Hermex→Flutter 客户端**后续功能对接的唯一后端索引**。

---

## 1. 总览

| 指标 | 数值 | 说明 |
|---|---|---|
| 后端唯一路径 | **222** | routes.py dispatch 区 `parsed.path == / startswith` 全部条目去重 |
| 接口卡片（方法×路径） | **255** | 含同路径多方法（GET/POST 等），三份 AGY 卡片交叉去重 |
| 客户端 endpoints.dart 定义 | **123** | 对齐蓝本 Endpoints.swift 125 case（含查询参数变体） |
| 客户端 API 方法（api_client*.dart） | **136** | 11 个扩展文件 |
| ✅ 已对接并落地 UI | **75** | client-bound-endpoints.md 逐条三层链路验证 |
| ⚠️ Client 已封装未接 UI | **48** | 24 组（§4.2） |
| ❌ 后端有、客户端完全未定义 | **119** | **本次审计核心差距（§4.1）** |
| ⚠️ 部分实现（路径参数形态） | **13** | kanban/mcp 等 {param} 形态，客户端覆盖不全 |

---

## 2. 接口总表（按功能域 18 组）

> 状态图例：✅ 已对接（UI 落地） ｜ ⚠️ Client 已定义（未接 UI） ｜ ❌ 未对接（后端有、客户端无） ｜ ⚠️部分 路径参数形态。routes.py 列为权威行号锚点。

### 1. 认证与安全 — 11 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/auth/login` | ✅ 已对接 | 16248 |
| POST | `/api/auth/logout` | ⚠️ Client 已定义 | 16382 |
| GET | `/api/auth/oidc/callback` | ❌ 未对接 | 12004 |
| GET | `/api/auth/oidc/start` | ❌ 未对接 | 11982 |
| POST | `/api/auth/passkey/delete` | ❌ 未对接 | 16359 |
| POST | `/api/auth/passkey/login` | ❌ 未对接 | 16298 |
| POST | `/api/auth/passkey/options` | ❌ 未对接 | 16283 |
| POST | `/api/auth/passkey/register` | ❌ 未对接 | 16343 |
| POST | `/api/auth/passkey/register/options` | ❌ 未对接 | 16327 |
| POST | `/api/auth/passkeys` | ❌ 未对接 | 16374 |
| GET | `/api/auth/status` | ✅ 已对接 | 12038 |

### 2. 系统健康与控制 — 8 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/admin/reload` | ❌ 未对接 | 14431 |
| POST | `/api/csp-report` | ❌ 未对接 | 13782 |
| GET | `/api/health/agent` | ❌ 未对接 | 12247 |
| POST | `/api/health/restart` | ❌ 未对接 | 13846 |
| GET | `/api/logs` | ❌ 未对接 | 12241 |
| POST | `/api/shutdown` | ❌ 未对接 | 13843 |
| GET | `/api/system/health` | ❌ 未对接 | 12253 |
| GET | `/health` | ✅ 已对接 | 12244 |

### 3. 模型与提供商 — 14 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/default-model` | ✅ 已对接 | 14324 |
| GET | `/api/model/auxiliary` | ❌ 未对接 | 12284 |
| POST | `/api/model/set` | ❌ 未对接 | 14337 |
| GET | `/api/models` | ✅ 已对接 | 12257 |
| GET | `/api/models/live` | ✅ 已对接 | 12278 |
| POST | `/api/models/refresh` | ✅ 已对接 | 14386 |
| GET | `/api/provider/cost-history` | ❌ 未对接 | 12331 |
| GET | `/api/provider/quota` | ❌ 未对接 | 12317 |
| GET | `/api/providers` | ⚠️ Client 已定义 | 12304 |
| POST | `/api/providers` | ⚠️ Client 已定义 | 14358 |
| POST | `/api/providers/delete` | ❌ 未对接 | 14370 |
| POST | `/api/providers/self-hosted` | ❌ 未对接 | 14379 |
| GET | `/api/reasoning` | ⚠️ Client 已定义 | 12401 |
| POST | `/api/reasoning` | ⚠️ Client 已定义 | 14394 |

### 4. 设置与配置 — 3 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/settings` | ⚠️ Client 已定义 | 12341 |
| POST | `/api/settings` | ⚠️ Client 已定义 | 15513 |
| GET | `/api/transcribe/capability` | ❌ 未对接 | 12398 |

### 5. 插件/扩展/更新 — 13 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/extensions/install` | ❌ 未对接 | 13946 |
| GET | `/api/extensions/registry` | ❌ 未对接 | 12426 |
| POST | `/api/extensions/sidecar-proxy-consent` | ❌ 未对接 | 13926 |
| GET | `/api/extensions/status` | ❌ 未对接 | 12421 |
| POST | `/api/extensions/toggle` | ❌ 未对接 | 13912 |
| POST | `/api/extensions/uninstall` | ❌ 未对接 | 13960 |
| GET | `/api/plugins` | ❌ 未对接 | 12315 |
| POST | `/api/updates/apply` | ⚠️ Client 已定义 | 16101 |
| GET | `/api/updates/check` | ⚠️ Client 已定义 | 13226 |
| POST | `/api/updates/check` | ⚠️ Client 已定义 | 13888 |
| POST | `/api/updates/clear_lock` | ❌ 未对接 | 16127 |
| POST | `/api/updates/force` | ❌ 未对接 | 16116 |
| POST | `/api/updates/summary` | ❌ 未对接 | 16142 |

### 6. 入驻引导 — 7 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/onboarding/complete` | ❌ 未对接 | 15722 |
| POST | `/api/onboarding/oauth/cancel` | ❌ 未对接 | 15699 |
| GET | `/api/onboarding/oauth/poll` | ❌ 未对接 | 13357 |
| POST | `/api/onboarding/oauth/start` | ❌ 未对接 | 15689 |
| POST | `/api/onboarding/probe` | ❌ 未对接 | 15731 |
| POST | `/api/onboarding/setup` | ❌ 未对接 | 15705 |
| GET | `/api/onboarding/status` | ❌ 未对接 | 12418 |

### 7. Profile/Personality — 7 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/personalities` | ⚠️ Client 已定义 | 13162 |
| POST | `/api/personality/set` | ⚠️ Client 已定义 | 14501 |
| GET | `/api/profile/active` | ❌ 未对接 | 13544 |
| POST | `/api/profile/create` | ⚠️ Client 已定义 | 15455 |
| POST | `/api/profile/delete` | ❌ 未对接 | 15495 |
| POST | `/api/profile/switch` | ✅ 已对接 | 15409 |
| GET | `/api/profiles` | ✅ 已对接 | 13523 |

### 8. 指令系统 — 5 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/commands` | ⚠️ Client 已定义 | 13211 |
| GET | `/api/commands/bundles` | ❌ 未对接 | 13215 |
| POST | `/api/commands/bundles/resolve` | ❌ 未对接 | 15350 |
| POST | `/api/commands/exec` | ❌ 未对接 | 15366 |
| GET | `/api/commands/moa/resolve` | ❌ 未对接 | 13219 |

### 9. 仪表盘/MCP/笔记/回滚 — 15 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/dashboard/config` | ❌ 未对接 | 12294 |
| POST | `/api/dashboard/config` | ❌ 未对接 | 13986 |
| GET | `/api/dashboard/status` | ❌ 未对接 | 12288 |
| GET | `/api/mcp/servers` | ❌ 未对接 | 13576 |
| DELETE | `/api/mcp/servers/{name}` | ⚠️ 部分实现(路径参数) | 16470 |
| PATCH | `/api/mcp/servers/{name}` | ⚠️ 部分实现(路径参数) | 16442 |
| PUT | `/api/mcp/servers/{name}` | ⚠️ 部分实现(路径参数) | 16506 |
| GET | `/api/mcp/tools` | ❌ 未对接 | 13580 |
| GET | `/api/notes/item` | ❌ 未对接 | 13587 |
| GET | `/api/notes/search` | ❌ 未对接 | 13585 |
| GET | `/api/notes/sources` | ❌ 未对接 | 13583 |
| GET | `/api/project-os/dashboard` | ❌ 未对接 | 12140 |
| GET | `/api/rollback/diff` | ❌ 未对接 | 13605 |
| GET | `/api/rollback/list` | ❌ 未对接 | 13591 |
| POST | `/api/rollback/restore` | ❌ 未对接 | 16408 |

### 10. 会话管理 — 44 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/session` | ✅ 已对接 | 12464 |
| POST | `/api/session/anchor-scene` | ❌ 未对接 | 14450 |
| POST | `/api/session/archive` | ✅ 已对接 | 15821 |
| POST | `/api/session/branch` | ✅ 已对接 | 14994 |
| POST | `/api/session/clear` | ❌ 未对接 | 14859 |
| POST | `/api/session/compress` | ✅ 已对接 | 15110 |
| POST | `/api/session/compress/start` | ❌ 未对接 | 15107 |
| GET | `/api/session/compress/status` | ❌ 未对接 | 12459 |
| POST | `/api/session/compression-recovery/start` | ❌ 未对接 | 14230 |
| POST | `/api/session/conversation-rounds` | ❌ 未对接 | 15113 |
| POST | `/api/session/delete` | ✅ 已对接 | 14744 |
| POST | `/api/session/draft` | ❌ 未对接 | 14576 |
| POST | `/api/session/duplicate` | ❌ 未对接 | 14233 |
| GET | `/api/session/events/:session_id` | ❌ 未对接 | 13308 |
| GET | `/api/session/export` | ✅ 已对接 | 13120 |
| POST | `/api/session/handoff-summary` | ❌ 未对接 | 15116 |
| POST | `/api/session/import` | ❌ 未对接 | 16097 |
| POST | `/api/session/import_cli` | ❌ 未对接 | 16244 |
| GET | `/api/session/lineage/report` | ❌ 未对接 | 12974 |
| POST | `/api/session/move` | ✅ 已对接 | 15911 |
| POST | `/api/session/new` | ✅ 已对接 | 14097 |
| POST | `/api/session/pin` | ✅ 已对接 | 15749 |
| GET | `/api/session/recovery/audit` | ❌ 未对接 | 12983 |
| POST | `/api/session/recovery/repair-safe` | ❌ 未对接 | 13974 |
| POST | `/api/session/rename` | ✅ 已对接 | 14453 |
| POST | `/api/session/retry` | ✅ 已对接 | 15119 |
| GET | `/api/session/status` | ⚠️ Client 已定义 | 12987 |
| GET | `/api/session/stream` | ❌ 未对接 | 13348 |
| POST | `/api/session/title/regenerate` | ❌ 未对接 | 14477 |
| POST | `/api/session/toolsets` | ❌ 未对接 | 14549 |
| POST | `/api/session/truncate` | ✅ 已对接 | 14951 |
| POST | `/api/session/undo` | ✅ 已对接 | 15135 |
| POST | `/api/session/update` | ✅ 已对接 | 14670 |
| GET | `/api/session/usage` | ❌ 未对接 | 13004 |
| POST | `/api/session/worktree/remove` | ❌ 未对接 | 14721 |
| GET | `/api/session/worktree/status` | ❌ 未对接 | 12440 |
| GET | `/api/session/yolo` | ⚠️ Client 已定义 | 12998 |
| POST | `/api/session/yolo` | ⚠️ Client 已定义 | 15159 |
| GET | `/api/sessions` | ✅ 已对接 | 13021 |
| POST | `/api/sessions/cleanup` | ❌ 未对接 | 14444 |
| POST | `/api/sessions/cleanup_zero_message` | ❌ 未对接 | 14447 |
| GET | `/api/sessions/events` | ❌ 未对接 | 13305 |
| GET | `/api/sessions/gateway/stream` | ❌ 未对接 | 13302 |
| GET | `/api/sessions/search` | ✅ 已对接 | 13144 |

### 11. 会话列表/文件/媒体 — 26 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/escape/authorize` | ❌ 未对接 | 13885 |
| GET | `/api/escape/file/raw` | ❌ 未对接 | 13318 |
| GET | `/api/escape/file/read` | ❌ 未对接 | 13327 |
| GET | `/api/escape/list` | ❌ 未对接 | 13150 |
| GET | `/api/file` | ✅ 已对接 | 13324 |
| POST | `/api/file/create` | ❌ 未对接 | 15307 |
| POST | `/api/file/create-dir` | ❌ 未对接 | 15316 |
| POST | `/api/file/delete` | ✅ 已对接 | 15298 |
| POST | `/api/file/move` | ❌ 未对接 | 15313 |
| POST | `/api/file/office-save` | ❌ 未对接 | 15304 |
| POST | `/api/file/open-vscode` | ❌ 未对接 | 15325 |
| POST | `/api/file/path` | ❌ 未对接 | 15322 |
| GET | `/api/file/raw` | ✅ 已对接 | 13315 |
| POST | `/api/file/rename` | ✅ 已对接 | 15310 |
| POST | `/api/file/reveal` | ❌ 未对接 | 15319 |
| POST | `/api/file/save` | ❌ 未对接 | 15301 |
| GET | `/api/folder/download` | ✅ 已对接 | 13321 |
| GET | `/api/list` | ✅ 已对接 | 13147 |
| GET | `/api/media` | ⚠️ Client 已定义 | 13312 |
| POST | `/api/workspace/upload` | ❌ 未对接 | 13853 |
| GET | `/api/workspaces` | ✅ 已对接 | 13123 |
| POST | `/api/workspaces/add` | ✅ 已对接 | 15329 |
| POST | `/api/workspaces/remove` | ✅ 已对接 | 15332 |
| POST | `/api/workspaces/rename` | ✅ 已对接 | 15335 |
| POST | `/api/workspaces/reorder` | ⚠️ Client 已定义 | 15338 |
| GET | `/api/workspaces/suggest` | ✅ 已对接 | 13133 |

### 12. 聊天与流式 — 20 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/approval/inject_test` | ❌ 未对接 | 13336 |
| GET | `/api/approval/pending` | ⚠️ Client 已定义 | 13330 |
| POST | `/api/approval/respond` | ✅ 已对接 | 15342 |
| GET | `/api/approval/stream` | ⚠️ Client 已定义 | 13333 |
| POST | `/api/background` | ⚠️ Client 已定义 | 15184 |
| GET | `/api/background/status` | ⚠️ Client 已定义 | 13014 |
| POST | `/api/bg-task-complete-ack` | ❌ 未对接 | 15190 |
| POST | `/api/btw` | ⚠️ Client 已定义 | 15181 |
| POST | `/api/chat` | ❌ 未对接 | 15196 |
| GET | `/api/chat/cancel` | ✅ 已对接 | 13281 |
| POST | `/api/chat/start` | ✅ 已对接 | 15193 |
| POST | `/api/chat/steer` | ✅ 已对接 | 15199 |
| GET | `/api/chat/stream` | ⚠️ Client 已定义 | 13296 |
| GET | `/api/chat/stream/status` | ✅ 已对接 | 13266 |
| GET | `/api/clarify/inject_test` | ❌ 未对接 | 13351 |
| GET | `/api/clarify/pending` | ⚠️ Client 已定义 | 13342 |
| POST | `/api/clarify/respond` | ✅ 已对接 | 15346 |
| GET | `/api/clarify/stream` | ⚠️ Client 已定义 | 13345 |
| POST | `/api/goal` | ⚠️ Client 已定义 | 15187 |
| POST | `/api/process-complete-ack` | ❌ 未对接 | 13800 |

### 13. 终端 — 5 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/terminal/close` | ❌ 未对接 | 15212 |
| POST | `/api/terminal/input` | ❌ 未对接 | 15206 |
| GET | `/api/terminal/output` | ❌ 未对接 | 13299 |
| POST | `/api/terminal/resize` | ❌ 未对接 | 15209 |
| POST | `/api/terminal/start` | ❌ 未对接 | 15203 |

### 14. 分享/上传/语音 — 7 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/share/<token>` | ❌ 未对接 | 12078 |
| POST | `/api/share/create` | ❌ 未对接 | 14013 |
| POST | `/api/share/revoke` | ❌ 未对接 | 14058 |
| POST | `/api/transcribe` | ⚠️ Client 已定义 | 13856 |
| POST | `/api/tts` | ⚠️ Client 已定义 | 13859 |
| POST | `/api/upload` | ⚠️ Client 已定义 | 13849 |
| POST | `/api/upload/extract` | ❌ 未对接 | 13851 |

### 15. Git/Workspaces/Projects — 16 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/git-info` | ⚠️ Client 已定义 | 13184 |
| GET | `/api/git/branches` | ✅ 已对接 | 13156 |
| POST | `/api/git/checkout` | ✅ 已对接 | 15291 |
| POST | `/api/git/commit` | ✅ 已对接 | 15276 |
| POST | `/api/git/commit-message` | ⚠️ Client 已定义 | 15270 |
| POST | `/api/git/commit-message-selected` | ⚠️ Client 已定义 | 15273 |
| POST | `/api/git/commit-selected` | ⚠️ Client 已定义 | 15279 |
| GET | `/api/git/diff` | ✅ 已对接 | 13159 |
| POST | `/api/git/discard` | ✅ 已对接 | 15267 |
| POST | `/api/git/fetch` | ✅ 已对接 | 15282 |
| POST | `/api/git/pull` | ✅ 已对接 | 15285 |
| POST | `/api/git/push` | ✅ 已对接 | 15288 |
| POST | `/api/git/stage` | ✅ 已对接 | 15261 |
| POST | `/api/git/stash-checkout` | ⚠️ Client 已定义 | 15294 |
| GET | `/api/git/status` | ✅ 已对接 | 13153 |
| POST | `/api/git/unstage` | ✅ 已对接 | 15264 |

### 16. Cron — 13 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/crons` | ✅ 已对接 | 13375 |
| POST | `/api/crons/create` | ✅ 已对接 | 15218 |
| POST | `/api/crons/delete` | ✅ 已对接 | 15232 |
| GET | `/api/crons/delivery-options` | ⚠️ Client 已定义 | 13434 |
| GET | `/api/crons/history` | ❌ 未对接 | 13407 |
| GET | `/api/crons/output` | ✅ 已对接 | 13400 |
| POST | `/api/crons/pause` | ✅ 已对接 | 15246 |
| GET | `/api/crons/recent` | ❌ 未对接 | 13421 |
| POST | `/api/crons/resume` | ✅ 已对接 | 15253 |
| GET | `/api/crons/run` | ✅ 已对接 | 13414 |
| POST | `/api/crons/run` | ✅ 已对接 | 15239 |
| GET | `/api/crons/status` | ⚠️ Client 已定义 | 13428 |
| POST | `/api/crons/update` | ✅ 已对接 | 15225 |

### 17. Kanban — 25 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/kanban/assignees` | ⚠️ Client 已定义 | 12143 |
| GET | `/api/kanban/board` | ✅ 已对接 | 12143 |
| GET | `/api/kanban/boards` | ✅ 已对接 | 12143 |
| POST | `/api/kanban/boards` | ✅ 已对接 | 13979 |
| DELETE | `/api/kanban/boards/{slug}` | ⚠️ 部分实现(路径参数) | 16481 |
| PATCH | `/api/kanban/boards/{slug}` | ⚠️ 部分实现(路径参数) | 16445 |
| POST | `/api/kanban/boards/{slug}/switch` | ⚠️ 部分实现(路径参数) | 13979 |
| GET | `/api/kanban/config` | ✅ 已对接 | 12143 |
| PATCH | `/api/kanban/config` | ✅ 已对接 | 16445 |
| POST | `/api/kanban/dispatch` | ⚠️ Client 已定义 | 13979 |
| GET | `/api/kanban/events` | ✅ 已对接 | 12143 |
| GET | `/api/kanban/events/stream` | ⚠️ Client 已定义 | 12143 |
| DELETE | `/api/kanban/links` | ⚠️ Client 已定义 | 16481 |
| POST | `/api/kanban/links` | ⚠️ Client 已定义 | 13979 |
| POST | `/api/kanban/links/delete` | ⚠️ Client 已定义 | 13979 |
| GET | `/api/kanban/stats` | ⚠️ Client 已定义 | 12143 |
| POST | `/api/kanban/tasks` | ✅ 已对接 | 13979 |
| POST | `/api/kanban/tasks/bulk` | ⚠️ Client 已定义 | 13979 |
| GET | `/api/kanban/tasks/{id}` | ⚠️ 部分实现(路径参数) | 12143 |
| PATCH | `/api/kanban/tasks/{id}` | ⚠️ 部分实现(路径参数) | 16445 |
| POST | `/api/kanban/tasks/{id}/block` | ⚠️ 部分实现(路径参数) | 13979 |
| POST | `/api/kanban/tasks/{id}/comments` | ⚠️ 部分实现(路径参数) | 13979 |
| GET | `/api/kanban/tasks/{id}/log` | ⚠️ 部分实现(路径参数) | 12143 |
| POST | `/api/kanban/tasks/{id}/patch` | ⚠️ 部分实现(路径参数) | 13979 |
| POST | `/api/kanban/tasks/{id}/unblock` | ⚠️ 部分实现(路径参数) | 13979 |

### 18. Skills/Memory/Insights/Prompts/Wiki — 15 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| GET | `/api/insights` | ✅ 已对接 | 12138 |
| GET | `/api/memory` | ✅ 已对接 | 13519 |
| POST | `/api/memory/write` | ⚠️ Client 已定义 | 15402 |
| DELETE | `/api/prompts` | ✅ 已对接 | 16473 |
| GET | `/api/prompts` | ✅ 已对接 | 13117 |
| POST | `/api/prompts` | ✅ 已对接 | 13998 |
| GET | `/api/skills` | ✅ 已对接 | 13442 |
| GET | `/api/skills/content` | ⚠️ Client 已定义 | 13484 |
| POST | `/api/skills/delete` | ❌ 未对接 | 15395 |
| POST | `/api/skills/save` | ❌ 未对接 | 15392 |
| POST | `/api/skills/toggle` | ✅ 已对接 | 15398 |
| GET | `/api/skills/usage` | ❌ 未对接 | 13448 |
| GET | `/api/wiki/browse` | ❌ 未对接 | 12155 |
| GET | `/api/wiki/page` | ❌ 未对接 | 12170 |
| GET | `/api/wiki/status` | ❌ 未对接 | 12153 |

### 其他 — 1 个

| 方法 | 路径 | 客户端 | routes.py |
|---|---|---|---|
| POST | `/api/client-events/log` | ❌ 未对接 | 13862 |

---

## 3. 三层关系说明

```
Hermes WebUI 后端 routes.py（222 路径 = 后端全部能力）
      │  ① 蓝本 Endpoints.swift 定义的产品面（123 case，Hermex iOS 已实现）
      │  ② 客户端 endpoints.dart 定义表（对齐①，123 路径字面量）
      │  ③ 客户端 api_client*.dart 扩展（136 方法，几乎全覆盖②）
      │  ④ features/* UI 落地（75 端点有真实页面/交互）
      └── ⑤ 后端有但①②③④都没有 = 本审计的 119 个「未对接功能」
```

- 蓝本产品面（Endpoints.swift）客户端 **100% 已定义**（②），但 UI 只落了 75（④）。
- **⑤ 的 119 个未对接 = 后端 fork 相对标准 hermes-webui 的深度增强**，多数是高频实用功能（Terminal、Wiki、Share、OIDC、Rollback、Dashboard、MCP 等）。

---

## 4. 未对接功能差距清单（核心产出）

> 以下皆为「后端已有接口、客户端完全未定义/未接」的功能，按用户可见功能分组。

### 4.1 完全未对接（后端有、客户端无）— 119 个

#### 认证与安全 — 8 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/auth/oidc/callback` | 12004 |
| GET | `/api/auth/oidc/start` | 11982 |
| POST | `/api/auth/passkey/delete` | 16359 |
| POST | `/api/auth/passkey/login` | 16298 |
| POST | `/api/auth/passkey/options` | 16283 |
| POST | `/api/auth/passkey/register` | 16343 |
| POST | `/api/auth/passkey/register/options` | 16327 |
| POST | `/api/auth/passkeys` | 16374 |

#### 系统健康与控制 — 7 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/admin/reload` | 14431 |
| POST | `/api/csp-report` | 13782 |
| GET | `/api/health/agent` | 12247 |
| POST | `/api/health/restart` | 13846 |
| GET | `/api/logs` | 12241 |
| POST | `/api/shutdown` | 13843 |
| GET | `/api/system/health` | 12253 |

#### 模型与提供商 — 7 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/model/auxiliary` | 12284 |
| POST | `/api/model/set` | 14337 |
| POST | `/api/models/refresh` | 14386 |
| GET | `/api/provider/cost-history` | 12331 |
| GET | `/api/provider/quota` | 12317 |
| POST | `/api/providers/delete` | 14370 |
| POST | `/api/providers/self-hosted` | 14379 |

#### 插件/扩展/更新 — 10 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/extensions/install` | 13946 |
| GET | `/api/extensions/registry` | 12426 |
| POST | `/api/extensions/sidecar-proxy-consent` | 13926 |
| GET | `/api/extensions/status` | 12421 |
| POST | `/api/extensions/toggle` | 13912 |
| POST | `/api/extensions/uninstall` | 13960 |
| GET | `/api/plugins` | 12315 |
| POST | `/api/updates/clear_lock` | 16127 |
| POST | `/api/updates/force` | 16116 |
| POST | `/api/updates/summary` | 16142 |

#### 入驻引导 — 7 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/onboarding/complete` | 15722 |
| POST | `/api/onboarding/oauth/cancel` | 15699 |
| GET | `/api/onboarding/oauth/poll` | 13357 |
| POST | `/api/onboarding/oauth/start` | 15689 |
| POST | `/api/onboarding/probe` | 15731 |
| POST | `/api/onboarding/setup` | 15705 |
| GET | `/api/onboarding/status` | 12418 |

#### Profile/Personality — 2 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/profile/active` | 13544 |
| POST | `/api/profile/delete` | 15495 |

#### 指令系统 — 4 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/commands/bundles` | 13215 |
| POST | `/api/commands/bundles/resolve` | 15350 |
| POST | `/api/commands/exec` | 15366 |
| GET | `/api/commands/moa/resolve` | 13219 |

#### 仪表盘/MCP/笔记/回滚 — 12 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/dashboard/config` | 12294 |
| POST | `/api/dashboard/config` | 13986 |
| GET | `/api/dashboard/status` | 12288 |
| GET | `/api/mcp/servers` | 13576 |
| GET | `/api/mcp/tools` | 13580 |
| GET | `/api/notes/item` | 13587 |
| GET | `/api/notes/search` | 13585 |
| GET | `/api/notes/sources` | 13583 |
| GET | `/api/project-os/dashboard` | 12140 |
| GET | `/api/rollback/diff` | 13605 |
| GET | `/api/rollback/list` | 13591 |
| POST | `/api/rollback/restore` | 16408 |

#### 会话管理 — 25 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/session/anchor-scene` | 14450 |
| POST | `/api/session/clear` | 14859 |
| POST | `/api/session/compress/start` | 15107 |
| GET | `/api/session/compress/status` | 12459 |
| POST | `/api/session/compression-recovery/start` | 14230 |
| POST | `/api/session/conversation-rounds` | 15113 |
| POST | `/api/session/draft` | 14576 |
| POST | `/api/session/duplicate` | 14233 |
| GET | `/api/session/events/:session_id` | 13308 |
| POST | `/api/session/handoff-summary` | 15116 |
| POST | `/api/session/import` | 16097 |
| POST | `/api/session/import_cli` | 16244 |
| GET | `/api/session/lineage/report` | 12974 |
| GET | `/api/session/recovery/audit` | 12983 |
| POST | `/api/session/recovery/repair-safe` | 13974 |
| GET | `/api/session/stream` | 13348 |
| POST | `/api/session/title/regenerate` | 14477 |
| POST | `/api/session/toolsets` | 14549 |
| GET | `/api/session/usage` | 13004 |
| POST | `/api/session/worktree/remove` | 14721 |
| GET | `/api/session/worktree/status` | 12440 |
| POST | `/api/sessions/cleanup` | 14444 |
| POST | `/api/sessions/cleanup_zero_message` | 14447 |
| GET | `/api/sessions/events` | 13305 |
| GET | `/api/sessions/gateway/stream` | 13302 |

#### 会话列表/文件/媒体 — 13 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/escape/authorize` | 13885 |
| GET | `/api/escape/file/raw` | 13318 |
| GET | `/api/escape/file/read` | 13327 |
| GET | `/api/escape/list` | 13150 |
| POST | `/api/file/create` | 15307 |
| POST | `/api/file/create-dir` | 15316 |
| POST | `/api/file/move` | 15313 |
| POST | `/api/file/office-save` | 15304 |
| POST | `/api/file/open-vscode` | 15325 |
| POST | `/api/file/path` | 15322 |
| POST | `/api/file/reveal` | 15319 |
| POST | `/api/file/save` | 15301 |
| POST | `/api/workspace/upload` | 13853 |

#### 聊天与流式 — 5 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/approval/inject_test` | 13336 |
| POST | `/api/bg-task-complete-ack` | 15190 |
| POST | `/api/chat` | 15196 |
| GET | `/api/clarify/inject_test` | 13351 |
| POST | `/api/process-complete-ack` | 13800 |

#### 终端 — 5 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/terminal/close` | 15212 |
| POST | `/api/terminal/input` | 15206 |
| GET | `/api/terminal/output` | 13299 |
| POST | `/api/terminal/resize` | 15209 |
| POST | `/api/terminal/start` | 15203 |

#### 分享/上传/语音 — 5 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/share/<token>` | 12078 |
| POST | `/api/share/create` | 14013 |
| POST | `/api/share/revoke` | 14058 |
| GET | `/api/transcribe/capability` | 12398 |
| POST | `/api/upload/extract` | 13851 |

#### Cron — 2 个

| 方法 | 路径 | routes.py |
|---|---|---|
| GET | `/api/crons/history` | 13407 |
| GET | `/api/crons/recent` | 13421 |

#### Skills/Memory/Insights/Prompts/Wiki — 6 个

| 方法 | 路径 | routes.py |
|---|---|---|
| POST | `/api/skills/delete` | 15395 |
| POST | `/api/skills/save` | 15392 |
| GET | `/api/skills/usage` | 13448 |
| GET | `/api/wiki/browse` | 12155 |
| GET | `/api/wiki/page` | 12170 |
| GET | `/api/wiki/status` | 12153 |

---

### 4.2 客户端已封装、未接 UI（24 组 / 44 项）

> 这些端点客户端 Client 层已就绪（endpoints.dart + api_client*.dart），**只差 UI 绑定**，对接成本最低。

| Client 端点 | 未接 UI 原因 |
|---|---|
| `POST /api/auth/logout` | 设置页或侧边栏未提供显式的「退出登录」按钮，客户端通过重新配置服务器或清除 Cookie 切换身份。 |
| `GET /api/session/status` | 会话状态查询。聊天断线检测直接使用了 GET /api/chat/stream/status，因此该独立会话状态接口未被直接调用。 |
| `POST /api/goal` | 长程目标任务提交接口已封装，但聊天输入框目前未提供 `/goal` 专用指令解析 UI。 |
| `POST /api/btw` | BTW 侧边提问接口已封装，但聊天页面未增加悬浮提问气泡或弹窗入口。 |
| `POST / GET /api/background ／ /api/background/status` | 后台独立会话任务提交与状态轮询接口已封装，UI 暂未实现后台任务管理面板。 |
| `GET /api/approval/pending ／ /api/approval/stream` | 审批流当前直接通过主聊天流 `/api/chat/stream` 下发的 `approval`/`initial` SSE 事件消费，独立的审批轮询/流端点未单独使用。 |
| `GET /api/clarify/pending ／ /api/clarify/stream` | 澄清流当前直接通过主聊天流 `/api/chat/stream` 下发的 `clarify`/`initial` SSE 事件消费，独立的澄清轮询/流端点未单独使用。 |
| `POST /api/workspaces/reorder` | 工作区列表目前仅支持添加、删除、重命名与路径补全建议，未实现拖拽重排交互。 |
| `GET /api/media` | 媒体附件通过 `ChatMediaView` 直接构造 `/api/media?path=...` 图片 URL 加载，ApiClient 的二进制下载方法未被直接显式调用。 |
| `GET /api/git-info` | Git 功能页已完整使用 `/api/git/status` 与 `/api/git/branches` 获取全量分支与变更信息，基础元数据接口无需重复调用。 |
| `POST /api/git/stash-checkout` | Git 分支切换当前统一使用 `gitCheckout(dirty_mode: block)`，未单独提供带自动暂存的切换选项。 |
| `POST /api/git/commit-selected` | Git 提交目前采用标准的 Stage 暂存机制 + `/api/git/commit`，未提供不暂存直接提交勾选文件的操作。 |
| `POST /api/git/commit-message ／ commit-message-selected` | AI 生成 Commit 提交信息端点（带 120s 超时配置）已完备，Git 提交框目前支持手动输入，尚未挂载「AI 生成提交信息」按钮。 |
| `GET /api/commands` | 服务端斜杠指令列表获取端点已封装，聊天输入框当前尚未接服务端动态指令补全。 |
| `GET /api/providers` | AI 提供商列表。设置页模型选择直接调用 `models()` 与 `modelsLive()`，未单独请求 providers 字典。 |
| `POST /api/settings (POST 更新)` | 设置页当前支持配置服务器地址、自定义 Header 与默认模型，未暴露服务端 CLI/Claude Code 会话过滤开关。 |
| `GET / POST /api/updates/check ／ /api/updates/apply` | 服务端版本更新检测与一键升级重启接口已封装，设置页目前未放置在线更新按钮。 |
| `GET / POST /api/personalities ／ /api/personality/set` | 预置人设列表与切换端点已封装，UI 暂未实现独立的人设选择器。 |
| `POST /api/profile/create` | Profile 切换功能已在设置页完整落地，但新建 Profile 的表单弹窗尚未实现。 |
| `GET /api/crons/status ／ /api/crons/delivery-options` | 定时任务管理页已对接列表、创建、编辑、启停、立即运行、查看输出，但未单独调用全局 status 与 delivery-options 接口。 |
| `POST / PATCH / DELETE /api/kanban 看板管理与高级卡片操作` | 看板客户端已完整实现核心业务闭环（查看快照、列流转、实时事件流、创建卡片、设置状态、添加评论、查看卡片详情），其余高级接口（创建/编辑看板、批量操作、依赖链路、阻塞标记、调度器分发、Worker 日志）已在 Client 层全部封装完毕，等待后续 UI 迭代接入。 |
| `POST /api/memory/write` | 记忆页面当前为只读展示（GET `/api/memory`），尚未提供手动编辑/写回记忆的 UI 入口。 |
| `GET /api/skills/content` | 技能页面当前实现了技能列表展示与启用/禁用 Toggle 开关，未提供点击查看单个 Skill 详细 Prompt 指令的弹窗。 |
| `POST /api/transcribe ／ /api/tts` | 多模态语音听写（Transcribe）与语音朗读（TTS）已在 ApiClient 完整实现 multipart 与字节流处理，输入框与消息列表尚未挂载麦克风录音与朗读播放按钮。 |

### 4.3 部分实现（路径参数形态 △）

> kanban/mcp/session 等含 `{param}` 路径参数的端点，客户端仅覆盖了常用子集：

- **kanban 高级**：boards 增改删/switch、dispatch、stats、assignees、worker log、bulk、block/unblock、links 依赖、comments → Client 23 方法全封装，UI 只落了核心闭环
- **mcp servers**：客户端完全未定义（GET/PUT/PATCH/DELETE /api/mcp/servers + tools）
- **session/recovery、file/office-save、session/compress/start** 等含 param 形态均未对接

---

## 5. SSE / WS 协议现状（客户端已消费）

### 5.1 SSE 事件消费表（17 种，chat_controller.dart 全量消费）

| 事件 | 载荷要点 | 消费位置 |
|---|---|---|
| ``token`` | `text: String` | `lib/features/chat/chat_controller.dart:861, 914-980` |
| ``interim_assistant`` | `text: String, already_streamed: bool` | `lib/features/chat/chat_controller.dart:863, 1021` |
| ``reasoning`` | `text: String` | `lib/features/chat/chat_controller.dart:865, 1032` |
| ``tool`` | `ToolStreamEvent: {name, stableId, preview, args}` | `lib/features/chat/chat_controller.dart:867, 1058` |
| ``tool_complete`` | `ToolStreamEvent: {name, stableId, preview, duration, isError}` | `lib/features/chat/chat_controller.dart:869, 1083` |
| ``title`` | `sessionId: String?, title: String?` | `lib/features/chat/chat_controller.dart:871, 1108` |
| ``metering`` | `tps: double?, tpsAvailable: bool, estimated: bool` | `lib/features/chat/chat_controller.dart:873, 1120` |
| ``done`` | `DoneStreamEvent: {usage, session}` | `lib/features/chat/chat_controller.dart:885, 1137` |
| ``initial`` | `Map<String, Object?> (根据字段判定)` | `lib/core/api/sse_client.dart:493 |
| ``approval`` | `ApprovalPendingResponse` | `lib/features/chat/chat_controller.dart:887, 1172` |
| ``clarify`` | `ClarificationPendingResponse` | `lib/features/chat/chat_controller.dart:889, 1195` |
| ``pending_steer_leftover`` | `text: String` | `lib/features/chat/chat_controller.dart:891, 1218` |
| ``stream_end`` | `(空)` | `lib/features/chat/chat_controller.dart:893, 1227` |
| ``cancel`` | `(空)` | `lib/features/chat/chat_controller.dart:895, 1238` |
| ``error / apperror`` | `error: String, message: String` | `lib/features/chat/chat_controller.dart:897, 1248` |
| ``transportError`` | `message: String` | `lib/features/chat/chat_controller.dart:899, 1260` |
| ``:comment (heartbeat)`` | `(空行注释)` | `lib/features/chat/chat_controller.dart:901, 1315` |

### 5.2 Kanban 事件流（SSE 帧协议，非标准 WS）
：WS（Kanban 事件流）消费说明

### 1. 协议实现本质

- 任务书中的「WS」在当前 Hermex 客户端实现中为 **Kanban 独立帧协议（基于 SSE 传输实现）**，文件位于 `lib/core/api/ws_client.dart` 中的 `KanbanEventStreamClient`（对齐 Swift 版 `KanbanEventStreamClient.swift` 架构，使用 GET `/api/kanban/events/stream?board={slug}&since={cursor}`）。

- 项目虽然引入了 `web_socket_channel` 基础依赖，但所有看板实时通信均通过该定制帧流完成。

### 2. 帧结构与解码器 (`KanbanStreamFrameDecoder`)

- **`hello` 帧 (`KanbanHelloFrame`)**：载荷包含 `{cursor: int, board: String}`（要求 `cursor >= 0` 且 `board` 非空）。连接成功时服务端首发，客户端记录当前游标基准。

- **`events` 帧 (`KanbanEventsFrame`)**：载荷包含 `{events: List<KanbanEvent>, cursor: int}`，`id:` 字段解析为 `frameId`。携带新增/更新的看板事件列表。

- **`malformed` 帧 (`KanbanMalformedFrame`)**：载荷缺失、游标无效或字段格式异常时本地识别为畸形帧，保证流不崩溃。

- **`ignored` 帧 (`KanbanIgnoredFrame`)**：非 `hello`/`events` 的未知事件类型静默丢弃。

### 3. Feature 层

---

## 6. 后端关键对接陷阱（AGY 审计发现，对接前必读）

1. **多 Profile 隔离 → 409**：访问/操作他 Profile 会话返回 `409 Conflict` + `code: session_profile_mismatch` + `profile` 字段，客户端须捕获并提示切换 Profile，**不得当 404 自愈清空 URL**（routes.py 全程）。
2. **子代理会话只读守卫**：subagent 衍生会话调写/改/删/重试/取消端点一律 `400`，UI 需置灰编辑按钮（`_session_is_subagent_view_only`）。
3. **SSE 断线重放**：`/api/chat/stream?stream_id=X&replay=1&after_seq=N` 从 run_journal 恢复；须过滤每 5s 的 `: keepalive` 心跳注释行。
4. **`/api/process-complete-ack` 已 410 废弃** → 统一用 `POST /api/bg-task-complete-ack`（响应带 X-Replaced-By 头）。
5. **`/api/crons/run` 双端点**：GET = 查单次运行 Markdown 日志（job_id+filename），POST = 手动触发（异步守护线程 + 防重入锁）。
6. **kanban 禁止直 PATCH status=running**：必须经 worker claim 调度，直接请求返回 400。
7. **`/api/media` 沙箱**：仅允许 HERMES_HOME、/tmp、工作区、MEDIA_ALLOWED_ROOTS，越界 403；`/api/file/raw?inline=1` 渲染 HTML 自动带 CSP Sandbox。
8. **onboarding 公网安全门禁**：未设置密码时仅局域网/本地可访问 onboarding 写接口，公网自动拦截（上云后注意）。
9. **`/api/updates/check`、`/api/reasoning`、`/api/settings`、`/api/dashboard/config`、`/api/session/yolo` 均为同路径双方法**（GET 查询/POST 写入），客户端方法名已按此设计。
10. **`/api/chat` POST 是独立低延迟通道**（非 SSE），区别于 /api/chat/stream，客户端未使用。


---

## 7. 后续对接建议优先级（P0 → P2）

### P0 — 高频刚需，建议下一迭代
- **交互式终端**（/api/terminal/start|input|output|resize|close）：后端已就绪，可做工作区内嵌终端页
- **会话导入/导出增强**（/api/session/import、import_cli、duplicate、clear）：补全会话管理面板
- **进度/标题增强**（/api/session/title/regenerate、draft、toolsets）：聊天体验优化
- **退出登录**（/api/auth/logout）：设置页显式登出（Client 已封装，只差按钮）

### P1 — 价值明确
- **OIDC / Passkey 登录**（/api/auth/oidc/* 5 个、passkey 6 个）：onboarding 增强，公网部署刚需
- **Wiki 知识库**（/api/wiki/status|browse|page）：会话侧边栏新功能
- **Rollback 快照回滚**（/api/rollback/list|diff|restore）：工作区健壮性
- **MCP 服务器管理**（/api/mcp/servers|tools）：配置页
- **AI 提交信息**（/api/git/commit-message*）：Git 页已有基础，挂按钮即可
- **语音输入/朗读**（/api/transcribe、/api/tts + capability）：输入框麦克风 + 消息朗读（Client 已封装）
- **人设选择器**（/api/personalities、set）：设置页（Client 已封装）
- **内存写入**（/api/memory/write）：记忆页只读→可编辑（Client 已封装）
- **技能 CRUD**（/api/skills/save|delete|usage）：技能页增强
- **Cron history/recent**（/api/crons/history|recent）：任务页运行历史

### P2 — 低频 / 运维向 / 生态
- **Extensions 管理**（/api/extensions/* 6 个）、**Plugins**（/api/plugins）、**Dashboard**（/api/dashboard/*）、**Project OS**（/api/project-os/dashboard）、**Notes（Joplin）**、**Share 分享**（/api/share/*）、**系统健康**（system/health、health/agent、restart、shutdown）、**admin/reload、sessions/cleanup、updates force/clear_lock/summary、client-events/log、inject_test（调试）、escape/*（沙箱逃生口）


---

## 8. 附录：审计方法与文件索引

- 后端权威路由表自动提取：`api/routes.py` dispatch 区 236 条（222 唯一路径），行号锚点 robot 校验
- AGY 并行 4 子代理（gemini-3.7-flash-high）：
  - `docs/specs/backend-api-details/domain_a_system-auth-config.md`（88 卡片：认证/系统/模型/设置/插件/onboarding/profile/指令/仪表盘/MCP/Notes/Rollback/ops）
  - `docs/specs/backend-api-details/domain_b_session-chat-files.md`（98 卡片：session 全系/chat/审批/澄清/终端/分享/上传/文件/媒体 + SSE 陷阱）
  - `docs/specs/backend-api-details/domain_c_tools-kanban-skills.md`（87 卡片：git/workspace/cron/kanban 25 子端点/skills/memory/insights/prompts/wiki/rollback）
  - `docs/specs/backend-api-details/client-bound-endpoints.md`（客户端 130 端点 × 136 方法三层链路 + SSE 17 事件 + 44 未用清单 + UI 落地对照表）
- Leader 独立复验：行号抽查（session/new=14097、transcribe/capability=12398、mcp=13576/13580/16442…）全部吻合；差距计算用脚本重新实现（两端独立交叉）
- 蓝本：`.reference/hermex-src/Networking/Endpoints.swift`（123 case）+ `docs/specs/api_spec.md`（客户端既有规格）

> ⚠️ 边界声明：本目录基于 **fork @ D:\hermes-webui（跑 :30002）当前代码**静态审计，不含协议级动态抓包验证；对接每个端点前建议用 `tools/fake_gateway` 契约测试或对真实服务器 curl 复核。
