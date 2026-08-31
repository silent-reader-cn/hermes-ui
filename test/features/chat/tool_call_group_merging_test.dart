import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('todo.md #15 复现与验证：聊天完毕后工具卡整卡消失与状态重置', () {
    testWidgets('复现 1: done 载荷 tool_calls 为空/不全时，转正后工具卡不得消失', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-repro-1',
          'title': 'repro',
          'active_stream_id': 'stream-1',
          'messages': [
            {'role': 'user', 'content': '帮我跑测试', 'message_id': 'u1'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-repro-1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // 1. live 期间产生工具调用
      api.emit(const ToolStartedSseEvent(ToolStreamEvent(stableId: 't1', name: 'bash')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));

      // 断言 live 期间工具卡可见
      expect(find.byType(ToolCallGroupCard), findsOneWidget, reason: 'live 期间工具卡应渲染');

      // 2. done 事件到达：但 session 载荷内 tool_calls 为空/缺失（真实服务端常见形状）
      api.emit(
        const DoneSseEvent(
          DoneStreamEvent(
            session: {
              'session_id': 's-repro-1',
              'messages': [
                {'role': 'user', 'content': '帮我跑测试', 'message_id': 'u1'},
                {
                  'role': 'assistant',
                  'content': '测试已跑完',
                  'message_id': 'a1',
                },
              ],
              // 没有 tool_calls 字段或为空
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言：转正归档后，工具卡必须依然存在于 transcript 气泡中，不得整卡消失！
      expect(
        find.byType(ToolCallGroupCard),
        findsOneWidget,
        reason: 'done 后 session 未带 tool_calls 时，工具卡不应消失（应由 live/completed fallback 保底）',
      );
    });

    testWidgets('复现 2: done 晚于 stream_end 到达（或空 session 载荷），工具卡不得消失', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-repro-2',
          'title': 'repro',
          'active_stream_id': 'stream-2',
          'messages': [
            {'role': 'user', 'content': '查看文件', 'message_id': 'u2'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-repro-2')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      api.emit(const ToolStartedSseEvent(ToolStreamEvent(stableId: 't2', name: 'read_file')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      expect(find.byType(ToolCallGroupCard), findsOneWidget);

      // stream_end 先到（或 done 携带空 session）
      api.emit(const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's-repro-2'})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(ToolCallGroupCard),
        findsOneWidget,
        reason: 'done 携带空 session 时，live 工具调用应归档到 completedToolCallGroups，不应丢失',
      );
    });

    testWidgets('复现 3: live 期间用户展开工具卡，done 转正后展开状态不重置为折叠', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-repro-3',
          'title': 'repro',
          'active_stream_id': 'stream-3',
          'messages': [
            {'role': 'user', 'content': '列出目录', 'message_id': 'u3'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-repro-3')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      api.emit(const ToolStartedSseEvent(ToolStreamEvent(stableId: 't3', name: 'list_dir')));
      api.emit(const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't3', name: 'list_dir')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));

      // 点击展开
      expect(find.byType(ToolCallGroupCard), findsOneWidget);
      await tester.tap(find.byType(ToolCallGroupCard));
      await tester.pumpAndSettle();

      // 展开态下应有 chevron_up
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);

      // done 转正
      api.emit(
        const DoneSseEvent(
          DoneStreamEvent(
            session: {
              'session_id': 's-repro-3',
              'messages': [
                {'role': 'user', 'content': '列出目录', 'message_id': 'u3'},
                {'role': 'assistant', 'content': '完成', 'message_id': 'a3'},
              ],
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言：转正后依然保持展开态（chevron_up），未被重置为 chevron_down
      expect(
        find.byIcon(CupertinoIcons.chevron_up),
        findsOneWidget,
        reason: 'live 展开态在 done 转正为 transcript 后应被保留，不应重置为折叠态',
      );
    });

    testWidgets('多工具回合聚合开关开/关两种模式下 done 收尾均保留所有工具卡', (
      tester,
    ) async {
      for (final coalesce in [true, false]) {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({
          kToolGroupCoalesceKey: coalesce,
        });
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        api.sessionResult = {
          'session': {
            'session_id': 's-multi-$coalesce',
            'title': 'multi-tools',
            'active_stream_id': 'stream-multi-$coalesce',
            'messages': [
              {'role': 'user', 'content': '多工具调用', 'message_id': 'u1'},
            ],
            'message_count': 1,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: CupertinoApp(home: ChatPage(sessionId: 's-multi-$coalesce')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));

        // 发出两个不同工具
        api.emit(const ToolStartedSseEvent(ToolStreamEvent(stableId: 'tool-1', name: 'read_file')));
        api.emit(const ToolCompletedSseEvent(ToolStreamEvent(stableId: 'tool-1', name: 'read_file')));
        api.emit(const TokenSseEvent('中间有文本输出\n'));
        api.emit(const ToolStartedSseEvent(ToolStreamEvent(stableId: 'tool-2', name: 'bash')));
        api.emit(const ToolCompletedSseEvent(ToolStreamEvent(stableId: 'tool-2', name: 'bash')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));

        // done 载荷（未带 tool_calls）
        api.emit(
          DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's-multi-$coalesce',
                'messages': [
                  {'role': 'user', 'content': '多工具调用', 'message_id': 'u1'},
                  {'role': 'assistant', 'content': '中间有文本输出\n完成', 'message_id': 'a1'},
                ],
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 无论 coalesce 为 true 还是 false，工具卡都必须存在且不丢失！
        expect(
          find.byType(ToolCallGroupCard),
          findsWidgets,
          reason: 'coalesce=$coalesce 下 done 后工具卡必须全部保留',
        );
      }
    });
  });

  group('ToolCallGroup.merging 纯模型保底单测', () {
    test('primaryGroups 为空时，返回 fallbackGroups 完整副本', () {
      final fallback = [
        ToolCallGroup(
          id: 'g-fallback-1',
          anchorMessageID: 'msg-1',
          toolCalls: [
            ToolCall(id: 'call-1', name: 'bash', isCompleted: true),
          ],
        ),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: const [],
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      expect(merged.first.id, 'g-fallback-1');
      expect(merged.first.toolCalls.first.name, 'bash');
    });

    test('primaryGroups 与 fallbackGroups anchor 一致时，toolCalls 深度合并且不覆盖丢失', () {
      final primary = [
        ToolCallGroup(
          id: 'g-primary-1',
          anchorMessageID: 'msg-1',
          toolCalls: [
            ToolCall(id: 'call-1', name: 'read_file', isCompleted: true),
          ],
        ),
      ];
      final fallback = [
        ToolCallGroup(
          id: 'g-fallback-1',
          anchorMessageID: 'msg-1',
          toolCalls: [
            ToolCall(id: 'call-2', name: 'write_file', isCompleted: true),
          ],
        ),
      ];

      final merged = ToolCallGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(1));
      expect(merged.first.toolCalls, hasLength(2));
      expect(merged.first.toolCalls.map((t) => t.name).toList(), ['read_file', 'write_file']);
    });
  });
}
