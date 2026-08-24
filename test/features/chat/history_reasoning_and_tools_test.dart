import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/models/tool_call.dart';
import 'package:hermex_flutter/features/chat/chat_models.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/widgets/message_bubble.dart';
import 'package:hermex_flutter/features/chat/widgets/tool_call_card.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('ReasoningGroup.groups & merging 纯函数测试', () {
    test('groups: 从历史消息正确提取每个 assistant 消息的推理段', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'What is 2+2?', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          content: '4',
          messageId: 'a1',
          reasoning: 'Calculate 2 + 2 = 4 directly.',
        ),
        const ChatMessage(role: 'user', content: 'Explain more', messageId: 'u2'),
        const ChatMessage(
          role: 'assistant',
          content: 'Addition is basic arithmetic.',
          messageId: 'a2',
          reasoning: 'Elaborate on elementary addition properties.',
        ),
        const ChatMessage(
          role: 'assistant',
          content: 'No reasoning here',
          messageId: 'a3',
        ),
      ];

      final groups = ReasoningGroup.groups(messages: messages);
      expect(groups, hasLength(2));
      expect(groups[0].anchorMessageId, 'a1');
      expect(groups[0].text, 'Calculate 2 + 2 = 4 directly.');
      expect(groups[1].anchorMessageId, 'a2');
      expect(groups[1].text, 'Elaborate on elementary addition properties.');
    });

    test('groups: 无 messageId 时用 raw:offset+index 兜底 anchor', () {
      final messages = [
        const ChatMessage(
          role: 'assistant',
          content: 'Result',
          reasoning: 'Step by step reasoning',
        ),
      ];
      final groups = ReasoningGroup.groups(messages: messages, messageOffset: 10);
      expect(groups, hasLength(1));
      expect(groups.single.anchorMessageId, 'raw:10');
      expect(groups.single.text, 'Step by step reasoning');
    });

    test('merging: primary 与 fallback 按 anchorMessageId 合并去重', () {
      const primary = [
        ReasoningGroup(anchorMessageId: 'a1', text: 'Server reasoning 1'),
        ReasoningGroup(anchorMessageId: 'a2', text: 'Server reasoning 2'),
      ];
      const fallback = [
        ReasoningGroup(anchorMessageId: 'a1', text: 'Local live reasoning 1'),
        ReasoningGroup(anchorMessageId: 'a3', text: 'Local live reasoning 3'),
      ];

      final merged = ReasoningGroup.merging(
        primaryGroups: primary,
        fallbackGroups: fallback,
      );

      expect(merged, hasLength(3));
      expect(merged[0].anchorMessageId, 'a1');
      expect(merged[0].text, 'Server reasoning 1');
      expect(merged[1].anchorMessageId, 'a2');
      expect(merged[1].text, 'Server reasoning 2');
      expect(merged[2].anchorMessageId, 'a3');
      expect(merged[2].text, 'Local live reasoning 3');
    });
  });

  group('ChatController 历史会话推理与工具调用链路测试', () {
    test('loadMessages 加载历史会话 → 正确填充 completedReasoningGroups 与 completedToolCallGroups', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-history-1',
          'title': '历史会话',
          'messages': [
            {'role': 'user', 'content': '查看文件并总结', 'message_id': 'u1'},
            {
              'role': 'assistant',
              'content': '已完成总结',
              'message_id': 'a1',
              'reasoning': '首先读取 readme.md 文件，然后整理核心要点。',
            },
          ],
          'tool_calls': [
            {
              'name': 'read_file',
              'snippet': 'README content...',
              'tid': 't1',
              'assistant_msg_idx': 1,
              'args': {'path': 'README.md'},
            },
          ],
        },
      };

      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider('sess-history-1').notifier);
      await controller.loadMessages();

      final state = container.read(chatControllerProvider('sess-history-1'));
      expect(state.completedReasoningGroups, hasLength(1));
      expect(state.completedReasoningGroups.single.anchorMessageId, 'a1');
      expect(
        state.completedReasoningGroups.single.text,
        '首先读取 readme.md 文件，然后整理核心要点。',
      );

      expect(state.completedToolCallGroups, hasLength(1));
      expect(state.completedToolCallGroups.single.anchorMessageID, 'a1');
      expect(state.completedToolCallGroups.single.toolCalls.single.name, 'read_file');

      final reasoningGroups = container.read(reasoningGroupsProvider('sess-history-1'));
      expect(reasoningGroups, hasLength(1));
      expect(reasoningGroups.single.text, '首先读取 readme.md 文件，然后整理核心要点。');

      final toolGroups = container.read(toolGroupsProvider('sess-history-1'));
      expect(toolGroups, hasLength(1));
      expect(toolGroups.single.toolCalls.single.name, 'read_file');
    });
  });

  group('Widget 测试：历史思考与工具调用折叠展开', () {
    testWidgets('ChatMessageBubble 渲染历史思考块与工具卡片，支持点击折叠与展开', (tester) async {
      const fullReasoningText =
          '这是历史思考过程的详细步骤：首先分析用户问题，其次查阅相关代码模块，最后组织回复结构并检查语法正确性。补充细节：涉及多轮工具调用与状态机合并，需保证锚点与转录消息索引一致，且在不同 collapsed/expanded 态下渲染稳定。';
      const reasoningGroup = ReasoningGroup(
        anchorMessageId: 'a1',
        text: fullReasoningText,
      );
      final toolCall = ToolCall(
        id: 't1',
        name: 'read_file',
        preview: 'line 1\nline 2\nline 3',
        args: {'path': const JsonString('lib/main.dart')},
        isCompleted: true,
      );
      final toolGroup = ToolCallGroup(
        anchorMessageID: 'a1',
        toolCalls: [toolCall],
      );

      const message = ChatMessage(
        role: 'assistant',
        content: '这是最终回答内容。',
        messageId: 'a1',
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: ChatMessageBubble(
                message: message,
                reasoningGroups: const [reasoningGroup],
                toolGroups: [toolGroup],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1) 验证初始状态：正文可见，思考块和工具卡片均处于默认收起态（向右箭头）
      expect(find.text('这是最终回答内容。'), findsOneWidget);
      expect(find.text('思考'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsWidgets); // tool card chevron_down
      // 收起时 preview 与完整文本相同（80 字符内不截断），或预览显示截断版本
      expect(find.byType(ToolCallGroupCard), findsOneWidget);
      expect(find.byType(ToolCallCard), findsNothing); // 工具详情收起中（外层 GroupCard 折叠时内层 Card 不在树）

      // 2) 点击思考块展开（箭头朝下，完整文本渲染）
      await tester.tap(find.text('思考'));
      await tester.pumpAndSettle();
      expect(find.text(fullReasoningText), findsOneWidget); // 展开成功
      expect(find.byIcon(CupertinoIcons.chevron_down), findsWidgets);

      // 3) 再次点击思考块折叠
      await tester.tap(find.text('思考'));
      await tester.pumpAndSettle();
      expect(find.text(fullReasoningText), findsNothing); // 折叠成功

      // 4) 点击工具卡片展开
      await tester.tap(find.byType(ToolCallGroupCard));
      await tester.pumpAndSettle();
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.textContaining('读取'), findsWidgets); // 工具卡片已展开（组标题+子卡片 header）
    });

    testWidgets('ChatPage 全链路：加载含 reasoning 与 toolCalls 的历史会话，气泡内可展开查看', (tester) async {
      const fullThinking =
          '深度思考全链路测试：第一步分析项目结构，第二步定位数据模型，第三步检查 UI 折叠状态机，最后确认各层数据传递与渲染一致性。额外补充：第四步验证边界条件与异常分支，第五步收敛为可复用工具与测试覆盖，确保历史回放与实时流式行为完全一致。';
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-hist-ui',
          'title': '历史会话 UI 测试',
          'messages': [
            {'role': 'user', 'content': '帮我分析代码', 'message_id': 'u1'},
            {
              'role': 'assistant',
              'content': '分析完毕，无任何错误。',
              'message_id': 'a1',
              'reasoning': fullThinking,
            },
          ],
          'tool_calls': [
            {
              'name': 'analyze_files',
              'snippet': 'No lint errors found.',
              'tid': 't1',
              'assistant_msg_idx': 1,
              'args': {'dir': 'lib/'},
            },
          ],
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 'sess-hist-ui'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 历史消息正文、思考预览与工具卡片均已渲染
      expect(find.text('帮我分析代码'), findsOneWidget);
      expect(find.text('分析完毕，无任何错误。'), findsOneWidget);
      expect(find.text('思考'), findsOneWidget);
      expect(find.text(fullThinking), findsNothing);
      expect(find.byType(ToolCallGroupCard), findsOneWidget);

      // 点击展开历史思考
      await tester.tap(find.text('思考'));
      await tester.pumpAndSettle();
      expect(find.text(fullThinking), findsOneWidget);
    });
  });
}
