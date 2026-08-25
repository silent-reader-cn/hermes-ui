import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermex_flutter/features/settings/chat_send_shortcut_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatSendShortcutController 状态与持久化', () {
    test('默认值为 enter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(chatSendShortcutSettingsProvider);
      expect(state.mode, ChatSendShortcutMode.enter);
    });

    test('初始状态从 SharedPreferences 读取（ctrlEnter）', () async {
      SharedPreferences.setMockInitialValues({
        ChatSendShortcutController.keySendMode: 'ctrlEnter',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        chatSendShortcutSettingsProvider.notifier,
      );
      await controller.load();

      expect(
        container.read(chatSendShortcutSettingsProvider).mode,
        ChatSendShortcutMode.ctrlEnter,
      );
    });

    test('未知存储值回落默认 enter', () async {
      SharedPreferences.setMockInitialValues({
        ChatSendShortcutController.keySendMode: 'bogus',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        chatSendShortcutSettingsProvider.notifier,
      );
      await controller.load();

      expect(
        container.read(chatSendShortcutSettingsProvider).mode,
        ChatSendShortcutMode.enter,
      );
    });

    test('setMode 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        chatSendShortcutSettingsProvider.notifier,
      );
      await controller.setMode(ChatSendShortcutMode.ctrlEnter);

      expect(
        container.read(chatSendShortcutSettingsProvider).mode,
        ChatSendShortcutMode.ctrlEnter,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ChatSendShortcutController.keySendMode),
        'ctrlEnter',
      );

      await controller.setMode(ChatSendShortcutMode.enter);
      expect(
        container.read(chatSendShortcutSettingsProvider).mode,
        ChatSendShortcutMode.enter,
      );
      expect(prefs.getString(ChatSendShortcutController.keySendMode), 'enter');
    });
  });
}
