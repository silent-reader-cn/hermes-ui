import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/session_list/session_row_subtitle_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话行副标题显示项开关：默认值 / 持久化 / 持久化恢复。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认值：消息数/项目名/工作区开，渠道/预估价钱关', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = container.read(sessionRowSubtitleSettingsProvider);
    expect(settings.messageCount, isTrue);
    expect(settings.projectName, isTrue);
    expect(settings.workspace, isTrue);
    expect(settings.channel, isFalse);
    expect(settings.estimatedCost, isFalse);
  });

  test('setter 立即更新状态并持久化到 shared_preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      sessionRowSubtitleSettingsProvider.notifier,
    );
    await controller.setChannel(true);
    await controller.setEstimatedCost(true);
    await controller.setMessageCount(false);

    final settings = container.read(sessionRowSubtitleSettingsProvider);
    expect(settings.channel, isTrue);
    expect(settings.estimatedCost, isTrue);
    expect(settings.messageCount, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(SessionRowSubtitleSettingsController.keyChannel),
      isTrue,
    );
    expect(
      prefs.getBool(SessionRowSubtitleSettingsController.keyEstimatedCost),
      isTrue,
    );
    expect(
      prefs.getBool(SessionRowSubtitleSettingsController.keyMessageCount),
      isFalse,
    );
  });

  test('重启（新容器）后从 shared_preferences 恢复自定义值', () async {
    SharedPreferences.setMockInitialValues({
      SessionRowSubtitleSettingsController.keyChannel: true,
      SessionRowSubtitleSettingsController.keyEstimatedCost: true,
      SessionRowSubtitleSettingsController.keyProjectName: false,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // build() 异步 _load：轮询等待持久化值恢复完成。
    for (var i = 0; i < 100; i++) {
      if (container.read(sessionRowSubtitleSettingsProvider).channel) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final settings = container.read(sessionRowSubtitleSettingsProvider);
    expect(settings.channel, isTrue);
    expect(settings.estimatedCost, isTrue);
    expect(settings.projectName, isFalse);
    expect(settings.messageCount, isTrue); // 未持久化 → 默认开
    expect(settings.workspace, isTrue); // 未持久化 → 默认开
  });
}