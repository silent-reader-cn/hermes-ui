import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/connections/connection_providers.dart';
import 'download_controller.dart';
import 'download_models.dart';
import 'download_repository.dart';
import 'download_save_service.dart';

/// 下载存储保存服务 Provider。
final downloadSaveServiceProvider = Provider<DownloadSaveService>((ref) {
  return DownloadSaveService();
});

/// 下载记录持久化仓储 Provider。
final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DownloadRepository(db);
});

/// 下载执行器签名：可选 [onProgress] 回调（received, total；total=-1 未知）。
typedef DownloadBytesDownloader = Future<Uint8List> Function(
  Uri url, {
  void Function(int receivedBytes, int totalBytes)? onProgress,
});

/// 下载网络执行器 Provider（默认走激活连接的 ApiClient.downloadData）。
final downloadDownloaderProvider = Provider<DownloadBytesDownloader>((ref) {
  final client = ref.watch(apiClientProvider);
  return (url, {onProgress}) =>
      client.downloadData(url, onReceiveProgress: onProgress);
});

/// 断点续传执行器签名：返回响应状态码、响应头与分片字节流（#98）。
typedef DownloadResumableDownloader = Future<ResumableDownloadResponse> Function(
  Uri url, {
  String? rangeHeader,
});

/// 退避时长计算器签名：根据重试序号（1, 2, 3）返回退避 Duration（#98）。
typedef DownloadBackoffCalculator = Duration Function(int attempt);

/// 生产默认退避时长：2s → 8s → 30s（#98）。
Duration defaultDownloadBackoff(int attempt) {
  switch (attempt) {
    case 1:
      return const Duration(seconds: 2);
    case 2:
      return const Duration(seconds: 8);
    case 3:
      return const Duration(seconds: 30);
    default:
      return const Duration(seconds: 30);
  }
}

/// 退避时长计算 Provider（测试可注入 Duration.zero；#98）。
final downloadBackoffProvider = Provider<DownloadBackoffCalculator>((ref) {
  return defaultDownloadBackoff;
});

/// 临时缓存目录解析器签名（#98）。
typedef DownloadTempDirectoryResolver = Future<Directory> Function();

/// 下载临时缓存目录 Provider（放置 .part 临时文件；#98）。
final downloadTempDirectoryProvider =
    Provider<DownloadTempDirectoryResolver>((ref) {
  return () async {
    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (_) {
      tempDir = Directory.systemTemp;
    }
    final partsDir = Directory('${tempDir.path}/downloads');
    if (!partsDir.existsSync()) {
      await partsDir.create(recursive: true);
    }
    return partsDir;
  };
});

/// 断点续传网络执行器 Provider（#98）。
///
/// 默认走激活连接的 ApiClient.downloadDataResumable；若未配置服务器连接（如纯
/// widget 测试），自动桥接兼容 legacy [downloadDownloaderProvider]。
final downloadResumableDownloaderProvider =
    Provider<DownloadResumableDownloader>((ref) {
  return (url, {rangeHeader}) async {
    try {
      final client = ref.read(apiClientProvider);
      return await client.downloadDataResumable(url, rangeHeader: rangeHeader);
    } catch (_) {
      final legacy = ref.read(downloadDownloaderProvider);
      final bytes = await legacy(url);
      final headers = Headers.fromMap({
        'accept-ranges': ['bytes'],
        'content-length': ['${bytes.length}'],
      });
      return ResumableDownloadResponse(
        statusCode: 200,
        headers: headers,
        stream: Stream.value(bytes),
      );
    }
  };
});

/// 下载状态与队列控制器 Provider。
final downloadControllerProvider =
    NotifierProvider<DownloadController, DownloadState>(DownloadController.new);

/// 全部下载任务列表 Provider。
final downloadTasksProvider = Provider<List<DownloadTask>>((ref) {
  final state = ref.watch(downloadControllerProvider);
  return state.tasks;
});

/// 活跃中（排队中 / 正在下载）任务计数 Provider。
final activeDownloadsCountProvider = Provider<int>((ref) {
  final state = ref.watch(downloadControllerProvider);
  return state.tasks.where((t) => t.isActive).length;
});
