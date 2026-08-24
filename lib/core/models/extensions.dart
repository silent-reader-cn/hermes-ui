import '../utils/equality.dart';
import '../utils/lossy_json.dart';

/// 单个扩展信息（Extensions 生态）。
class ExtensionInfo {
  const ExtensionInfo({
    this.id = '',
    this.name = '',
    this.enabled = false,
    this.sidecarActive = false,
    this.sidecarProxyConsent = false,
  });

  factory ExtensionInfo.fromJson(Map<String, Object?> json) {
    final id = lossyString(json, 'id') ?? '';
    final name = lossyString(json, 'name');
    return ExtensionInfo(
      id: id,
      name: (name != null && name.isNotEmpty) ? name : id,
      enabled: lossyBool(json, 'enabled') ?? false,
      sidecarActive: lossyBool(json, 'sidecar_active') ??
          lossyBool(json, 'sidecarActive') ??
          false,
      sidecarProxyConsent: lossyBool(json, 'sidecar_proxy_consent') ??
          lossyBool(json, 'sidecarProxyConsent') ??
          false,
    );
  }

  final String id;
  final String name;
  final bool enabled;
  final bool sidecarActive;
  final bool sidecarProxyConsent;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'sidecar_active': sidecarActive,
        'sidecar_proxy_consent': sidecarProxyConsent,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionInfo &&
        other.id == id &&
        other.name == name &&
        other.enabled == enabled &&
        other.sidecarActive == sidecarActive &&
        other.sidecarProxyConsent == sidecarProxyConsent;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        enabled,
        sidecarActive,
        sidecarProxyConsent,
      );

  @override
  String toString() =>
      'ExtensionInfo(id: $id, name: $name, enabled: $enabled, sidecarActive: $sidecarActive, sidecarProxyConsent: $sidecarProxyConsent)';
}

/// 扩展状态列表响应（GET /api/extensions/status）。
class ExtensionsStatusResponse {
  const ExtensionsStatusResponse({
    this.enabled = false,
    this.extensions = const [],
  });

  factory ExtensionsStatusResponse.fromJson(Map<String, Object?> json) {
    final rawList = json['extensions'];
    final extensions = <ExtensionInfo>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          extensions.add(
            ExtensionInfo.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    return ExtensionsStatusResponse(
      enabled: lossyBool(json, 'enabled') ?? false,
      extensions: extensions,
    );
  }

  final bool enabled;
  final List<ExtensionInfo> extensions;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'extensions': extensions.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is ExtensionsStatusResponse &&
      other.enabled == enabled &&
      deepEquals(other.extensions, extensions);

  @override
  int get hashCode => Object.hash(enabled, deepHash(extensions));

  @override
  String toString() =>
      'ExtensionsStatusResponse(enabled: $enabled, extensions: ${extensions.length})';
}

/// 注册表中的单个扩展项。
class ExtensionRegistryItem {
  const ExtensionRegistryItem({
    this.id = '',
    this.name = '',
    this.version = '',
    this.downloadUrl = '',
    this.sha256 = '',
  });

  factory ExtensionRegistryItem.fromJson(Map<String, Object?> json) {
    return ExtensionRegistryItem(
      id: lossyString(json, 'id') ?? '',
      name: lossyString(json, 'name') ?? '',
      version: lossyString(json, 'version') ?? '',
      downloadUrl: lossyString(json, 'download_url') ??
          lossyString(json, 'downloadUrl') ??
          '',
      sha256: lossyString(json, 'sha256') ?? '',
    );
  }

  final String id;
  final String name;
  final String version;
  final String downloadUrl;
  final String sha256;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'download_url': downloadUrl,
        'sha256': sha256,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionRegistryItem &&
        other.id == id &&
        other.name == name &&
        other.version == version &&
        other.downloadUrl == downloadUrl &&
        other.sha256 == sha256;
  }

  @override
  int get hashCode => Object.hash(id, name, version, downloadUrl, sha256);

  @override
  String toString() =>
      'ExtensionRegistryItem(id: $id, name: $name, version: $version)';
}

/// 扩展注册表响应（GET /api/extensions/registry）。
class ExtensionsRegistryResponse {
  const ExtensionsRegistryResponse({
    this.registry = const [],
  });

  factory ExtensionsRegistryResponse.fromJson(Map<String, Object?> json) {
    final rawList = json['registry'];
    final registry = <ExtensionRegistryItem>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          registry.add(
            ExtensionRegistryItem.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    return ExtensionsRegistryResponse(registry: registry);
  }

  final List<ExtensionRegistryItem> registry;

  Map<String, Object?> toJson() => {
        'registry': registry.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is ExtensionsRegistryResponse &&
      deepEquals(other.registry, registry);

  @override
  int get hashCode => Object.hashAll([deepHash(registry)]);

  @override
  String toString() =>
      'ExtensionsRegistryResponse(registry: ${registry.length})';
}

/// 扩展启停切换响应（POST /api/extensions/toggle）。
class ExtensionToggleResponse {
  const ExtensionToggleResponse({
    this.ok = false,
    this.id = '',
    this.enabled = false,
  });

  factory ExtensionToggleResponse.fromJson(Map<String, Object?> json) {
    return ExtensionToggleResponse(
      ok: lossyBool(json, 'ok') ?? false,
      id: lossyString(json, 'id') ?? '',
      enabled: lossyBool(json, 'enabled') ?? false,
    );
  }

  final bool ok;
  final String id;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'id': id,
        'enabled': enabled,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionToggleResponse &&
        other.ok == ok &&
        other.id == id &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(ok, id, enabled);

  @override
  String toString() =>
      'ExtensionToggleResponse(ok: $ok, id: $id, enabled: $enabled)';
}

/// 扩展安装响应（POST /api/extensions/install）。
class ExtensionInstallResponse {
  const ExtensionInstallResponse({
    this.ok = false,
    this.installed = '',
  });

  factory ExtensionInstallResponse.fromJson(Map<String, Object?> json) {
    return ExtensionInstallResponse(
      ok: lossyBool(json, 'ok') ?? false,
      installed: lossyString(json, 'installed') ?? lossyString(json, 'id') ?? '',
    );
  }

  final bool ok;
  final String installed;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'installed': installed,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionInstallResponse &&
        other.ok == ok &&
        other.installed == installed;
  }

  @override
  int get hashCode => Object.hash(ok, installed);

  @override
  String toString() =>
      'ExtensionInstallResponse(ok: $ok, installed: $installed)';
}

/// 扩展卸载响应（POST /api/extensions/uninstall）。
class ExtensionUninstallResponse {
  const ExtensionUninstallResponse({
    this.ok = false,
    this.uninstalled = '',
  });

  factory ExtensionUninstallResponse.fromJson(Map<String, Object?> json) {
    return ExtensionUninstallResponse(
      ok: lossyBool(json, 'ok') ?? false,
      uninstalled:
          lossyString(json, 'uninstalled') ?? lossyString(json, 'id') ?? '',
    );
  }

  final bool ok;
  final String uninstalled;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'uninstalled': uninstalled,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionUninstallResponse &&
        other.ok == ok &&
        other.uninstalled == uninstalled;
  }

  @override
  int get hashCode => Object.hash(ok, uninstalled);

  @override
  String toString() =>
      'ExtensionUninstallResponse(ok: $ok, uninstalled: $uninstalled)';
}

/// 扩展 Sidecar 代理授权响应（POST /api/extensions/sidecar-proxy-consent）。
class ExtensionConsentResponse {
  const ExtensionConsentResponse({
    this.ok = false,
    this.id = '',
    this.sidecarProxyConsent = false,
  });

  factory ExtensionConsentResponse.fromJson(Map<String, Object?> json) {
    return ExtensionConsentResponse(
      ok: lossyBool(json, 'ok') ?? false,
      id: lossyString(json, 'id') ?? '',
      sidecarProxyConsent: lossyBool(json, 'sidecar_proxy_consent') ??
          lossyBool(json, 'sidecarProxyConsent') ??
          false,
    );
  }

  final bool ok;
  final String id;
  final bool sidecarProxyConsent;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'id': id,
        'sidecar_proxy_consent': sidecarProxyConsent,
      };

  @override
  bool operator ==(Object other) {
    return other is ExtensionConsentResponse &&
        other.ok == ok &&
        other.id == id &&
        other.sidecarProxyConsent == sidecarProxyConsent;
  }

  @override
  int get hashCode => Object.hash(ok, id, sidecarProxyConsent);

  @override
  String toString() =>
      'ExtensionConsentResponse(ok: $ok, id: $id, sidecarProxyConsent: $sidecarProxyConsent)';
}
