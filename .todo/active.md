# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#87/#88 已收口誊写至 `.todo/20260907.md` @f01c91d；#91 @0076554；#93 @0a69ee2；#95 @da21ea2；#96/#97 APK 安装权限与分享按钮已收口誊写至 20260907.md，随补丁批次 commit；#98 @5c19de7 与 #99 交付 @b9df051（含诊断原档）已收口誊写至 `.todo/20260908.md`）

---

## #76 二期（待一期真机复验后另批开工）

- 内置服务砍 embedded Python 打包瘦身（方案已定 · 未开工），见 `.todo/20260907.md` #76 条目。

---

## #103 引导页高级设置布局：端口/IP 输入框对齐 + 密码行两行式（主人 2026-09-09 反馈）

- 位置：`lib/features/onboarding/widgets/builtin_tab.dart` 高级设置区（`_buildAdvancedSettingsContent` / `_buildPasswordTile`，约 701-971 行）；同步 `lib/features/settings/webui_sidecar_section.dart`（`_buildPasswordTile` 同款分叉，171-365 / 366-518 行）。
- 复现：引导页 → 内置服务 Tab → 展开高级设置。截图现象：①监听端口输入框（maxWidth 100）比监听 IP（maxWidth 140）窄，两框右缘参差；②密码行 `title + trailing: Row(圆点+重新生成+复制+编辑)` 与 460 宽列 + ListTile 左右 padding 打架，`WebUI 密码` title 被挤到几乎看不见。
- 现状 vs 预期：现状=输入框宽度不一、密码标签被挤没；预期=端口/IP 等宽右对齐、密码标签完整可见、操作区独立成行。
- 修复（CupertinoListTile 内重构，不动逻辑/文案/Key）：
  1. 端口输入框 `maxWidth: 100 → 140`，与 IP 等宽（两文件四处统一 140）；
  2. 密码 Tile 两态（编辑态/展示态）`trailing` 只留轻量元素（编辑态=输入框；展示态=圆点 `••••••••`），三按钮 / 输入框+三按钮搬进 `subtitle: Column` 第二行（`Row(mainAxisSize.min)`，按钮 Key/padding/onPressed 原样）；
  3. `config` 未使用参数保留（签名兼容，避免调用点改动）。
- 验收：`C:/tmp/f.bat analyze` 零告警；`onboarding_builtin_tab_test.dart` + `webui_sidecar_section_test.dart` 全绿（28 用例）；settings 金照 light/dark 通过（布局在金照覆盖范围外，未触发更新）。
- 状态：已交付 main 待主人真机复验（窄屏/宽屏双栏右列 460 下验证标签与按钮是否换行）。

---

## #104 引导页/设置页 WebUI 密码行改内联密码框（主人 2026-09-09 选方案 B）

- 位置：`lib/features/onboarding/widgets/builtin_tab.dart`（`_buildPasswordTile`，约 820-980 行）；同步 `lib/features/settings/webui_sidecar_section.dart`（`_buildPasswordTile`，约 366-527 行）。
- 现状 vs 预期：现状=密码行 subtitle 塞三文字按钮（重新生成/复制/编辑）+ 灰字提示 + 右侧圆点，编辑态整行三倍高跳变，与端口/IP 右对齐输入框不是一个画风；预期=密码行与端口/IP 统一为右对齐内联 `CupertinoTextField`，无 subtitle（仅校验失败时红字），无任何文字按钮（含重新生成按钮一并删除，首次随机密码由 `WebuiSidecarConfigStorage.load()` 为空时自动生成落盘保留），框内 suffix 一只眼睛图标切显隐，复制靠系统长按选中。
- 规格（两文件同构，仅默认显隐不同）：
  1. `CupertinoListTile(title: WebUI 密码，subtitle: 仅 _passwordError 非空时红字)`，`trailing: ConstrainedBox(maxWidth 200) > Row(Expanded CupertinoTextField + 眼睛 CupertinoButton)`；Key 保留 `*-password-input`，新增 `onboarding-sidecar-password-visibility-btn` / `settings-webui-password-visibility-btn`；删除 `regen/copy/edit/save/cancel/display` 五 Key 与 `_isEditingPassword/_copiedNotice/Timer/Clipboard` 相关状态逻辑（`dart:async` 中 Timer 停用但 `unawaited` 仍用则保留 import，`services.dart` 无他用则删）。
  2. 引导页 `_passwordObscured` 初值 false（默认明文，方便复制），图标 `eye_slash`；设置页初值 true（默认遮罩），图标 `eye`；点眼睛 `setState` 翻转。
  3. 编辑即改：`onChanged` 清错，`onSubmitted` + 失焦 `_submitPassword`（trim；空→红字 `webuiPasswordEmpty` 不写回；非空且与 provider 不同才 `setPassword`）；联动 `ref.listen` 改为「未聚焦时跟随 provider」。
  4. `generateRandomPassword` 保留给首次生成；`agentGatePasswordHint/agentGateRegeneratePassword` 文案保留（他处无引用亦不删，避 l10n churn）。
- 测试更新：`onboarding_builtin_tab_test.dart` TASK U2 密码段（约 580-610 行）改新流程（框有值→眼睛切显隐→改字 done 写回→空字红字）；`webui_sidecar_section_test.dart` 密码两用例（约 394-549 行）重写（默认遮罩→眼睛明文→改字提交写回→空字红字，删复制/重生成断言）。
- 验收：`C:/tmp/f.bat analyze` 零告警；两密码用例文件全绿；`--update-goldens` 仅布局金照受影响时刷新（onboarding 金照大概率命中）。
- 状态：规格已落盘，待实现。
