import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_media_cache.dart';

const _k1x1Png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _FakeActiveConnectionController extends ActiveConnectionController {
  _FakeActiveConnectionController(this._initial);
  final ServerConnection? _initial;
  @override
  ServerConnection? build() => _initial;
}

void main() {
  group('意见4a: 图片异步加载撑高列表滚动条跟随与手势状态测试', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    ChatMessageListState stateOf(WidgetTester tester) {
      return tester.state<ChatMessageListState>(
        find.byType(ChatMessageList).first,
      );
    }

    List<Map<String, dynamic>> generateMessages({
      required int count,
      Map<int, String>? imageAt,
    }) {
      return List.generate(count, (i) {
        final imgUrl = imageAt?[i];
        final content = imgUrl != null
            ? '图片消息 $i：MEDIA:$imgUrl'
            : '测试文本消息第 $i 轮：用于撑高滚动视图的内容。' * 4;
        return {
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm-$i',
        };
      });
    }

    /// 推进固定帧以完成初始布局与收敛（避免 CupertinoActivityIndicator 无限动画导致 pumpAndSettle 超时）。
    Future<void> pumpInitialSettlement(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 推进图片解码与 AnimatedSize 展开多帧。
    Future<void> pumpImageLoadFrames(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets(
      '1. 初始进入含异步图片会话：图片异步加载撑高 extent → 保持贴底跟随（pixels 贴近 maxScrollExtent 且 nearBottom == true）',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final imageCompleter = Completer<Uint8List>();
        final rig = buildFakeMediaCache(
          downloader: (uri) => imageCompleter.future,
        );
        addTearDown(rig.dispose);

        final api = FakeChatApi();
        api.sessionResult = {
          'session': {
            'session_id': 's-img-follow-1',
            'messages': generateMessages(
              count: 20,
              imageAt: {19: 'https://example.com/bottom_photo.png'},
            ),
            'message_count': 20,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeConnectionProvider.overrideWith(
                () => _FakeActiveConnectionController(null),
              ),
              appDatabaseProvider.overrideWithValue(rig.database),
              chatApiProvider.overrideWithValue(api),
              mediaCacheOverride(rig.service),
            ],
            child: const CupertinoApp(
              home: ChatPage(sessionId: 's-img-follow-1'),
            ),
          ),
        );

        // 初始等待布局收敛，此时图片尚在下载中（占位态）
        await pumpInitialSettlement(tester);

        final state = stateOf(tester);
        final pos = positionOf(tester);

        expect(state.initialPositioned, isTrue);
        expect(state.userHasScrolled, isFalse);
        expect(state.nearBottom, isTrue);
        expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));

        // 模拟网络图片下载完成，返回有效 PNG 数据
        final pngBytes = base64Decode(_k1x1Png.split(',')[1]);
        imageCompleter.complete(Uint8List.fromList(pngBytes));

        // 推进图片解码与 AnimatedSize 布局多帧
        await pumpImageLoadFrames(tester);

        // 验证图片加载撑高后，底部跟随未被打断，滚动条依然紧贴底部
        expect(
          state.userHasScrolled,
          isFalse,
          reason: '图片异步加载不应被误判为用户主动离底滚动',
        );
        expect(
          state.nearBottom,
          isTrue,
          reason: '图片异步加载撑高后 _nearBottom 必须保持为 true',
        );
        expect(
          pos.pixels,
          closeTo(pos.maxScrollExtent, 1.0),
          reason: '滚动条像素必须自动跟进到最新的 maxScrollExtent',
        );
        expect(
          find.text('回到底部'),
          findsNothing,
          reason: '跟随状态下不应弹出「回到底部」悬浮按钮',
        );
      },
    );

    testWidgets('2. 多张异步图片先后加载完成：连续撑高 extent 持续保持贴底跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final completer1 = Completer<Uint8List>();
      final completer2 = Completer<Uint8List>();

      final rig = buildFakeMediaCache(
        downloader: (uri) {
          if (uri.toString().contains('img1')) return completer1.future;
          return completer2.future;
        },
      );
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-img-multi',
          'messages': generateMessages(
            count: 20,
            imageAt: {
              10: 'https://example.com/img1.png',
              19: 'https://example.com/img2.png',
            },
          ),
          'message_count': 20,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-img-multi')),
        ),
      );

      await pumpInitialSettlement(tester);

      final state = stateOf(tester);
      final pos = positionOf(tester);

      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);

      final pngBytes = Uint8List.fromList(
        base64Decode(_k1x1Png.split(',')[1]),
      );

      // 第一张图加载完成
      completer1.complete(pngBytes);
      await pumpImageLoadFrames(tester);

      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));

      // 第二张图加载完成
      completer2.complete(pngBytes);
      await pumpImageLoadFrames(tester);

      expect(state.nearBottom, isTrue);
      expect(state.userHasScrolled, isFalse);
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));
    });

    testWidgets('3. 用户手势上滚（drag）离底后：图片异步加载不打断用户阅读，不再自动滚底', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<Uint8List>();
      final rig = buildFakeMediaCache(
        downloader: (uri) => imageCompleter.future,
      );
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-img-user-scrolled',
          'messages': generateMessages(
            count: 25,
            imageAt: {24: 'https://example.com/late_image.png'},
          ),
          'message_count': 25,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-img-user-scrolled'),
          ),
        ),
      );

      await pumpInitialSettlement(tester);

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 用户主动向下滑动 400px（手指从上往下滑，内容下移，查看历史消息）
      await tester.drag(scrollable, const Offset(0, 400));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(state.userHasScrolled, isTrue, reason: '用户主动滑动离底后应置 userHasScrolled 为 true');
      expect(state.nearBottom, isFalse);

      final readingPixels = pos.pixels;

      // 此时图片异步加载完成
      final pngBytes = Uint8List.fromList(
        base64Decode(_k1x1Png.split(',')[1]),
      );
      imageCompleter.complete(pngBytes);

      await pumpImageLoadFrames(tester);

      // 验证：用户处于离底阅读态时，图片加载绝不自动拉到底部
      expect(
        state.userHasScrolled,
        isTrue,
        reason: '用户已离底阅读，图片加载不得重置 userHasScrolled',
      );
      expect(state.nearBottom, isFalse);
      expect(
        (pos.pixels - readingPixels).abs(),
        lessThan(5.0),
        reason: '用户视口阅读位置应保持稳定，不被自动拽回底部',
      );
    });

    testWidgets('4. 用户离底后点击「回到底部」恢复跟随：后续图片加载继续正常跟随', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<Uint8List>();
      final rig = buildFakeMediaCache(
        downloader: (uri) => imageCompleter.future,
      );
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-img-resume',
          'messages': generateMessages(
            count: 25,
            imageAt: {24: 'https://example.com/future_image.png'},
          ),
          'message_count': 25,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-img-resume'),
          ),
        ),
      );

      await pumpInitialSettlement(tester);

      final scrollable = find.byType(Scrollable).first;
      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 先离底
      await tester.drag(scrollable, const Offset(0, 300));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);

      // 点击「回到底部」
      await tester.tap(find.text('回到底部'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);

      // 恢复跟随之后图片完成加载
      final pngBytes = Uint8List.fromList(
        base64Decode(_k1x1Png.split(',')[1]),
      );
      imageCompleter.complete(pngBytes);

      await pumpImageLoadFrames(tester);

      // 验证恢复跟随后的图片加载正常跟底
      expect(state.userHasScrolled, isFalse);
      expect(state.nearBottom, isTrue);
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));
    });

    testWidgets('5. 大纲跳转（outlineJumpTo）主动离底后：图片异步加载不拉回底部', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<Uint8List>();
      final rig = buildFakeMediaCache(
        downloader: (uri) => imageCompleter.future,
      );
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-img-outline',
          'messages': generateMessages(
            count: 30,
            imageAt: {29: 'https://example.com/bottom_img.png'},
          ),
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-img-outline'),
          ),
        ),
      );

      await pumpInitialSettlement(tester);

      final state = stateOf(tester);
      final pos = positionOf(tester);

      // 主动大纲跳转到第 2 条消息
      state.outlineJumpTo('m-2', 2);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(state.userHasScrolled, isTrue, reason: '大纲跳转后必须进入主动离底阅读态');
      expect(state.nearBottom, isFalse);

      final jumpPixels = pos.pixels;

      // 图片加载完成
      final pngBytes = Uint8List.fromList(
        base64Decode(_k1x1Png.split(',')[1]),
      );
      imageCompleter.complete(pngBytes);

      await pumpImageLoadFrames(tester);

      // 验证大纲跳转位置不被图片加载破坏
      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      expect(
        (pos.pixels - jumpPixels).abs(),
        lessThan(50.0),
        reason: '大纲跳转后的阅读位置不受底部图片异步加载影响',
      );
    });

    testWidgets('6. 搜索高亮定位进入会话：图片异步加载不破坏高亮定位与离底阅读态', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final imageCompleter = Completer<Uint8List>();
      final rig = buildFakeMediaCache(
        downloader: (uri) => imageCompleter.future,
      );
      addTearDown(rig.dispose);

      final api = FakeChatApi();
      final messages = generateMessages(
        count: 30,
        imageAt: {29: 'https://example.com/bottom_img.png'},
      );
      messages[3]['content'] = '这是包含 UNIQUE_SEARCH_KEYWORD 的特殊历史消息';

      api.sessionResult = {
        'session': {
          'session_id': 's-img-highlight',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(null),
            ),
            appDatabaseProvider.overrideWithValue(rig.database),
            chatApiProvider.overrideWithValue(api),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(
            home: ChatPage(
              sessionId: 's-img-highlight',
              searchQuery: 'UNIQUE_SEARCH_KEYWORD',
              matchType: 'content',
            ),
          ),
        ),
      );

      await pumpInitialSettlement(tester);

      final state = stateOf(tester);
      final pos = positionOf(tester);

      expect(state.userHasScrolled, isTrue, reason: '搜索高亮定位必须进入离底阅读态');
      expect(state.nearBottom, isFalse);

      final highlightPixels = pos.pixels;

      // 图片加载完成
      final pngBytes = Uint8List.fromList(
        base64Decode(_k1x1Png.split(',')[1]),
      );
      imageCompleter.complete(pngBytes);

      await pumpImageLoadFrames(tester);

      expect(state.userHasScrolled, isTrue);
      expect(state.nearBottom, isFalse);
      expect(
        (pos.pixels - highlightPixels).abs(),
        lessThan(50.0),
        reason: '高亮定位位置不被底部图片加载破坏',
      );
    });
  });
}
