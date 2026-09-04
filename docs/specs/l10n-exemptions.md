# L10n 硬编码中文豁免清单（L3 审计产出）

> 2026-09-04 全仓审计。判定标准：**用户在 UI/系统通知中可见的字符串必须走 l10n**；
> 以下四类按规格（`.todo/active.md`「多语言切换设置」风险④）豁免，逐条列明路径与理由。
> 审计命令基线：
> ```
> grep -rnP "Text\(\s*'?[\x{4e00}-\x{9fff}]" lib/
> grep -rnP "(label|title|hintText|placeholder|tooltip|semanticsLabel|middle|message|body):\s*(const )?(Text\()?\s*'[^']*[\x{4e00}-\x{9fff}]" lib/
> ```

## 本轮已修复（真实泄漏 → 接 l10n）

| 位置 | 内容 | 接法 |
|---|---|---|
| `onboarding/install_guide_page.dart` | `Text('选择模型服务商')` / `Text('取消')` | 复用既有键 `installGuideSelectProvider`/`cancel`（modal ctx） |
| `notifications/notification_providers.dart` | in-app toast 兜底标题「回合完成/需要澄清/会话异常」×3 | `AppLocalizations(LocaleResolver.resolve())`（服务层无 context） |
| `notifications/turn_notification_service.dart` | 系统通知 title「需要澄清/下载完成」×2 | 同上 |
| `notifications/background_keepalive_service.dart` | WorkManager 后台 isolate 通知 title×4 + body×3 | isolate 内先从 prefs `app_locale_mode` 恢复 LocaleResolver 再本地化 |
| `workspace/workspace_providers.dart` | 面包屑「根目录」×3 | `_rootCrumbTitle()` 走 LocaleResolver |
| `desktop/tray_manager_service.dart` | 托盘菜单 label×5 + 状态行×4 + 会话状态标签×4 | `AppLocalizations(LocaleResolver.resolve())` |
| `notifications/background_keepalive_service.dart` | 常驻通知文本调用侧×5 | `formatNotificationText(count, isEnglish: LocaleResolver.isEnglish)`（K 线遗留参数补接线） |

## 豁免清单

### ① 内部键（渲染层已双语映射）

| 位置 | 字符串 | 理由 |
|---|---|---|
| `session_list/session_list_providers.dart:1393,1457-1461` 及 `buildSessionSections` | `'搜索结果'/'置顶'/'今天'/'昨天'/'更早'/'定时'` | 分区 title 是**内部枚举键**；渲染入口 `session_list_page.dart:1237 _sectionTitle(context, rawTitle)` 已 switch 到 `l10n.pinnedSection/todaySection/...`，随主题语言自动切换。改 providers 反而会脱离 widget 重建机制 |
| `memory/memory_providers.dart:89-98 memorySectionInfo()` | `'我的笔记'/'用户画像'/'智能体灵魂'` 等 | 全仓 grep 零调用方（死代码）；tab 标题实际渲染走 `memory_page.dart:470-476 l10n.memoryNotesTitle/...` 已双语。待后续清理任务顺手删除 |

### ② Android 通知渠道标识（建后不可变）

| 位置 | 字符串 | 理由 |
|---|---|---|
| `notifications/turn_notification_service.dart` `channel*Name/Description` 常量（需要澄清/下载完成/回合完成/异常中断 等 4 渠道） | 渠道 channelName 创建后系统缓存不可更新，改英文名需改 channelId 或删渠道重建（丢用户权限设置），且渠道名仅出现在系统设置页角落。**缺省裁定豁免** |
| `webui_sidecar/background_keepalive_service.dart` `channelName: '后台生成保活'` | 同上（前台服务渠道） |

### ③ 开发者面文本

| 范围 | 理由 |
|---|---|
| 全部 `developer.log(...)` / `DiagnosticsService.instance.log(message:)`（含 keepalive/notifications/desktop 各处中文日志） | 诊断页属开发者面，规格风险④裁定保留中文 |
| 代码注释、doc comment（含本清单、`status_colors.dart:10` 用法示例注释） | 非运行时文本 |

### ④ 后端转发/用户数据

| 范围 | 理由 |
|---|---|
| 会话标题、消息内容、工具输出、`formatPreview` 截断结果 | 源自后端/用户，不由 app 本地化 |

## 审计回归测试

`test/features/l10n_audit_test.dart`：脚本化扫 `lib/`，断言 ①`Text('中文`、②`label: '中文` 两类模式除豁免路径外零命中，防未来回归。
