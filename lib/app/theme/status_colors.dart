// 状态文字颜色（WCAG AA 达标版）。
//
// 系统状态色（systemGreen/systemOrange/systemBlue/systemGrey）在浅色背景下
// 对比度不足（绿 #34C759 白底 ~2.0:1、橙 #FF9500 白底 ~2.0:1），不适合
// 直接用作文字色（圆点/图标装饰不受此限）。本组动态色：
// - 浅色模式用深色变体（白底对比 >= 4.5:1）
// - 深色模式用亮色变体（黑底对比 >= 4.5:1）
// - highContrast* 为系统增强对比度模式下的更强变体。
//
// 用法：Text('运行中', style: TextStyle(color: statusGreenText))
import 'package:flutter/cupertino.dart';

/// 状态「运行中/成功」文字色：浅 #1E7A34（白底 ~5.9:1）/ 深 #34C759（黑底 ~6.3:1）。
const CupertinoDynamicColor statusGreenText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF1E7A34),
  darkColor: Color(0xFF34C759),
  highContrastColor: Color(0xFF0E6B2C),
  darkHighContrastColor: Color(0xFF40DD74),
);

/// 状态「暂停/警告」文字色：浅 #B25000（白底 ~5.2:1）/ 深 #FF9500（黑底 ~9.6:1）。
const CupertinoDynamicColor statusOrangeText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFFB25000),
  darkColor: Color(0xFFFF9500),
  highContrastColor: Color(0xFF9A3F00),
  darkHighContrastColor: Color(0xFFFFB340),
);

/// 状态「进行中/主色」文字色：浅 #005FB8（白底 ~4.7:1）/ 深 #0A84FF（黑底 ~7.5:1）。
const CupertinoDynamicColor statusBlueText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF005FB8),
  darkColor: Color(0xFF0A84FF),
  highContrastColor: Color(0xFF004A94),
  darkHighContrastColor: Color(0xFF45A3FF),
);

/// 状态「关闭/离线」文字色：浅 #595959（白底 ~5.9:1）/ 深 #8E8E93（黑底 ~4.8:1）。
const CupertinoDynamicColor statusGreyText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF595959),
  darkColor: Color(0xFF8E8E93),
  highContrastColor: Color(0xFF3E3E44),
  darkHighContrastColor: Color(0xFFAEAEB6),
);

/// 状态「就绪/teal」文字色：浅 #0E7C86（白底 ~4.9:1）/ 深 #30B0C7（黑底 ~8.2:1）。
const CupertinoDynamicColor statusTealText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF0E7C86),
  darkColor: Color(0xFF30B0C7),
  highContrastColor: Color(0xFF0A6169),
  darkHighContrastColor: Color(0xFF40C4D6),
);
