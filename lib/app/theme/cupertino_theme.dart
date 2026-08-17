import 'package:flutter/cupertino.dart';

/// Hermex Cupertino 主题（app_shell_spec.md §4）。
///
/// 主色为 Hermex 风格 iOS 蓝 `0xFF007AFF`（与 Hermex 原生一致）；
/// 深色模式 scaffold 背景纯黑，浅色模式为系统分组背景。
CupertinoThemeData buildCupertinoTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: const Color(0xFF007AFF),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF000000)
        : CupertinoColors.systemGroupedBackground,
    // CupertinoApp 的默认 TextStyle 在自定义 textTheme 下不会自动补齐
    // 前景色。显式绑定语义 label，避免浅色模式继承到白色文字。
    textTheme: const CupertinoTextThemeData(
      // 正文 17pt（iOS 默认）
      textStyle: TextStyle(fontSize: 17, color: CupertinoColors.label),
      // 导航栏标题 17pt 半粗
      navTitleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.label,
      ),
      // 大标题 34pt Bold
      navLargeTitleTextStyle: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: CupertinoColors.label,
      ),
    ),
  );
}
