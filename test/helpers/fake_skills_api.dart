import 'dart:async';

import 'package:hermex_flutter/core/models/skills.dart';
import 'package:hermex_flutter/features/skills/skills_api.dart';

/// 可配置的 [SkillsApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空技能列表；测试可按需配置 [skills] / [fetchError] /
/// [fetchGate]，并通过 [fetchCount] 断言调用次数。
class FakeSkillsApi implements SkillsApi {
  FakeSkillsApi({List<SkillSummary>? skills}) : skills = skills ?? [];

  /// `fetchSkills` 返回的技能列表。
  List<SkillSummary> skills;

  /// `fetchSkills` 抛出的异常（非 null 时优先于 [skills]）。
  Object? fetchError;

  /// 非 null 时 `fetchSkills` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// `fetchSkills` 调用次数。
  int fetchCount = 0;

  /// `toggleSkill` 抛出的异常。
  Object? toggleError;

  /// `toggleSkill` 记录的调用历史：`[(name, enabled), ...]`。
  final List<({String name, bool enabled})> toggleCalls = [];

  @override
  Future<SkillsResponse> fetchSkills() async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return SkillsResponse(skills: skills);
  }

  @override
  Future<ToggleSkillResponse> toggleSkill({
    required String name,
    required bool enabled,
  }) async {
    toggleCalls.add((name: name, enabled: enabled));
    final error = toggleError;
    if (error != null) throw error;
    final index = skills.indexWhere((s) => s.name == name);
    if (index != -1) {
      skills[index] = skills[index].copyWith(disabled: !enabled);
    }
    return ToggleSkillResponse(ok: true, name: name, enabled: enabled);
  }
}
