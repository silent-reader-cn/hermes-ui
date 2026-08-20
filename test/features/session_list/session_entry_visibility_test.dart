import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/session_list/session_entry_visibility.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionEntryVisibility 模型单测', () {
    test('默认配置全为 true', () {
      const visibility = SessionEntryVisibility();
      expect(visibility.tasks, isTrue);
      expect(visibility.kanban, isTrue);
      expect(visibility.skills, isTrue);
      expect(visibility.memory, isTrue);
      expect(visibility.insights, isTrue);
      expect(visibility.showsAny, isTrue);
      expect(SessionEntryVisibility.defaults, equals(visibility));
    });

    test('showsAny 语义判定', () {
      expect(
        const SessionEntryVisibility(
          tasks: false,
          kanban: false,
          skills: false,
          memory: false,
          insights: false,
        ).showsAny,
        isFalse,
      );

      expect(
        const SessionEntryVisibility(
          tasks: true,
          kanban: false,
          skills: false,
          memory: false,
          insights: false,
        ).showsAny,
        isTrue,
      );

      expect(
        const SessionEntryVisibility(
          tasks: false,
          kanban: false,
          skills: false,
          memory: false,
          insights: true,
        ).showsAny,
        isTrue,
      );
    });

    test('isVisible 对应各入口标识', () {
      const visibility = SessionEntryVisibility(
        tasks: true,
        kanban: false,
        skills: true,
        memory: false,
        insights: true,
      );

      expect(visibility.isVisible('tasks'), isTrue);
      expect(visibility.isVisible('kanban'), isFalse);
      expect(visibility.isVisible('skills'), isTrue);
      expect(visibility.isVisible('memory'), isFalse);
      expect(visibility.isVisible('insights'), isTrue);
      expect(visibility.isVisible('unknown'), isTrue);
    });

    test('copyWith 支持增量覆盖', () {
      const original = SessionEntryVisibility();
      final modified = original.copyWith(tasks: false, memory: false);

      expect(modified.tasks, isFalse);
      expect(modified.kanban, isTrue);
      expect(modified.skills, isTrue);
      expect(modified.memory, isFalse);
      expect(modified.insights, isTrue);
    });

    test('== 与 hashCode 及 toString', () {
      const a = SessionEntryVisibility(tasks: false);
      const b = SessionEntryVisibility(tasks: false);
      const c = SessionEntryVisibility(tasks: true);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('tasks: false'));
    });
  });

  group('sessionEntryVisibilityProvider 与 Controller 单测', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('初始状态从 SharedPreferences 读取（无记录时默认全开）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isTrue);
      expect(state.kanban, isTrue);
      expect(state.skills, isTrue);
      expect(state.memory, isTrue);
      expect(state.insights, isTrue);
    });

    test('初始状态从 SharedPreferences 读取已有持久化值', () async {
      SharedPreferences.setMockInitialValues({
        'session_entry_visibility_tasks': false,
        'session_entry_visibility_kanban': true,
        'session_entry_visibility_skills': false,
        'session_entry_visibility_memory': true,
        'session_entry_visibility_insights': false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 读取并等待 _load 异步完成
      container.read(sessionEntryVisibilityProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isTrue);
      expect(state.skills, isFalse);
      expect(state.memory, isTrue);
      expect(state.insights, isFalse);
    });

    test('setVisible 更新状态并持久化到 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(sessionEntryVisibilityProvider.notifier);

      await controller.setVisible('tasks', false);
      await controller.setVisible('insights', false);

      final state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isTrue);
      expect(state.skills, isTrue);
      expect(state.memory, isTrue);
      expect(state.insights, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_entry_visibility_tasks'), isFalse);
      expect(prefs.getBool('session_entry_visibility_insights'), isFalse);
    });

    test('setVisible 处理所有 5 个合法 key 及未知 key', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(sessionEntryVisibilityProvider.notifier);

      await controller.setVisible('tasks', false);
      await controller.setVisible('kanban', false);
      await controller.setVisible('skills', false);
      await controller.setVisible('memory', false);
      await controller.setVisible('insights', false);
      await controller.setVisible('unknown_key', false);

      final state = container.read(sessionEntryVisibilityProvider);
      expect(state.showsAny, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_entry_visibility_tasks'), isFalse);
      expect(prefs.getBool('session_entry_visibility_kanban'), isFalse);
      expect(prefs.getBool('session_entry_visibility_skills'), isFalse);
      expect(prefs.getBool('session_entry_visibility_memory'), isFalse);
      expect(prefs.getBool('session_entry_visibility_insights'), isFalse);
      expect(prefs.containsKey('session_entry_visibility_unknown_key'), isFalse);
    });
  });
}
