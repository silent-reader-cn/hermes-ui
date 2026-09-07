# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（#56-#63 已全部收口誊写至 `.todo/20260905.md`；#64 胶囊方案 E 已收口至 `.todo/20260905.md`；#65-#70、#71、#73、#74、#75 已收口誊写至 `.todo/20260906.md`；#76一期/#77/#78-#82 已收口誊写至 `.todo/20260907.md`）

---

---

---

---

---

### #83 [P2] 已完成聊天消息 meta 行补完成时间显示

- 位置：`lib/features/chat/widgets/message_bubble.dart:380-390`（现 meta 行仅 `message.turnTps` → `xxx tok/s`，11px secondaryLabel）
- 现状 vs 预期：现状 = 完成的 assistant 消息只显示 tok/s；预期 = 同行追加消息完成时间（`message.timestamp` 为 Unix 秒 double，ChatMessage 已有字段，无完成时间专用字段时发起时间即可——主人拍板）
- 方案：meta 行改 Row（tok/s + ` · ` + `HH:mm` 或 `MM-dd HH:mm`，跨天带日期）；时间解析 timestamp*1000 → DateTime 本地时区。纯符号无文案，若确需新增文案走 l10n 前缀 `msgMeta`（disjoint 纪律）
- 验收：有 timestamp 的消息 meta 显示时间；无 timestamp 不显示时间部分；金照如受影响 --update-goldens
- 备注：P2 视觉增强，与 #78-82 无文件冲突（message_bubble.dart 当前无人独占）

---

### #84 [P1] 内置服务 host/port/password 配置 — 引导页与设置页对照盘点与补齐

- 主人要求（2026-09-07）：引导页与设置页都必须有 host 和 port（提供默认值），密码必须让用户设置
- 现状盘点（2026-09-07 代码实查）：
  - **设置页**（webui_sidecar_section.dart）：host 输入（settings-webui-host-input）+ port 输入（settings-webui-port-input）+ 密码（settings-webui-password-tile，脱敏显示+编辑态输入）——**三字段常驻齐全，无需补**
  - **引导页**（builtin_tab.dart）：host/port/密码三字段在「高级设置」折叠区（默认收起 `_isAdvancedExpanded=false` @ line 39，onboarding-advanced-disclosure 展开），字段与校验齐全
  - **默认值**：host=127.0.0.1、port=8787（SidecarConfig.defaultHost/defaultPort）；密码首启自动生成随机串（`generateRandomPassword`，webui_sidecar_models.dart:128，DPAPI 加密存 secure storage）——非空、但**不是用户设置的**
- 缺口（对照主人要求）：① 引导页高级折叠默认收起 → host/port/密码对首启用户不可见，「引导用户设置密码」的意图未达成；② 密码是自动生成而非用户主动设置；③ 设置页三字段齐全但密码同样首启为自动生成
- 修复方向（一期小改）：
  1. 引导页：内置 Tab 选中或首次进入时高级区**默认展开**（`_isAdvancedExpanded` 初始 true），让 host/port/密码首见即见
  2. 密码字段旁加「重新生成」按钮（复用 `SidecarConfig.generateRandomPassword`，引导页 + 设置页同款）+ 提示文案「默认已生成随机密码，可修改为你自己的密码」
  3. 设置页密码行同款提示文案；host/port 默认值已填入输入框（现状已满足）
- 验收：首启引导页内置 Tab 高级区展开可见三字段且 host/port 带默认值；密码可改可重新生成；改后一键启动并连接用新配置；设置页同步生效
- 备注：#76 一期已收口（08e316a），worktree 从 main 重建即可；agentGate* l10n 前缀已有，本次补 agentGatePasswordHint / agentGateRegeneratePassword 等，尾部追加

---

### #85 [P1] 设置页「自动加载图片」开关 — 关闭后聊天图片点击才加载

- 主人要求（2026-09-07）：设置中加入「自动加载图片」功能开关，**默认打开**；关闭后聊天中的图片点击后才会加载
- 位置盘点（2026-09-07 代码实查）：
  - 聊天内联图片统一走 `ChatInlineMediaWidget`（`lib/features/chat/widgets/chat_media_view.dart:35`，ConsumerWidget）→ watch `mediaFileProvider`（:30，FutureProvider.family 下载）→ 渲染；onTap 开 lightbox（:236）。message_bubble.dart 两处 imageBuilder（:234/:356）都接到它
  - data: URI 内联 base64 在 build 内直接解码（:95-96），不走网络
  - 设置开关现成模式：`AutoOpenContextOnNewSessionController`（settings_providers.dart:996-1044，SharedPreferences + `loadPref` + Notifier + setEnabled）；设置页聊天分区 `_ChatSection`（settings_page.dart:195+）
- 方案：
  1. settings_providers.dart 新增 `kAutoLoadImagesKey = 'settings.autoLoadImages'` + `autoLoadImagesProvider`（模式复刻 AutoOpenContextOnNewSessionController，**默认 true**），`loadPref` 接入现有启动预载调用点（grep `loadPref(` 的调用处同步补）
  2. settings_page.dart `_ChatSection` 加开关 tile（CupertinoSwitch，key `settings-auto-load-images`，l10n 前缀 `chatAutoLoad*` 尾部追加：label「自动加载图片」/ 'Auto-load Images'）
  3. chat_media_view.dart：`ChatInlineMediaWidget` 改 ConsumerStatefulWidget；`ref.watch(autoLoadImagesProvider)` 为 true → 现状渲染；为 false 且网络 URL → 未点击前渲染占位（alt 文本 + 图片 icon + 「点击加载」提示，l10n `chatAutoLoadTapToLoad`，点击后 setState 加载，本会话内保持已加载）；**data: URI 不设闸**（不耗流量，直接渲染）
  4. lightbox（AttachmentLightbox）路径不动（用户主动点击才开，本来就按需）
- 验收：默认开=渲染行为与现状一致；关闭后历史/live 聊天图片变占位、点击加载、加载后不再回退；重启后开关记忆；data: URI 不受影响；flutter analyze 零告警 + test 全绿
- 备注：流量宝贵诉求；与 #83 同为 chat 域但文件不重叠（chat_media_view vs message_bubble）

---

（当前队列：#83 P2、#84 P1、#85 P1 —— 三条已打包 agy/sep07-batch worktree 并行实施；#76二期（砍python+打包链）待一期真机复验后另批开工）
