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
import 'package:flutter/rendering.dart' show RenderDecoratedBox;

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

/// 模拟 Decoration paint 的真实渲染色。
///
/// paint 路径用的是 `color.toARGB32()`：动态色（CupertinoDynamicColor）
/// 的 toARGB32 返回 `_effectiveColor`——**从未被 resolve 过的系统常量
/// 返回 light 值**（直塞 BoxDecoration 的 bug 正是这样画出浅色底）；
/// 已被组件/业务层 resolveFrom 过的动态色返回解析后值（如 TextField
/// 内部 dark 黑底）。这一个函数同时建模两种情况，与真实渲染一致。
///
/// 注意：不能反过来把动态色强转成 `.color`（永远 light，会误伤
/// 框架组件内部已 resolve 的深色底）；也不能 maybeResolve（会把业务层
/// 直塞的常量错判成 dark，漏掉「暗黑模式画成浅色底」的 bug）。
Color renderedDecorationColor(Color raw) => Color(raw.toARGB32());

/// 向上查找最近的有色背景 RenderDecoratedBox（Container/DecoratedBox/
/// ColoredBox 渲染层统一是它），取 paint 真实渲染色（动态色按 light 值）
/// 作为文字的 **局部背景参考**；找不到（文字直接在页面底色上）返回主题
/// 页面底色。
///
/// 为什么必须局部背景：对比度要以真实渲染背景为参考。若气泡/卡片上的
/// 文字一律按页面底色算，会系统性漏掉「亮块混入暗主题」这类主题错配——
/// 白色气泡 + 黑色文字按 WCAG 是 13:1「达标」，但暗黑模式下整块刺眼白，
/// 正是本次接入的漏检根因。
Color localBackgroundFor(BuildContext context, Brightness brightness) {
  final fallback = brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFF2F2F7);
  Color? found;
  context.visitAncestorElements((element) {
    final render = element.renderObject;
    if (render is RenderDecoratedBox) {
      final decoration = render.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        found = renderedDecorationColor(decoration.color!);
        return false;
      }
    }
    return true;
  });
  final background = found ?? fallback;
  // 半透明背景（如 20% 黄徽章）必须合成到页面底色——对比度按用户真实
  // 看到的合成色算，否则半透明底上文字会误判（白字对半透明黄是 1.5:1，
  // 合成到黑底后是 14:1）。
  return background.a >= 0.999 ? background : compositeOver(background, fallback);
}

/// 格式化颜色为 `#RRGGBB`（报告定位用）。
String formatColor(Color color) {
  final argb = color.toARGB32();
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}