import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'install_detector.dart';

/// WebUI 部署与启动异常。
class WebuiBootstrapException implements Exception {
  const WebuiBootstrapException(this.message);
  final String message;

  @override
  String toString() => 'WebuiBootstrapException: $message';
}

/// 健康检查器抽象（用于测试注入 fake）。
abstract interface class HealthChecker {
  Future<bool> checkHealth(String url);
}

/// 生产环境健康检查器。
class SystemHealthChecker implements HealthChecker {
  const SystemHealthChecker();

  @override
  Future<bool> checkHealth(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['status'] == 'ok') {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

/// WebUI 启动与健康检查器接口。
abstract interface class WebuiBootstrap {
  static const int defaultPort = 8787;

  /// 轮询 /health 接口直至健康检查通过或超时。
  Future<bool> waitForHealth({
    String baseUrl = 'http://127.0.0.1:8787',
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  });

  /// 解析 Python 可执行文件路径。
  String resolvePythonPath();
}

/// [WebuiBootstrap] 默认实现。
class DefaultWebuiBootstrap implements WebuiBootstrap {
  DefaultWebuiBootstrap({
    this.processExecutor = const SystemProcessExecutor(),
    this.fileSystem = const SystemFileSystemAdapter(),
    this.healthChecker = const SystemHealthChecker(),
  });

  final ProcessExecutor processExecutor;
  final FileSystemAdapter fileSystem;
  final HealthChecker healthChecker;

  @override
  String resolvePythonPath() {
    final base = fileSystem.localAppData;
    if (base.isNotEmpty) {
      // 1. 检查 agent 虚拟环境 python
      final venvPython = '$base\\hermes\\hermes-agent\\venv\\Scripts\\python.exe';
      if (fileSystem.fileExists(venvPython)) {
        return venvPython;
      }
      // 2. 检查统一 venv 目录 python
      final altVenvPython = '$base\\hermes\\venv\\Scripts\\python.exe';
      if (fileSystem.fileExists(altVenvPython)) {
        return altVenvPython;
      }
    }
    // 3. 降级到 PATH 中的 python.exe 或 python
    return fileSystem.isWindows ? 'python.exe' : 'python';
  }

  @override
  Future<bool> waitForHealth({
    String baseUrl = 'http://127.0.0.1:8787',
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final healthUrl =
        baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health';
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final ok = await healthChecker.checkHealth(healthUrl);
      if (ok) return true;
      await Future<void>.delayed(interval);
    }
    throw WebuiBootstrapException(
      'WebUI 服务未在 ${timeout.inSeconds} 秒内就绪 (/health 轮询超时)',
    );
  }
}

/// [WebuiBootstrap] Provider。
final webuiBootstrapProvider = Provider<WebuiBootstrap>(
  (ref) => DefaultWebuiBootstrap(),
);
