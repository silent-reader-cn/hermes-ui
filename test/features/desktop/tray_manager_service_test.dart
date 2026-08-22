import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/desktop/tray_manager_service.dart';
import 'package:tray_manager/tray_manager.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.view(bytes.buffer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('prepareTrayIconFile 临时图标落盘测试', () {
    test('从 assetBundle 读取字节并成功写入指定临时文件', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final testBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
      ]);
      final fakeBundle = _FakeAssetBundle(testBytes);

      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon_32.png',
        fileName: 'test_tray_icon.png',
      );

      final file = File(iconPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), testBytes.length);
      expect(await file.readAsBytes(), testBytes);
    });
  });

  group('会话状态与文案格式化纯函数测试', () {
    test('formatSessionStatus 状态映射', () {
      expect(
        formatSessionStatus(const SessionSummary(isStreaming: true)),
        '运行中',
      );
      expect(
        formatSessionStatus(const SessionSummary(activeStreamId: 'stream-123')),
        '运行中',
      );
      expect(
        formatSessionStatus(const SessionSummary(hasPendingUserMessage: true)),
        '排队中',
      );
      expect(formatSessionStatus(const SessionSummary(archived: true)), '已归档');
      expect(formatSessionStatus(const SessionSummary(readOnly: true)), '只读');
      expect(formatSessionStatus(const SessionSummary(isReadOnly: true)), '只读');
      expect(
        formatSessionStatus(const SessionSummary(sourceTag: 'subagent')),
        '只读',
      );
      expect(formatSessionStatus(const SessionSummary()), isNull);
    });

    test('formatRecentSessionLabel 标题与状态组合及截断', () {
      expect(
        formatRecentSessionLabel(const SessionSummary(title: '日常答疑')),
        '日常答疑',
      );
      expect(
        formatRecentSessionLabel(
          const SessionSummary(title: '日常答疑', isStreaming: true),
        ),
        '日常答疑 (运行中)',
      );
      expect(
        formatRecentSessionLabel(
          const SessionSummary(title: '', archived: true),
        ),
        'Untitled (已归档)',
      );

      const longTitle = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十';
      expect(longTitle.length, 30);
      final labeled = formatRecentSessionLabel(
        const SessionSummary(title: longTitle, archived: true),
        maxTitleLength: 24,
      );
      expect(labeled, '${longTitle.substring(0, 24)}... (已归档)');
    });
  });

  group('buildMenuItems 菜单构建纯函数测试', () {
    test('空会话列表展示 "暂无最近会话" 禁用项', () {
      final items = TrayManagerService.buildMenuItems(sessions: const []);
      expect(items.length, 6);
      expect(items[0].key, TrayManagerService.menuItemShowWindow);
      expect(items[1].key, TrayManagerService.menuItemNewSession);
      // items[2] is separator
      expect(items[3].key, TrayManagerService.menuItemNoRecentSessions);
      expect(items[3].label, '暂无最近会话');
      expect(items[3].disabled, isTrue);
      // items[4] is separator, items[5] is quit
    });

    test('会话列表渲染最近会话项并截取上限', () {
      final sessions = List.generate(
        10,
        (i) => SessionSummary(
          sessionId: 'sess_$i',
          title: '会话 $i',
          messageCount: 5,
        ),
      );

      final items = TrayManagerService.buildMenuItems(
        sessions: sessions,
        maxRecentSessions: 5,
      );

      final recentItems = items
          .where(
            (it) =>
                it.key?.startsWith(TrayManagerService.recentSessionPrefix) ==
                true,
          )
          .toList();

      expect(recentItems.length, 5);
      expect(recentItems[0].key, 'recent_sess_0');
      expect(recentItems[0].label, '会话 0');
      expect(recentItems[4].key, 'recent_sess_4');
      expect(recentItems[4].label, '会话 4');
    });

    test('自动过滤无消息占位会话', () {
      final sessions = [
        const SessionSummary(
          sessionId: 'placeholder',
          title: 'Untitled',
          messageCount: 0,
        ),
        const SessionSummary(
          sessionId: 'real_sess',
          title: '真实会话',
          messageCount: 2,
        ),
      ];

      final items = TrayManagerService.buildMenuItems(sessions: sessions);
      final recentItems = items
          .where(
            (it) =>
                it.key?.startsWith(TrayManagerService.recentSessionPrefix) ==
                true,
          )
          .toList();

      expect(recentItems.length, 1);
      expect(recentItems.first.key, 'recent_real_sess');
      expect(recentItems.first.label, '真实会话');
    });
  });

  group('TrayManagerService 系统托盘逻辑测试', () {
    test('非桌面平台 initialize / updateContextMenu / dispose 安全 no-op', () async {
      final service = TrayManagerService(isDesktop: false);

      await service.initialize();
      expect(service.isInitialized, isFalse);

      await service.updateContextMenu();
      await service.dispose();
    });

    test('handleShowWindow 触发自定义回调', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      await service.handleShowWindow();
      expect(showCalled, isTrue);
    });

    test('handleNewSession 触发自定义回调', () async {
      bool newSessionCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onNewSession: () {
          newSessionCalled = true;
        },
      );

      await service.handleNewSession();
      expect(newSessionCalled, isTrue);
    });

    test('handleOpenSession 触发自定义回调', () async {
      String? openedId;
      final service = TrayManagerService(
        isDesktop: false,
        onOpenSession: (sid) {
          openedId = sid;
        },
      );

      await service.handleOpenSession('target_session_999');
      expect(openedId, 'target_session_999');
    });

    test('handleQuit 触发自定义回调', () async {
      bool quitCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onQuit: () {
          quitCalled = true;
        },
      );

      await service.handleQuit();
      expect(quitCalled, isTrue);
    });

    test('onTrayIconMouseDown 触发 handleShowWindow', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      service.onTrayIconMouseDown();
      await pumpEventQueue();
      expect(showCalled, isTrue);
    });

    test('onTrayMenuItemClick 菜单项分发（包含最近会话分发）', () async {
      bool showCalled = false;
      bool newSessionCalled = false;
      String? openedSessionId;
      bool quitCalled = false;

      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () => showCalled = true,
        onNewSession: () => newSessionCalled = true,
        onOpenSession: (sid) => openedSessionId = sid,
        onQuit: () => quitCalled = true,
      );

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemShowWindow, label: '显示主窗口'),
      );
      await pumpEventQueue();
      expect(showCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemNewSession, label: '新建会话'),
      );
      await pumpEventQueue();
      expect(newSessionCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: 'recent_sess_abc', label: '会话 ABC'),
      );
      await pumpEventQueue();
      expect(openedSessionId, 'sess_abc');

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemQuitApp, label: '退出应用'),
      );
      await pumpEventQueue();
      expect(quitCalled, isTrue);
    });

    test('Provider 注入与释放测试', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(trayManagerServiceProvider);
      expect(service, isNotNull);
    });
  });

  group('prepareTrayIconFile ICO 分支', () {
    test('写入 .ico 资产时保留 ICO 字节与 .ico 后缀', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_ico_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      // 最小合法 ICO 头：保留字 0 + 类型 1 + 数量 1，后续 16 字节目录项
      // 这里仅验证字节透传能力，不要求图像合法
      final icoBytes = Uint8List.fromList([
        0x00, 0x00, // reserved
        0x01, 0x00, // type = 1 (ICO)
        0x01, 0x00, // count = 1
        0x10, 0x10, 0x00, 0x00, 0x01, 0x00, 0x04, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00,
        0x28, 0x00, 0x00, 0x00,
      ]);
      final fakeBundle = _FakeAssetBundle(icoBytes);

      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon.ico',
        fileName: 'hermex_tray_icon.ico',
      );

      expect(iconPath.endsWith('.ico'), isTrue);
      final file = File(iconPath);
      expect(file.existsSync(), isTrue);
      expect(file.absolute.path, iconPath);
      expect(await file.readAsBytes(), icoBytes);
    });

    test('返回路径为绝对路径', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_abs_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final fakeBundle = _FakeAssetBundle(Uint8List.fromList([0x00, 0x01]));
      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon.ico',
        fileName: 'hermex_tray_icon.ico',
      );
      expect(File(iconPath).isAbsolute, isTrue);
    });
  });
}
