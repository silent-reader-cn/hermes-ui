# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### #46 [P2] Windows 首次运行自安装引导页 — 一键拉取/配置/部署 agent + webui（方向类 · 主人 2026-09-02 拍板）

- 类型：方向类（Windows 端部署体验新功能）。主人指令：「在 Flutter 应用中提供一个自动安装引导页，帮助 Windows 用户一步一步从 GitHub 拉取、配置和安装部署，不用依赖 webui 才能运行我们的项目」。三个决策点已 clarify 拍板：**webui 仓库 = 官方 upstream（nesquena/hermes-webui，非主人 fork）**；**LLM 配置 = 引导页接管**（步骤向导填 provider/key，走 webui onboarding API）；**优先级 = P2**（排在 #44/#45 之后）。
- 位置（全部为新增，无现有代码可改）：
  - `lib/features/onboarding/` 新增安装引导页（后续确认承接 onboarding_page 还是独立路由）；复用 `ServerConnection{baseUrl,password}` + `ConnectionStore` 自动写入 `http://127.0.0.1:8787` 本地连接并激活
  - Windows 进程中转层（新增 `lib/core/install/`）：Dart `Process` 驱动 PowerShell 调官方 `install.ps1 -Stage <name> -NonInteractive -Json`，逐行解析 JSON 事件帧 → 进度条 + 日志流；`-Manifest` 列 stages、`{ok:false,stage,reason}` 错误帧 → 失败页直接展示
  - webui 部署：官方 upstream clone 后 `python -m pip install -r requirements.txt`（仅 pyyaml+cryptography，超薄）；启动 `server.py` 用 pythonw + DETACHED_PROCESS|CREATE_NO_WINDOW + log 重定向（bootstrap.py:622-658 现成模板语义）；轮询 `/health` 直到 ok（bootstrap.py wait_for_health 语义）
  - LLM 配置向导：走 webui onboarding API（已有 `/api/onboarding` 契约，参考 onboarding-projects 现有 client 能力）
- 现状 vs 预期：
  - 现状：hermes-ui 是纯远程客户端，onboarding 让用户填服务器地址+密码；**没有 webui 服务端就完全不可用**（依赖另装 Hermes Agent + webui 部署），普通 Windows 用户门槛极高。
  - 预期：Windows 首启检测 `%LOCALAPPDATA%\hermes` 不存在 → 引导页「本机部署」入口 → 分步安装（官方 install.ps1 免交互驱动：prereqs → git clone → venv → deps → PATH）→ 部署 webui → 启动 → 健康轮询 → provider 向导 → 自动建 ServerConnection(localhost) → 直接进聊天。已有连接时跳过（检测 `hermes` 命令 / `%LOCALAPPDATA%\hermes\hermes-agent` 存在）。
- 范围：
  - 仅 Windows 平台（Android 不需要自安装——手机连远程服务器是常态；勿扩展到 Android）
  - **不**动 API 契约（仍走同一套 webui /api/*）、不动远程连接模式（保留，多 ServerConnection 并存）、不改现有 10 个 feature
  - **不**重复造安装器轮子：官方 install.ps1 已做 git 拉取/venv/deps/PATH/更新标记，引导页只做「驱动 + 展示 + 联调」
  - webui 用官方 upstream 意味着端口默认 8787（非 fork 30002）——引导页写 localhost 连接一律以实际启动端口为准
- 验收：
  1. 全新 Windows（无 hermes-agent）：首启引导页识别「未安装」→ 点「本机部署」→ 分步安装完成（各 stage 有标题/进度/日志，失败有 stage+reason 错误提示与重试）
  2. 装完自动拉起 webui → /health ok → 自动写入并激活 ServerConnection(baseUrl=http://127.0.0.1:8787) → 进聊天页可对话
  3. provider 配置向导：填 key/选 provider → onboarding API 保存成功 → 模型列表可见
  4. 已安装环境：首启直接进连接页/聊天页，不重复安装
  5. `flutter analyze` 零告警；`flutter test` 全绿（新增安装中转层单测 + 引导页 widget 测试）
- 备注：实现时机在 #44/#45 收口后（现已收口，可启动）；官方 desktop（Electron）已存在同类能力，本项目差异化 = webui 契约 + Flutter 跨端（手机连远程、PC 连本机同一套契约）。可行性已实证：官方 install.ps1（`https://hermes-agent.nousresearch.com/install.ps1`，~245KB）内置 -Stage/-NonInteractive/-Json/-Manifest/-HermesHome 参数，注释明说供 GUI installer 调用。