import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/models/tool_call.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:hermex_flutter/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ToolGroupCoalesceController 状态与持久化', () {
    test('默认值为 true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(toolGroupCoalesceProvider);
      expect(state, isTrue);
    });

    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({
        kToolGroupCoalesceKey: false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(toolGroupCoalesceProvider.notifier);
      await controller.load();

      final state = container.read(toolGroupCoalesceProvider);
      expect(state, isFalse);
    });

    test('setCoalesce 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(toolGroupCoalesceProvider.notifier);
      await controller.setCoalesce(false);

      expect(container.read(toolGroupCoalesceProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kToolGroupCoalesceKey), isFalse);

      await controller.setCoalesce(true);
      expect(container.read(toolGroupCoalesceProvider), isTrue);
      expect(prefs.getBool(kToolGroupCoalesceKey), isTrue);
    });
  });

  group('ToolCallGroup.groups 聚合与穿插', () {
    test('coalesce: true 聚合模式：合并同一回合内不同 assistant 消息的工具调用', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'hello', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'let me check', messageId: 'm1'),
        const ChatMessage(role: 'assistant', content: 'now editing', messageId: 'm2'),
      ];
      final persistedCalls = [
        const PersistedToolCall(
          name: 'read_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        const PersistedToolCall(
          name: 'write_file',
          tid: 'call_2',
          assistantMsgIdx: 2,
        ),
      ];

      final aggregated = ToolCallGroup.groups(
        persistedToolCalls: persistedCalls,
        messages: messages,
        coalesce: true,
      );
      expect(aggregated, hasLength(1));
      expect(aggregated.single.anchorMessageID, 'm1');
      expect(aggregated.single.toolCalls, hasLength(2));
      expect(aggregated.single.toolCalls[0].id, 'call_1');
      expect(aggregated.single.toolCalls[1].id, 'call_2');
    });

    test('coalesce: false 穿插模式：保留独立 anchorMessageID 分别挂载在对应 assistant 消息旁', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'hello', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'let me check', messageId: 'm1'),
        const ChatMessage(role: 'assistant', content: 'now editing', messageId: 'm2'),
      ];
      final persistedCalls = [
        const PersistedToolCall(
          name: 'read_file',
          tid: 'call_1',
          assistantMsgIdx: 1,
        ),
        const PersistedToolCall(
          name: 'write_file',
          tid: 'call_2',
          assistantMsgIdx: 2,
        ),
      ];

      final interleaved = ToolCallGroup.groups(
        persistedToolCalls: persistedCalls,
        messages: messages,
        coalesce: false,
      );
      expect(interleaved, hasLength(2));
      expect(interleaved[0].anchorMessageID, 'm1');
      expect(interleaved[0].toolCalls, hasLength(1));
      expect(interleaved[0].toolCalls.single.id, 'call_1');

      expect(interleaved[1].anchorMessageID, 'm2');
      expect(interleaved[1].toolCalls, hasLength(1));
      expect(interleaved[1].toolCalls.single.id, 'call_2');
    });

    test('从消息元数据派生时 coalesce 开关同样生效', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'query', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_1'),
              'function': JsonObject({
                'name': JsonString('grep'),
                'arguments': JsonString('{"pattern": "abc"}'),
              }),
            }),
          ],
        ),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm2',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_2'),
              'function': JsonObject({
                'name': JsonString('cat'),
                'arguments': JsonString('{"file": "a.txt"}'),
              }),
            }),
          ],
        ),
      ];

      final coalesced = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
        coalesce: true,
      );
      expect(coalesced, hasLength(1));
      expect(coalesced.single.anchorMessageID, 'm1');
      expect(coalesced.single.toolCalls, hasLength(2));

      final nonCoalesced = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
        coalesce: false,
      );
      expect(nonCoalesced, hasLength(2));
      expect(nonCoalesced[0].anchorMessageID, 'm1');
      expect(nonCoalesced[0].toolCalls.single.id, 'call_1');
      expect(nonCoalesced[1].anchorMessageID, 'm2');
      expect(nonCoalesced[1].toolCalls.single.id, 'call_2');
    });
  });

  group('SettingsPage 对话分区 Widget 测试', () {
    testWidgets('渲染工具按回合聚合开关并响应点击切换', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => FakeSettingsApi(),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (_, _) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(const ValueKey('settings-group-tools-by-turn'));
      final switchFinder = find.byKey(const ValueKey('settings-switch-group-tools-by-turn'));

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('工具按回合聚合'), findsOneWidget);
      expect(find.text('关闭后工具折叠面板将穿插在对应回复旁'), findsOneWidget);

      expect(tileFinder, findsOneWidget);
      expect(switchFinder, findsOneWidget);

      // 默认开启
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);

      // 点击切换为关闭
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(toolGroupCoalesceProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kToolGroupCoalesceKey), isFalse);

      // 再次点击恢复开启
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(toolGroupCoalesceProvider), isTrue);
      expect(prefs.getBool(kToolGroupCoalesceKey), isTrue);
    });
  });
}
