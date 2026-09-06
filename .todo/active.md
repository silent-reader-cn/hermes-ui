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
  - `lib/features/shared/app_navigation.dart:29-36` `openAdaptiveRoute`/`leaveToRoot` 宽屏分支
- 根因：go_router `go` 无历史栈，#51 拍板「宽屏保持 go」后宽屏右侧面板没有「上一页」概念；AppBackButton 无栈可 pop 只能兜底 `/`，宽屏 `/` 即空面板
- 主人裁决（2026-09-06 两轮）：①聊天↔模块/设置双向不得 replace（聊天输入中途去看设置，返回必须回原聊天继续输入，草稿由 #18 会话级草稿兜住）；②最终方案 = **全平台允许 push 积累栈，唯「点进具体聊天」先清栈再进入**
- 探针实证（2026-09-06，go_router 17.5.0，tap 驱动 context.push，等价生产路径）：
  1. ShellRoute 内 push **不复制 shell**——push 页渲染在 shell 内层 Navigator，侧栏单实例存活（#51「宽屏禁 push 防叠 shell」的前提不成立）
  2. push 后旧页 offstage 存活，pop 原样恢复（状态不丢）
  3. push 页上 `go('/chat/:id')` → push 出的页全部丢弃、栈回单层 = **点聊天天然清栈**
  4. shell builder 收到的 `state.matchedLocation` 不跟 push（停在底页）；`currentConfiguration.last.matchedLocation` 才跟——侧栏模块高亮如需跟随需换数据源
  5. 测试坑：裸调 `router.push()` 在 widget 测试环境静默无效，必须 tap 驱动 UI 回调里的 `context.push`
- 修复方案（改动面极小）：
  1. **宽屏模块/设置入口 `go`→`push`**：`sidebar_utility_toolbar.dart:132`、`openAdaptiveRoute` 宽屏分支改 `unawaited(context.push(path))`
  2. **宽屏聊天入口保持 `go`**（`session_list_page.dart` `_openChatRoute` 宽屏分支）= 主人规则「进聊天先清栈」，零改动
  3. **窄屏零改动**：全程 push 现状即主人规则（聊天必经列表中转，返回天然回列表）
  4. `AppBackButton` 零改动：push 层 `canPop=true` 自动走 pop；聊天（go 进）`canPop=false` 走 fallback `/`
  5. `leaveToRoot`（归档/删除会话）保持 `go('/')` 清栈；chat 内部 go 跳转（新会话占位/跳父/分支）保持 go——「聊天=重置点」
  6. 可选增强（验收不强制）：侧栏模块高亮源改读 `currentConfiguration.last.matchedLocation`；Android 系统返回三级分流第②级优先内层 Navigator canPop→pop
- 深度上限：不做（push 页轻量；病态积累需连续切 8+ 模块且从不进聊天/返回，Android 返回键可逐级弹）
- 现状 vs 预期：现状 = 宽屏从聊天进功能页按返回落到空面板；预期 = 模块页返回回原聊天（输入保留），聊天重进即清栈，窄屏不受影响
- 验收：
  1. widget 测试（tap 驱动，参照 session_open_chat_route_test.dart 范式）：宽屏 聊天A→设置→记忆 → 返回×2 依次回设置→聊天A（输入保留）；聊天A→设置→侧栏点聊天B → 栈清空、返回到 `/`；宽屏侧栏点模块后模块页出现、侧栏仍单实例（ShellProbe 计数=1）
  2. 窄屏回归：session_open_chat_route_test 既有两例直接绿（宽屏点会话仍 go，canPop=false 不变）
  3. 深链直进功能页 → fallback 现行行为不变
  4. `C:/tmp/f.bat analyze` 零告警 + 全量 test 绿
- 备注：go_router 17.5；改动面仅 sidebar_utility_toolbar.dart + app_navigation.dart 两个文件的两处 go→push，14 处 AppBackButton 挂点零改动。探针学习已录 skill（hermex-flutter-codebase）。

---

（当前队列：#76 方案已定 · 未开工、#77 方案已定 · 未开工）

