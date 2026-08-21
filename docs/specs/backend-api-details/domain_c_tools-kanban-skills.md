# AGY 后端接口大全 · 域 C（生产工具：Git / Workspace / Cron / Kanban / Skills / Memory / Insights / Prompts / Wiki / Rollback / Compress）

> **说明**：本手册为「域 C」完整后端接口审计卡片，依据 `/d/hermes-webui/api/routes.py`（单文件分发核心，26555 行）、`api/kanban_bridge.py`、`api/workspace_git.py`、`api/rollback.py` 等底层模块逐行核对，行号均以 `routes.py` 权威分发区与实现区为准。

---

## 目录
1. [Git 工具群 (Git Operations)](#1-git-工具群-git-operations)
2. [工作区管理 (Workspace Management)](#2-工作区管理-workspace-management)
3. [定时任务 (Cron / Scheduled Jobs)](#3-定时任务-cron--scheduled-jobs)
4. [看板与任务调度系统 (Kanban & Task System)](#4-看板与任务调度系统-kanban--task-system)
5. [技能生态 (Skills Ecosystem)](#5-技能生态-skills-ecosystem)
6. [长期记忆与人格 (Memory & Soul)](#6-长期记忆与人格-memory--soul)
7. [洞察与用量统计 (Insights & Usage)](#7-洞察与用量统计-insights--usage)
8. [快捷提示词库 (Prompts Library)](#8-快捷提示词库-prompts-library)
9. [知识库 / 文档 (LLM Wiki)](#9-知识库--文档-llm-wiki)
10. [生产辅助：回滚快照 / 导出 / 压缩 / 决策看板 (Rollback, Export, Compress, Project OS)](#10-生产辅助回滚快照--导出--压缩--决策看板)
11. [域 C 未分类 / 疑点清单](#11-域-c-未分类--疑点清单)

---

# 1. Git 工具群 (Git Operations)

## GET /api/git/status  (routes.py:13153, impl: 22640)
- **功能**：查询当前会话对应工作区的完整 Git 状态（分支、暂存区/未暂存区文件列表、冲突、统计信息等）
- **参数**：
  - Query: `session_id` (string, 必填)
- **响应**：`{"git": {...}}`
  - 关键字段：`is_git` (bool), `branch` (string), `ahead` (int), `behind` (int), `staged` (list), `unstaged` (list), `untracked` (list), `conflicted` (list), `totals` ({staged, unstaged, untracked, changed}), `clean` (bool)
- **认证**：需要登录（若开启身份校验）；Profile 隔离受限
- **备注**：内部调用 `api.workspace_git.git_status`。若会话正在运行活跃流，读取依然允许，但写操作会被锁定。

---

## GET /api/git/branches  (routes.py:13156, impl: 22653)
- **功能**：获取工作区当前 Git 仓库的本地分支与远程分支列表
- **参数**：
  - Query: `session_id` (string, 必填)
- **响应**：`{"branches": [{"name": str, "current": bool, "remote": bool, "upstream": str|null}, ...]}`
- **认证**：需要登录
- **备注**：基于 `git branch -a -vv` 解析，标明当前所在分支与上游追踪分支。

---

## GET /api/git/diff  (routes.py:13159, impl: 22666)
- **功能**：获取指定单个文件的 Git Diff 差异内容
- **参数**：
  - Query: 
    - `session_id` (string, 必填)
    - `path` (string, 必填，相对工作区路径)
    - `kind` (string, 可选，默认 `"unstaged"`；可选 `"unstaged"` | `"staged"` | `"untracked"`)
- **响应**：`{"diff": str}`（unified diff 文本，若为 untracked 则合成虚拟 diff）
- **认证**：需要登录
- **备注**：防止路径穿越；若文件不存在或 path 未提供返回 400。

---

## GET /api/git-info  (routes.py:13184)
- **功能**：轻量级获取会话工作区 Git 概览（供界面顶部状态栏或会话元信息徽章使用）
- **参数**：
  - Query: `session_id` (string, 必填)
- **响应**：`{"git": null | {"branch": str, "dirty": int, "modified": int, "untracked": int, "ahead": int, "behind": int, "is_git": true}}`
- **认证**：需要登录
- **备注**：非 git 仓库时 `git` 字段返回 `null`。与 `/api/git/status` 相比更轻量，不返回具体文件列表。

---

## POST /api/git/stage  (routes.py:15261, impl: 22705)
- **功能**：将指定文件加入暂存区（`git add`）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `paths` (string[] | string, 必填，支持单文件 `path` 或多文件数组 `paths`)
- **响应**：`{"ok": true, "git": {...}}`（返回最新 git_status）
- **认证**：需要登录；CSRF 校验；受活跃会话流与破坏性操作开关保护
- **备注**：若环境变量未开启破坏性操作或会话流正在运行，返回 403/409。

---

## POST /api/git/unstage  (routes.py:15264, impl: 22723)
- **功能**：将指定文件移出暂存区（`git restore --staged` 或 `git reset HEAD`）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `paths` (string[] | string, 必填)
- **响应**：`{"ok": true, "git": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：支持单路径或数组路径。

---

## POST /api/git/discard  (routes.py:15267, impl: 22741)
- **功能**：丢弃工作区指定文件的改动（危险操作：回滚修改或删除未跟踪文件）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `paths` (string[] | string, 必填)
    - `delete_untracked` (bool, 可选，默认 false；若为 true 且目标为 untracked 则物理删除)
- **响应**：`{"ok": true, "git": {...}}`
- **认证**：需要登录；CSRF 校验；受 `HERMES_WORKSPACE_GIT_DESTRUCTIVE=1` 保护
- **备注**：破坏性操作，执行前必须检查环境变量；未开启时返回 403 `destructive_git_disabled`。

---

## POST /api/git/commit-message  (routes.py:15270, impl: 22864)
- **功能**：利用 LLM 根据当前**全部已暂存文件 (staged)** 的 diff 自动生成 Git 提交信息
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
- **响应**：`{"ok": true, "message": str, "truncated": bool}`
- **认证**：需要登录；CSRF 校验
- **备注**：优先使用 auxiliary 模型或当前会话绑定的模型生成 Conventional Commits 格式规范信息。

---

## POST /api/git/commit-message-selected  (routes.py:15273, impl: 22900)
- **功能**：利用 LLM 根据**前端勾选的指定文件列表**生成 Git 提交信息（无需先全局 stage）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `paths` (string[] | string, 必填)
- **响应**：`{"ok": true, "message": str, "truncated": bool}`
- **认证**：需要登录；CSRF 校验
- **备注**：与 `commit-message` 的区别在于支持针对部分选中文件进行 diff 分析并生成 message。

---

## POST /api/git/commit  (routes.py:15276, impl: 22937)
- **功能**：提交当前暂存区中的改动（`git commit -m`）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `message` (string, 必填)
- **响应**：`{"ok": true, "commit": str, "git": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：要求暂存区非空。与 `commit-selected` 区别在于直接针对已有暂存区执行提交。

---

## POST /api/git/commit-selected  (routes.py:15279, impl: 22954)
- **功能**：原子提交指定的未暂存/已暂存文件列表（内部先 stage 指定 paths，执行 commit，并在失败时保护现场）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `paths` (string[] | string, 必填)
    - `message` (string, 必填)
- **响应**：`{"ok": true, "commit": str, "git": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：前端 Git 面板精细化提交的核心端点。

---

## POST /api/git/fetch  (routes.py:15282, impl: 22972)
- **功能**：从远程仓库拉取最新索引与分支引用（`git fetch`）
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"ok": true, "output": str, "git": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：无破坏性，不受破坏性开关限制。

---

## POST /api/git/pull  (routes.py:15285, impl: 22972)
- **功能**：拉取并合并远程分支改动（`git pull`）
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"ok": true, "output": str, "git": {...}}`
- **认证**：需要登录；CSRF 校验；受破坏性开关及活跃流锁限制
- **备注**：若存在未提交冲突可能导致 pull 失败。

---

## POST /api/git/push  (routes.py:15288, impl: 22972)
- **功能**：推送本地分支改动到远程仓库（`git push`）
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"ok": true, "output": str, "git": {...}}`
- **认证**：需要登录；CSRF 校验；受破坏性开关及活跃流锁限制
- **备注**：若远程有新提交未拉取会报错并由前端提示。

---

## POST /api/git/checkout  (routes.py:15291, impl: 22994)
- **功能**：切换分支、检出远程分支或创建新分支（`git checkout`）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `ref` (string, 必填，目标分支名或 commit hash)
    - `mode` (string, 必填，`"local"` | `"remote"` | `"create"`)
    - `new_branch` (string, 可选，创建新分支时的分支名)
    - `track` (bool, 可选，是否追踪远程分支)
    - `dirty_mode` (string, 可选，默认 `"block"`；可选 `"block"` | `"carry"` 等)
- **响应**：`{"ok": true, "git": {...}, "branches": [...], "current_branch": str, "message": str}`
- **认证**：需要登录；CSRF 校验
- **备注**：当工作区有 dirty 改动且 `dirty_mode="block"` 时拒绝切换。

---

## POST /api/git/stash-checkout  (routes.py:15294, impl: 23028)
- **功能**：暂存当前未提交改动并切换分支（`git stash -> git checkout -> git stash pop`）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `ref` (string, 必填)
    - `mode` (string, 必填)
    - `new_branch` (string, 可选)
    - `track` (bool, 可选)
- **响应**：`{"ok": true, "git": {...}, "branches": [...], "current_branch": str, "stashed": bool, "pop_ok": bool}`
- **认证**：需要登录；CSRF 校验
- **备注**：用于带未提交改动跨分支切换。若 pop 冲突，工作区将保留冲突标记供用户解决。

---

# 2. 工作区管理 (Workspace Management)

## GET /api/workspaces  (routes.py:13123)
- **功能**：获取所有已保存的工作区列表及最后使用的工作区
- **参数**：无
- **响应**：
  ```json
  {
    "workspaces": [{"path": "/d/project", "name": "project"}, ...],
    "last": "/d/project",
    "terminal_remote_backend": false
  }
  ```
- **认证**：需要登录
- **备注**：数据持久化保存在 `workspaces.json`。

---

## GET /api/workspaces/suggest  (routes.py:13133)
- **功能**：根据路径前缀自动补全系统目录，用于工作区添加输入框
- **参数**：
  - Query: `prefix` (string, 可选)
- **响应**：`{"suggestions": ["/path/a", "/path/b"], "prefix": "..."}`
- **认证**：需要登录
- **备注**：过滤受限系统敏感路径，支持 `~` 展开。

---

## POST /api/workspaces/add  (routes.py:15329, impl: 23510)
- **功能**：添加一个新的工作区路径到列表
- **参数**：
  - JSON Body:
    - `path` (string, 必填)
    - `name` (string, 可选，默认使用目录名)
    - `create` (bool, 可选，若目录不存在是否自动创建)
- **响应**：`{"ok": true, "workspaces": [...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：严格防御系统根目录及敏感系统路径（如 `/System`, `/etc`, `C:\Windows` 等），支持用户 home 目录下的子目录例外。自动去除 macOS 单引号包裹。

---

## POST /api/workspaces/remove  (routes.py:15332, impl: 23563)
- **功能**：从常用列表中移除指定工作区（不删除磁盘文件）
- **参数**：
  - JSON Body: `path` (string, 必填)
- **响应**：`{"ok": true, "workspaces": [...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：仅移除配置表记录。

---

## POST /api/workspaces/rename  (routes.py:15335, impl: 23573)
- **功能**：修改已添加工作区的显示别名
- **参数**：
  - JSON Body:
    - `path` (string, 必填)
    - `name` (string, 必填)
- **响应**：`{"ok": true, "workspaces": [...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：找不到指定 path 时返回 404。

---

## POST /api/workspaces/reorder  (routes.py:15338, impl: 23589)
- **功能**：重新排列工作区列表展示顺序
- **参数**：
  - JSON Body: `paths` (string[], 必填，按新顺序排列的路径列表)
- **响应**：`{"ok": true, "workspaces": [...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：未出现在 `paths` 中的已有工作区会自动追加到末尾，防止数据丢失。

---

# 3. 定时任务 (Cron / Scheduled Jobs)

## GET /api/crons  (routes.py:13375)
- **功能**：列出当前活跃 Profile（或所有 Profile）下的全部定时任务
- **参数**：
  - Query: `all_profiles` (bool, 可选，默认 false)
- **响应**：
  ```json
  {
    "jobs": [
      {
        "id": "a1b2c3d4e5f6",
        "name": "Daily Report",
        "schedule": "0 9 * * *",
        "prompt": "Summarize tasks",
        "enabled": true,
        "deliver": "local",
        "skills": [],
        "model": "...",
        "provider": "...",
        "profile": "default",
        "last_run_at": "2026-08-21T09:00:00Z",
        "last_status": "success",
        "toast_notifications": true
      }
    ],
    "all_profiles": false,
    "active_profile": "default",
    "other_profile_count": 0,
    "cron_unavailable": false
  }
  ```
- **认证**：需要登录
- **备注**：环境缺失 `cron` 包时自动降级返回 `cron_unavailable: true` 而非 500。

---

## GET /api/crons/output  (routes.py:13400, impl: 20115)
- **功能**：获取指定定时任务最新的输出文件列表与内容窗口
- **参数**：
  - Query:
    - `job_id` (string, 必填)
    - `limit` (int, 可选，默认 5，范围 1~500)
- **响应**：`{"job_id": str, "outputs": [{"filename": str, "content": str}, ...]}`
- **认证**：需要登录
- **备注**：校验 `job_id` 防御目录遍历。

---

## GET /api/crons/history  (routes.py:13407, impl: 19954)
- **功能**：分页获取指定定时任务的历史执行记录元数据（不含全量正文，含 token/cost 用量解析）
- **参数**：
  - Query:
    - `job_id` (string, 必填)
    - `offset` (int, 可选，默认 0)
    - `limit` (int, 可选，默认 50，上限 500)
- **响应**：
  ```json
  {
    "job_id": "...",
    "runs": [
      {
        "filename": "2026-08-21_09-00-00.md",
        "size": 1024,
        "modified": 1787302800.0,
        "usage": {
          "model": "gemini-1.5-pro",
          "provider": "google",
          "input_tokens": 1200,
          "output_tokens": 350,
          "total_tokens": 1550,
          "estimated_cost_usd": 0.002,
          "duration_seconds": 3.4
        }
      }
    ],
    "total": 12,
    "offset": 0
  }
  ```
- **认证**：需要登录
- **备注**：用于轻量渲染运行历史列表。

---

## GET /api/crons/run  (routes.py:13414, impl: 20005)
- **功能**：读取单次定时任务执行产出的 Markdown 详细正文
- **参数**：
  - Query:
    - `job_id` (string, 必填)
    - `filename` (string, 必填，如 `2026-08-21_09-00-00.md`)
- **响应**：`{"job_id": str, "filename": str, "content": str, "snippet": str, "usage": {...}}`
- **认证**：需要登录
- **备注**：**注意此端点为 GET 方法**，专用于查看历史 run 的 Markdown 详情；与 `POST /api/crons/run`（手动触发执行）并存。

---

## GET /api/crons/recent  (routes.py:13421, impl: 20164)
- **功能**：查询自指定时间戳以来已完成的 cron 任务（供前端轮询推送完成通知或 Toast）
- **参数**：
  - Query: `since` (float, 可选，默认 0.0)
- **响应**：
  ```json
  {
    "completions": [
      {
        "job_id": "...",
        "name": "...",
        "status": "success",
        "completed_at": 1787302810.0,
        "toast_notifications": true,
        "session_id": "...",
        "message_count": 2
      }
    ],
    "since": 1787300000.0
  }
  ```
- **认证**：需要登录
- **备注**：自动关联最后一次生成的会话 ID 与消息条数。

---

## GET /api/crons/status  (routes.py:13428, impl: 20151)
- **功能**：查询当前正在后台执行中的 cron 任务状态与已耗时
- **参数**：
  - Query: `job_id` (string, 可选；传参查单任务，不传查所有运行中任务)
- **响应**：
  - 单任务: `{"job_id": str, "running": bool, "elapsed": float}`
  - 全局: `{"running": {"<job_id>": float, ...}}`
- **认证**：需要登录
- **备注**：基于内存锁 `_RUNNING_CRON_JOBS` 实时统计。

---

## GET /api/crons/delivery-options  (routes.py:13434, impl: 22458)
- **功能**：获取可用的 Cron 投递渠道列表（如 local、telegram、discord、slack、webhook 等）
- **参数**：无
- **响应**：`{"platforms": [{"value": "local", "label": "Local (save output only)"}, {"value": "origin", "label": "Origin (reply to creator)"}, ...]}`
- **认证**：需要登录
- **备注**：根据后端支持的 delivery plugin 动态枚举。

---

## POST /api/crons/create  (routes.py:15218, impl: 22418)
- **功能**：创建新的定时任务
- **参数**：
  - JSON Body:
    - `prompt` (string, 必填)
    - `schedule` (string, 必填，标准 5 段 cron 表达式如 `*/30 * * * *` 或自然语言)
    - `name` (string, 可选)
    - `deliver` (string, 可选，默认 `"local"`)
    - `skills` (string[], 可选)
    - `model` (string, 可选)
    - `provider` (string, 可选)
    - `profile` (string, 可选)
    - `toast_notifications` (bool, 可选，默认 true)
- **响应**：`{"ok": true, "job": {...}}`
- **认证**：需要登录；CSRF 校验；写入当前 Profile 的 `jobs.json`
- **备注**：调度器会自动校验 schedule 合法性。

---

## POST /api/crons/update  (routes.py:15225, impl: 22473)
- **功能**：修改已有定时任务的配置
- **参数**：
  - JSON Body:
    - `job_id` (string, 必填)
    - `name`, `schedule`, `prompt`, `deliver`, `skills`, `model`, `provider`, `profile`, `enabled`, `toast_notifications` 等可选修改字段
- **响应**：`{"ok": true, "job": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：未找到任务返回 404。

---

## POST /api/crons/delete  (routes.py:15232, impl: 22499)
- **功能**：删除指定定时任务
- **参数**：
  - JSON Body: `job_id` (string, 必填)
- **响应**：`{"ok": true, "job_id": str}`
- **认证**：需要登录；CSRF 校验
- **备注**：物理移出 `jobs.json` 并注销调度。

---

## POST /api/crons/run  (routes.py:15239, impl: 22512)
- **功能**：手动立即触发一次定时任务执行（异步在后台守护线程启动）
- **参数**：
  - JSON Body: `job_id` (string, 必填)
- **响应**：
  - 正常启动: `{"ok": true, "job_id": str, "status": "running"}`
  - 重复触发拦截: `{"ok": false, "job_id": str, "status": "already_running", "elapsed": float}`
- **认证**：需要登录；CSRF 校验
- **备注**：**注意此端点为 POST 方法**，触发后台 agent 实例执行，捕获当前 Profile 上下文；防重入机制避免重复启动。

---

## POST /api/crons/pause  (routes.py:15246, impl: 22548)
- **功能**：暂停定时任务（设为 disabled 状态，保留配置）
- **参数**：
  - JSON Body:
    - `job_id` (string, 必填)
    - `reason` (string, 可选)
- **响应**：`{"ok": true, "job": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：暂停后不再按 cron 时间表触发。

---

## POST /api/crons/resume  (routes.py:15253, impl: 22560)
- **功能**：恢复已暂停的定时任务
- **参数**：
  - JSON Body: `job_id` (string, 必填)
- **响应**：`{"ok": true, "job": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：重新计算下次运行时间。

---

# 4. 看板与任务调度系统 (Kanban & Task System)

> **架构总览**：`routes.py` 将 `/api/kanban/*` 全量委托给 `api.kanban_bridge` 分发器（GET: 12143, POST: 13979, PATCH: 16445, DELETE: 16481），底层统一由 SQLite `tasks`, `task_events`, `task_links`, `task_comments`, `task_runs` 驱动，支持多看板、依赖链、worker claim 分布式调度与 SSE 实时同步。

## GET /api/kanban/boards  (routes.py:12143 -> kanban_bridge.py:1167)
- **功能**：列出所有看板（含多看板元数据、各列任务计数、当前活跃看板 slug）
- **参数**：
  - Query: `include_archived` (bool, 可选，默认 false)
- **响应**：
  ```json
  {
    "boards": [
      {
        "slug": "default",
        "name": "Main Board",
        "description": "Default workspace board",
        "icon": "📋",
        "color": "#3b82f6",
        "is_current": true,
        "counts": {"todo": 5, "ready": 2, "running": 1, "blocked": 0, "done": 10},
        "total": 18
      }
    ],
    "current": "default",
    "read_only": false
  }
  ```
- **认证**：需要登录
- **备注**：单次往返获取完整多看板列表与统计。

---

## GET /api/kanban/board  (routes.py:12143 -> kanban_bridge.py:1169)
- **功能**：获取指定看板的完整泳道列与任务卡片列表（核心渲染接口）
- **参数**：
  - Query:
    - `board` (string, 可选，看板 slug，默认当前活跃看板)
    - `tenant` (string, 可选，按租户/项目过滤)
    - `assignee` (string, 可选，按执行人过滤)
    - `include_archived` (bool, 可选，默认 false)
    - `only_mine` (bool, 可选，默认 false)
    - `since` (int, 可选，增量对比 cursor)
- **响应**：
  - 若无变化（`since >= latest_event_id`）: `{"changed": false, "latest_event_id": 128, "read_only": false}`
  - 全量数据:
    ```json
    {
      "columns": [
        {"name": "triage", "tasks": [...]},
        {"name": "todo", "tasks": [...]},
        {"name": "ready", "tasks": [...]},
        {"name": "running", "tasks": [...]},
        {"name": "blocked", "tasks": [...]},
        {"name": "done", "tasks": [...]}
      ],
      "tenants": ["proj-a"],
      "assignees": ["agent-1"],
      "latest_event_id": 128,
      "changed": true,
      "read_only": false,
      "filters": {...}
    }
    ```
- **认证**：需要登录
- **备注**：每张卡片均带有 `link_counts`（父子依赖数）、`comment_count`、`age_seconds` 等增强字段。

---

## GET /api/kanban/config  (routes.py:12143 -> kanban_bridge.py:1171)
- **功能**：获取看板系统配置（标准列定义、已知分配者、Profile 泳道开关等）
- **参数**：
  - Query: `board` (string, 可选)
- **响应**：
  ```json
  {
    "columns": ["triage", "todo", "ready", "running", "blocked", "done"],
    "assignees": ["default", "agent-alpha"],
    "default_tenant": "",
    "lane_by_profile": true,
    "include_archived_by_default": false,
    "render_markdown": true,
    "read_only": false
  }
  ```
- **认证**：需要登录
- **备注**：配置融合自 `hermes_cli.config` 与 SQLite 历史分配人。

---

## GET /api/kanban/stats  (routes.py:12143 -> kanban_bridge.py:1173)
- **功能**：获取看板统计指标（按状态与按分配人聚合计数）
- **参数**：
  - Query: `board` (string, 可选)
- **响应**：`{"by_status": {"todo": 5, "done": 12, ...}, "by_assignee": {"unassigned": 3, "admin": 14}}`
- **认证**：需要登录
- **备注**：排除 archived 状态任务。

---

## GET /api/kanban/assignees  (routes.py:12143 -> kanban_bridge.py:1175)
- **功能**：获取看板已知的所有分配人列表（用于新建/指派卡片下拉菜单）
- **参数**：
  - Query: `board` (string, 可选)
- **响应**：`{"assignees": ["agent-1", "agent-2", "user"]}`
- **认证**：需要登录
- **备注**：从 tasks 表中去重提取历史 assignee。

---

## GET /api/kanban/events  (routes.py:12143 -> kanban_bridge.py:1177)
- **功能**：分页获取看板全局任务事件日志（轮询模式）
- **参数**：
  - Query:
    - `board` (string, 可选)
    - `since` (int, 可选，默认 0)
    - `limit` (int, 可选，默认 200，范围 1~200)
- **响应**：`{"events": [{"id": 1, "task_id": "...", "kind": "status", "payload": {...}, "created_at": 1787300000}], "cursor": 128, "latest_event_id": 128, "read_only": false}`
- **认证**：需要登录
- **备注**：事件类型包含 `created`, `status`, `assigned`, `updated`, `comment`, `blocked`, `unblocked`, `run_started`, `run_ended` 等。

---

## GET /api/kanban/events/stream  (routes.py:12143 -> kanban_bridge.py:1179)
- **功能**：长连接 Server-Sent Events (SSE) 实时推送看板事件流
- **参数**：
  - Query:
    - `board` (string, 可选)
    - `since` (int, 可选，支持从 `Last-Event-ID` 头部或 query 恢复游标)
- **响应**：SSE Stream (`text/event-stream; charset=utf-8`)
  - 事件帧：
    - `event: hello` (`{"cursor": int, "board": str}`)
    - `id: <event_id>` 
 `event: events` 
 `data: {"events": [...], "cursor": int}`
    - `: keepalive`（心跳，每 15 秒）
- **认证**：需要登录
- **备注**：长连接推送，前端无需 30s 轮询，延迟降低至 300ms 内。

---

## GET /api/kanban/tasks/{id}/log  (routes.py:12143 -> kanban_bridge.py:1180)
- **功能**：读取指定任务对应后台 Worker 进程的原始执行日志
- **参数**：
  - Path: `id` (string, 任务 ID)
  - Query:
    - `board` (string, 可选)
    - `tail` (int, 可选，截取末尾字节数，上限 2MB)
- **响应**：`{"task_id": str, "path": str, "exists": bool, "size_bytes": int, "content": str, "truncated": bool}`
- **认证**：需要登录
- **备注**：任务不存在时返回 404。

---

## GET /api/kanban/tasks/{id}  (routes.py:12143 -> kanban_bridge.py:1188)
- **功能**：获取单个任务卡片的完整详情（任务字段、所有评论、事件流、依赖关系、历史执行轮次 runs）
- **参数**：
  - Path: `id` (string, 任务 ID)
  - Query: `board` (string, 可选)
- **响应**：
  ```json
  {
    "task": {"id": "t-123", "title": "...", "status": "todo", "priority": 1, "body": "...", ...},
    "comments": [{"id": 1, "author": "user", "body": "...", "created_at": 1787300000}],
    "events": [...],
    "links": {"parents": ["t-100"], "children": ["t-124"]},
    "runs": [{"id": "r-1", "worker_pid": 12345, "status": "succeeded", ...}],
    "read_only": false
  }
  ```
- **认证**：需要登录
- **备注**：卡片模态弹窗的核心数据接口。

---

## POST /api/kanban/boards  (routes.py:13979 -> kanban_bridge.py:1218)
- **功能**：创建新的看板
- **参数**：
  - JSON Body:
    - `slug` (string, 必填，字母数字中划线)
    - `name` (string, 可选)
    - `description` (string, 可选)
    - `icon` (string, 可选，如 emoji 图标)
    - `color` (string, 可选，十六进制色值)
    - `switch` (bool, 可选，创建后是否立即设为当前活跃看板)
- **响应**：`{"board": {...}, "current": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：创建操作幂等，相同 slug 重复提交返回已有看板元数据。

---

## POST /api/kanban/boards/{slug}/switch  (routes.py:13979 -> kanban_bridge.py:1222)
- **功能**：切换全局当前活跃看板
- **参数**：
  - Path: `slug` (string, 目标看板 slug)
- **响应**：`{"current": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：活跃看板指针写入 `<root>/kanban/current`，CLI、Gateway、Dashboard、WebUI 全端同步生效。

---

## POST /api/kanban/dispatch  (routes.py:13979 -> kanban_bridge.py:1232)
- **功能**：手动触发单次看板自动任务派发（调度器扫描 ready 任务并拉起 worker）
- **参数**：
  - Query:
    - `board` (string, 可选)
    - `dry_run` (bool, 可选，默认 false)
    - `max` (int, 可选，最大派发数，默认 8，上限 100)
- **响应**：`{"spawned": 2, "ready": 0, "claimed": [...], ...}`
- **认证**：需要登录；CSRF 校验
- **备注**：调度器不可用时抛出 400。

---

## POST /api/kanban/tasks/bulk  (routes.py:13979 -> kanban_bridge.py:1234)
- **功能**：批量操作任务（批量归档、批量改状态、批量指派、批量改优先级）
- **参数**：
  - JSON Body:
    - `ids` (string[], 必填，任务 ID 列表)
    - `archive` (bool, 可选，为 true 时批量归档)
    - `status` (string, 可选，目标状态)
    - `assignee` (string, 可选，目标分配人)
    - `priority` (int, 可选，目标优先级)
    - `board` (string, 可选)
- **响应**：`{"results": [{"id": "t-1", "ok": true}, {"id": "t-2", "ok": false, "error": "not found"}], "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：单次事务内批量执行，返回每条任务的独立执行结果。

---

## POST /api/kanban/tasks  (routes.py:13979 -> kanban_bridge.py:1236)
- **功能**：新建看板任务卡片
- **参数**：
  - JSON Body:
    - `title` (string, 必填)
    - `body` (string, 可选)
    - `assignee` (string, 可选)
    - `created_by` (string, 可选，默认 `"webui"`)
    - `tenant` (string, 可选)
    - `priority` (int, 可选，默认 0)
    - `status` (string, 可选，默认 `"todo"`)
    - `parents` (string[], 可选，前置依赖任务 ID 列表)
    - `triage` (bool, 可选，若为 true 初始状态进入 triage 列)
    - `workspace_kind` (string, 可选，默认 `"scratch"`)
    - `workspace_path` (string, 可选)
    - `idempotency_key` (string, 可选)
    - `max_runtime_seconds` (int, 可选)
    - `skills` (string[], 可选)
    - `board` (string, 可选)
- **响应**：`{"task": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：支持在创建时直接声明前置依赖关系及自定义运行环境配置。

---

## POST /api/kanban/links  (routes.py:13979 -> kanban_bridge.py:1238)
- **功能**：在两个任务之间建立父子依赖关系（Parent -> Child）
- **参数**：
  - JSON Body:
    - `parent_id` (string, 必填)
    - `child_id` (string, 必填)
    - `board` (string, 可选)
- **响应**：`{"ok": true, "parent_id": str, "child_id": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：建立后 Child 任务在 Parent 未完成（done）前会被阻塞在依赖等待队列。

---

## POST /api/kanban/links/delete  (routes.py:13979 -> kanban_bridge.py:1240)
- **功能**：解除两个任务之间的父子依赖关系（POST 兼容端点）
- **参数**：
  - JSON Body:
    - `parent_id` (string, 必填)
    - `child_id` (string, 必填)
    - `board` (string, 可选)
- **响应**：`{"ok": true, "changed": bool, "parent_id": str, "child_id": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：为不支持 DELETE 方法或习惯 POST 的客户端提供的兼容端点，与 `DELETE /api/kanban/links` 功能完全一致。

---

## POST /api/kanban/tasks/{id}/comments  (routes.py:13979 -> kanban_bridge.py:1242)
- **功能**：为指定任务卡片添加讨论评论
- **参数**：
  - Path: `id` (string, 任务 ID)
  - JSON Body:
    - `body` (string, 必填，评论正文)
    - `author` (string, 可选，默认 `"webui"`)
    - `board` (string, 可选)
- **响应**：`{"ok": true, "comment_id": int, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：触发 task_events `comment` 事件通知。

---

## POST /api/kanban/tasks/{id}/block  (routes.py:13979 -> kanban_bridge.py:1245)
- **功能**：将任务标记为阻塞状态（`status = "blocked"`）
- **参数**：
  - Path: `id` (string, 任务 ID)
  - JSON Body:
    - `reason` 或 `block_reason` (string, 可选，阻塞原因)
    - `board` (string, 可选)
- **响应**：`{"task": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：记录结构化 block 原因并触发 blocked 事件。

---

## POST /api/kanban/tasks/{id}/unblock  (routes.py:13979 -> kanban_bridge.py:1245)
- **功能**：解除任务的阻塞状态，将其推进到 `ready` 状态
- **参数**：
  - Path: `id` (string, 任务 ID)
  - JSON Body:
    - `board` (string, 可选)
- **响应**：`{"task": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：触发 unblocked 事件并重新计算 ready 队列。

---

## POST /api/kanban/tasks/{id}/patch  (routes.py:13979 -> kanban_bridge.py:1249)
- **功能**：更新任务字段（POST 兼容端点，功能等同于 `PATCH /api/kanban/tasks/{id}`）
- **参数**：
  - Path: `id` (string, 任务 ID)
  - JSON Body: `title`, `body`, `status`, `assignee`, `priority`, `tenant`, `result`, `summary`, `board` 等
- **响应**：`{"task": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：旧版前端/第三方客户端兼容路由。

---

## PATCH /api/kanban/config  (routes.py:16445 -> kanban_bridge.py:1268)
- **功能**：修改看板显示全局配置（如按 Profile 划分泳道）
- **参数**：
  - JSON Body:
    - `lane_by_profile` (bool, 必填)
- **响应**：`{"columns": [...], "lane_by_profile": bool, ...}`
- **认证**：需要登录；CSRF 校验
- **备注**：配置持久化写入全局 `config.yaml`。

---

## PATCH /api/kanban/boards/{slug}  (routes.py:16445 -> kanban_bridge.py:1277)
- **功能**：修改指定看板的展示属性（名称、描述、图标、主题色、归档状态）
- **参数**：
  - Path: `slug` (string, 看板 slug)
  - JSON Body:
    - `name` (string, 可选)
    - `description` (string, 可选)
    - `icon` (string, 可选)
    - `color` (string, 可选)
    - `archived` (bool, 可选)
- **响应**：`{"board": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：看板 slug 本身作为主键不可变。

---

## PATCH /api/kanban/tasks/{id}  (routes.py:16445 -> kanban_bridge.py:1287)
- **功能**：标准 RESTful 局部更新任务卡片属性（支持拖拽改状态、改指派人、改标题等）
- **参数**：
  - Path: `id` (string, 任务 ID)
  - JSON Body:
    - `title` (string, 可选)
    - `body` (string, 可选)
    - `status` (string, 可选，`"triage"` | `"todo"` | `"ready"` | `"blocked"` | `"done"` | `"archived"`)
    - `assignee` (string, 可选)
    - `priority` (int, 可选)
    - `tenant` (string, 可选)
    - `result` (string, 可选，完成时填入)
    - `summary` (string, 可选)
    - `block_reason` (string, 可选)
    - `board` (string, 可选)
- **响应**：`{"task": {...}, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：**核心约束**：严禁直接将 status PATCH 为 `"running"`（running 必须通过 claim 调度进入，直接写入将返回 400 报错）；从 running 拖出时会自动解除 claim lock 并结束 active run。

---

## DELETE /api/kanban/boards/{slug}  (routes.py:16481 -> kanban_bridge.py:1311)
- **功能**：归档或硬删除指定看板
- **参数**：
  - Path: `slug` (string, 看板 slug)
  - Query: `delete` (bool, 可选，默认 false；若为 1 则从磁盘彻底硬删除，否则仅置为 archived)
- **响应**：`{"result": {...}, "current": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：**严禁删除 `default` 看板**（尝试删除 default 会返回 400）。若删除了当前活跃看板，系统自动回退至 default。

---

## DELETE /api/kanban/links  (routes.py:16481 -> kanban_bridge.py:1319)
- **功能**：标准 RESTful 解除两个任务之间的父子依赖关系
- **参数**：
  - JSON Body:
    - `parent_id` (string, 必填)
    - `child_id` (string, 必填)
    - `board` (string, 可选)
- **响应**：`{"ok": true, "changed": bool, "parent_id": str, "child_id": str, "read_only": false}`
- **认证**：需要登录；CSRF 校验
- **备注**：解除后若 Child 任务无其他未完成依赖，自动重算进入 ready 候选。

---

# 5. 技能生态 (Skills Ecosystem)

## GET /api/skills  (routes.py:13442)
- **功能**：获取当前 Profile 激活的所有技能清单（支持按分类筛选）
- **参数**：
  - Query: `category` (string, 可选)
- **响应**：
  ```json
  {
    "skills": [
      {
        "name": "git-tools",
        "description": "Git operations skill",
        "category": "developer",
        "enabled": true,
        "path": "/.../skills/git-tools/SKILL.md",
        "builtin": false
      }
    ]
  }
  ```
- **认证**：需要登录
- **备注**：合并内置 skills 与用户 profile 下自定义 skills。

---

## GET /api/skills/usage  (routes.py:13448)
- **功能**：获取技能调用与使用统计分析（use_count, view_count, patch_count 等）
- **参数**：无
- **响应**：
  ```json
  {
    "usage": {
      "git-tools": {"use_count": 14, "view_count": 5, "patch_count": 1}
    },
    "skill_names": ["git-tools", "..."],
    "total_invocations": 20,
    "unique_skills_used": 1
  }
  ```
- **认证**：需要登录
- **备注**：从 `skill_usage.json` 读取并聚合计量数据。

---

## GET /api/skills/content  (routes.py:13484)
- **功能**：获取指定技能的 `SKILL.md` 正文或其目录下的关联附加文件
- **参数**：
  - Query:
    - `name` (string, 必填，技能名称)
    - `file` (string, 可选，技能目录下的子文件相对路径)
- **响应**：
  - 默认: `{"name": str, "content": str, "metadata": {...}, "linked_files": {...}}`
  - 子文件: `{"content": str, "path": str}`
- **认证**：需要登录
- **备注**：严格防御路径遍历与非法通配符字符（`*?[\]`）。

---

## POST /api/skills/save  (routes.py:15392, impl: 25137)
- **功能**：创建或更新技能的 `SKILL.md` 源码文件
- **参数**：
  - JSON Body:
    - `name` (string, 必填，技能唯一标识名)
    - `content` (string, 必填，Markdown 源码)
    - `category` (string, 可选)
- **响应**：`{"ok": true, "name": str, "path": str}`
- **认证**：需要登录；CSRF 校验
- **备注**：安全沙箱限制：禁止写入符号链接文件；严格校验路径必须限定在 active profile skills 目录下。保存后自动刷新统计缓存。

---

## POST /api/skills/delete  (routes.py:15395, impl: 25168)
- **功能**：删除指定自定义技能（物理删除整个技能目录）
- **参数**：
  - JSON Body: `name` (string, 必填)
- **响应**：`{"ok": true, "name": str}`
- **认证**：需要登录；CSRF 校验
- **备注**：未找到技能返回 404。

---

## POST /api/skills/toggle  (routes.py:15398, impl: 25209)
- **功能**：启用或禁用指定技能（更新 active profile `config.yaml` 中的 disabled 列表）
- **参数**：
  - JSON Body:
    - `name` (string, 必填)
    - `enabled` (bool, 必填)
- **响应**：`{"ok": true, "name": str, "enabled": bool}`
- **认证**：需要登录；CSRF 校验
- **备注**：双写更新全局 `skills.disabled` 以及 WebUI 平台特定禁用项 `skills.platform_disabled.webui`。

---

# 6. 长期记忆与人格 (Memory & Soul)

## GET /api/memory  (routes.py:13519, impl: 20406)
- **功能**：读取当前 Profile 下的长期记忆 (`MEMORY.md`)、用户信息 (`USER.md`)、人设 (`SOUL.md`) 及当前工作区的项目上下文 (`PROJECT.md` / `HERMES.md`)
- **参数**：
  - Query: `workspace` (string, 可选)
- **响应**：
  ```json
  {
    "memory": "# Long-term Memories
...",
    "user": "# User Profile
...",
    "soul": "# Soul & Tone
...",
    "project_context": "...",
    "memory_path": "/.../memories/MEMORY.md",
    "user_path": "/.../memories/USER.md",
    "soul_path": "/.../SOUL.md",
    "project_context_path": "/.../HERMES.md",
    "project_context_name": "HERMES.md",
    "project_context_workspace": "/d/workspace",
    "memory_mtime": 1787300000.0,
    "user_mtime": 1787300000.0,
    "soul_mtime": 1787300000.0,
    "project_context_mtime": 1787300000.0,
    "project_context_shadowed": false,
    "external_notes_enabled": false
  }
  ```
- **认证**：需要登录
- **备注**：返回内容均经过敏感凭据脱敏清洗 (`_redact_text`)。

---

## POST /api/memory/write  (routes.py:15402, impl: 25263)
- **功能**：修改长期记忆 (`MEMORY.md`)、用户信息 (`USER.md`) 或人设 (`SOUL.md`)
- **参数**：
  - JSON Body:
    - `section` (string, 必填，只能为 `"memory"` | `"user"` | `"soul"`)
    - `content` (string, 必填，Markdown 文本)
- **响应**：`{"ok": true, "section": str, "path": str, "mtime": float}`
- **认证**：需要登录；CSRF 校验
- **备注**：安全沙箱机制：拒绝向符号链接目标写入，防止通过恶意符号链接破坏外部宿主系统文件。

---

# 7. 洞察与用量统计 (Insights & Usage)

## GET /api/insights  (routes.py:12138, impl: 10695)
- **功能**：获取全站会话用量分析与洞察图表数据（Token 消耗、费用走势、模型分布、Prompt 缓存命中率、活跃时段等）
- **参数**：
  - Query: `days` (int, 可选，默认 30，范围 1~365)
- **响应**：
  ```json
  {
    "period_days": 30,
    "total_sessions": 45,
    "total_messages": 380,
    "total_input_tokens": 1250000,
    "total_output_tokens": 85000,
    "total_cache_read_tokens": 450000,
    "prompt_cache_hit_percent": 26.5,
    "total_cost": 1.45,
    "models": [
      {
        "model": "claude-3-7-sonnet",
        "sessions": 30,
        "input_tokens": 800000,
        "output_tokens": 60000,
        "cache_read_tokens": 300000,
        "cache_hit_percent": 27.2,
        "total_tokens": 860000,
        "cost": 1.12,
        "session_share": 67,
        "token_share": 64,
        "cost_share": 77
      }
    ],
    "daily": [{"date": "2026-08-20", "input_tokens": 50000, "output_tokens": 4000, "cost": 0.05, "sessions": 3}, ...],
    "activity_by_dow": [{"day": "Mon", "sessions": 10}, ...],
    "activity_by_hour": [{"hour": 14, "sessions": 8}, ...]
  }
  ```
- **认证**：需要登录
- **备注**：聚合算法同时扫描 WebUI 的 `_index.json` 及 Hermes CLI 的 `state.db` 本地数据库，提供全景统计；Prompt 缓存命中率经上下界严格钳位（0~100%）。

---

## GET /api/session/usage  (routes.py:13004)
- **功能**：查询单个会话的详细 Token 消耗、缓存读取与预估开销明细
- **参数**：
  - Query: `session_id` (string, 必填)
- **响应**：`{"session_id": str, "input_tokens": int, "output_tokens": int, "cache_read_tokens": int, "total_tokens": int, "estimated_cost_usd": float, "prompt_cache_hit_percent": float|null}`
- **认证**：需要登录
- **备注**：会话不存在返回 404。

---

# 8. 快捷提示词库 (Prompts Library)

## GET /api/prompts  (routes.py:13117)
- **功能**：获取所有已保存的常用快捷提示词 (Saved Prompts)
- **参数**：无
- **响应**：`{"prompts": [{"id": "p-1a2b3c", "label": "Code Review", "text": "Please review this code for...", "created_at": 1787300000.0}, ...]}`
- **认证**：需要登录
- **备注**：存储在 `saved_prompts.json`。

---

## POST /api/prompts  (routes.py:13998)
- **功能**：保存一条新的常用提示词
- **参数**：
  - JSON Body:
    - `text` (string, 必填，单条上限 8000 字符)
    - `label` (string, 可选，若不填默认截取 text 前 60 字符)
- **响应**：`{"ok": true, "prompt": {"id": str, "label": str, "text": str, "created_at": float}}`
- **认证**：需要登录；CSRF 校验
- **备注**：系统上限保护：最多保存 200 条提示词，超出返回 400 `saved prompts limit reached`。

---

## DELETE /api/prompts  (routes.py:16473)
- **功能**：删除指定已保存的常用提示词
- **参数**：
  - JSON Body: `id` (string, 必填)
- **响应**：`{"ok": true}`
- **认证**：需要登录；CSRF 校验
- **备注**：未提供 id 返回 400。

---

# 9. 知识库 / 文档 (LLM Wiki)

## GET /api/wiki/status  (routes.py:12153, impl: 10690)
- **功能**：检测 LLM 知识库 (Wiki) 的配置与可用状态
- **参数**：无
- **响应**：`{"enabled": bool, "path": str|null, "exists": bool, "page_count": int}`
- **认证**：需要登录
- **备注**：从配置文件或环境变量探查 wiki_root 是否配置且有效。

---

## GET /api/wiki/browse  (routes.py:12155)
- **功能**：浏览 Wiki 根目录下的所有 Markdown 文档页面清单
- **参数**：无
- **响应**：
  ```json
  {
    "pages": [
      {
        "name": "architecture.md",
        "path": "docs/architecture.md",
        "size": 4096,
        "mtime": 1787300000
      }
    ]
  }
  ```
- **认证**：需要登录
- **备注**：白名单机制过滤非 md 文件及隐藏文件。

---

## GET /api/wiki/page  (routes.py:12170)
- **功能**：读取 Wiki 中的单篇 Markdown 页面正文
- **参数**：
  - Query: `path` (string, 必填，相对 wiki_root 的页面路径)
- **响应**：`{"content": str, "path": str}`
- **认证**：需要登录
- **备注**：**安全加固**：包含 `O_NOFOLLOW` 描述符打开、`(st_dev, st_ino)` 稳定身份核对与 TOCTOU 竞争防御，杜绝符号链接逃逸与越权读取敏感文件；最大单页读取上限为 `_LLM_WIKI_MAX_PAGE_BYTES`。

---

# 10. 生产辅助：回滚快照 / 导出 / 压缩 / 决策看板

## GET /api/session/export  (routes.py:13120, impl: 16621)
- **功能**：导出指定会话记录为 JSON 格式或独立可渲染的 HTML 离线查看包
- **参数**：
  - Query:
    - `session_id` (string, 必填)
    - `format` (string, 可选，`"json"` (默认) | `"html"`)
    - `theme` (string, 可选，默认 `"dark"`)
    - `palette` (string, 可选，base64 编码的自定义色盘 JSON)
- **响应**：
  - JSON 导出: 下载 `hermes-{sid}.json` (`application/json`)
  - HTML 导出: 下载 `hermes-{sid}.html` (`text/html; charset=utf-8`)
- **认证**：需要登录；受 Profile 会话隔离约束
- **备注**：所有导出均经过 `redact_session_data` 脱敏，防止导出泄露 API Key 等机密。

---

## GET /api/rollback/list  (routes.py:13591, impl: api/rollback.py:list_checkpoints)
- **功能**：获取指定工作区由 Hermes Agent CheckpointManager 创建的文件系统还原检查点列表
- **参数**：
  - Query: `workspace` (string, 必填，必须为已知配置的工作区路径)
- **响应**：
  ```json
  {
    "workspace": "/d/project",
    "checkpoints": [
      {
        "id": "c1a2b3c4d5e6",
        "timestamp": 1787300000.0,
        "datetime": "2026-08-21T09:00:00Z",
        "turn": 3,
        "files_changed": 4,
        "description": "Before tool execution"
      }
    ]
  }
  ```
- **认证**：需要登录
- **备注**：检查点保存在 `{hermes_home}/checkpoints/<hash>/` 的 Shadow Git 仓库中；校验 checkpoint id 正则防遍历。

---

## GET /api/rollback/diff  (routes.py:13605, impl: api/rollback.py:get_checkpoint_diff)
- **功能**：比较指定检查点快照与当前工作区实际文件之间的 Diff 差异
- **参数**：
  - Query:
    - `workspace` (string, 必填)
    - `checkpoint` (string, 必填)
- **响应**：
  ```json
  {
    "workspace": "/d/project",
    "checkpoint": "c1a2b3c4d5e6",
    "diff": "diff --git a/src/main.py b/src/main.py
...",
    "files": [{"path": "src/main.py", "status": "modified"}]
  }
  ```
- **认证**：需要登录
- **备注**：还原前预览改动。

---

## POST /api/rollback/restore  (routes.py:16408, impl: api/rollback.py:restore_checkpoint)
- **功能**：将工作区文件物理还原回指定的检查点快照状态
- **参数**：
  - JSON Body:
    - `workspace` (string, 必填)
    - `checkpoint` (string, 必填)
- **响应**：`{"ok": true, "workspace": str, "checkpoint": str, "restored_files": [...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：物理回滚文件系统；自动保留并恢复文件可执行权限位。

---

## GET /api/session/compress/status  (routes.py:12459, impl: 24123)
- **功能**：查询当前会话后台上下文压缩任务的执行进度与状态
- **参数**：
  - Query: `session_id` (string, 必填)
- **响应**：`{"compressing": bool, "progress": str|null, "error": str|null, "started_at": float|null}`
- **认证**：需要登录
- **备注**：配合压缩启动端点使用。

---

## POST /api/session/compress/start  (routes.py:15107, impl: 24037)
- **功能**：异步启动会话上下文压缩任务（在后台线程执行 LLM 对话摘要与精简）
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"ok": true, "session_id": str, "status": "started"}`
- **认证**：需要登录；CSRF 校验
- **备注**：若已有压缩正在进行则返回 409。

---

## POST /api/session/compress  (routes.py:15110, impl: 24142)
- **功能**：同步执行会话上下文压缩（直接等待压缩完成并返回新消息列表）
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `target_tokens` (int, 可选)
- **响应**：`{"ok": true, "session_id": str, "original_messages": int, "compressed_messages": int, "tokens_saved": int}`
- **认证**：需要登录；CSRF 校验
- **备注**：适合短会话或自动化脚本同步等待。

---

## POST /api/session/compression-recovery/start  (routes.py:14230, impl: 21603)
- **功能**：在会话遭遇破坏性上下文溢出时，拉起智能安全修复流程（重建索引并裁剪损坏的上下文轮次）
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"ok": true, "session_id": str, "repaired": bool, "details": {...}}`
- **认证**：需要登录；CSRF 校验
- **备注**：极端异常下的恢复工具。

---

## POST /api/session/conversation-rounds  (routes.py:15113, impl: 24454)
- **功能**：智能解析会话历史，将扁平消息列表聚合为逻辑上的「多轮交互回合 (Conversation Rounds)」，支持选定轮次截断或总结
- **参数**：
  - JSON Body: `session_id` (string, 必填)
- **响应**：`{"rounds": [{"round_index": 0, "user_message": {...}, "assistant_messages": [...], "token_estimate": int}, ...]}`
- **认证**：需要登录；CSRF 校验
- **备注**：用于分轮次精细化上下文管理。

---

## POST /api/session/handoff-summary  (routes.py:15116, impl: 24689)
- **功能**：生成会话交接摘要 (Handoff Summary)，提炼当前会话的核心结论、已完成项与待办项，用于传递给新会话或 Project OS
- **参数**：
  - JSON Body:
    - `session_id` (string, 必填)
    - `workspace` (string, 可选)
- **响应**：`{"ok": true, "summary": str, "handoff": {"goal": str, "completed": [...], "pending": [...], "next_steps": [...]}}`
- **认证**：需要登录；CSRF 校验
- **备注**：结构化提炼任务进展。

---

## GET /api/project-os/dashboard  (routes.py:12140, impl: 11172)
- **功能**：获取 Project OS 统一项目态势看板（融合 Git 状态、项目文档 PROJECT/PLAN/STATUS.md、交接状态 handoff、心跳 active 等）
- **参数**：
  - Query: `board` (string, 可选，关联的看板 slug)
- **响应**：
  ```json
  {
    "workspace": "/d/repo",
    "repo_root": "/d/repo",
    "selected_board_slug": "default",
    "git": {"branch": "main", "dirty": 0, ...},
    "docs": {
      "project": "# Project Overview
...",
      "plan": "# Roadmap
...",
      "status": "# Current Sprint
...",
      "blocker_resolver": "..."
    },
    "handoff": {"board": {...}, "goal_summary": "..."},
    "active": {...},
    "heartbeat": {...},
    "onboarding": {"active": false, ...},
    "goal_summary": "..."
  }
  ```
- **认证**：需要登录
- **备注**：Project OS 决策层核心端点，自动嗅探工作区 `.ax/` 状态文件与根目录文档。

---

# 11. 域 C 未分类 / 疑点清单

1. **`routes.py:13414` 与 `routes.py:15239` 路径重名 (`/api/crons/run`)**：
   - **已确认**：GET 对应 `_handle_cron_run_detail`（查看单次运行 Markdown 日志内容）；POST 对应 `_handle_cron_run`（手动触发执行）。二者方法不同，功能互补，已分别建卡。
2. **`routes.py:12143`, `13979`, `16445`, `16481` 之 `/api/kanban/*` 分发**：
   - **已确认**：`routes.py` 内部使用统一前缀桥接至 `kanban_bridge.py` 中的 `handle_kanban_get`, `handle_kanban_post`, `handle_kanban_patch`, `handle_kanban_delete`，且对 `is False` 进行了 404 捕获。所有 25 个子路径已全量展开建卡。
3. **`routes.py:13853` 之 `/api/workspace/upload`**：
   - **已确认**：该端点处理工作区文件上传，属于域 B 媒体与文件管理范畴（在 `task_domain_b.md:23` 中覆盖），本域 C 保留标准工作区元数据管理端点（`/api/workspaces/*`）。
4. **`POST /api/git/commit` vs `POST /api/git/commit-selected`**：
   - **已确认**：前者假定文件已在暂存区（纯 commit），后者由前端传入目标文件列表自动完成 stage 并原子 commit。
