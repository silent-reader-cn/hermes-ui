# 后端接口大全 · 域 A（系统 / 认证 / 配置 / 生态）

> 本文档由 Hermes WebUI 后端权威路由分发器 `api/routes.py`（26554 行）及 `api/` 下各核心模块全量源码静态审计生成。
> 所有端点严格以 `parsed.path` 分发位置为唯一权威行号锚点，逐项详细记录 HTTP 方法、行号、功能、入参、出参、鉴权要求与运维注意事项。

---

## 目录
1. [认证与密钥体系 (Auth, OIDC & Passkeys)](#1-认证与密钥体系-auth-oidc--passkeys)
2. [系统健康、控制与日志 (System Health, Control & Logs)](#2-系统健康控制与日志-system-health-control--logs)
3. [模型与推理配置 (Models, Reasoning & Providers)](#3-模型与推理配置-models-reasoning--providers)
4. [系统设置与配置 (Settings, Config & Admin)](#4-系统设置与配置-settings-config--admin)
5. [插件、扩展与更新 (Plugins, Extensions & Updates)](#5-插件扩展与更新-plugins-extensions--updates)
6. [引导入驻流程 (Onboarding)](#6-引导入驻流程-onboarding)
7. [Profile 与 Personality 管理 (Profiles & Personalities)](#7-profile-与-personality-管理-profiles--personalities)
8. [指令系统 (Commands & Bundles)](#8-指令系统-commands--bundles)
9. [仪表盘、MCP、笔记、回滚与运维确认 (Dashboard, MCP, Notes, Rollback & Acks)](#9-仪表盘mcp笔记回滚与运维确认-dashboard-mcp-notes-rollback--acks)
10. [语音能力 (Transcribe Capability)](#10-语音能力-transcribe-capability)
11. [域 A 未分类 / 疑点清单](#11-域-a-未分类--疑点清单)

---

## 1. 认证与密钥体系 (Auth, OIDC & Passkeys)

### GET /api/auth/oidc/start  (routes.py:11982)
- **功能**：发起 OIDC / OAuth2 单点登录授权重定向流程，生成带 CSRF state 与 nonce 的 IdP 授权 URL。
- **参数**：
  - Query: `?next=<path>`（可选，登录成功后跳转的目标页面相对路径，默认 `/`）。经过 `_safe_login_redirect_path()` 校验防 Open Redirect。
- **响应**：
  - HTTP 302 重定向到 OIDC IdP 授权页面（Header: `Location: <IdP_auth_url>`，`Cache-Control: no-store`）。
  - 错误时（如未配置 OIDC）：HTTP 404/4xx `{"error": "<msg>"}`。
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：底层调用 `api.auth_oidc.build_authorization_redirect()`。仅在 OIDC 启用配置有效时可用。

### GET /api/auth/oidc/callback  (routes.py:12004)
- **功能**：处理 OIDC Provider 授权后的回调，交换 ID Token / Access Token，建立 WebUI 登录会话并下发 Session Cookie。
- **参数**：
  - Query: `state`（必填，防 CSRF 状态令牌）、`code`（必填，授权码）、`error`（可选，IdP 错误码）、`error_description`（可选）。
- **响应**：
  - HTTP 302 重定向至原始请求路径（Header: `Location: <next_path>`，`Set-Cookie: hermes_session=...; Path=/; HttpOnly; SameSite=Lax`）。
  - 错误时：HTTP 400/401/404 `{"error": "<msg>"}`。
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：底层调用 `api.auth_oidc.complete_authorization_code_flow()` 及 `api.auth.create_session()`。

### GET /api/auth/status  (routes.py:12038)
- **功能**：获取当前服务的全局认证状态以及当前客户端的登录态、通行密钥配置、信任网关鉴权信息。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "auth_enabled": true,
    "logged_in": true,
    "oidc_enabled": false,
    "password_auth_enabled": true,
    "passwordless_enabled": false,
    "passkeys_enabled": false,
    "passkeys_count": 0,
    "passkey_feature_flag": true,
    "auth_disabled_acknowledged": false,
    "trusted_auth_enabled": false,
    "auth_type": "trusted",
    "user": "admin",
    "bound_profile": "default"
  }
  ```
- **认证**：豁免（属于 `PUBLIC_PATHS`，用于前端引导页和登录遮罩判断）。
- **备注**：若开启 trusted auth（反向代理鉴权），会解析上游请求头注入 user/profile 等绑定信息。

### POST /api/auth/login  (routes.py:16248)
- **功能**：口令密码登录验证，成功后建立会话并在响应头写入 Session Cookie。
- **参数**：
  - Body (JSON): `{"password": "<password_string>"}`
- **响应**：
  - 成功：HTTP 200 `{"ok": true}`（附带 `Set-Cookie: hermes_session=...; HttpOnly; SameSite=Lax; Path=/`）
  - 若未开启认证：HTTP 200 `{"ok": true, "message": "Auth not enabled"}`
  - 密码错误：HTTP 401 `{"error": "Invalid password"}`
  - 频控超限：HTTP 429 `{"error": "Too many attempts. Try again in a minute."}`
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：受 IP 登录频率限制器（`_check_login_rate` / `_record_login_attempt`）保护。

### POST /api/auth/logout  (routes.py:16382)
- **功能**：登出会话，使当前 Session Cookie 令牌失效并清除关联 Cookie。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "trusted_logout_url": "<url_if_trusted_auth>"
  }
  ```
- **认证**：需要登录（若已开启认证且无有效 cookie 则报 401）。
- **备注**：清除 `hermes_session` 与 profile 相关 cookie。若为 trusted auth，返回配置的第三方登出 URL 供前端跳转。

### POST /api/auth/passkey/options  (routes.py:16283)
- **功能**：获取 WebAuthn / Passkey 登录认证 Challenge 选项（PublicKeyCredentialRequestOptions）。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "publicKey": {
      "challenge": "...",
      "timeout": 60000,
      "rpId": "localhost",
      "allowCredentials": [...]
    }
  }
  ```
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：需满足 `HERMES_WEBUI_PASSKEY=1` 或 `webui_passkey_enabled: true`；若未开启认证则返回 400；若特性未开启返回 404。

### POST /api/auth/passkey/login  (routes.py:16298)
- **功能**：验证客户端浏览器提交的 WebAuthn 凭据签名，完成 Passkey 无密码/双因子登录并下发会话 Cookie。
- **参数**：
  - Body (JSON): WebAuthn `navigator.credentials.get()` 产出的 Credential JSON 载荷（含 `id`, `rawId`, `response: { clientDataJSON, authenticatorData, signature, userHandle }`）。
- **响应**：
  - 成功：HTTP 200 `{"ok": true}`（写入 `hermes_session` Cookie）
  - 失败：HTTP 401 `{"error": "<err>"}`；频控拦截：HTTP 429。
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：底层调用 `api.passkeys.finish_login()`。

### POST /api/auth/passkey/register/options  (routes.py:16327)
- **功能**：获取 WebAuthn 注册凭据 Challenge 选项（PublicKeyCredentialCreationOptions）。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "publicKey": {
      "challenge": "...",
      "rp": {"name": "Hermes WebUI", "id": "localhost"},
      "user": {"id": "...", "name": "admin", "displayName": "admin"},
      "pubKeyCredParams": [...]
    }
  }
  ```
- **认证**：需要认证（调用 `_require_passkey_registration_auth`：已登录，或未设置密码且处于本地初始化注册期）。
- **备注**：未开启 Passkey 特性时返回 404。

### POST /api/auth/passkey/register  (routes.py:16343)
- **功能**：完成 WebAuthn 凭据注册流程，验证并存储公钥凭据到本地密钥库。
- **参数**：
  - Body (JSON): WebAuthn `navigator.credentials.create()` 产出的注册凭据对象。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "id": "<credential_id>",
    "credentials": [{"id": "...", "name": "...", "created_at": 123456}]
  }
  ```
- **认证**：需要认证（调用 `_require_passkey_registration_auth`）。
- **备注**：底层调用 `api.passkeys.finish_registration()`。

### POST /api/auth/passkey/delete  (routes.py:16359)
- **功能**：删除指定的已注册 Passkey 凭据。
- **参数**：
  - Body (JSON): `{"id": "<credential_id>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "deleted": "<id>"}`
  - 冲突拒绝：若未设置常规密码且该凭据为唯一的 Passkey，返回 HTTP 409 `{"error": "Set a password or disable auth before removing the last passkey."}`。
  - 凭据不存在：HTTP 404 `{"error": "Credential not found"}`。
- **认证**：需要登录。
- **备注**：防止用户误删最后一个凭据导致永久锁死（Lockout Prevention 安全约束）。

### POST /api/auth/passkeys  (routes.py:16374)
- **功能**：查询当前已注册的所有 Passkey 凭据摘要列表。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON
  ```json
  {
    "credentials": [
      {
        "id": "<cred_id>",
        "name": "MacBook TouchID",
        "created_at": 1718000000
      }
    ],
    "disabled": false
  }
  ```
- **认证**：需要登录。
- **备注**：若 Passkey 未启用，返回 `{"credentials": [], "disabled": true}`。

---

## 2. 系统健康、控制与日志 (System Health, Control & Logs)

### GET /health  (routes.py:12244)
- **功能**：基础与深度探活健康检查端点。用于容器编排存活探测、服务就绪检测。
- **参数**：
  - Query: `?deep=1`（可选，触发深度探测：包含 accept 循环、SSE 事件流锁、线程活跃状态与持久化存储检测）。
- **响应**：
  - 浅探测：HTTP 200 JSON `{"status": "ok"}`
  - 深探测：HTTP 200 / 503 JSON
    ```json
    {
      "status": "ok",
      "accept_loop": {"status": "ok"},
      "streams_lock": {"status": "ok"},
      "lifecycle": {"status": "ok"}
    }
    ```
- **认证**：豁免（属于 `PUBLIC_PATHS`）。
- **备注**：浅检查极低开销，毫秒级响应；深检查用于 supervisor/diagnostics。

### GET /api/health/agent  (routes.py:12247)
- **功能**：获取 Hermes Agent 核心进程、网关、模型服务与配置链路的细粒度健康状态。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "status": "ok",
    "agent_ready": true,
    "gateway": {"running": true, "status": "active"},
    "gateway_chat": {"configured": true, "channel": "telegram"},
    "models": {"available_count": 12}
  }
  ```
- **认证**：需要登录。
- **备注**：包含 `gateway_chat_config_status()` 检查，方便前端在顶栏展示网关联动图标。

### GET /api/system/health  (routes.py:12253)
- **功能**：获取宿主机系统资源与运行环境健康指标（CPU/内存/磁盘/运行时间）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "status": "ok",
    "cpu_percent": 12.5,
    "memory": {"total_mb": 16384, "available_mb": 8192, "used_percent": 50.0},
    "disk": {"free_gb": 120.5, "total_gb": 512.0},
    "uptime_seconds": 3600
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.system_health.build_system_health_payload()`。

### POST /api/health/restart  (routes.py:13846)
- **功能**：重启当前激活 Profile 的 Hermes 消息网关（Messaging Gateway）后台服务进程。
- **参数**：无 / 空 Body。
- **响应**：
  - 成功完成：HTTP 200 `{"ok": true, "message": "Gateway service restarted successfully"}`
  - 重启中：HTTP 200 `{"ok": true, "message": "Gateway service restart initiated (in progress)"}`
  - 重复触发：HTTP 429 `{"ok": false, "error": "Restart already in progress. Please wait a moment and try again."}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `restart_active_profile_gateway()`，非 WebUI 自身重启。

### POST /api/shutdown  (routes.py:13843)
- **功能**：优雅终止 Hermes WebUI 自身服务进程。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON `{"status": "shutting_down"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：响应返回后异步延迟 0.3 秒，向自身进程发送 `SIGINT` 信号并执行全量 session drain 退出。

### POST /api/csp-report  (routes.py:13782)
- **功能**：接收并记录浏览器 CSP（Content Security Policy）安全违规日志上报。
- **参数**：
  - Body (JSON): 浏览器标准 `{"csp-report": {...}}` 违规报告载荷。
- **响应**：HTTP 204 No Content（经 `_send_no_content(handler)`）。
- **认证**：豁免（浏览器端原生触发，不携带会话鉴权头与 CSRF token）。
- **备注**：受内部 `_csp_report_rate_limited` 频控保护，防止恶意刷日志。

### GET /api/logs  (routes.py:12241)
- **功能**：读取当前激活 Profile 下指定模块日志文件末尾指定行数（tail），受白名单及安全目录锚定。
- **参数**：
  - Query: `?file=<key>&tail=<lines>`（`file` 可选值：`agent`, `webui`, `gateway`, `cron` 等白名单；`tail` 默认 200，受 `_LOG_TAIL_VALUES` 约束，最大读取 4MB）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "file": "agent",
    "tail": 200,
    "lines": ["[2026-08-21 18:00:00] INFO ...", "..."],
    "truncated": false,
    "total_bytes": 1048576,
    "mtime": 1724234400,
    "hint": null
  }
  ```
- **认证**：需要登录。
- **备注**：严格限制在 `~/.hermes/logs` 目录下，严防路径穿越；文件不存在时返回友好空列表。

---

## 3. 模型与推理配置 (Models, Reasoning & Providers)

### GET /api/models  (routes.py:12257)
- **功能**：获取当前 Profile 已配置、支持的模型全量列表、默认模型及 Provider 状态。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "models": [
      {
        "id": "anthropic/claude-3-7-sonnet-20250219",
        "name": "Claude 3.7 Sonnet",
        "provider": "anthropic",
        "context_length": 200000,
        "supports_reasoning": true
      }
    ],
    "default_model": "anthropic/claude-3-7-sonnet-20250219",
    "providers": [...]
  }
  ```
- **认证**：需要登录。
- **备注**：支持后台异步预热与本地缓存，跨 profile 时自动切换 TLS 与环境变量上下文。

### GET /api/models/live  (routes.py:12278)
- **功能**：向指定的 Provider 上游 API 实时拉取最新活跃可用模型列表（支持 OpenRouter, Anthropic, Copilot, Codex, Nous, 自建 OpenAI-compat 等）。
- **参数**：
  - Query: `?provider=<provider_id>`（可选，默认使用当前 Profile 激活的主 provider）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "provider": "openrouter",
    "models": [
      {
        "id": "anthropic/claude-3.7-sonnet",
        "name": "Anthropic: Claude 3.7 Sonnet",
        "context_length": 200000
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 agent 的 `provider_model_ids()`，内置内存缓存与 Provider 别名解析（如 `z.ai` -> `zai`）。

### GET /api/model/auxiliary  (routes.py:12284)
- **功能**：获取专有辅助子任务（Auxiliary Tasks，如 title 生成、summary 压缩、code review 等）所绑定的模型及 Provider 配置。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "title": {"model": "gpt-4o-mini", "provider": "openai"},
    "summary": {"model": "claude-3-haiku", "provider": "anthropic"}
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.config.get_auxiliary_models()`。

### POST /api/models/refresh  (routes.py:14386)
- **功能**：使指定 Provider 的模型缓存失效，促使下一次查询时重新向上游探测或加载配置。
- **参数**：
  - Body (JSON): `{"provider": "<provider_id>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "provider": "<provider_id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.config.invalidate_provider_models_cache()`。

### POST /api/default-model  (routes.py:14324)
- **功能**：设置全局 / 当前 Profile 的默认主对话模型及 Provider。
- **参数**：
  - Body (JSON):
    ```json
    {
      "model": "anthropic/claude-3-7-sonnet-20250219",
      "provider": "anthropic",
      "advanced": {"temperature": 0.7}
    }
    ```
- **响应**：HTTP 200 JSON `{"ok": true, "model": "...", "provider": "..."}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：若 `provider` 为 `"auto"`，服务端将自动置为 `None` 并执行 provider 推导。

### POST /api/model/set  (routes.py:14337)
- **功能**：通用模型设置端点，根据 `scope` 统一设置主模型（`scope="main"`）或特定辅助任务模型（`scope="auxiliary"`）。
- **参数**：
  - Body (JSON):
    ```json
    {
      "scope": "main | auxiliary",
      "task": "title",
      "provider": "anthropic",
      "model": "claude-3-7-sonnet-20250219",
      "advanced": {}
    }
    ```
- **响应**：HTTP 200 JSON 包含更新后的模型配置结构。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：`scope="auxiliary"` 时 `task` 字段必填（如 `title`, `compress` 等）。

### GET /api/reasoning  (routes.py:12401)
- **功能**：获取当前模型的深度思考 / 推理（Reasoning / Thinking）状态及档位（对齐 CLI `display.show_reasoning` 与 `agent.reasoning_effort`）。
- **参数**：
  - Query: `?model=<model_id>&provider=<provider_id>&base_url=<url>`（可选，查询特定模型支持的档位与当前设置）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "show_reasoning": true,
    "effort": "high",
    "supported_efforts": ["none", "low", "medium", "high"],
    "supported": true
  }
  ```
- **认证**：需要登录。
- **备注**：与 CLI 共享 `config.yaml` 配置源。

### POST /api/reasoning  (routes.py:14394)
- **功能**：设置思考过程展示开关（`display`）或推理力度档位（`effort`）。
- **参数**：
  - Body (JSON):
    - 方式 1（显隐开关）: `{"display": "show" | "hide" | "on" | "off"}`
    - 方式 2（推理档位）: `{"effort": "none" | "minimal" | "low" | "medium" | "high" | "xhigh", "model": "...", "provider": "..."}`
- **响应**：HTTP 200 JSON `{"ok": true, "show_reasoning": true}` 或 `{"ok": true, "effort": "high"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：修改即时同步写入 `config.yaml`。

### GET /api/providers  (routes.py:12304)
- **功能**：获取系统支持的所有 Provider 列表、配置状态（是否已设置 API Key / OAuth）、自建端点信息及凭据池配置。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "providers": [
      {
        "id": "anthropic",
        "name": "Anthropic",
        "configured": true,
        "is_custom": false
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：通过 `profile_env_for_active_request_readonly` 严格限制在当前 Profile 的环境变量沙箱内。

### POST /api/providers  (routes.py:14358)
- **功能**：配置或更新指定 Provider 的 API Key。
- **参数**：
  - Body (JSON): `{"provider": "<provider_id>", "api_key": "<key_string>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "provider": "<provider_id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `set_provider_key()`，敏感密钥存入对应 Profile 的 `.env` / 密钥存储区。

### POST /api/providers/delete  (routes.py:14370)
- **功能**：删除 / 清除指定 Provider 的已配置密钥。
- **参数**：
  - Body (JSON): `{"provider": "<provider_id>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "provider": "<provider_id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `remove_provider_key()`。

### POST /api/providers/self-hosted  (routes.py:14379)
- **功能**：配置自建 / 本地私有模型 Provider（如 Ollama, vLLM, LocalAI, 自定义 OpenAI 兼容端点）。
- **参数**：
  - Body (JSON):
    ```json
    {
      "provider": "ollama | custom",
      "base_url": "http://127.0.0.1:11434/v1",
      "api_key": "optional_key",
      "model": "llama3.3"
    }
    ```
- **响应**：HTTP 200 JSON 包含成功配置后的 Profile 与模型信息。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.onboarding.apply_self_hosted_provider_setup()`。

### GET /api/provider/quota  (routes.py:12317)
- **功能**：获取指定 Provider 的用量配额、余额与请求限额统计（如 OpenRouter, ZAI, DeepSeek 等）。
- **参数**：
  - Query: `?provider=<id>&refresh=true`（`refresh` 可选布尔值，强制向上游刷新配额）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "provider": "openrouter",
    "credit_remaining": 15.42,
    "usage_today": 0.58,
    "limit": null
  }
  ```
- **认证**：需要登录。
- **备注**：多凭据轮询池时自动汇聚当前 Profile 的凭据池状态。

### GET /api/provider/cost-history  (routes.py:12331)
- **功能**：查询指定 Provider 过去 N 天的历史消费金额与 Token 消耗走势。
- **参数**：
  - Query: `?provider=<id>&days=7`（`days` 取值范围 1-365，默认 7）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "provider": "anthropic",
    "days": 7,
    "history": [
      {"date": "2026-08-20", "cost": 0.45, "tokens": 45000}
    ],
    "total_cost": 3.12
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `get_provider_cost_history()`。

---

## 4. 系统设置与配置 (Settings, Config & Admin)

### GET /api/settings  (routes.py:12341)
- **功能**：获取当前 WebUI 全量前端设置、系统版本、更新通道、Token 限制及认证开关状态（安全屏蔽 password_hash）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "bot_name": "Hermes",
    "theme": "dark",
    "language": "en",
    "webui_version": "v0.8.0",
    "agent_version": "v0.8.0",
    "update_channel": "stable",
    "update_channel_version": "v0.8.0",
    "auth_enabled": true,
    "password_auth_enabled": true,
    "password_env_var": false,
    "passkeys_enabled": false,
    "passwordless_enabled": false,
    "max_tokens": 4096,
    "max_tokens_effective": 4096,
    "max_tokens_fallback": 8192
  }
  ```
- **认证**：需要登录（若开启 auth 且未登录会拦截；若 auth 关闭则放行）。
- **备注**：确保不泄露 `password_hash`；携带 `password_env_var` 标识以便前端禁用被环境变量覆盖的修改项。

### POST /api/settings  (routes.py:15513)
- **功能**：保存更新系统设置，包括改密（`_set_password`）、清除密码（`_clear_password`）、切换无密码（`_passwordless`）、Token 限制、侧边栏可见会话类型过滤等。
- **参数**：
  - Body (JSON): Key-Value 键值对，特殊字段：
    - `_set_password`: 新密码字符串
    - `_current_password`: 原密码字符串（修改/关闭已启用的密码认证时必填）
    - `_passwordless`: 布尔值（需已注册 passkey）
    - `_clear_password`: 布尔值
    - `max_tokens`: 数值或 null
    - `show_cli_sessions`, `show_cron_sessions` 等。
- **响应**：HTTP 200 JSON（返回更新并净化后的全量 settings 对象，必要时下发新 Session Cookie）。
  - 密码错误：HTTP 403 `{"error": "Current password is incorrect."}`。
  - 环境变量覆盖冲突：HTTP 409。
  - 首次公网无密初始化拦截：HTTP 403。
- **认证**：视当前状态而定（已开启认证需鉴权；首次无密设置受本地网段限制保护）。
- **备注**：改动侧边栏会话类型过滤字段时，会自动同步清除会话列表多级缓存。

### /api/config  (调研专题说明)
- **状态**：**无独立 HTTP 路由**（`routes.py` 中无 `parsed.path == "/api/config"` 分发项）。
- **定位与架构说明**：
  - `api/config.py` 是 Hermes WebUI 内部核心配置数据层模块，承担 `config.yaml`、`.env`、`settings.json` 的读写与合并。
  - WebUI 对外暴露的系统配置 REST 接口被专门规划为两类：
    1. 基础偏好与认证配置：`/api/settings`（GET 读取，POST 保存）；
    2. 仪表盘专项配置：`/api/dashboard/config`（GET 读取，POST 保存）。
  - 客户端若需读取或修改配置，应调用 `/api/settings` 或 `/api/dashboard/config`。

### POST /api/admin/reload  (routes.py:14431)
- **功能**：热重载（Hot-Reload）`api.models` 模块，无需重启 WebUI 守护进程即可实时应用模型定义与会话层代码改动。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON `{"status": "ok", "reloaded": "api.models"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：开发与热补丁运维调试端点。

---

## 5. 插件、扩展与更新 (Plugins, Extensions & Updates)

### GET /api/plugins  (routes.py:12315)
- **功能**：获取当前系统加载的 Hermes Agent 生命周期 Hook 插件及 WebUI Dashboard 插件安全元数据列表。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "plugins": [
      {
        "name": "Memory Provider",
        "key": "memory/sqlite",
        "version": "1.0.0",
        "description": "SQLite storage",
        "kind": "exclusive",
        "activation": "exclusive",
        "enabled": true,
        "is_active_provider": true,
        "hooks": ["pre_turn", "post_turn"]
      }
    ],
    "empty": false,
    "supported_hooks": ["pre_turn", "post_turn", "session_start", "session_end"],
    "read_only": true
  }
  ```
- **认证**：需要登录。
- **备注**：严格过滤内部文件绝对路径与回调 repr，防止敏感系统路径外泄。

### GET /api/extensions/status  (routes.py:12421)
- **功能**：获取扩展系统（Extensions）当前的运行状态、已安装扩展列表及其 Sidecar Proxy 状态。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "enabled": true,
    "extensions": [
      {
        "id": "ext_canvas",
        "name": "Canvas",
        "enabled": true,
        "sidecar_active": false,
        "sidecar_proxy_consent": true
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.extensions.get_extension_status()`。

### GET /api/extensions/registry  (routes.py:12426)
- **功能**：拉取官方 / 社区扩展应用市场（Extension Registry）目录及可用插件安装包元数据。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "registry": [
      {
        "id": "ext_diagram",
        "name": "Diagram Editor",
        "version": "0.2.1",
        "download_url": "https://...",
        "sha256": "..."
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.extensions.get_extension_registry()`。

### POST /api/extensions/toggle  (routes.py:13912)
- **功能**：启用或停用指定的已安装扩展。
- **参数**：
  - Body (JSON): `{"id": "<extension_id>", "enabled": true | false}`
- **响应**：HTTP 200 JSON `{"ok": true, "id": "<extension_id>", "enabled": true}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.extensions.set_extension_user_enabled()`。

### POST /api/extensions/install  (routes.py:13946)
- **功能**：从远程 URL 或 Registry 下载并安装指定的扩展包（校验 sha256 完整性）。
- **参数**：
  - Body (JSON): `{"id": "<id>", "download_url": "<url>", "sha256": "<hash>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "installed": "<id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.extensions.install_extension()`。

### POST /api/extensions/uninstall  (routes.py:13960)
- **功能**：卸载指定扩展并清理其本地资源。
- **参数**：
  - Body (JSON): `{"id": "<id>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "uninstalled": "<id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.extensions.uninstall_extension()`。

### POST /api/extensions/sidecar-proxy-consent  (routes.py:13926)
- **功能**：记录用户对扩展 Sidecar 独立进程反向代理通信的安全授权同意状态。
- **参数**：
  - Body (JSON): `{"id": "<id>", "approved": true | false}`
- **响应**：HTTP 200 JSON `{"ok": true, "id": "<id>", "sidecar_proxy_consent": true}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.extensions.set_extension_sidecar_proxy_consent()`。

### GET /api/updates/check  (routes.py:13226)
- **功能**：读取已缓存的 WebUI 及 Hermes Agent 软件版本更新检查结果（支持 `?simulate=1` 调试模拟）。
- **参数**：
  - Query: `?simulate=1`（仅 localhost 可用，返回测试模拟落后 commit 数据）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "webui": {
      "name": "webui",
      "behind": 0,
      "current_sha": "abc1234",
      "latest_sha": "abc1234",
      "branch": "master"
    },
    "agent": {
      "name": "agent",
      "behind": 2,
      "current_sha": "aaa0001",
      "latest_sha": "bbb0002"
    },
    "checked_at": 1724234000
  }
  ```
- **认证**：需要登录。
- **备注**：若设置中 `check_for_updates` 为 false，返回 `{"disabled": true}`。

### POST /api/updates/check  (routes.py:13888)
- **功能**：立即主动触发与远程 Git 仓库的线上版本更新探测（支持指定通道与强制检查）。
- **参数**：
  - Body (JSON): `{"force": true, "channel": "stable | experimental"}`
- **响应**：HTTP 200 JSON（返回最新探测到的版本对比结构体）。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：`force=true` 可绕过自动检查开关。

### POST /api/updates/apply  (routes.py:16101)
- **功能**：执行软件自我更新（git pull + 依赖检查），支持升级 WebUI 或 Agent。
- **参数**：
  - Body (JSON): `{"target": "webui" | "agent", "channel": "stable | experimental"}`
- **响应**：HTTP 200 JSON `{"ok": true, "target": "webui", "output": "..."}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.updates.apply_update()`。

### POST /api/updates/force  (routes.py:16116)
- **功能**：强制拉取远程指定分支并重置本地工作区（非破坏性备份后 force pull）。
- **参数**：
  - Body (JSON): `{"target": "webui" | "agent", "channel": "stable | experimental"}`
- **响应**：HTTP 200 JSON `{"ok": true, "forced": true}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：用于解决本地脏工作区导致更新卡死的情况。

### POST /api/updates/clear_lock  (routes.py:16127)
- **功能**：排查并提供 `.git/index.lock` 残留锁文件的修复指引与状态检测。
- **参数**：
  - Body (JSON): `{"target": "webui" | "agent"}`
- **响应**：HTTP 200 JSON 包含锁文件状态诊断及手动处理指引。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：为保证 Git 仓库安全，该端点不会直接在服务端物理强删锁文件，而是返回诊断与指令，并在锁消失后重新尝试更新。

### POST /api/updates/summary  (routes.py:16142)
- **功能**：利用当前 Profile 的默认大模型对即将更新的 Git Commit Log 生成中文/英文更新亮点摘要。
- **参数**：
  - Body (JSON): `{"updates": {...}, "target": "webui | agent"}`
- **响应**：HTTP 200 JSON `{"summary": "本次更新主要改进了..."}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层在后台 Worker 中绑定活跃 Profile 的 LLM 上下文执行生成。

---

## 6. 引导入驻流程 (Onboarding)

### GET /api/onboarding/status  (routes.py:12418)
- **功能**：获取首次启动入驻向导（Onboarding Wizard）完成状态与初始配置检测。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "completed": false,
    "has_config": false,
    "detected_providers": []
  }
  ```
- **认证**：豁免（用于初次启动导流）。
- **备注**：底层调用 `api.onboarding.get_onboarding_status()`。

### POST /api/onboarding/setup  (routes.py:15705)
- **功能**：保存引导向导提交的初始 Provider API Key、默认模型与系统基础配置。
- **参数**：
  - Body (JSON): `{"provider": "...", "api_key": "...", "default_model": "..."}`
- **响应**：HTTP 200 JSON `{"ok": true}`
- **认证**：在未设置密码时受本地私网网段安全限制（`_onboarding_gate_allows`；可通过 `HERMES_WEBUI_ONBOARDING_OPEN=1` 放行）。
- **备注**：将初始密钥持久化写入系统。

### POST /api/onboarding/complete  (routes.py:15722)
- **功能**：标记首次入驻向导已完成，后续打开页面不再自动跳出向导。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON `{"ok": true, "onboarding_completed": true}`
- **认证**：受本地网段门禁限制（`_onboarding_gate_allows`）。
- **备注**：修改并持久化 `onboarding_completed=true`。

### POST /api/onboarding/probe  (routes.py:15731)
- **功能**：向导阶段测试自建 Provider（如 Ollama / LocalAI）端点连通性，并解析上游返回的模型清单。
- **参数**：
  - Body (JSON): `{"provider": "ollama", "base_url": "http://localhost:11434/v1", "api_key": "optional"}`
- **响应**：HTTP 200 JSON `{"ok": true, "models": ["llama3:latest", "mistral:latest"]}`
- **认证**：受本地网段门禁限制（`_onboarding_gate_allows`）。
- **备注**：纯只读探测，不产生文件落盘。

### POST /api/onboarding/oauth/start  (routes.py:15689)
- **功能**：在向导中启动第三方提供商（如 Google Gemini / GitHub Copilot / Anthropic）的 OAuth 登录认证流程。
- **参数**：
  - Body (JSON): `{"provider": "google | copilot"}`
- **响应**：HTTP 200 JSON `{"flow_id": "<uuid>", "auth_url": "https://..."}`
- **认证**：受本地网段门禁限制（`_onboarding_gate_allows`）。
- **备注**：响应带 `Cache-Control: no-store`。

### POST /api/onboarding/oauth/cancel  (routes.py:15699)
- **功能**：取消正在进行中的向导 OAuth 授权流程并释放对应 flow 资源。
- **参数**：
  - Body (JSON): `{"flow_id": "<uuid>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "canceled": true}`
- **认证**：受本地网段门禁限制。
- **备注**：底层调用 `cancel_onboarding_oauth_flow()`。

### GET /api/onboarding/oauth/poll  (routes.py:13357)
- **功能**：轮询指定 OAuth 授权流程的状态（判断用户是否已在浏览器中完成授权）。
- **参数**：
  - Query: `?flow_id=<uuid>`
- **响应**：HTTP 200 JSON
  ```json
  {
    "status": "pending | completed | error",
    "error": null,
    "provider": "google"
  }
  ```
- **认证**：受本地网段门禁限制。
- **备注**：前端定时间隔请求，直到状态变为 `completed` 或超时。

---

## 7. Profile 与 Personality 管理 (Profiles & Personalities)

### GET /api/profiles  (routes.py:13523)
- **功能**：获取系统全部已创建的 Profile 配置清单、当前激活的 Profile 名称及是否处于单 Profile 隔离模式。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "profiles": [
      {"name": "default", "is_default": true, "path": "~/.hermes"},
      {"name": "work", "is_default": false, "path": "~/.hermes/profiles/work"}
    ],
    "active": "default",
    "single_profile_mode": false
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.profiles.list_profiles_api()`。

### GET /api/profile/active  (routes.py:13544)
- **功能**：查询当前会话生效的 Profile 详细上下文信息（含家目录路径、默认工作区目录）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "name": "default",
    "path": "/home/user/.hermes",
    "is_default": true,
    "default_workspace": "/home/user/projects"
  }
  ```
- **认证**：需要登录。
- **备注**：关键启动端点，即使工作区推导异常也会 fail-open 返回 None，绝不抛 500。

### POST /api/profile/switch  (routes.py:15409)
- **功能**：切换当前客户端的激活 Profile，通过下发专属 Profile Cookie 实现单用户会话级隔离。
- **参数**：
  - Body (JSON): `{"name": "work"}`
- **响应**：HTTP 200 JSON `{"ok": true, "switched": "work"}`（附带 `Set-Cookie: hermes_profile=...`）
  - 权限拒绝：HTTP 403（若当前会话被 Trusted Auth 强制绑定为某一 profile 且企图越权切换）。
  - 目标不存在：HTTP 404。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：切换成功后会自动同步使模型缓存失效（`invalidate_models_cache()`）并重启对应的 Gateway Watcher。

### POST /api/profile/create  (routes.py:15455)
- **功能**：创建全新的独立 Profile，支持从现有 Profile 克隆配置或传入初始 Base URL / Key。
- **参数**：
  - Body (JSON):
    ```json
    {
      "name": "dev_env",
      "clone_from": "default",
      "clone_config": true,
      "base_url": "http://...",
      "api_key": "...",
      "default_model": "...",
      "model_provider": "..."
    }
    ```
- **响应**：HTTP 200 JSON `{"ok": true, "profile": {"name": "dev_env", ...}}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：Profile 名称正则强校验：`^[a-z0-9][a-z0-9_-]{0,63}$`。

### POST /api/profile/delete  (routes.py:15495)
- **功能**：删除指定的 Profile 及其持久化配置目录。
- **参数**：
  - Body (JSON): `{"name": "test_profile"}`
- **响应**：HTTP 200 JSON `{"ok": true, "deleted": "test_profile"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：禁止删除默认 root profile (`default`)。

### GET /api/personalities  (routes.py:13162)
- **功能**：读取 `config.yaml` 中配置的 Agent 预设人格角色列表（Personalities）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "personalities": [
      {"name": "Coder", "description": "Focused on software engineering"},
      {"name": "Writer", "description": "Creative writing assistant"}
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：请求时会自动触发 `reload_config()`，实时同步磁盘变动。

### POST /api/personality/set  (routes.py:14501)
- **功能**：为指定会话（Session）绑定或切换 Agent 角色人格。
- **参数**：
  - Body (JSON): `{"session_id": "<sid>", "name": "Coder"}`
- **响应**：HTTP 200 JSON `{"ok": true, "personality": "Coder"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：若目标 Session 属于只读 Subagent，将拒绝修改并返回 400。

---

## 8. 指令系统 (Commands & Bundles)

### GET /api/commands  (routes.py:13211)
- **功能**：获取系统内已注册的所有斜杠指令（Slash Commands）元数据列表。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "commands": [
      {"name": "/help", "description": "Show help message"},
      {"name": "/clear", "description": "Clear conversation"}
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.commands.list_commands()`。

### GET /api/commands/bundles  (routes.py:13215)
- **功能**：获取已配置的复合指令包（Command Bundles / Multi-action Bundles）列表。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "bundles": [
      {"name": "review_pr", "description": "Run tests and summarize diff"}
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.commands.list_command_bundles()`。

### GET /api/commands/moa/resolve  (routes.py:13219)
- **功能**：解析混合专家架构（Mixture-of-Agents / MoA）的聚合配置与参与模型分工拓扑。
- **参数**：无。
- **响应**：HTTP 200 JSON 返回 MoA 配置解析详情。
- **认证**：需要登录。
- **备注**：若 MoA 依赖服务不可用返回 HTTP 503。

### POST /api/commands/bundles/resolve  (routes.py:15350)
- **功能**：解析并展开指定指令包（Bundle Command），得到其子步骤或具体执行动作。
- **参数**：
  - Body (JSON): `{"command": "review_pr"}`
- **响应**：HTTP 200 JSON 包含展开后的动作流程与参数。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：未找到指令包时返回 HTTP 404。

### POST /api/commands/exec  (routes.py:15366)
- **功能**：直接在服务端执行指定的 Agent 内置指令或插件指令。
- **参数**：
  - Body (JSON): `{"command": "/compact"}`
- **响应**：HTTP 200 JSON `{"output": "Session compacted successfully."}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：先后尝试 `execute_agent_command()` 与 `execute_plugin_command()`。

---

## 9. 仪表盘、MCP、笔记、回滚与运维确认 (Dashboard, MCP, Notes, Rollback & Acks)

### GET /api/dashboard/status  (routes.py:12288)
- **功能**：获取 Project OS 仪表盘探针的实时运行状态（服务存活、工作流状态、监控指标）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "status": "ready",
    "active_agents": 2,
    "metrics": {}
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.dashboard_probe.get_dashboard_status()`。

### GET /api/dashboard/config  (routes.py:12294)
- **功能**：获取仪表盘（Dashboard）的当前展示与布局配置。
- **参数**：无。
- **响应**：HTTP 200 JSON 包含面板组件布局、刷新频率等配置。
- **认证**：需要登录。
- **备注**：底层调用 `api.dashboard_probe.get_dashboard_config()`。

### POST /api/dashboard/config  (routes.py:13986)
- **功能**：保存更新仪表盘布局与监控配置。
- **参数**：
  - Body (JSON): 新的仪表盘配置字典。
- **响应**：HTTP 200 JSON 返回保存后的配置对象。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.dashboard_probe.save_dashboard_config(body)`。

### GET /api/project-os/dashboard  (routes.py:12140)
- **功能**：获取 Project OS 项目级上下文仪表盘数据（包含看板 Truth Board、目标概览、入驻状态等）。
- **参数**：
  - Query: `?workspace=<path>&board=<slug>`（可选）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "workspace_root": "/path/to/repo",
    "truth_boards": ["board-1"],
    "goals": "...",
    "onboarding": {}
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `_handle_project_os_dashboard()`。

### GET /api/mcp/servers  (routes.py:13576)
- **功能**：获取系统已注册的所有 MCP（Model Context Protocol）服务连接状态、配置摘要及工具数量。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "servers": [
      {
        "name": "filesystem",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem"],
        "enabled": true,
        "status": "connected"
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `_handle_mcp_servers_list()`。

### PATCH /api/mcp/servers/{name}  (routes.py:16442)
- **功能**：启用或停用指定的 MCP Server 服务。
- **参数**：
  - URL Path: `{name}` 为 MCP 服务标识名。
  - Body (JSON): `{"enabled": true | false}`
- **响应**：HTTP 200 JSON `{"ok": true, "name": "filesystem", "enabled": true}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `_handle_mcp_server_toggle()`。

### DELETE /api/mcp/servers/{name}  (routes.py:16470)
- **功能**：删除指定的 MCP Server 配置。
- **参数**：
  - URL Path: `{name}` 为 MCP 服务标识名。
- **响应**：HTTP 200 JSON `{"ok": true, "deleted": "filesystem"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `_handle_mcp_server_delete()`。

### PUT /api/mcp/servers/{name}  (routes.py:16506)
- **功能**：新增或全量更新指定的 MCP Server 配置（Command, Args, Env 等）。
- **参数**：
  - URL Path: `{name}` 为 MCP 服务标识名。
  - Body (JSON):
    ```json
    {
      "command": "node",
      "args": ["server.js"],
      "env": {"DEBUG": "1"},
      "enabled": true
    }
    ```
- **响应**：HTTP 200 JSON `{"ok": true, "server": {...}}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `_handle_mcp_server_update()`。

### GET /api/mcp/tools  (routes.py:13580)
- **功能**：获取所有当前已连接 MCP 服务暴露的可用 Tools 工具列表与 JSON Schema 描述。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "tools": [
      {
        "name": "filesystem_read_file",
        "server": "filesystem",
        "description": "Read file contents",
        "parameters": {...}
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：聚合运行时已启动的 Server 和注册表配置。

### GET /api/notes/sources  (routes.py:13583)
- **功能**：获取可用的外部笔记集成数据源（如 Joplin、MCP 笔记服务）列表与连接状态。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "sources": [
      {"id": "joplin", "name": "Joplin Notes", "available": true}
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：若未开启外部笔记特性，返回 `{"sources": [], "disabled": true}`。

### GET /api/notes/search  (routes.py:13585)
- **功能**：在已连接的外部笔记库中搜索笔记条目（目前支持 Joplin）。
- **参数**：
  - Query: `?source=joplin&q=<keyword>&limit=20`
- **响应**：HTTP 200 JSON
  ```json
  {
    "source": "joplin",
    "query": "arch",
    "results": [
      {"id": "note_123", "title": "System Architecture", "snippet": "..."}
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `_joplin_search_notes()`。

### GET /api/notes/item  (routes.py:13587)
- **功能**：获取单篇指定外部笔记的详细内容与 Markdown 文本。
- **参数**：
  - Query: `?source=joplin&id=<note_id>`
- **响应**：HTTP 200 JSON
  ```json
  {
    "source": "joplin",
    "note": {
      "id": "note_123",
      "title": "System Architecture",
      "body": "# Architecture Doc\n..."
    }
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `_joplin_get_note()`。

### GET /api/rollback/list  (routes.py:13591)
- **功能**：查询指定工作区目录（Workspace）下的全部代码检查点（Checkpoints / Snapshots）。
- **参数**：
  - Query: `?workspace=<workspace_path>`（必填）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "checkpoints": [
      {
        "id": "chk_20260821_120000",
        "created_at": 1724232000,
        "message": "Before tool execution"
      }
    ]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.rollback.list_checkpoints()`。

### GET /api/rollback/diff  (routes.py:13605)
- **功能**：比对当前工作区代码与指定检查点之间的文件变更 Diff。
- **参数**：
  - Query: `?workspace=<workspace_path>&checkpoint=<checkpoint_id>`（均必填）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "diff": "diff --git a/app.py b/app.py...",
    "files_changed": ["app.py"]
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.rollback.get_checkpoint_diff()`。

### POST /api/rollback/restore  (routes.py:16408)
- **功能**：将工作区代码强制回滚/还原到指定的历史检查点快照。
- **参数**：
  - Body (JSON): `{"workspace": "<path>", "checkpoint": "<checkpoint_id>"}`
- **响应**：HTTP 200 JSON `{"ok": true, "restored": "<checkpoint_id>"}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `api.rollback.restore_checkpoint()`。

### POST /api/sessions/cleanup  (routes.py:14444)
- **功能**：执行全量无效/空孤儿会话清理（删除无实质内容的 "Untitled" 会话及索引孤立幽灵项）。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON `{"ok": true, "cleaned": 3}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：执行两阶段清理（文件清理与索引重建），加全局 `_INDEX_WRITE_LOCK` 锁防并发冲突。

### POST /api/sessions/cleanup_zero_message  (routes.py:14447)
- **功能**：定向清理 0 条消息的空会话（Zero-Message Sessions）。
- **参数**：无 / 空 Body。
- **响应**：HTTP 200 JSON `{"ok": true, "cleaned": 1}`
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：底层调用 `_handle_sessions_cleanup(handler, body, zero_only=True)`。

### POST /api/client-events/log  (routes.py:13862)
- **功能**：接收前端客户端上报的运行埋点、页面崩溃与交互事件日志。
- **参数**：
  - Body (JSON): `{"event": "<event_name>", "data": {...}}`
- **响应**：
  - 正常：HTTP 200 `{"ok": true, "event": "<event_name>"}`
  - 频控：HTTP 429 `{"ok": false, "error": "rate_limited"}`
- **认证**：受 IP 限流保护，记录在专用客户端事件日志通道。
- **备注**：入参执行严格字符截断与 URL 净化（`_sanitize_client_event_payload`）。

### POST /api/process-complete-ack  (routes.py:13800)
- **功能**：**[已废弃 / 410 Gone]** 历史旧版后台进程完成确认端点。
- **参数**：任意。
- **响应**：HTTP 410 Gone
  ```json
  {
    "error": "gone: /api/process-complete-ack was replaced by /api/bg-task-complete-ack as part of the process_complete -> bg_task_complete event rename",
    "replaced_by": "/api/bg-task-complete-ack"
  }
  ```
  （Header: `X-Replaced-By: /api/bg-task-complete-ack`）
- **认证**：CSRF 检查前优先直接返回 410。
- **备注**：提供明确迁移指引，确保旧版缓存网页能明确捕获协议变更。

### POST /api/bg-task-complete-ack  (routes.py:15190)
- **功能**：确认接收后台任务完成（`bg_task_complete`）SSE 通知的诊断端点（纯诊断 ACK，状态已由服务端自主唤醒）。
- **参数**：
  - Body (JSON): `{"session_id": "<sid>", "task_id": "<tid>"}` （兼容过渡别名 `process_id`）。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "session_id": "sid_123",
    "task_id": "task_abc",
    "noop": true
  }
  ```
  （若使用 `process_id` 则响应带 `Deprecation: true` Header）。
- **认证**：需要登录（受 CSRF 防护）。
- **备注**：基于 Option-Z 架构，Agent 唤醒由服务端 Drain 线程自主完成，此端点为客户端纯诊断确认。

---

## 10. 语音能力 (Transcribe Capability)

### GET /api/transcribe/capability  (routes.py:12398)
- **功能**：查询当前环境的语音听写 / 语音识别（Speech-to-Text, STT）能力可用性及底层 Provider（faster-whisper, openai, mistral 等）。
- **参数**：无。
- **响应**：HTTP 200 JSON
  ```json
  {
    "ok": true,
    "available": true,
    "provider": "faster-whisper"
  }
  ```
- **认证**：需要登录。
- **备注**：底层调用 `api.upload.handle_transcribe_capability()`，只做静态探针探测，不会触发懒安装副作用。

---

## 11. 域 A 未分类 / 疑点清单

| 序号 | 路由路径 / 特殊项 | 所在行号 | 疑点 / 审计发现说明 |
|:---|:---|:---|:---|
| 1 | `/api/config` | routes.py 无独立路由 | **确定无独立路由**。系统配置通过 `api/config.py` 底层承载，API 路由层划分为 `/api/settings` 与 `/api/dashboard/config`。 |
| 2 | `/api/process-complete-ack` | routes.py:13800 | **确定返回 HTTP 410 Gone**。已废弃并迁移至 `/api/bg-task-complete-ack`。 |
| 3 | `/api/updates/check` (GET vs POST) | routes.py:13226 (GET) / 13888 (POST) | **同路径双方法并存**：`GET` 用于读取缓存状态（支持 `?simulate=1`）；`POST` 用于强制即时联网检查并允许传入 `channel` 与 `force` 参数。 |
| 4 | `/api/reasoning` (GET vs POST) | routes.py:12401 (GET) / 14394 (POST) | **同路径双方法并存**：`GET` 读取推理档位与显示开关；`POST` 写入 `display` 或 `effort` 档位。 |
| 5 | `/api/providers` (GET vs POST) | routes.py:12304 (GET) / 14358 (POST) | **同路径双方法并存**：`GET` 列出所有 provider；`POST` 用于写入 provider 的 API Key。 |
| 6 | `/api/settings` (GET vs POST) | routes.py:12341 (GET) / 15513 (POST) | **同路径双方法并存**：`GET` 读取全量安全设置；`POST` 负责保存、改密、Token 调优及会话缓存联动失效。 |
| 7 | `/api/dashboard/config` (GET vs POST) | routes.py:12294 (GET) / 13986 (POST) | **同路径双方法并存**：`GET` 获取仪表盘布局；`POST` 保存仪表盘配置。 |
| 8 | `/api/mcp/servers` (GET / PATCH / DELETE / PUT) | routes.py:13576 (GET) / 16442 (PATCH) / 16470 (DELETE) / 16506 (PUT) | **RESTful 完整动作集**：列表(GET)、开关(PATCH)、删除(DELETE)、新增/修改(PUT)，后三者路径为 `/api/mcp/servers/{name}`。 |
| 9 | `/api/onboarding/*` 网段安全门禁 | routes.py:15689 等 | 在未配置系统密码时，所有入驻向导写入接口均受 `_onboarding_gate_allows()` 保护，默认拒绝来自公网的初始化请求，仅允许本地/局域网访问，除非设置 `HERMES_WEBUI_ONBOARDING_OPEN=1`。 |
