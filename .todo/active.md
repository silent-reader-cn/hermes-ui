# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#56-#63 已全部收口誊写至 `.todo/20260905.md`；#64 胶囊方案 E 已收口至 `.todo/20260905.md`；#65-#70、#71、#73、#74、#75 已收口誊写至 `.todo/20260906.md`）

---

---

---

---

---

### #76 [P1] 内置服务 agent 门禁 + 砍 embedded Python（两期，方案已定 · 未开工）

- 位置：
  - 引导页内置 Tab：`lib/features/onboarding/widgets/builtin_tab.dart`（agent 缺失卡 + `:574/:615` 「启动并连接」按钮）
  - 设置页内置服务区：`lib/features/settings/webui_sidecar_section.dart`（开关行）
  - 解释器选择：`webui_sidecar_service.dart:299-314`（三级 venv→.venv→embedded 塌缩为一级）
  - 打包：`scripts/packaging/build_webui_bundle.ps1`（砍 python 下载/裁剪段）、`installer/hermes-ui.iss`（删 `webui\python` 打包行）
- 范围（两期）：
  - **一期（纯客户端门禁）**：未检测到 agent venv（`%LOCALAPPDATA%\hermes\hermes-agent\venv|.venv\Scripts\python.exe` 均不存在）时——① 引导页「启动并连接」置灰 + 引导卡给 Hermes Agent 官方安装文档外链 + 「我装好了，重新检测」按钮（主人拍板：入口可见、点击弹提示+外链）；② 设置页内置服务开关禁开，点击弹「需要先安装 Hermes Agent」+ 前往/重新检测；③ spawn 前 preflight `venv python -c "import yaml, cryptography"`，缺依赖给「解释器缺失/依赖缺失」独立诊断状态，watchdog 重拉失败不无限重试
  - **二期（打包瘦身）**：砍 embedded Python——`build_webui_bundle.ps1` 不再下载/裁剪 Python，`resolvePythonPath` 塌缩为一级（venv→.venv），embedded 兜底分支与对应单测删除；`.iss` 删 `webui\python` 打包行 + 加 `[InstallDelete]` 清存量用户 `webui\python`；`webui/server`（15MB）保留照旧捆绑（主人拍板：webui 仍捆绑安装）
- 现状 vs 预期：现状 = 未装 agent 时引导页仅 agent 检测卡提示、内置 Tab 照常可点，embedded python 33MB 随包分发给每个用户；预期 = agent 缺失即硬门禁不可启用内置服务，安装包 50.6MB → 约 18MB
- 验收：
  1. 全新机（无 agent）走引导页：按钮置灰 + 引导卡外链可达 + 重检按钮工作；装 agent 后重检 → 按钮解禁，一键启动并连接全通
  2. 设置页未装 agent：开关点击弹提示不解开关；装后可开
  3. 二期产物：新装包无 `webui\python`；覆盖安装后旧 `webui\python` 被清；sidecar 以 venv python 起服 + 发收消息正常（venv 内 pyyaml/cryptography 已实测覆盖 webui 依赖）
  4. `C:/tmp/f.bat analyze` 零告警 + `flutter test` 全绿（含解释器选择单测改写）
- 备注：#71（B′ 解释器选择）已收口 @ 9cfbfb5，本条一期沿用其 agent venv 检测逻辑；设置页门禁（①②）与二期均依赖同一检测结果 provider（建议命名 `agentEnvPresent`），一期实现后两处复用。

---

### #77 [P1] 宽屏右侧面板「返回」吞聊天——go 替换栈无来源可回，落空到 EmptyDetailPane

- 复现：宽屏（≥900）点击进入某聊天 → 点侧栏「记忆/定时任务」等模块 → 右侧进入功能页 → 按页面左上角返回 → 落到空面板（EmptyDetailPane），聊天页丢失
- 位置：
  - `lib/app/shell/sidebar_utility_toolbar.dart:132` 宽屏侧栏入口 `context.go(item.path)`（替换栈）
  - `lib/features/shared/app_back_button.dart:36-42` `canPop()`=false → `fallback='/'`
  - `lib/app/shell/adaptive_shell.dart:270-272` 宽屏 `/` 渲染 `EmptyDetailPane`
  - `lib/features/shared/app_navigation.dart:29-36` `leaveToRoot` 宽屏分支同病（`go('/')`）
- 根因：go_router `go` 无历史栈，#51 拍板「宽屏保持 go」后宽屏右侧面板没有「上一页」概念；AppBackButton 无栈可 pop 只能兜底 `/`，宽屏 `/` 即空面板
- 修复方向（来源单槽，推荐）：
  1. 新增 `detailNavOriginProvider`（StateProvider<String?>）：宽屏进入功能页（openAdaptiveRoute 宽屏分支 + sidebar_utility_toolbar 侧栏入口两处接线）时记录切换前完整路径；功能页之间跳转**不覆盖**（保留最早来源）；侧栏点会话则覆盖为新聊天路径（面板旅程重置）
  2. `AppBackButton` 改 ConsumerWidget：宽屏且 origin 非空且 ≠ 当前路径 → `go(origin)` 并清槽；否则现行逻辑（canPop→pop / fallback）
  3. `leaveToRoot` 宽屏分支同样优先 origin（chat_page 归档/删除后回列表场景）
  4. git_page 现硬编码 `fallback: '/chat/<id>'`（git_page.dart:52）可被 origin 机制覆盖，改回默认 AppBackButton（可选，验收不强制）
- 现状 vs 预期：现状 = 宽屏从聊天进功能页按返回落到空面板；预期 = 返回原聊天（含流式状态），窄屏不受影响（push/pop 语义不变）
- 验收：
  1. widget 测试：宽屏视口 chat→记忆→back → 断言回原聊天路径；记忆→定时任务→back → 回聊天（非记忆）；侧栏换会话后功能页 back → 回新聊天
  2. 窄屏回归：push/pop 行为与现有一致（既有 session_open_chat_route_test 不破）
  3. 深链直进功能页（无来源）→ fallback 现行行为不变
  4. `C:/tmp/f.bat analyze` 零告警 + 全量 test 绿
- 备注：go_router 17.5；改动面 = app_navigation.dart + app_back_button.dart + sidebar_utility_toolbar.dart + 新 provider 文件，14 处 AppBackButton 挂点无需逐页改。

---

（当前队列：#76 方案已定 · 未开工、#77 宽屏返回吞聊天 · 待排期）
