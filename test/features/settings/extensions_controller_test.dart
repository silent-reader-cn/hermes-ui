import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/extensions.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';

import '../../helpers/fake_settings_api.dart';

ProviderContainer makeContainer(FakeSettingsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      settingsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ExtensionsController 加载状态机', () {
    test('加载成功：解析已安装扩展 + 注册表', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        enabled: true,
        extensions: [
          ExtensionInfo(
            id: 'ext-1',
            name: 'Extension One',
            enabled: true,
            sidecarActive: true,
            sidecarProxyConsent: true,
          ),
          ExtensionInfo(
            id: 'ext-2',
            name: 'Extension Two',
            enabled: false,
          ),
        ],
      );
      api.extensionsRegistryResponse = const ExtensionsRegistryResponse(
        registry: [
          ExtensionRegistryItem(
            id: 'reg-1',
            name: 'Registry Ext',
            version: '1.0.0',
            downloadUrl: 'https://example.com/ext.tar.gz',
            sha256: 'abc123',
          ),
        ],
      );
      final container = makeContainer(api);

      await container.read(extensionsControllerProvider.future);
      final state = container.read(extensionsControllerProvider).valueOrNull!;

      expect(api.extensionsStatusCount, 1);
      expect(api.extensionsRegistryCount, 1);
      expect(state.systemEnabled, isTrue);
      expect(state.extensions, hasLength(2));
      expect(state.extensions.first.id, 'ext-1');
      expect(state.extensions.first.name, 'Extension One');
      expect(state.extensions.first.sidecarActive, isTrue);
      expect(state.registry, hasLength(1));
      expect(state.registry.first.id, 'reg-1');
    });

    test('registry 加载失败 → 不阻断整体加载，registry 设为空', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        enabled: true,
        extensions: [
          ExtensionInfo(id: 'ext-1', name: 'Extension 1'),
        ],
      );
      api.extensionsRegistryError = HttpException(404, null, message: 'Not found');
      final container = makeContainer(api);

      await container.read(extensionsControllerProvider.future);
      final state = container.read(extensionsControllerProvider).valueOrNull!;

      expect(api.extensionsStatusCount, 1);
      expect(state.extensions, hasLength(1));
      expect(state.registry, isEmpty);
      expect(state.actionError, isNull);
    });

    test('extensionsStatus 加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(extensionsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(extensionsControllerProvider).hasError, isTrue);

      api.extensionsStatusError = null;
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        enabled: true,
        extensions: [ExtensionInfo(id: 'ext-1', name: 'Ext 1')],
      );
      await container.read(extensionsControllerProvider.notifier).refresh();

      final state = container.read(extensionsControllerProvider).valueOrNull!;
      expect(state.extensions, hasLength(1));
    });
  });

  group('ExtensionsController 操作方法', () {
    test('toggleExtension 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        extensions: [ExtensionInfo(id: 'ext-1', enabled: false)],
      );
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);

      final controller = container.read(extensionsControllerProvider.notifier);
      final ok = await controller.toggleExtension('ext-1', true);

      expect(ok, isTrue);
      expect(api.toggleExtensionCalls, [('ext-1', true)]);
      expect(api.extensionsStatusCount, 2);
    });

    test('toggleExtension 失败：设置 actionError', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        extensions: [ExtensionInfo(id: 'ext-1', enabled: false)],
      );
      api.toggleExtensionError = HttpException(500, null, message: '切换失败');
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);

      final controller = container.read(extensionsControllerProvider.notifier);
      final ok = await controller.toggleExtension('ext-1', true);

      expect(ok, isFalse);
      var state = container.read(extensionsControllerProvider).valueOrNull!;
      expect(state.actionError, contains('切换失败'));

      await controller.clearActionError();
      state = container.read(extensionsControllerProvider).valueOrNull!;
      expect(state.actionError, isNull);
    });

    test('installExtension 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);

      final controller = container.read(extensionsControllerProvider.notifier);
      final ok = await controller.installExtension(
        id: 'new-ext',
        downloadUrl: 'https://example.com/ext.zip',
        sha256: 'hash123',
      );

      expect(ok, isTrue);
      expect(api.installExtensionCalls, [
        (id: 'new-ext', downloadUrl: 'https://example.com/ext.zip', sha256: 'hash123'),
      ]);
      expect(api.extensionsStatusCount, 2);
    });

    test('uninstallExtension 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        extensions: [ExtensionInfo(id: 'ext-1')],
      );
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);

      final controller = container.read(extensionsControllerProvider.notifier);
      final ok = await controller.uninstallExtension('ext-1');

      expect(ok, isTrue);
      expect(api.uninstallExtensionCalls, ['ext-1']);
      expect(api.extensionsStatusCount, 2);
    });

    test('setSidecarConsent 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      api.extensionsStatusResponse = const ExtensionsStatusResponse(
        extensions: [ExtensionInfo(id: 'ext-1', sidecarProxyConsent: false)],
      );
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);

      final controller = container.read(extensionsControllerProvider.notifier);
      final ok = await controller.setSidecarConsent('ext-1', true);

      expect(ok, isTrue);
      expect(api.setSidecarConsentCalls, [('ext-1', true)]);
      expect(api.extensionsStatusCount, 2);
    });

    test('切换服务器（apiClientProvider 重建）→ extensions 自动重载', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(extensionsControllerProvider.future);
      expect(api.extensionsStatusCount, 1);

      container.invalidate(apiClientProvider);
      await container.pump();
      await container.read(extensionsControllerProvider.future);
      expect(api.extensionsStatusCount, 2);
    });
  });
}
