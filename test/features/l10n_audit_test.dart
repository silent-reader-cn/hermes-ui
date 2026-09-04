import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L3 审计回归测试：扫描 lib/ 源码，断言「用户可见字符串位」的硬编码中文
/// 只剩豁免清单内的位置（docs/specs/l10n-exemptions.md）。
///
/// 两类模式：
/// 1. `Text('…中文…'` —— widget 层直接中文文本
/// 2. `label: '…中文…'` —— 表单/菜单 label
///
/// 豁免文件（内部键/渠道名/死代码，见豁免清单）：
/// - `lib/features/desktop/tray_manager_service.dart` 不再豁免（L2 已全本地化）——
///   若未来有人重新加硬编码中文 label，本测试变红。
void main() {
  group('l10n 硬编码中文审计回归', () {
    test('Text( 中文字面量零残留（豁免：无）', () {
      final violations = _scan(
        RegExp(r"Text\(\s*'(?:[^']*[\u4e00-\u9fff])"),
      );
      expect(
        violations,
        isEmpty,
        reason: '发现硬编码中文 Text()：\n${violations.join("\n")}\n'
            '→ 接 AppLocalizations（服务层用 LocaleResolver.resolve()），'
            '或更新 docs/specs/l10n-exemptions.md 并经主人批准',
      );
    });

    test("label: '中文' 零残留（豁免：session_list 内部键、memory 死代码、渠道常量）", () {
      final exemptFragments = [
        'session_list_providers.dart', // 内部键（_sectionTitle 渲染层映射）
        'memory_providers.dart', // 死代码（tab 实际渲染走 l10n）
        'turn_notification_service.dart', // 渠道 channelName 建后不可变
        'background_keepalive_service.dart', // 前台服务渠道名
      ];
      final violations = _scan(
        RegExp(r"label:\s*'(?:[^']*[\u4e00-\u9fff])"),
        excludePathFragments: exemptFragments,
      );
      expect(
        violations,
        isEmpty,
        reason: '发现硬编码中文 label：\n${violations.join("\n")}',
      );
    });
  });
}

/// 递归扫 lib/ 下全部 .dart，返回命中 [pattern] 的 `路径:行号: 内容` 列表。
List<String> _scan(RegExp pattern, {List<String> excludePathFragments = const []}) {
  final root = Directory('lib');
  expect(root.existsSync(), isTrue, reason: 'flutter test 工作目录应为项目根');
  final hits = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (excludePathFragments.any((f) => entity.path.contains(f))) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      // 跳过注释行
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
      if (pattern.hasMatch(line)) {
        hits.add('${entity.path}:${i + 1}: $trimmed');
      }
    }
  }
  return hits;
}
