# Auto-Reauth: 401 自动用保存密码重登（通用机制）

## 目标

app 任何数据端点（会话列表、模型目录、创建会话、聊天、其它）返回 **401**（会话 cookie
过期/失效）时，自动用当前激活连接里**保存的密码**重新登录（POST /api/auth/login 种新
cookie），成功后**重试原请求一次**——用户无需手动操作。

仅当**重新登录也失败**（保存的账号密码已修改/失效）时，才把 401 冒泡给 UI 提示用户
重新连接，绝不在登录本身失败后仍死循环重试。

## 现状（必须先了解）

- `lib/core/api/api_client.dart`：`ApiClient` 封装 dio；`validateStatus: (_) => true`
  （**所有状态码都被 dio 当成功返回**），401 由 `_throwUnless2xx(Response)` 手动抛
  `UnauthorizedException`（line ~340）。所以 **dio onError 拦截器收不到 401**，
  自动重登必须做在**请求原语层**。
- 请求原语（`api_client.dart`）：`sendJson` / `sendData` / `sendDataReturningResponse` /
  `sendUnchecked` / `downloadData`，以及内部 `_fetchWithRedirects`。
- 目前只有 `lib/features/session_list/session_list_providers.dart` 的
  `SessionListController._tryAutoReauth()`（line ~393）在 `_loadFirstPage` 一处手动做
  auto-reauth（用 `onboardingApiFactoryProvider` + `activeConnectionProvider` 的密码
  调 `api.login`）。settings（模型）、createSession 等其它地方**没有**，所以它们 401
  时直接报「服务器未返回会话 ID」/ 空态。
- 登录端点：`POST /api/auth/login {password}` → `ApiClient.login(password)`
  （`api_client.dart` 的 `ApiClientServer` 扩展，line ~445）；成功响应 Set-Cookie 由
  dio onResponse interceptor 自动写入 `CookieStore.shared`。
- `activeConnectionProvider`（`lib/core/connections/connection_providers.dart`）提供
  当前激活连接，含 `password` 字段（`ServerConnection.password`）。

## 设计

### 1. ApiClient 支持注入「重登处理器」（core 层，不依赖 Riverpod）

在 `lib/core/api/api_client.dart`：

- 新增一个回调类型（放本文件或单独文件）：
  ```dart
  /// 401 时的自动重登回调：返回 true 表示已用保存的凭证重登成功。
  typedef AutoReauthHandler = Future<bool> Function();
  ```
- `ApiClient` 构造函数增加可选参数：
  ```dart
  this.autoReauth,             // AutoReauthHandler?  401 时触发；null = 不做自动重登
  this.allowAutoReauth = true, // 是否启用自动重登（login/health 等端点本身可关）
  ```
  存为 `final AutoReauthHandler? _autoReauth;` / `final bool _autoReauthEnabled;`。

### 2. 请求原语层加「401 → 重登 → 重试一次」封装

在 `api_client.dart` 增加一个辅助：
```dart
/// 执行请求；收到 401 且启用自动重登时，触发一次重登并重放原请求。
/// 重登或重试仍 401 → 抛 UnauthorizedException（不递归，防死循环）。
Future<Response<Uint8List>> _fetchWithAutoReauth(
  Future<Response<Uint8List>> Function() perform, // 重放函数
) async {
  var response = await perform();
  if (response.statusCode == 401 && _autoReauthEnabled && _autoReauth != null &&
      !_reauthInFlight) {
    _reauthInFlight = true;
    try {
      if (await _autoReauth!()) {
        response = await perform(); // 重放一次
      }
    } finally {
      _reauthInFlight = false;
    }
  }
  return response;
}
```
- `bool _reauthInFlight = false;`（实例字段）防并发重登。
- 只重试一次，天然防递归。

然后让这几个原语在「构造请求→执行」处用 `_fetchWithAutoReauth` 包一层（把
`_fetchWithRedirects(...)` 调用包成 `perform` 闭包）：
- `sendJson`（line ~105）
- `sendData`（line ~131）
- `sendDataReturningResponse`（line ~152）
- `sendUnchecked`（line ~176）
- `downloadData`（line ~203）——发送后正常做 2xx/401 判定前调用

注意：`sendJson/sendData` 等已有自己的 401 → `_throwUnless2xx` / `downloadData` 的
`mapsUnauthorized` 分支。**重试逻辑要放在捕获 401 之前**，即：请求执行完拿到 response
后，若 401 且可重登，则重登并重放，之后再进行 `_throwUnless2xx`/返回判定。这样最终
401 才会被抛给调用方。

### 3. 排除不应触发重登的场景

- **login 请求本身 401**：不应触发重登（会死循环）。做法：`ApiClient.login` 走
  `sendJson` 时传 `allowAutoReauth: false`；或内部对 `Endpoint.login` 请求跳过重试。
  建议给 `sendJson/sendData` 加可选 `bool allowAutoReauth = true` 参数，login 传 false。
  （登录验证失败 → 直接抛 UnauthorizedException → 上层告诉用户密码错/自动重登失败。）
- 同域判定：`_fetchWithRedirects` 里同域/跨域已有区分；跨域媒体下载（`_publicMediaDio`）
  的 401 不应触发主连接重登。确保 `downloadData` 只在主 client 同域请求上重试。

### 4. 接入 Riverpod：注入真正的重登实现

在 `lib/core/connections/connection_providers.dart` 的 `apiClientProvider`（line ~132）
构造 `ApiClient` 时，注入 `autoReauth`：

```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final active = ref.watch(activeConnectionProvider);
  if (active == null) {
    throw StateError('尚未配置服务器连接');
  }
  return ApiClient(
    baseUrl: active.baseUrl,
    initialHeaders: [for (final e in active.customHeaders.entries)
      CustomHeader(name: e.key, value: e.value)],
    autoReauth: () async {
      final conn = ref.read(activeConnectionProvider);
      final password = conn?.password;
      if (password == null || password.isEmpty) return false;
      final factory = ref.read(onboardingApiFactoryProvider);
      final api = factory(conn!.baseUrl, [
        for (final e in conn.customHeaders.entries)
          CustomHeader(name: e.key, value: e.value),
      ]);
      try {
        await api.login(password);
        return true;
      } on Exception {
        return false;
      }
    },
  );
});
```
- 需 `import '../features/onboarding/onboarding_providers.dart';`
- 重登成功会种新 cookie 到 `CookieStore.shared`，原 client 的同域请求自动带上。

### 5. 兼容 session_list 现有手动 `_tryAutoReauth`

保留亦可（它：`allowAutoReauth` 字段 + 401 重试一次）。但注意：现在 ApiClient 层已
统一处理，`_loadFirstPage` 的 401 会被 ApiClient 消化后重试成功，不再走到 controller
的 `UnauthorizedException` 分支。为不破坏现有测试与行为：

- 保留 `_tryAutoReauth` 作为**最终兜底**（双重保险），但确认两者不会并发重复重登
  （`onboardingApiFactoryProvider` 各自对 `CookieStore.shared` 操作，最终 cookie 一致）。
- 若 ApiClient 层完成后 401 已被吞掉，controller 的 auto-reauth 分支自然不触发，无冲突。

### 6. createSession / settings 等的修复收益

因为 `apiClientProvider` 注入同一个 autoReauth，所有走 `ApiClient` 的端点
（`createSession` / `models` / `chat` / ...）自动获得 401 重登。这就是把机制
「通用化」的价值——不需要在每一个 Controller 手写 reauth。

## 需要新增/更新的测试（DoD 必需）

- `test/core/api/api_client_test.dart`：
  - 401 → 触发 autoReauth → 重放成功（断言请求执行了 2 次，第二次 200，返回正确结果，
    且 `_reauthInFlight` 无泄漏）。
  - 401 + autoReauth 返回 false（重登失败）→ 最终仍抛 `UnauthorizedException`，且
    只请求 1 次。
  - `allowAutoReauth: false`（login 场景）→ 401 不重登，直接抛。
  - 并发 401 只触发一次重登（`_reauthInFlight` 互斥）。
- `test/core/connections/connection_providers_test.dart`（若有）：autoReauth 注入后、
  401 时用保存密码成功重登并重放。
- 迁移 `test/features/session_list/session_list_test.dart` 现有 auto-reauth 用例，确保
  仍绿。

## 完成标准

- `flutter analyze` 零告警
- `flutter test` 全绿（运行用 `C:\tmp\f.bat test`，注意 MSYS HOME/PATH 环境）
- 无 Material 混入业务 UI（本改动纯 Dart，不涉及 UI）
- 遵守 `AGENTS.md`：无 `dynamic` 滥用、用 `Unawaited` 或注释说明裸 Future、
  私有 `_` 前缀、`///` doc comment、`dart format` 行宽 100
