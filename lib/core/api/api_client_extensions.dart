import 'api_client.dart';
import 'endpoints.dart';
import '../models/extensions.dart';

/// Extensions 生态相关 ApiClient 扩展（6 个端点，对应规格 §3.1）。
extension ApiClientExtensions on ApiClient {
  /// GET /api/extensions/status
  Future<ExtensionsStatusResponse> extensionsStatus() async {
    final json = await sendJson(Endpoint.extensionsStatus);
    return ExtensionsStatusResponse.fromJson(_asMap(json));
  }

  /// GET /api/extensions/registry
  Future<ExtensionsRegistryResponse> extensionsRegistry() async {
    final json = await sendJson(Endpoint.extensionsRegistry);
    return ExtensionsRegistryResponse.fromJson(_asMap(json));
  }

  /// POST /api/extensions/toggle {id, enabled}
  Future<ExtensionToggleResponse> toggleExtension(
    String id,
    bool enabled,
  ) async {
    final json = await sendJson(
      Endpoint.extensionToggle,
      method: 'POST',
      body: {'id': id, 'enabled': enabled},
    );
    return ExtensionToggleResponse.fromJson(_asMap(json));
  }

  /// POST /api/extensions/install {id, download_url, sha256}
  Future<ExtensionInstallResponse> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  }) async {
    final json = await sendJson(
      Endpoint.extensionInstall,
      method: 'POST',
      body: {
        'id': id,
        'download_url': downloadUrl,
        'sha256': sha256,
      },
    );
    return ExtensionInstallResponse.fromJson(_asMap(json));
  }

  /// POST /api/extensions/uninstall {id}
  Future<ExtensionUninstallResponse> uninstallExtension(String id) async {
    final json = await sendJson(
      Endpoint.extensionUninstall,
      method: 'POST',
      body: {'id': id},
    );
    return ExtensionUninstallResponse.fromJson(_asMap(json));
  }

  /// POST /api/extensions/sidecar-proxy-consent {id, approved}
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(
    String id,
    bool approved,
  ) async {
    final json = await sendJson(
      Endpoint.extensionSidecarProxyConsent,
      method: 'POST',
      body: {'id': id, 'approved': approved},
    );
    return ExtensionConsentResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
