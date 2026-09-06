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

（当前队列：#76 方案已定 · 未开工，等待排期）
