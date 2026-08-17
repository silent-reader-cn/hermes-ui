/// WCAG 2.x 文字对比度工具（test 专用，不依赖业务代码）。
///
/// 实现 WCAG 2.1 §1.4.3（Contrast Minimum）的相对亮度与对比度公式：
/// - 相对亮度：sRGB 通道先线性化（`c/12.92` 或 `((c+0.055)/1.055)^2.4`），
///   再按 `0.2126R + 0.7152G + 0.0722B` 加权。
/// - 对比度：(L1 + 0.05) / (L2 + 0.05)，L1/L2 为亮/暗两色的相对亮度。
///
/// 注意：含 alpha 的文字色（如 CupertinoColors.secondaryLabel 定义在
/// `0x99` 透明度上）必须先合成到背景色上再算对比度——见 [contrastRatio]，
/// 它自动完成合成；[relativeLuminance] 只处理不透明颜色（忽略 alpha）。
library;

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// sRGB 通道线性化（WCAG 公式 2 段分段函数）。
double _linearizeChannel(double channel) {
  if (channel <= 0.03928) {
    return channel / 12.92;
  }
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 相对亮度：`0`（黑）~ `1`（白）。
///
/// [c] 应为不透明颜色；带 alpha 的颜色请先用 [compositeOver] 合成，
/// 或直接使用 [contrastRatio]（内部自动合成）。
double relativeLuminance(Color c) {
  return 0.2126 * _linearizeChannel(c.r) +
      0.7152 * _linearizeChannel(c.g) +
      0.0722 * _linearizeChannel(c.b);
}

/// 把半透明的 [foreground] 合成到不透明 [background] 上，
/// 得到实际渲染颜色（iOS 语义色常自带 alpha，如 secondaryLabel = 0x99 透明度）。
Color compositeOver(Color foreground, Color background) {
  final a = foreground.a;
  if (a >= 0.999) return foreground;
  return Color.from(
    alpha: 1.0,
    red: foreground.r * a + background.r * (1 - a),
    green: foreground.g * a + background.g * (1 - a),
    blue: foreground.b * a + background.b * (1 - a),
  );
}

/// WCAG 对比度：`(L亮 + 0.05) / (L暗 + 0.05)`，范围 1:1 ~ 21:1。
///
/// [foreground] 若带 alpha，先合成到 [background] 再计算（与实际渲染一致）。
double contrastRatio(Color foreground, Color background) {
  final fg = compositeOver(foreground, background);
  final lFg = relativeLuminance(fg);
  final lBg = relativeLuminance(background);
  final lighter = math.max(lFg, lBg);
  final darker = math.min(lFg, lBg);
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA 达标判定：正文 4.5:1，大字号/装饰性文字可放宽 3:1（[threshold]）。
bool passesAA(Color foreground, Color background, {double threshold = 4.5}) {
  return contrastRatio(foreground, background) >= threshold;
}

/// 解析动态色（如 CupertinoColors.* 语义色）为当前主题亮度下的具体颜色；
/// 非动态色原样返回。
Color resolveTextColor(Color color, BuildContext context) {
  return CupertinoDynamicColor.maybeResolve(color, context) ?? color;
}

/// 格式化颜色为 `#RRGGBB`（报告定位用）。
String formatColor(Color color) {
  final argb = color.toARGB32();
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}