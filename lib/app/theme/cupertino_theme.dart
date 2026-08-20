import 'package:flutter/cupertino.dart';

/// Hermex 默认全局字体族名（MiSans）。
const String kAppFontFamily = 'MiSans';

/// Hermex Cupertino 主题（app_shell_spec.md §4）。
///
/// 主色为 Hermex 风格 iOS 蓝 `0xFF007AFF`（与 Hermex 原生一致）；
/// 深色模式 scaffold 背景纯黑，浅色模式为系统分组背景；
/// 全局文字绑定 [kAppFontFamily]（MiSans），提供清晰美观的中文与英文/数字排版体验。
CupertinoThemeData buildCupertinoTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: const Color(0xFF007AFF),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF000000)
        : CupertinoColors.systemGroupedBackground,
    // CupertinoApp 的默认 TextStyle 在自定义 textTheme 下不会自动补齐
    // 前景色。显式绑定语义 label 与全局 fontFamily，保证全应用文字统一。
    textTheme: const CupertinoTextThemeData(
      // 正文 17pt（iOS 默认）
      textStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 17,
        color: CupertinoColors.label,
      ),
      // 操作项（按钮等）
      actionTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 17,
        color: Color(0xFF007AFF),
      ),
      // 底部标签栏 10pt
      tabLabelTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 10,
        letterSpacing: -0.24,
        color: CupertinoColors.inactiveGray,
      ),
      // 导航栏操作项
      navActionTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 17,
        color: Color(0xFF007AFF),
      ),
      // 导航栏标题 17pt 半粗
      navTitleTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.label,
      ),
      // 大标题 34pt Bold
      navLargeTitleTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: CupertinoColors.label,
      ),
      // 滚轮选择器
      pickerTextStyle: TextStyle(
        inherit: false,
        fontFamily: kAppFontFamily,
        fontSize: 21,
        color: CupertinoColors.label,
      ),
    ),
  );
}

