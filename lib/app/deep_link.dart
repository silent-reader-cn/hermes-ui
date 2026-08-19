import 'package:flutter/foundation.dart';

/// URL scheme 深链解析（app_shell_spec.md §3 路由表子集）。
///
/// iOS/Android 通过 URL scheme 冷启动时，引擎会把原始 URL 塞进
/// [PlatformDispatcher.defaultRouteName]（如 `hermex://chat/abc123` 或
/// `/chat/abc123`）。本函数将其规范化为路由表内路径：
///
/// - 剥掉 `scheme://` 前缀与 query/fragment；
/// - 统一补前导 `/`；
/// - 只放行路由表已知路径（[knownRoutePaths]），未知一律回退 `/`。
///
/// 已知限制：仅覆盖冷启动深链；App 运行中收到深链（热启动）需
/// app_links 等平台通道，待 iOS 真机验证批次接入。
String resolveInitialRoute(String raw, {TargetPlatform? platform, bool? isWeb}) {
  if (raw.isEmpty || raw == '/') return '/';

  var path = raw;
  // 剥掉 scheme://（hermex://chat/abc → chat/abc）
  final schemeIdx = path.indexOf('://');
  if (schemeIdx >= 0) path = path.substring(schemeIdx + 3);
  // 剥掉 query / fragment
  final qIdx = path.indexOf('?');
  if (qIdx >= 0) path = path.substring(0, qIdx);
  final fIdx = path.indexOf('#');
  if (fIdx >= 0) path = path.substring(0, fIdx);
  // 去除多余斜杠，统一补前导 /
  path = path.replaceAll(RegExp(r'/+'), '/');
  if (!path.startsWith('/')) path = '/$path';

  // 白名单：路由表已知形状（/chat/:sessionId 等参数段任意非空）
  for (final pattern in knownRoutePaths) {
    if (RegExp(pattern).hasMatch(path)) return path;
  }
  return '/';
}

/// 路由表已知路径正则（参数段 `[^/]+`）。
///
/// 与 lib/app/router.dart 路由表一一对应；新增路由时同步补此表。
const List<String> knownRoutePaths = <String>[
  r'^/onboarding$',
  r'^/$',
  r'^/chat$',
  r'^/chat/[^/]+$',
  r'^/settings$',
  r'^/tasks$',
  r'^/skills$',
  r'^/memory$',
  r'^/workspace/[^/]+$',
  r'^/kanban$',
  r'^/git/[^/]+$',
  r'^/insights$',
];