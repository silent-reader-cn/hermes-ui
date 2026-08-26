import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/extensions.dart';

void main() {
  group('ExtensionInfo', () {
    test('正常解析全量字段', () {
      final ext = ExtensionInfo.fromJson({
        'id': 'hermes-sidebar',
        'name': 'Sidebar Extension',
        'enabled': true,
        'sidecar_active': true,
        'sidecar_proxy_consent': true,
      });
      expect(ext.id, 'hermes-sidebar');
      expect(ext.name, 'Sidebar Extension');
      expect(ext.enabled, isTrue);
      expect(ext.sidecarActive, isTrue);
      expect(ext.sidecarProxyConsent, isTrue);

      final json = ext.toJson();
      expect(json['id'], 'hermes-sidebar');
      expect(json['name'], 'Sidebar Extension');
      expect(json['enabled'], isTrue);
      expect(json['sidecar_active'], isTrue);
      expect(json['sidecar_proxy_consent'], isTrue);
    });

    test('name 缺失时回退到 id', () {
      final ext = ExtensionInfo.fromJson({'id': 'auto-fallback'});
      expect(ext.id, 'auto-fallback');
      expect(ext.name, 'auto-fallback');
      expect(ext.enabled, isFalse);
      expect(ext.sidecarActive, isFalse);
      expect(ext.sidecarProxyConsent, isFalse);
    });

    test('支持 camelCase 变体与 lossy 转换', () {
      final ext = ExtensionInfo.fromJson({
        'id': 12345,
        'name': '',
        'enabled': 'true',
        'sidecarActive': '1',
        'sidecarProxyConsent': 'yes',
      });
      expect(ext.id, '12345');
      expect(ext.name, '12345');
      expect(ext.enabled, isTrue);
      expect(ext.sidecarActive, isTrue);
      expect(ext.sidecarProxyConsent, isTrue);
    });

    test('畸形输入与空值容错', () {
      const ext = ExtensionInfo();
      expect(ext.id, '');
      expect(ext.name, '');
      expect(ext.enabled, isFalse);

      final fromBad = ExtensionInfo.fromJson({
        'id': null,
        'name': null,
        'enabled': 'invalid_bool',
        'sidecar_active': 99,
        'sidecar_proxy_consent': null,
      });
      expect(fromBad.id, '');
      expect(fromBad.name, '');
      expect(fromBad.enabled, isFalse);
      expect(fromBad.sidecarActive, isFalse);
      expect(fromBad.sidecarProxyConsent, isFalse);
    });

    test('== / hashCode / toString', () {
      const a = ExtensionInfo(id: 'a', name: 'A', enabled: true);
      const b = ExtensionInfo(id: 'a', name: 'A', enabled: true);
      const c = ExtensionInfo(id: 'c', name: 'C', enabled: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('ExtensionInfo'));
    });
  });

  group('ExtensionsStatusResponse', () {
    test('正常解析与 toJson', () {
      final res = ExtensionsStatusResponse.fromJson({
        'enabled': true,
        'extensions': [
          {
            'id': 'ext-1',
            'name': 'Ext 1',
            'enabled': true,
            'sidecar_active': false,
            'sidecar_proxy_consent': false,
          },
        ],
      });
      expect(res.enabled, isTrue);
      expect(res.extensions.length, 1);
      expect(res.extensions.first.id, 'ext-1');

      final json = res.toJson();
      expect(json['enabled'], isTrue);
      expect((json['extensions'] as List).length, 1);
    });

    test('extensions 非 List 或含非 Map 元素容错', () {
      final resBadList = ExtensionsStatusResponse.fromJson({
        'enabled': 'yes',
        'extensions': 'not_a_list',
      });
      expect(resBadList.enabled, isTrue);
      expect(resBadList.extensions, isEmpty);

      final resDirtyList = ExtensionsStatusResponse.fromJson({
        'extensions': [
          {'id': 'valid-1'},
          'string_item',
          123,
          null,
        ],
      });
      expect(resDirtyList.extensions.length, 1);
      expect(resDirtyList.extensions.first.id, 'valid-1');
    });

    test('== / hashCode / toString', () {
      const a = ExtensionsStatusResponse(
        enabled: true,
        extensions: [ExtensionInfo(id: '1')],
      );
      const b = ExtensionsStatusResponse(
        enabled: true,
        extensions: [ExtensionInfo(id: '1')],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ExtensionsStatusResponse'));
    });
  });

  group('ExtensionRegistryItem & ExtensionsRegistryResponse', () {
    test('正常解析与 camelCase 兼容', () {
      final item = ExtensionRegistryItem.fromJson({
        'id': 'git-tool',
        'name': 'Git Tool',
        'version': '1.2.0',
        'download_url': 'https://example.com/git.tar.gz',
        'sha256': 'abcdef123456',
      });
      expect(item.id, 'git-tool');
      expect(item.name, 'Git Tool');
      expect(item.version, '1.2.0');
      expect(item.downloadUrl, 'https://example.com/git.tar.gz');
      expect(item.sha256, 'abcdef123456');

      final itemCamel = ExtensionRegistryItem.fromJson({
        'downloadUrl': 'https://example.com/camel.tar.gz',
      });
      expect(itemCamel.downloadUrl, 'https://example.com/camel.tar.gz');
    });

    test('registry 响应解析与容错', () {
      final res = ExtensionsRegistryResponse.fromJson({
        'registry': [
          {
            'id': 'pkg1',
            'name': 'Pkg 1',
            'version': '0.1.0',
            'download_url': 'http://pkg.com',
            'sha256': '123',
          },
        ],
      });
      expect(res.registry.length, 1);
      expect(res.registry.first.id, 'pkg1');

      final badRes = ExtensionsRegistryResponse.fromJson({
        'registry': 123,
      });
      expect(badRes.registry, isEmpty);
    });

    test('== / hashCode / toString', () {
      const itemA = ExtensionRegistryItem(id: 'x', name: 'X');
      const itemB = ExtensionRegistryItem(id: 'x', name: 'X');
      expect(itemA, equals(itemB));
      expect(itemA.hashCode, equals(itemB.hashCode));
      expect(itemA.toString(), contains('ExtensionRegistryItem'));

      const resA = ExtensionsRegistryResponse(registry: [itemA]);
      const resB = ExtensionsRegistryResponse(registry: [itemB]);
      expect(resA, equals(resB));
      expect(resA.hashCode, equals(resB.hashCode));
      expect(resA.toString(), contains('ExtensionsRegistryResponse'));
    });
  });

  group('写操作响应模型', () {
    test('ExtensionToggleResponse', () {
      final res = ExtensionToggleResponse.fromJson({
        'ok': true,
        'id': 'ext-1',
        'enabled': true,
      });
      expect(res.ok, isTrue);
      expect(res.id, 'ext-1');
      expect(res.enabled, isTrue);

      final lossy = ExtensionToggleResponse.fromJson({
        'ok': '1',
        'id': 999,
        'enabled': 'false',
      });
      expect(lossy.ok, isTrue);
      expect(lossy.id, '999');
      expect(lossy.enabled, isFalse);

      const a = ExtensionToggleResponse(ok: true, id: 'a', enabled: true);
      const b = ExtensionToggleResponse(ok: true, id: 'a', enabled: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ExtensionToggleResponse'));
    });

    test('ExtensionInstallResponse', () {
      final res = ExtensionInstallResponse.fromJson({
        'ok': true,
        'installed': 'ext-new',
      });
      expect(res.ok, isTrue);
      expect(res.installed, 'ext-new');

      // fallback to id
      final resFallback = ExtensionInstallResponse.fromJson({
        'ok': true,
        'id': 'ext-fallback',
      });
      expect(resFallback.installed, 'ext-fallback');

      const a = ExtensionInstallResponse(ok: true, installed: 'x');
      const b = ExtensionInstallResponse(ok: true, installed: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ExtensionInstallResponse'));
    });

    test('ExtensionUninstallResponse', () {
      final res = ExtensionUninstallResponse.fromJson({
        'ok': true,
        'uninstalled': 'ext-old',
      });
      expect(res.ok, isTrue);
      expect(res.uninstalled, 'ext-old');

      // fallback to id
      final resFallback = ExtensionUninstallResponse.fromJson({
        'ok': true,
        'id': 'ext-id',
      });
      expect(resFallback.uninstalled, 'ext-id');

      const a = ExtensionUninstallResponse(ok: true, uninstalled: 'x');
      const b = ExtensionUninstallResponse(ok: true, uninstalled: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ExtensionUninstallResponse'));
    });

    test('ExtensionConsentResponse', () {
      final res = ExtensionConsentResponse.fromJson({
        'ok': true,
        'id': 'ext-sidecar',
        'sidecar_proxy_consent': true,
      });
      expect(res.ok, isTrue);
      expect(res.id, 'ext-sidecar');
      expect(res.sidecarProxyConsent, isTrue);

      final resCamel = ExtensionConsentResponse.fromJson({
        'ok': 'yes',
        'id': 'ext-sidecar',
        'sidecarProxyConsent': 'true',
      });
      expect(resCamel.ok, isTrue);
      expect(resCamel.sidecarProxyConsent, isTrue);

      const a = ExtensionConsentResponse(
        ok: true,
        id: 's',
        sidecarProxyConsent: true,
      );
      const b = ExtensionConsentResponse(
        ok: true,
        id: 's',
        sidecarProxyConsent: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ExtensionConsentResponse'));
    });
  });
}
