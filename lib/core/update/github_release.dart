import 'package:flutter/foundation.dart';

/// GitHub Release 单个文件资产模型。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    this.size = 0,
  });

  /// 资产文件名（例如 `hermes-ui-setup.exe`、`app-release.apk`）。
  final String name;

  /// 下载链接。
  final String browserDownloadUrl;

  /// 文件大小（字节）。
  final int size;

  /// 手写容错 fromJson。
  factory ReleaseAsset.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ReleaseAsset(name: '', browserDownloadUrl: '', size: 0);
    }

    final rawName = json['name'];
    final rawUrl = json['browser_download_url'];
    final rawSize = json['size'];

    final name = rawName is String ? rawName : '';
    final url = rawUrl is String ? rawUrl : '';
    final size = rawSize is int
        ? rawSize
        : (rawSize is num ? rawSize.toInt() : (int.tryParse('$rawSize') ?? 0));

    return ReleaseAsset(
      name: name,
      browserDownloadUrl: url,
      size: size,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'browser_download_url': browserDownloadUrl,
        'size': size,
      };
}

/// GitHub Release 模型。
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.htmlUrl,
    required this.name,
    this.body = '',
    this.publishedAt,
    this.assets = const [],
  });

  /// 标签名（例如 `v0.1.30`）。
  final String tagName;

  /// Release 网页链接。
  final String htmlUrl;

  /// 发布标题。
  final String name;

  /// 发布日志说明。
  final String body;

  /// 发布时间。
  final DateTime? publishedAt;

  /// 资产列表。
  final List<ReleaseAsset> assets;

  /// 手写容错 fromJson。
  factory GithubRelease.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GithubRelease(
        tagName: '',
        htmlUrl: '',
        name: '',
        body: '',
        assets: [],
      );
    }

    final tagName =
        json['tag_name'] is String ? json['tag_name'] as String : '';
    final htmlUrl =
        json['html_url'] is String ? json['html_url'] as String : '';
    final name = json['name'] is String ? json['name'] as String : '';
    final body = json['body'] is String ? json['body'] as String : '';

    DateTime? publishedAt;
    final rawPublishedAt = json['published_at'];
    if (rawPublishedAt is String && rawPublishedAt.isNotEmpty) {
      publishedAt = DateTime.tryParse(rawPublishedAt);
    }

    final assetsList = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) {
          assetsList.add(ReleaseAsset.fromJson(item));
        } else if (item is Map) {
          assetsList.add(ReleaseAsset.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    return GithubRelease(
      tagName: tagName,
      htmlUrl: htmlUrl,
      name: name,
      body: body,
      publishedAt: publishedAt,
      assets: assetsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag_name': tagName,
        'html_url': htmlUrl,
        'name': name,
        'body': body,
        'published_at': publishedAt?.toIso8601String(),
        'assets': assets.map((a) => a.toJson()).toList(),
      };
}

/// 在 Release assets 中按平台寻找适用的安装包资产。
///
/// - Android: 寻找 `*.apk`（优先匹配 `app-release.apk`）
/// - Windows: 寻找 `*-setup.exe`（或包含 `setup` 的 `.exe`，或任意 `.exe`）
/// - 其他平台: 返回 null（调用方退化为打开 Release 页）
ReleaseAsset? findPlatformAsset(
  GithubRelease release, {
  TargetPlatform? platform,
}) {
  final p = platform ?? defaultTargetPlatform;
  if (p == TargetPlatform.android) {
    for (final asset in release.assets) {
      final n = asset.name.toLowerCase();
      if (n.endsWith('.apk') && n.contains('app-release')) {
        return asset;
      }
    }
    for (final asset in release.assets) {
      if (asset.name.toLowerCase().endsWith('.apk')) {
        return asset;
      }
    }
    return null;
  } else if (p == TargetPlatform.windows) {
    for (final asset in release.assets) {
      final n = asset.name.toLowerCase();
      if (n.endsWith('-setup.exe') ||
          (n.endsWith('.exe') && n.contains('setup'))) {
        return asset;
      }
    }
    for (final asset in release.assets) {
      if (asset.name.toLowerCase().endsWith('.exe')) {
        return asset;
      }
    }
    return null;
  }
  return null;
}
