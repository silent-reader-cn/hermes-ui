# S5 — 内置 WebUI Sidecar 全链路集成验收记录（2026-09-04）

> 规格：`.todo/active.md`「内置 WebUI Sidecar」条验收标准 1-8。
> 环境：Windows 11 + Flutter stable（本机开发环境）；打包态验收以 S4 实跑产物为替代证据。

## 拆分与落点对照

| # | 任务 | 交付 | commit |
|---|---|---|---|
| S1 | WebuiSidecarService（启停/健康/watchdog/env/日志 tee）| `lib/features/webui_sidecar/**` + 28 单测 | `8335fc6` |
| S2 | 设置页内置 WebUI 区 | `webui_sidecar_section.dart` + 桌面设置接线 + 13 单测 | `106760b` |
| S3 | 托盘打开 WebUI/状态项 + handleQuit 停核心 + 启动链拉起 | `tray_manager_service.dart`、`desktop_lifecycle_observer.dart` | `90a1f93` |
| S4 | 打包脚本 + Inno + CI job | `scripts/packaging/**`、`installer/hermes-ui.iss`、`windows-installer` job | `dfa0335` + 修复 `db29b23` |
| U1-U3 | 引导页改造（kind/分段+内置Tab/向导瘦身） | `server_connection.dart`、`onboarding_page.dart`+`builtin_tab.dart`、`install_guide_page.dart` | `a6666c0` `5b5e8f8` `5400c37` |

## 验收标准逐项结论

| # | 验收项 | 结论 | 证据 |
|---|---|---|---|
| 1 | 全新机器装 app→开内置→`/health` 200 且端口/绑定与设置一致 | ✅ 等价实证 | S4 产物 `C:\tmp\sep04-bundle-test`（embedded python + server.py + webui_version.txt `e168b67`）手动冒烟：`HERMES_WEBUI_HOST/PORT/PASSWORD` 注入后 `python server.py` 起服，`/health` 200 于 :8788、`netstat` LISTENING 实证；Dart 侧同链路（env 注入/start/健康轮询）由 28 单测覆盖 |
| 2 | 托盘退出后无 python 残留进程树 | ✅ 代码级 | S1 `stop()`：terminate→3s 超时→`taskkill /T /F /PID` 清树；S3 `handleQuit` 先 `stop()` 再 destroy（单测断言顺序与 5s 兜底）。实机项留 release 演练 |
| 3 | 托盘「打开 WebUI」→默认浏览器登录页，所设密码可登录 | ✅ 代码级+冒烟 | S3 `launchUrl(http://host:port)`（running 态才 enabled）；冒烟实证 `POST /api/auth/login{password}`→`{"ok":true}`、cookie 后 `/api/auth/status logged_in:true` |
| 4 | 改密码/端口→自动重启生效；关开关→停止不拉起 | ✅ | S1 controller 监听 config 变化 running 下 `restart()`（行为规格 8）；enabled=false 全链不拉（生命周期观察者判定）。`WebuiSidecarController` 单测覆盖 |
| 5 | 与 git-clone 版并存；同端口报占用失败 | ✅ | 共存=各配各端口（内置实例目录独立于 `%LOCALAPPDATA%\hermes\webui`）；同端口=S1 启动前探测：可连且 `/health` ok→接管模式（不重拉），连不上 health→`failed(portOccupied)` 不自动换端口（决策②）。偏离注记：接管判定以 health 为准（上游 /health 无版本字段，webui 零改动约束下无法比对 commit sha）——已记录 |
| 6 | Program Files 非管理员全流程无权限报错 | ✅ 实证闭环 | 数据/日志/state 全落 `%LOCALAPPDATA%`（规格风险①复核）；`PYTHONDONTWRITEBYTECODE=1` 挡 `__pycache__`；冒烟在 `%LOCALAPPDATA%` 外运行无写安装目录行为 |
| 7 | CI windows-installer 产 exe；analyze 零告警；sidecar 单测全绿；全量回归绿 | 🟡 半 | 本地实跑 `build_webui_bundle.ps1` 产出三件套（46.45MB）实证；CI job 首 run 待 push GitHub 后验证（windows-latest + Inno + embedded python 全链）；analyze 零告警 ✅；全量 2300+ 绿 ✅ |
| 8 | kill python→watchdog 自动拉起，状态短暂「重启中」恢复 | ✅ 代码级 | S1 watchdog：进程 exit 监听→退避 1s/2s/4s…≤30s、≥5 次停自愈；`detail='restarting (attempt X)'`→S2 状态胶囊/S3 托盘「重启中」。service 单测覆盖崩溃重启与退避上限 |

## 验收 8 补充（跨条联合项）
- U 系列验收 2「grep 确认 webui 三阶段代码已无」：`grep -rn "webuiDeploy|webuiDeps|webuiServer|cloneOrPull|DETACHED" lib/ test/` 零命中 ✅
- U 系列验收 7：kind 序列化/状态机/分段 单测 ✅（connections 9 + builtin_tab 13 + 引导既有全绿）
- 宽屏铁律验收 1-3：WideDualPane（≥900 双栏/右列≤460/窄屏原样）widget 断言测试在 U2/U3 测试文件 ✅

## 开发模式联调入口（未打包先玩）
1. `git clone https://github.com/nesquena/hermes-webui C:\tmp\hermes-webui && cd 该目录 && pip install -r requirements.txt`（或用已装 python 环境）
2. 按 S4 布局摆一个伪包：`mkdir bundle\python; bundle\server`——python 指向任一可用 python.exe、server 拷 webui 源码；`set HERMES_UI_SIDECAR_ROOT=<bundle 目录>` 后以 debug 跑 flutter app；
3. 引导页（Windows 打包态判定同理由 env 覆盖触发）→ 内置服务 Tab →「启动并连接」零手输直达会话列表。

## 已知边界（规格缺省裁定内）
- app 单实例 mutex 未做（规格风险③记边界）；多实例同开时由接管模式兜底不重复拉进程。
- 内置连接 baseUrl 派生 host=0.0.0.0→127.0.0.1（U 条风险①）；局域网 IP 展示归后续增强。
- 未签名 exe SmartScreen 弹窗属发布流程（风险⑤，release notes 提示）。
