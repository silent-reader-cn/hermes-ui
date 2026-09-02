# TASK #50 实施结果报告 — Android 后台保活常驻通知重构

## 1. 改动文件清单
- `android/app/src/main/AndroidManifest.xml`:
  - 添加 `FOREGROUND_SERVICE_SPECIAL_USE` 权限；
  - `ForegroundService` 声明 `android:foregroundServiceType="specialUse"`；
  - 添加 `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="hermes_keepalive" />`。
- `lib/l10n/app_localizations.dart`:
  - 严格在 `AppLocalizations` 类闭合前追加 `bgKeepalivePersistentHint`、`bgKeepaliveNoActiveSessions`、`bgKeepaliveActiveCount(int count)` 双语 getter，未修改已有行及格式。
- `lib/features/notifications/background_keepalive_settings_page.dart`:
  - 前台服务保活开关副标题同步为 `l10n.bgKeepalivePersistentHint`（“开启后常驻通知显示进行中会话数”）。
- `lib/features/notifications/notification_providers.dart`:
  - `setBgForegroundServiceEnabled` 变更时直启/强制停止前台服务（`value ? startForegroundService() : stopForegroundService(force: true)`）。
- `lib/features/notifications/background_keepalive_service.dart`:
  - `BackgroundKeepaliveService` / `ProductionBackgroundKeepaliveService` / `FakeBackgroundKeepaliveService` 接口与实现同步；
  - 移除 `onAppLifecycleChanged` 中 `resumed -> stopForegroundService` 逻辑，仅保留会话/流状态更新；
  - FGS 通知文本动态显示会话数（`formatNotificationText`: 0 -> 「暂无进行中会话」/ N -> 「N 个会话正在生成」）；
  - WorkManager `handleTask` 在后台周期/加急触发时通过 `/health?deep=1` 获取 `active_streams` 刷新常驻通知文本；
  - 无会话进行中时通知保持常驻不消失；
  - 冷启动若 `bg_foreground_service_enabled == true` 自动直启常驻服务。
- `test/features/notifications/background_keepalive_service_test.dart`:
  - 同步 fake 实现，新增开关直启、前后台常驻、流起止计数 0↔N 动态刷新、无会话文本展示且不停止、文本格式化等单元测试。

## 2. 方案取舍说明
- **开关监听与触发位置**：选在 `notification_providers.dart` 的 `NotificationSettingsNotifier.setBgForegroundServiceEnabled` 内直接驱动 `keepalive.startForegroundService()` / `keepalive.stopForegroundService(force: true)`，属于最小侵入方案，既保证了 UI 交互的即时响应与 SharedPreferences 持久化同步，又无需在 service 内部轮询观察设置变化。
- **常驻通知文本更新机制**：
  - 前台：单窗口模型下 `onAppLifecycleChanged` 及流起止事件即时调用 `FlutterForegroundTask.updateService` 刷新会话数；
  - 后台：复用 WorkManager 既有 dio 通路拉取服务端 `/health?deep=1` 的 `active_streams` 真值，在跨平台/进程被杀后仍能维持准确的活跃会话数。
- **Android 14+ specialUse 声明**：manifest 声明 `FOREGROUND_SERVICE_SPECIAL_USE`、`specialUse` service type 与 `hermes_keepalive` subtype，flutter_foreground_task 8.x 的 Dart options 无 type 字段故注释说明依托 manifest 配置，规避了 `dataSync` 类型的 6h/24h 运行限制。

## 3. 验收结果
1. `C:/tmp/f.bat analyze`：**No issues found!**（0 错误 0 告警 0 info）
2. `C:/tmp/f.bat test`：**All tests passed!** 全绿（共 2125 个测试用例全部通过）
3. `onAppLifecycleChanged` 中确认无 `stopForegroundService` 残留逻辑。
4. `AndroidManifest.xml` 完整包含 `specialUse` 三件套。
5. 工作区干净，未执行 `git add` / `git commit`。

## 4. 遗留风险
- 无遗留编译或逻辑风险。iOS 与 Desktop 平台保留了平台门控与空实现，行为平稳兼容。
