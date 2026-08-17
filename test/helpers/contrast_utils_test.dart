import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast_utils.dart';

/// WCAG 对比度计算单元测试。
///
/// 参考值对照 WCAG 2.1 §1.4.3 公式手工核算：
/// - 黑 #000000 相对亮度 0，白 #FFFFFF 相对亮度 1，两者对比度 21:1。
/// - #777777 与白色对比度 ≈ 4.48:1（不满足 AA 4.5）；#767676 ≈ 4.54:1（满足）。
/// - #FF0000 相对亮度恰为 0.2126（只有 R 通道有贡献）。
void main() {
  group('relativeLuminance', () {
    test('黑白端点', () {
      expect(relativeLuminance(const Color(0xFF000000)), 0.0);
      expect(relativeLuminance(const Color(0xFFFFFFFF)), 1.0);
    });

    test('纯红 = 0.2126（0.2126 × 1.0）', () {
      expect(relativeLuminance(const Color(0xFFFF0000)), closeTo(0.2126, 1e-4));
    });

    test('纯绿 > 纯红 > 纯蓝（WCAG 权重 0.7152 > 0.2126 > 0.0722）', () {
      final lG = relativeLuminance(const Color(0xFF00FF00));
      final lR = relativeLuminance(const Color(0xFFFF0000));
      final lB = relativeLuminance(const Color(0xFF0000FF));
      expect(lG, greaterThan(lR));
      expect(lR, greaterThan(lB));
    });

    test('中等灰 #777777 ≈ 0.1845（手算参考）', () {
      expect(relativeLuminance(const Color(0xFF777777)), closeTo(0.1845, 1e-3));
    });
  });

  group('contrastRatio', () {
    test('黑/白 = 21:1，白/黑 = 21:1（对称）', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), 21.0);
      expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)), 21.0);
    });

    test('同色 = 1:1', () {
      expect(contrastRatio(const Color(0xFF007AFF), const Color(0xFF007AFF)), 1.0);
    });

    test('#777777 vs 白色 ≈ 4.48:1（低于 AA 4.5）', () {
      expect(
        contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)),
        closeTo(4.48, 0.02),
      );
    });

    test('#767676 vs 白色 ≈ 4.54:1（通过 AA 4.5）', () {
      expect(
        contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        closeTo(4.54, 0.02),
      );
    });

    test('半透明前景先合成再计算：60% 黑 on 白 = #666666 ≈ 5.74:1', () {
      expect(
        contrastRatio(const Color(0x99000000), const Color(0xFFFFFFFF)),
        closeTo(5.74, 0.05),
      );
    });

    test('60% 白 on 白 = 纯白 1:1（透明度不改变最终渲染色）', () {
      expect(
        contrastRatio(const Color(0x99FFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1.0, 1e-6),
      );
    });

    test('iOS secondaryLabel（0x99 alpha）on 白 ≈ 3.4:1（警告区间）', () {
      final ratio = contrastRatio(
        CupertinoColors.secondaryLabel,
        const Color(0xFFFFFFFF),
      );
      // 动态色未解析时，CupertinoColors.secondaryLabel 即浅色定义 0x993C3C43。
      expect(ratio, closeTo(3.44, 0.05));
    });
  });

  group('passesAA', () {
    test('黑字 on 白 / 白字 on 黑 均通过', () {
      expect(passesAA(const Color(0xFF000000), const Color(0xFFFFFFFF)), isTrue);
      expect(passesAA(const Color(0xFFFFFFFF), const Color(0xFF000000)), isTrue);
    });

    test('#767676 通过、#777777 不通过（4.5 门槛）', () {
      expect(passesAA(const Color(0xFF767676), const Color(0xFFFFFFFF)), isTrue);
      expect(passesAA(const Color(0xFF777777), const Color(0xFFFFFFFF)), isFalse);
    });

    test('大字门槛 3:1 与正文门槛 4.5:1 分开判定', () {
      // systemGrey 浅色 ≈ 2.93:1：大字号 3:1 也不达标。
      expect(
        passesAA(
          const Color(0xFF8E8E93),
          const Color(0xFFF2F2F7),
          threshold: 3.0,
        ),
        isFalse,
      );
      // iOS 蓝 on 白 ≈ 4.02:1：大字门槛通过、正文 4.5 不通过。
      expect(
        passesAA(const Color(0xFF007AFF), const Color(0xFFFFFFFF)),
        isFalse,
        reason: 'iOS 蓝 on 白实际 ≈ 4.02:1，正文不满足 AA 4.5',
      );
      expect(
        passesAA(
          const Color(0xFF007AFF),
          const Color(0xFFFFFFFF),
          threshold: 3.0,
        ),
        isTrue,
        reason: 'iOS 蓝 on 白 ≈ 4.02:1，满足大字/装饰 3:1',
      );
    });
  });

  group('compositeOver', () {
    test('不透明前景原样返回', () {
      final c = const Color(0xFF123456);
      expect(compositeOver(c, const Color(0xFFFFFFFF)), c);
    });

    test('60% 黑 on 白 = #666666', () {
      expect(
        compositeOver(const Color(0x99000000), const Color(0xFFFFFFFF)),
        const Color(0xFF666666),
      );
    });
  });

  group('formatColor', () {
    test('#RRGGBB 大写', () {
      expect(formatColor(const Color(0xFF007AFF)), '#007AFF');
      expect(formatColor(const Color(0xFF8E8E93)), '#8E8E93');
    });
  });
}