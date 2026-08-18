# 第二阶段：会话能力补齐计划（2026-08-18）

背景：API/模型层已 100% 就绪（sessions 18 端点 + projects 4 端点全实现，SessionSummary
字段全解析），缺的全是 UI 挂载。本计划把这些能力全部暴露到 UI。

## 已核实的事实（调研 hermes-webui routes.py / agent_sessions.py）

| 端点 | 请求体 | 响应 | 前端语义 |
|---|---|---|---|
| POST /api/session/compress[/start] | {session_id, focus_topic?} | {ok, session} | 压缩会话（可选聚焦主题）；start 为流式版（返回 stream_id） |
| POST /api/session/undo | {session_id} | {ok, ...} | 删除最后一轮（用户消息及其后全部），返回被删预览 |
| POST /api/session/retry | {session_id} | {ok, text} | 截断到最后一个用户消息前，**返回该文本**→前端回填输入框 |
| POST /api/session/truncate | {session_id, keep_count} | {ok, session{messages}} | 保留前 N 条消息；keep_count 必须是 >=0 整数 |
| POST /api/session/update | {session_id, workspace?, model?, model_provider?} | {ok, session} | 会话设置；只读导入会话 403 |
| POST /api/session/move | {session_id, project_id?} | {ok, session} | 移动项目（project_id=null 清空）；跨 profile 项目 404；流式时 503 |
| GET/POST /api/session/yolo | GET(可选 sid) / POST{sid, enabled} | {ok, yolo_enabled} | 服务端内存态开关；重启丢失 |
| GET /api/sessions?include_archived=1 | — | {sessions, archived_count} | 归档列表 |
| GET /api/sessions/search?q=&content=1 | — | {sessions[{match_type, match_preview?}], query, count} | match_type: title|content；content 命中带摘录 |
| GET /api/projects / POST create / rename / delete | — | {projects[], ...} | 项目 CRUD；GET 按活动 profile 过滤 |
| POST /api/projects/bind | {project_id, workspaces...} | — | 项目绑定 workspace/模型（本轮 UI 不做 bind，只做 CRUD+assign） |

- **无 tags 端点**（已 grep 确认）→「标签」= 来源标签筛选（sourceTag/sourceLabel）+ 项目归组。
- SessionSummary 已解析：projectId / parentSessionId / relationshipType / readOnly /
  isReadOnly / sourceTag / sourceLabel / estimatedCost / hasPendingUserMessage /
  pendingStartedAt / worktreePath / matchType / inputTokens / outputTokens。
- retry 语义非自动重跑：服务端返回 last user text，客户端回填文本输入框。

## 实施分区（文件所有权，避免并行冲突）

### 批 1（并行 2 个）：
- **S1 列表筛选+归档+批量+项目系统**
  所有权：`lib/features/session_list/session_list_providers.dart`、
  `lib/features/session_list/session_list_page.dart`、`lib/features/projects/`（新）、
  及相关测试（session_list 测试文件、新增 projects 测试）。
  内容：筛选 chips（全部/已归档[count]/来源标签/项目）→ state.filterMode；
  归档模式 fetchSessions(includeArchived)；行长按进入多选 → 底部批量栏
  （批量归档/删除[确认]/移动到项目）；项目 CRUD sheet + 行菜单「移动到项目」
  picker；列表行 badge：分支/只读/来源/成本/待输入。
- **S2 聊天页会话操作扩展**
  所有权：`lib/features/chat/chat_page.dart`、`chat_controller.dart`、
  `chat_server_api.dart`、`chat_state.dart`、新增 `chat_session_settings_sheet.dart`、
  相关测试。
  内容：会话菜单新增 压缩（focus topic 可选）/ 撤销上一轮（确认）/
  重试上一轮（结果回填输入框）/ 会话设置（workspace/model → updateSession）/
  YOLO 开关（GET 拉状态 + POST 切换）；只读会话（readOnly/isReadOnly）→
  输入栏与操作禁用；pendingUserMessage 状态展示。
  ⚠️ ChatServerApi 加方法后 5 处测试 fake 必须同步实现（chat_controller_test /
  chat_page_test / contrast_scan_test / notification_providers_test /
  golden_screens_test）。

### 批 2（批 1 合并后，并行 2 个）：
- **S3 消息级操作**：长按/右键消息菜单 → 复制文本 / 复制 Markdown / 编辑（回填重发）/
  从本条分支（branch keep_count=i+1）/ 从此处截断（truncate keep_count=i+1，确认）。
  所有权：chat widgets + chat_controller（消息方法）+ 测试。
- **S4 搜索高亮与定位 + 分支关系**：列表搜索结果 title/preview 关键词高亮
  （RichText textSpan）；点击 content 命中 → `/chat/:id?q=xxx` 深链，chat 页
  加载后本地检索含关键词首条消息 → 滚动定位 + 闪烁高亮；聊天页「分支关系」
  展示（parentSessionId → 跳转父会话按钮）。所有权：session_list 搜索渲染 +
  chat 定位逻辑 + 路由 + 测试。

## 验收标准（柚子统一执行）
- `C:/tmp/f.bat analyze` 零告警；`C:/tmp/f.bat test` 全绿；golden 更新。
- 全量 `flutter test` 后在 `feat/session-gaps-phase2` 分支分 commit 落盘。
- 无 Material 组件混入业务 UI；对话框按钮全部 ValueKey；错误文本 statusRedText。

## 明确不做（上游无能力，需动服务器）
- 自定义自由标签（tags）API
- 项目 bind（workspace→project 自动归档绑定，需 webui 管理页设计）
- compress 流式进度 UI（用同步版 compress 端点）