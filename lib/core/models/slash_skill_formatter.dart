import 'skills.dart';

/// 技能斜杠建议（Swift: SkillSlashSuggestion）。纯客户端逻辑，无 JSON。
class SkillSlashSuggestion {
  const SkillSlashSuggestion({
    required this.name,
    this.category,
    this.description,
  });

  final String name;
  final String? category;
  final String? description;

  String get id => slashName;

  /// `/skill` 斜杠名（小写、空白与下划线转 `-`、只留 [a-z0-9-]、
  /// 去重连字符、trim 两端 `-`）。
  String get slashName => SlashSkillFormatter.slug(name);

  @override
  bool operator ==(Object other) {
    return other is SkillSlashSuggestion &&
        other.name == name &&
        other.category == category &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(name, category, description);

  @override
  String toString() => 'SkillSlashSuggestion(name: $name)';
}

/// 技能斜杠调用（Swift: SkillSlashInvocation）。
class SkillSlashInvocation {
  const SkillSlashInvocation({required this.skill, required this.message});

  final SkillSlashSuggestion skill;
  final String message;

  @override
  bool operator ==(Object other) {
    return other is SkillSlashInvocation &&
        other.skill == skill &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(skill, message);

  @override
  String toString() => 'SkillSlashInvocation(skill: ${skill.name})';
}

/// 斜杠技能格式化器（Swift `SlashSkillFormatter`）。
class SlashSkillFormatter {
  const SlashSkillFormatter._();

  /// 生成 `/skill` 斜杠名。
  static String slug(String name) {
    final lower = name.trim().toLowerCase();
    final collapsed = lower
        .split(RegExp(r'[\s_]+'))
        .where((s) => s.isNotEmpty)
        .join('-');
    final filtered = collapsed.replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final deduped = filtered.replaceAll(RegExp(r'-+'), '-');
    return deduped.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// 从技能列表生成建议（trim 非空 + 斜杠名非空；按斜杠名去重；排序）。
  static List<SkillSlashSuggestion> suggestions(List<SkillSummary> skills) {
    final parsed = <SkillSlashSuggestion>[];
    for (final skill in skills) {
      final rawName = skill.name?.trim();
      if (rawName == null || rawName.isEmpty) continue;
      if (slug(rawName).isEmpty) continue;

      final category = skill.category?.trim();
      final description = skill.description?.trim();
      parsed.add(SkillSlashSuggestion(
        name: rawName,
        category: (category == null || category.isEmpty) ? null : category,
        description:
            (description == null || description.isEmpty) ? null : description,
      ));
    }

    final seen = <String>{};
    final result = <SkillSlashSuggestion>[];
    for (final suggestion in parsed) {
      if (seen.add(suggestion.slashName)) {
        result.add(suggestion);
      }
    }
    result.sort((a, b) =>
        a.slashName.toLowerCase().compareTo(b.slashName.toLowerCase()));
    return result;
  }

  /// 从 args 提取技能查询词（第一个空白分隔段）。
  static String skillQuery(String args) {
    final trimmed = args.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.first;
  }

  /// 解析 `/skill <message>` 调用；格式不符 → null。
  static SkillSlashInvocation? invocation(
    String args,
    List<SkillSlashSuggestion> suggestions,
  ) {
    final trimmed = args.trim();
    final parts = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length != 2) return null;

    final skill = skillNamed(parts[0], suggestions);
    if (skill == null) return null;

    final message = parts[1].trim();
    if (message.isEmpty) return null;
    return SkillSlashInvocation(skill: skill, message: message);
  }

  static SkillSlashSuggestion? skillNamed(
    String name,
    List<SkillSlashSuggestion> suggestions,
  ) {
    final requested = name.trim().toLowerCase();
    if (requested.isEmpty) return null;
    for (final suggestion in suggestions) {
      if (suggestion.slashName.toLowerCase() == requested ||
          suggestion.name.toLowerCase() == requested) {
        return suggestion;
      }
    }
    return null;
  }

  static String messageText(SkillSlashInvocation invocation) {
    return '/${invocation.skill.slashName} ${invocation.message}';
  }

  static String detailMessage(SkillSlashSuggestion skill) {
    final lines = <String>[
      '### `/${skill.slashName}`',
      '',
      '**${skill.name}**',
    ];
    if (skill.category != null) {
      lines.add('');
      lines.add('Category: ${skill.category}');
    }
    if (skill.description != null) {
      lines.add('');
      lines.add(skill.description!);
    }
    lines.add('');
    lines.add('Send `/${skill.slashName} <message>` to use this skill.');
    return lines.join('\n');
  }

  /// 匹配查询（斜杠名 / 名称 / 分类 / 描述大小写不敏感包含）。
  static List<SkillSlashSuggestion> matching(
    String query,
    List<SkillSlashSuggestion> suggestions,
  ) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return suggestions;
    return suggestions.where((suggestion) {
      return suggestion.slashName.toLowerCase().contains(trimmed.toLowerCase()) ||
          suggestion.name.toLowerCase().contains(trimmed.toLowerCase()) ||
          (suggestion.category?.toLowerCase().contains(trimmed.toLowerCase()) ??
              false) ||
          (suggestion.description
                  ?.toLowerCase()
                  .contains(trimmed.toLowerCase()) ??
              false);
    }).toList();
  }

  /// 生成技能列表消息（空列表 / 无匹配 / 分类分组展示）。
  static String message(
    List<SkillSlashSuggestion> suggestions,
    String query,
  ) {
    final trimmed = query.trim();
    if (suggestions.isEmpty) {
      return 'No skills are configured on the server.';
    }
    final matches = matching(trimmed, suggestions);
    if (matches.isEmpty) {
      return 'No skills match `$trimmed`.';
    }

    final heading = trimmed.isEmpty
        ? 'Available skills:'
        : 'Skills matching `$trimmed`:';

    final grouped = <String, List<SkillSlashSuggestion>>{};
    for (final suggestion in matches) {
      grouped
          .putIfAbsent(suggestion.category ?? 'Uncategorized', () => [])
          .add(suggestion);
    }
    final categoryKeys = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sections = categoryKeys.map((category) {
      final rows = grouped[category]!;
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final rowText = rows.map((suggestion) {
        if (suggestion.description != null && suggestion.description!.isNotEmpty) {
          return '- `/${suggestion.slashName}` - **${suggestion.name}** - '
              '${suggestion.description}';
        }
        return '- `/${suggestion.slashName}` - **${suggestion.name}**';
      }).join('\n');
      return '### $category\n$rowText';
    }).join('\n\n');

    return '$heading\n\n$sections';
  }
}
