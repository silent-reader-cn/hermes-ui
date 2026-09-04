# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

## [方向·已定案] 内置 WebUI Sidecar — 像 Clash Verge 捆 mihomo 那样一键捆绑 Hermes WebUI 后端（Windows）

**类型**：功能方向类（2026-09-03 与主人对齐完毕，可直接转任务书扇出 agy）

### 背景与目标

现状：hermes-ui 对 WebUI 的集成止步于「引导安装」——onboarding 页让用户点按钮走 git clone + pip + 手动启动（`lib/features/onboarding/install_guide_page.dart`，阶段枚举 `webuiDeploy/webuiDeps/webuiServer`）。

目标（主人原话画像）：把 WebUI 做成**一键下载、随 app 内置**的组件：
- app 静默启动 → 按 app 内配置的**端口 / 监听 IP / WebUI 密码**自动拉起 WebUI 后端；
- 托盘右键退出 → 连带停掉 WebUI 后端；
- 托盘右键 → 直接在浏览器中打开本 app 捆绑的 WebUI。

类比：**Clash Verge 捆绑 mihomo 核心**（Clash 启动核心启动、Clash 关闭核心关闭、Verge 提供设置界面写核心配置）。同类产品对照：Ollama（app 拉 server:11434、随退、开机自启）、ComfyUI Desktop（embedded Python + zip 整包）。差异点：本栈是 GUI(hermes-ui) ↔ webui(服务器,轻) ↔ agent(引擎,重) 三层，本次只绑中间层。

### 实测基础（2026-09-03 源码/磁盘实证）

| 事实 | 位置 |
|---|---|
| WebUI 本体极轻：stdlib `http.server` 单进程，依赖仅 pyyaml+cryptography | `D:\hermes-webui\requirements.txt`（18 行）、`server.py` |
| 代码 ~20MB（api 12M + static 7.1M + scripts 104K，排除 .git/tests/docs）；**agent 全家 3.6G / venv 1.8G** | du 实测 |
| 端口/绑定/密码全走环境变量，**webui 侧零改动**：`HERMES_WEBUI_HOST`（默认 127.0.0.1）/ `HERMES_WEBUI_PORT`（默认 8787）/ `HERMES_WEBUI_PASSWORD`（优先级 env > settings 文件） | `api/config.py:49-50`、`api/auth.py:2-4` |
| webui 的 state/session/config 落 `HERMES_HOME`（默认 `~\AppData\Local\hermes` 侧），与 agent 共用 profile → 不写安装目录。**2026-09-03 复核实证**：`STATE_DIR = HERMES_WEBUI_STATE_DIR→HERMES_HOME→平台默认` 拼 `webui`，Windows 平台默认即 `%LOCALAPPDATA%\hermes`（paths.py:47 注释官方明示），sessions/settings.json/.sessions.json/.login_attempts.json 全在 STATE_DIR 下（auth.py:103,218,329）；SQLite `state.db` 属 **agent**（agent_sessions.py:10-39 优先 readonly URI 打开），同在 HERMES_HOME；`server.py` 无 FileHandler（日志全 stdout/stderr，app tee 接走）；自更新 `updates.py:8-9` 对无 `.git` 的 repo 自动 skip → 内置包删 .git 后天然熄火 | `api/config.py:77-88`、`api/paths.py:44-59`、`api/auth.py:103` |
| app 已有：clone/pip/DETACHED 启动 + `/health` 轮询骨架（**DETACHED 发射后不管：不持 PID、不能停，与 Verge 式托管的差距核心在这**） | `lib/core/install/webui_bootstrap.dart:52-86,106-120` |
| 托盘已有（显示主窗口/新建会话/最近会话/退出应用），`handleQuit` 仅 `windowManager.destroy()`，无核心停止钩子、无「打开 WebUI」项 | `lib/features/desktop/tray_manager_service.dart:93-96,351-363` |
| 静默启动/开机自启已通（注册表 `--silent`），supervisor 挂启动链空位现成 | `lib/features/desktop/desktop_settings.dart:17,32,161-189` + `startup_registrar.dart` |
| pubspec 有 tray_manager/window_manager，**无 url_launcher**（开浏览器需新增） | `pubspec.yaml:55,57` |
| CI 只有 analyze-test / android-debug / fake-gateway，**无 Windows 桌面打包流水线** | `.github/workflows/ci.yml` |

### 主人已拍板决策（2026-09-03，9 项）

1. **捆绑范围：只绑 WebUI 后端**；agent 维持现状（`install_detector` 检测已有安装 + 引导安装），不绑 3.6G 引擎。
2. **运行时策略：A 内置 sidecar**——安装包携带 embedded Python + webui 源码 zip，子进程托管（持 PID 可停可查）。排除 B（PyInstaller/Nuitka 冻结 exe：动态导入+自带 self-update 维护成本高）与 C（首启联网自动安装：内置感弱）。
3. **生命周期：设置页加开关「内置 WebUI 服务」**。开启 → app 启动（正常窗口/静默均）自动拉起、托盘退出连带停；关闭 → 完全不拉。符合"WebUI 新功能须设置开关"惯例。
4. **浏览器打开体验：直达登录页**，密码 app 已配、用户复制粘贴输一次；不做 trusted-header 免密（`HERMES_WEBUI_TRUSTED_AUTH_HEADER` 能力存在但本期不用）。
5. **版本通道：随 app 版本走**（Verge 绑核心节奏）——app 更新即换内置包，不单独做「检查 WebUI 更新」。
6. **运行目录：安装目录内直接运行**（`<安装目录>\webui\`），日志写 `%LOCALAPPDATA%\hermes\webui-bundled\logs\`。
7. **共存语义：开关只管内置实例**——与引导安装的 git-clone 版（`%LOCALAPPDATA%\hermes\webui`）、用户自建 fork 实例并存互不干涉，端口/密码各配各的；内置实例遇**同端口**已有监听才报占用失败。
8. **范围包含 Windows 打包工程**：Inno Setup + CI `windows-installer` job 全写入本规格，一并拆任务。
9. **默认端口 8787**（webui 上游默认），host 默认 `127.0.0.1`，均可在设置页改。

### 技术方案要点

**新增 Dart 服务 `WebuiSidecarService`**（`lib/features/webui_sidecar/`）：
- 定位内置包：打包后安装目录下 `<exe所在目录>\webui\`（embedded python + `webui\server.py`）；开发模式可用 env/配置覆盖路径（方便未打包先联调）。
- 启动：`Process.start`（**子进程非 DETACHED**，持 PID；stdout/stderr app 侧 tee 到 LOCALAPPDATA 日志）；env 注入：`HERMES_WEBUI_HOST/PORT/PASSWORD` + `HERMES_HOME`（沿用默认 profile）+ `PYTHONDONTWRITEBYTECODE=1`（Program Files 只读防 `__pycache__` 写入失败，见风险①）。
- 停止：先温和 terminate；Windows 下用 `taskkill /T /PID`（或 job object）连进程树清，防 agent 会话 spawn 的孤儿。
- 健康：复用现有 `HealthChecker`（`/health` status:ok 轮询）；运行期 watchdog：进程意外退出 → 自动重启（带上限退避），托盘图标/设置页反映状态（运行中/失败/已停止）。
- 配置存储：`desktop_settings.dart` 同款 shared_preferences 模式新增 `webui_sidecar_enabled/port/host/password`（password 是秘密，遵循 `server_connection.dart:8` 安全约定，只存本地不进日志）。

**托盘与生命周期**：
- `tray_manager_service.dart` 菜单新增：「在浏览器中打开 WebUI」（sidecar 开启且健康时启用，否则置灰；`url_launcher` 打开 `http://<host>:<port>`）＋状态展示（菜单项 label 带运行状态即可，不加二级控制——启停归设置页）。
- `handleQuit()`：destroy 窗口前先 `sidecar.stop()`（超时兜底强杀）。
- app 启动链（main / `desktop_lifecycle_observer`）：`silentStart` 与正常启动均检查开关 → 拉起。

**设置页**（`settings_subpages.dart` 桌面区扩展）：开关 + 端口 + 监听 IP + 密码 + 状态指示 + 日志目录快捷入口；文案本地化进 l10n（中英）。

**内置包构建（CI 新 job `windows-installer`）**：
1. `flutter build windows --release`；
2. 下载 Python **embeddable amd64 3.11.x** zip 解压；
3. 给 embeddable 启用 site-packages 并用完整版 pip `--target` 预装 `pyyaml cryptography`（embeddable 发行版默认无 pip，**运行时零 pip**）；
4. `git clone --depth=1 nesquena/hermes-webui` → 删 `.git/tests/docs` → 记 `webui_version.txt`（上游 commit）；
5. 组装 `webui\`（python-embed + 源码）→ Inno Setup 编译安装包；
6. agent 不在包内：首启检测缺失 → 现有引导流程（决策 1）。

**webui 上游改动预期：零**（全部 env 注入满足；若实测发现 Windows 下 `bootstrap.py` 平台拒绝等问题，走 `start.ps1` 注释所示直调 `server.py`，app 侧本就直调 `python server.py`）。

### 风险与边界（缺省裁定，主人可推翻）

① Program Files 只读：**已实证闭环**（见上表 2026-09-03 复核行）——数据/SQLite/日志默认全落 `%LOCALAPPDATA%`，免管理员；安装目录唯一潜在写入 `__pycache__` 用 `PYTHONDONTWRITEBYTECODE=1` 挡掉；**S4 打包硬约束追记**：内置包发布前必须删 `.git`（自更新 updates.py 依赖 .git 存在才动作，删后天然熄火，与决策 5「版本随 app 走」闭环）。
② 端口占用：内置实例启动前探测目标端口，被占 → 状态置「启动失败·端口占用」并托盘/设置页可见，**不自动换端口**（语义明确优先）。
③ app 多实例同时拉 sidecar：启动前 `/health` 探测——若目标端口已是**本内置实例**（版本文件比对）则接管不重拉；是陌生进程按②处理。app 单实例 mutex 是否已存在待实施时核实，若无则记已知边界。
④ 卸载残留：Inno 卸载器清安装目录；LOCALAPPDATA 日志与 `HERMES_HOME` state 属用户数据默认保留（卸载页给勾选清理事项）。
⑤ 未签名 exe + Windows Defender SmartScreen 弹窗：发布流程问题，不在本条代码范围，release notes 提示。
⑥ Android/macOS：本条 **Windows only**；sidecar 服务接口留跨平台抽象但不做分发。

### 验收标准

1. 全新 Windows 机器（有 agent、无 git 无 python）：装 app → 开「内置 WebUI 服务」→ 重启 app（含 `--silent`）→ `/health` 200 且配置端口/绑定 IP 与设置一致（实证：netstat + 响应体）。
2. 托盘「退出应用」后 `tasklist` 无 webui 残留 python 进程及其子进程树。
3. 托盘「在浏览器中打开 WebUI」→ 默认浏览器打开登录页，app 内所设密码可登录。
4. 改密码/端口 → 重启 sidecar（或提示重启生效）后新配置生效；关开关 → 实例停止且不再自动拉起。
5. 与 git-clone 版实例（不同端口）并存互不干涉；同端口 → 明确报占用失败。
6. 安装到 `C:\Program Files\` 下（非管理员运行 app）全流程无权限报错（验证①）。
7. CI `windows-installer` job 产出可安装 exe；`flutter analyze` 零告警；新增 sidecar 单测（fake ProcessExecutor + HealthChecker 注入，沿用 `webui_bootstrap` 既有测试模式）全绿；全量回归绿。
8. 崩溃演练：手动 kill 内置 python 进程 → watchdog 自动拉起，托盘状态短暂「重启中」后恢复。

### 建议拆分（agy worktree 并行，1 任务 1 worktree）

| # | 任务 | 分区（文件） | 依赖 |
|---|---|---|---|
| S1 | WebuiSidecarService（启动/停止/健康/watchdog/env 注入/日志 tee）+ 单测 | `lib/features/webui_sidecar/**`, `pubspec.yaml`（如引 win32/process 依赖） | 无（开发模式路径 env 覆盖，不依赖打包） |
| S2 | 设置页开关+端口+IP+密码+状态 UI + l10n | `lib/features/settings/settings_subpages.dart`（桌面区）, `lib/l10n/**` | S1 接口 |
| S3 | 托盘菜单两项（打开 WebUI + 状态）+ handleQuit 停核心 + 启动链拉起 + `url_launcher` | `lib/features/desktop/tray_manager_service.dart`, `desktop_lifecycle_observer.dart`, `pubspec.yaml` | S1 |
| S4 | 内置包构建脚本 + Inno Setup + CI `windows-installer` job | `scripts/packaging/**`, `installer/**`, `.github/workflows/ci.yml` | 独立可并行（产物路径与 S1 约定 `<安装目录>\webui\`） |
| S5 | 全链路集成验收（验收 1-8 实测 + 文档 `docs/specs/`） | docs | S1-S4 收口后 |

**不做（明确排除）**：不绑 agent；不做 webui 独立更新通道；不做 trusted-header 免密；不做 Android/macOS 分发；不改 webui 上游代码（除非实测卡点，卡点须书面说明）。

---

## [方向·已定案] 引导页改造 — 「内置服务」优先（分段控件+一键启动并连接），并废弃 git clone WebUI 部署流

**类型**：功能方向类（2026-09-03 与主人对齐完毕，依赖上一条 sidecar 的 S1/S2；可直接转任务书）

### 背景与目标

主人诉求：Windows 下引导页允许直接使用内置 Hermes WebUI 服务，**不必填外部 URL/端口/密码**；UI 设计上「内置」优先于「连接远程」。

### 现状（源码实证 2026-09-03）

| 事实 | 位置 |
|---|---|
| 引导页=单页「连接服务器」：URL 输入框+两阶段提交（`/health`→`/api/auth/status`→就地密码框→login→upsert+setActive→`context.go('/')`） | `lib/features/onboarding/onboarding_page.dart:31-61,150-330` |
| 页面底部「本机一键安装部署」Banner（仅 Windows 且未安装显示）→ push `/install-guide` 7 阶段向导（prereqs/agent/agentDeps/**webuiDeploy/webuiDeps/webuiServer**/llmConfig） | `onboarding_page.dart:397-405,410-465`；`install_guide_page.dart:19-26` |
| 连接模型通用 `ServerConnection`（baseUrl/password/customHeaders），secure storage；`activeConnectionProvider` 变化→`apiClientProvider` 重建；路由守卫要求有 active 连接 | `lib/core/connections/server_connection.dart:15-35`、`connection_providers.dart:86-161` |
| `CupertinoSlidingSegmentedControl` 为项目成熟范式 | `lib/features/settings/settings_page.dart:123,228,739` |
| webui 找不到 agent 时 `_discover_agent_dir()` 返回 None → 服务可起但聊天不可用 → 内置 Tab 必须处理 agent 缺失 | `D:\hermes-webui\api\config.py:132-187` |

### 主人已拍板决策（2026-09-03，4 项）

1. **引导页形制=分段控件增强版**：Windows 打包版标题下加 `CupertinoSlidingSegmentedControl` 两段「内置服务 | 连接服务器」，**默认选中「内置服务」**（柚子缺省裁定：记忆用户上次选择，主人可推翻）；内置 Tab 一键**「启动并连接」**——端口/IP/密码本来就是 app 注入 sidecar 的，app 全知道 → **自动 login，用户零手输**；高级设置折叠（端口/监听 IP/密码/开机自启，与 S2 设置页同源数据）。
2. **agent 缺失时**：内置 Tab 不置灰，顶部插「需先安装 Hermes 引擎」卡，按钮进安装向导**只跑 agent 相关阶段**。
3. **废弃 git clone WebUI 部署流**（推翻柚子"保留退路"建议）：内置 sidecar 上线后删除 webuiDeploy/webuiDeps/webuiServer 三阶段与对应能力，减少双轨维护。连带影响见下"裁撤清单"。
4. **多服务器列表中内置连接固定存在、不可删、只能停用**：列表 UI 对 builtin 行不渲染删除按钮，给「停用/启用」；停用=关 sidecar 开关。

### 裁撤清单（决策 3 的连带范围，实施时精确执行）

- `install_guide_page.dart`：`InstallStageKey` 删 `webuiDeploy/webuiDeps/webuiServer` 三枚举及对应执行代码；保留 prereqs/agent/agentDeps/llmConfig（agent 本身仍需 Python+pip）。向导入口从「远程 Tab 底部 Banner」迁为「内置 Tab agent 缺失卡」（Banner 本体删除）。
- `lib/core/install/webui_bootstrap.dart`：删 `cloneOrPull/installDependencies/startServer`（DETACHED 启动整段废弃）；**`HealthChecker`/`SystemHealthChecker` 保留**（S1 sidecar 复用）。实施前必须 grep 该文件全部引用，防止误伤 agent 安装/llm_onboarding 链路（`powershell_installer.dart` 若同时服务 agent 安装则只裁 webui 相关调用方，文件本体保留）。
- l10n：webui 部署三阶段相关键清理，新增内置 Tab 键。
- 远程 Tab 只留 URL 表单原样（假定用户已有服务器），不再有本地部署入口。

### 数据模型（决策 4 落地）

- `ServerConnection` 新增 `kind: 'builtin' | 'remote'`（默认 remote，**存量已存连接反序列化兼容**：无字段→remote）。
- builtin 连接：`baseUrl` 由 sidecar 配置派生（host 为 `0.0.0.0` 时 app 本地连接用 `127.0.0.1`——记入风险①）；password 与 sidecar 注入值同源，存 secure storage 同规（不进日志）。
- 引导页/连接列表/路由守卫按 kind 区分渲染（删除按钮、停用动作、Tab 默认选中）；`apiClientProvider` 链路零改动。

### 内置 Tab 状态机

`未启动`（按钮=启动并连接）→ `启动中`（loading，超时 30s 判失败）→ `● 运行中 host:port`（已 active 则按钮=进入会话列表；健康）｜`失败`（区分端口占用/agent 缺失/健康超时，就地红字+重试）。运行中 sidecar 崩溃 → watchdog 拉起期间胶囊显示「重启中」（沿用上条风险②③语义）。

### 跨平台边界

非 Windows / 检测不到内置包（`<安装目录>\webui\` 不存在）→ **分段控件不渲染**，页面=现有 URL 表单原样（Android 零回归，金照不变）。原 `install_detector.isInstalled` 语义拆为两个探测：`bundledWebuiAvailable`（新）与 `agentInstalled`（沿用）。

### 平台差异说明

内置 sidecar 上线后，引导页存在**三种形态**：A=Windows 打包版（双段内置优先）；B=Windows 未打包/dev 或非 Windows（纯远程表单，现状原样）。任务书须写明 A/B 判定条件（打包版=安装目录内置包探测）。

### 风险与边界（缺省裁定，可推翻）

① builtin 连接 host=0.0.0.0 派生规则如上；若主人希望监听 0.0.0.0 时托盘/浏览器打开也换成本机局域网 IP，属 sidecar 条目的展示增强，不在本条。
② 「停用」时若 active 恰为 builtin：自动 clearActive → 回引导页（内置 Tab 仍选中、状态=未启动）——柚子的缺省裁定，主人可推翻。
③ 决策 3 废弃后，Windows 极客"自定义路径部署 WebUI"退路消失；远程 Tab 仍可连任意已有服务器（含用户自部署的），故实际不损失"连自建服务器"能力，损失的是"让 app 帮我 git clone 部署"能力。已知悉并拍板。

### 验收标准

1. Windows 打包版冷启动（有 agent）：引导页默认「内置服务」选中 → 点「启动并连接」→ **全程零手输**进会话列表；`/health` 200 于配置端口。
2. Windows 打包版（无 agent）：内置 Tab 顶部出现引擎引导卡 → 向导只跑 prereqs/agent/agentDeps/llmConfig 四阶段（**grep 确认 webui 三阶段代码已无**）。
3. 「连接服务器」段：与改造前行为逐像素一致（URL+两阶段提交+错误弹窗）；页面上无安装部署 Banner。
4. 连接列表：builtin 行无删除按钮、有停用/启用；停用后按风险②裁定表现；remote 连接照常可删。
5. 存量升级：改造前保存的 remote 连接在新版全部正常（kind 兼容），active 不变。
6. Android 全量回归：引导页/连接流程零变化，金照绿。
7. `flutter analyze` 零告警；新增引导分段/状态机/kind 序列化单测全绿；全量测试绿。

### 建议拆分（接上一条 S 系列，1 任务 1 worktree）

| # | 任务 | 分区（文件） | 依赖 |
|---|---|---|---|
| U1 | 数据模型 kind 字段+存量兼容+连接列表停用/无删除 UI | `lib/core/connections/**`, `lib/features/settings/profile_section.dart` | 无（先行） |
| U2 | 引导页分段控件+内置 Tab（状态机/一键启动并连接/agent 缺失卡/高级折叠） | `lib/features/onboarding/onboarding_page.dart`, 新 `lib/features/onboarding/widgets/**` | S1, S2, U1 |
| U3 | 向导瘦身（webui 三阶段裁撤+bootstrap 删留+Banner 移除） | `lib/features/onboarding/install_guide_page.dart`, `lib/core/install/webui_bootstrap.dart` | S1 收口后执行（先删会有空窗） |
| U4 | l10n 中英键 + 金照更新 + 回归 | `lib/l10n/**`, golden | U1-U3 |

**不做（明确排除）**：不做 trusted-header 免密直达（登录概念在内置路径被"app 自动 login"吸收，浏览器路径沿用上条决策 4）；不动 `ServerConnection` 的多服务器切换/路由守卫主链路；不做非 Windows 的内置形态。

**修订注记（2026-09-03 主人追加，同日翻案定稿）**：本条 U2/U3 的 UI 布局规格以下一条「宽屏双栏铁律」为准——引导页与向导页宽屏形态一律**双栏：左品牌氛围区 + 右单列表单**，禁止窄屏拉伸逻辑上宽屏。拆任务书时两条合并。

---

## [方向·已定案] 引导体系宽屏双栏铁律 — 左品牌氛围区 + 右单列表单（第一印象优先）

**类型**：问题+方向混合（主人 2026-09-03 强调并同日定稿形制；修订上两条 sidecar/引导页任务的 UI 规格，U2/U3 实施必须遵守本铁律）

**主人诉求（原话画像）**：Windows 引导页一般是宽屏模式，不得沿用窄屏布局逻辑；不要再出现全宽文本框（很丑）；应用给用户的第一印象最重要。形制翻案定稿：**双栏布局，左部品牌氛围区，右侧单列**（否决初选"整窗居中窄列"案）。

### 现状问题（源码实证 2026-09-03）

| 问题 | 位置 |
|---|---|
| `/onboarding`、`/install-guide` 为**顶层 GoRoute，不进 `AdaptiveShell` 外壳**（router.dart:30 注释官方定义「全屏向导」；守卫白名单豁免重定向） → `kAdaptiveBreakpoint=900` 宽屏适配体系完全管不到两页 | `lib/app/router.dart:30,72-74`（及 shell 外的两 GoRoute 定义） |
| 引导表单=`ListView(padding:24)` **无任何 maxWidth 约束** → 宽屏下标题/说明/URL 输入框/健康状态行 edge-to-edge 拉伸（主人点名丑的全宽输入框即此） | `lib/features/onboarding/onboarding_page.dart:363-405` |
| 底部按钮「Column+Expanded+贴底通栏大按钮」是手机键盘避让的窄屏骨架，宽屏上=横跨全屏巨条 | `onboarding_page.dart:340-358` |
| 安装向导主内容区同样无宽度约束（仅非 Windows 占位页有 Center） | `install_guide_page.dart:427-446` |
| 项目内宽屏收束先例：设置页 segmented control 套 `ConstrainedBox(maxWidth: 220~240)` | `settings_page.dart:119-125,224,734` |

### 已定案

1. **布局形制=双栏**（主人翻案定稿，否决初选"整窗居中窄列"案）：
   - **左栏=品牌氛围区**：app 名/Logo/slogan/卖点插画类内容（极简灰白调性，与主人审美一致），占 40-50% 宽，可随主题明暗；具体美术素材由主人后续定（缺省裁定：先用文字+几何/插画占位氛围，不阻塞开发）。
   - **右栏=单列功能区**：`maxWidth 420~480` 表单列，垂直（含水平）居中；分段控件、远程表单、内置 Tab、高级折叠、向导步骤列表全收于此列；按钮右栏列内通宽，**禁止**跟窗口同宽。同类产品参照：Notion/Figma/Raycast 官网登录页双栏形态。
2. **两页同受约束**（主人确认）：onboarding 与 install-guide 都走双栏形态。
3. **断点策略**（缺省裁定——主人对本问超时未选，柚子按推荐落"是"，可推翻）：窗口宽 `≥ kAdaptiveBreakpoint(900)` 启用双栏；`<900`（含 Android、窄窗口）**保持现有全宽移动端形态不变**（窄屏退化为纯右栏内容形态，左品牌区隐藏），Android 零回归、现有金照不动。断点常量从 `adaptive_shell.dart:19` 导出复用，不再造新值。
4. **不改行为只改骨架**：两阶段提交逻辑、文案、路由、状态机全部不动；纯布局层改造。

### 验收标准

1. Windows 宽窗（≥1280 实测）：引导页与向导页呈双栏——左品牌氛围区（约占 40-50% 宽）、右表单列（实际渲染宽度 ≤480 且列内水平垂直居中）；widget test 实证右栏表单容器 ≤480，无任何 edge-to-edge 拉伸控件、无全宽文本框。
2. 窄窗/Android：渲染与改造前一致（双栏退化为纯右栏内容形态、左品牌区隐藏，视觉等于现状），现有金照全绿不动。
3. 断点跨界 resize（900↔1280 拖动）：双栏↔单栏即时切换、零 RenderFlex overflow。
4. 宽屏双栏新形态补金照（Windows 桌面尺寸档，含左品牌区）入 U4 收尾。
5. 主人实机目检验收（第一印象主观项，重点左栏氛围与右栏比例）。

### 与前两条的关系

本条为 U2（引导页分段+内置 Tab）、U3（向导瘦身）的**布局层强制规格**；拆任务书时：U2/U3 的任务描述合并本条铁律，宽屏金照归 U4。上两条若先拆分，须携本条一并下发。

---

## [问题·待取证定稿] 安卓前台服务保活开关打开后无常驻通知、系统通知类别无对应渠道（服务从未启动，失败被三层静默吞）

**类型**：问题类（Android 后台保活 / flutter_foreground_task 插件契约）

**测试机**：HyperOS（小米/红米），Android 14+（主人确认）。

**位置**：
- `lib/features/notifications/background_keepalive_service.dart:151-228` — `initialize()`：`_initialized=true` 在 try 之前（:153）；步骤顺序 ①WorkManager.initialize ②registerPeriodicTask ③`FlutterForegroundTask.init()`（:179-192）④冷启动条件拉起（:199-207）；整段 try/catch 仅写诊断日志。
- `lib/features/notifications/background_keepalive_service.dart:290-340` — `startForegroundService()`：`FlutterForegroundTask.startService()`（:314-316）**未传 `callback` 参数**。
- `lib/features/notifications/notification_providers.dart:145-156` — `setBgForegroundServiceEnabled()`：`state.copyWith` 先乐观置 true，再 `startForegroundService()`，外层 `catch (_) {}` 全吞。
- `lib/main.dart:421-423` — 冷启动 `unawaited(initialize())`。
- 渠道创建方（插件原生）：`flutter_foreground_task-8.17.0/android/.../ForegroundService.kt:249-251` — `startForegroundService()` 内 `createNotificationChannel()`，**服务不启动则渠道必不存在**。
- 插件抛点：`flutter_foreground_task-8.17.0/lib/flutter_foreground_task.dart:107-108` — `startService()` 首行 `if (!isInitialized) throw ServiceNotInitializedException()`。

**范围**：Android 前台服务保活链路（常驻通知 + WakeLock/WifiLock + 渠道）。不涉及：WorkManager 周期轮询本身（独立链路，可能正常）、`flutter_local_notifications` 的 4 个业务渠道（截图证实存在：需要澄清/下载完成/异常中断/回合完成）、回合完成通知推送、iOS/桌面。

**复现**（主人实机 2026-09-04 截图 `Screenshot_2026-09-04-11-03-06-226`）：设置→后台保活→打开「前台服务保活」开关（UI 显示开启）→ ①下拉通知栏无常驻通知；②系统设置→应用→Hermes→通知权限设置：「常驻通知」权限开关系统级已开（蓝），但「通知类别」列表**无「后台生成保活」渠道**（channelId `hermes_foreground_service`）。

**现状 vs 预期**：
- 现状：开关乐观置 true、无报错无通知无渠道——服务从未启动，失败三层静默（init catch 只进诊断日志 / 开关 catch 全吞 / 插件异常无 UI 反馈）。
- 预期：开关打开 → 数秒内通知栏出现常驻通知（「Hermes / N 个会话正在生成」）+ 系统通知类别出现「后台生成保活」渠道；任何一步失败 → 开关回滚 + 就地错误提示，绝不假成功。

**根因（两分支，待诊断日志取证定稿）**：
- **分支 A（首要嫌疑）**：`initialize()` 在 ①② 步（WorkManager initialize / registerPeriodicTask）抛异常 → ③ `FlutterForegroundTask.init()` 从未执行 → 插件 `isInitialized=false`；又因 `_initialized=true` 先置位，后续调用**永不重试 init**。开关触发 `startForegroundService()` → 插件抛 `ServiceNotInitializedException` → `catch (_) {}` 吞 → 症状完全吻合。**取证点**：诊断页 tag=keepalive 应有「后台保活服务初始化失败」+「启动前台保活服务失败」两条（errorKind 含 ServiceNotInitializedException）。
- **分支 B（契约违约，独立成立）**：全工程无 `setTaskHandler`/TaskHandler 实现，`startService()` 未传 `callback`（插件 README:353 明确 callback 为调 setTaskHandler 的顶层函数）。即使分支 A 排除、服务侥幸启动，任务 isolate 无 handler → `eventAction` 事件循环与任务生命周期全废（插件源码 `ForegroundTask.kt:63-69`：callbackHandle==null 时不执行 Dart 回调）。本 app 的 handler 无业务逻辑需求（`eventAction: nothing()`），但**契约上必须注册**，否则行为不受插件支持。
- 排除项：HyperOS 通知拦截概率低——拦截场景渠道仍会注册，与"渠道不存在"不符。

**取证状态**：主人正在 App 内诊断页（设置→诊断，drift 持久化）搜 `keepalive` 取条目；结果贴回后本条根因定稿、状态改 [已定稿]。若两条失败日志皆无 → 需补查 initialize 是否被调用（`main.dart:422` 平台判定）。

**修复规格（主人已拍板两项，取证定稿后转任务书）**：
1. **init 顺序/标志位修复 + 失败可见化**：
   - `FlutterForegroundTask.init()` 提前为第一步（纯 Dart 静态赋值，无依赖，不该排在易抛的 WorkManager 之后）；`_initialized=true` 移到全部关键步骤成功之后，或分步标志位（fgTaskReady / wmReady 独立，互不阻塞）。
   - `setBgForegroundServiceEnabled`：失败 → `state` 回滚 false + 就地红字/toast 显示具体原因（复用 l10n 错误文案模式），**禁 `catch (_) {}` 静默**；诊断日志照写。
   - `startForegroundService` 的 catch 同理：向上冒泡返回值或异常，供调用方回滚。
2. **按插件契约补 TaskHandler + callback**：
   - 顶层 `@pragma('vm:entry-point') void foregroundTaskCallback() { FlutterForegroundTask.setTaskHandler(HermesKeepaliveTaskHandler()); }`（对齐 `workmanagerCallbackDispatcher` 既有模式）。
   - `HermesKeepaliveTaskHandler extends TaskHandler`：onStart/onRepeatEvent/onStop 空实现或仅诊断日志（当前 eventAction=nothing()，无周期逻辑）。
   - 三处 `startService()` 调用（冷启动 :206、开关 :152、生命周期 :260）统一传 `callback: foregroundTaskCallback`。

**验收**：
1. HyperOS/Android14+ 实机：开关打开 → 通知栏出常驻通知；系统通知类别出现「后台生成保活」渠道。
2. 杀掉 app 重开（开关已开）→ 冷启动自动拉起，通知恢复（:199-207 路径）。
3. 故障注入（测试）：mock 插件 startService 抛异常 → 开关回滚 false + 错误提示可见，无假成功态。
4. 常驻通知文本随流状态更新（复用既有 `updateNotification`/`onAppLifecycleChanged` 链路回归）。
5. 单测：init 步骤部分失败后 fgTask init 仍完成、重试语义正确；widget/unit 测开关回滚路径。
6. `flutter analyze` 零告警 + 全量测试绿。

**备注**：本条为独立 bug 修复线，与 sidecar/引导页三条无文件交集，可并行开 worktree。取证结果若指向分支 A 之外的第三种异常（如 WorkManager 步骤本身在 HyperOS 抛错），修复面 ① 的顺序调整已天然覆盖；若日志显示 initialize 从未运行（无「初始化失败」条目），则根因上移至 `main.dart:422` 调用时机，届时修订本条。
