import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'install_detector.dart';
import 'powershell_installer.dart';

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

/// WebUI 部署与启动器接口。
abstract interface class WebuiBootstrap {
  static const String upstreamRepoUrl =
      'https://github.com/nesquena/hermes-webui.git';
  static const int defaultPort = 8787;

  /// 克隆或拉取 WebUI 仓库代码。
  Stream<InstallerEvent> cloneOrPull({
    String? repoUrl,
    String? webuiPath,
  });

  /// 安装 WebUI 运行依赖（requirements.txt）。
  Stream<InstallerEvent> installDependencies({
    String? webuiPath,
    String? pythonPath,
  });

  /// 启动 WebUI 后台服务进程（pythonw + DETACHED_PROCESS）。
  Future<void> startServer({
    String? webuiPath,
    String? pythonPath,
    int port = defaultPort,
    String? logFilePath,
  });

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

  String get _defaultWebuiPath {
    final base = fileSystem.localAppData;
    if (base.isEmpty) return 'webui';
    return '$base\\hermes\\webui';
  }

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
  Stream<InstallerEvent> cloneOrPull({
    String? repoUrl,
    String? webuiPath,
  }) {
    final controller = StreamController<InstallerEvent>();
    final targetPath = webuiPath ?? _defaultWebuiPath;
    final targetRepo = repoUrl ?? WebuiBootstrap.upstreamRepoUrl;

    controller.add(InstallerEvent.stageStart(
      'webui_clone',
      title: '部署 WebUI 仓库',
      message: '正在拉取官方 WebUI ($targetRepo)...',
    ));

    unawaited(() async {
      final gitDir = '$targetPath\\.git';
      final isExisting = fileSystem.directoryExists(gitDir);

      try {
        ProcessResult res;
        if (isExisting) {
          controller.add(InstallerEvent.log(
            '检测到已有 WebUI 仓库，正在更新代码 (git pull)...',
            stage: 'webui_clone',
          ));
          res = await processExecutor.run(
            'git',
            ['pull'],
            workingDirectory: targetPath,
          );
        } else {
          // 确保目标路径的父目录存在
          final lastSlash = targetPath.lastIndexOf(Platform.pathSeparator);
          if (lastSlash > 0) {
            final parent = targetPath.substring(0, lastSlash);
            await fileSystem.createDirectory(parent);
          }
          controller.add(InstallerEvent.log(
            '正在克隆官方仓库 nesquena/hermes-webui 到 $targetPath...',
            stage: 'webui_clone',
          ));
          res = await processExecutor.run('git', [
            'clone',
            '--depth=1',
            targetRepo,
            targetPath,
          ]);
        }

        if (res.exitCode != 0) {
          controller.add(InstallerEvent.stageFailure(
            'webui_clone',
            'Git 操作失败 (code ${res.exitCode}): ${res.stderr}',
          ));
        } else {
          controller.add(InstallerEvent.stageSuccess(
            'webui_clone',
            message: 'WebUI 源码部署成功',
          ));
        }
      } catch (e) {
        controller.add(InstallerEvent.stageFailure(
          'webui_clone',
          '执行 git 命令异常: $e',
        ));
      } finally {
        await controller.close();
      }
    }());

    return controller.stream;
  }

  @override
  Stream<InstallerEvent> installDependencies({
    String? webuiPath,
    String? pythonPath,
  }) {
    final controller = StreamController<InstallerEvent>();
    final targetPath = webuiPath ?? _defaultWebuiPath;
    final py = pythonPath ?? resolvePythonPath();

    controller.add(InstallerEvent.stageStart(
      'webui_deps',
      title: '安装 WebUI 依赖',
      message: '正在安装 WebUI 运行环境依赖 (pip install -r requirements.txt)...',
    ));

    unawaited(() async {
      try {
        final reqFile = '$targetPath\\requirements.txt';
        if (!fileSystem.fileExists(reqFile)) {
          controller.add(InstallerEvent.log(
            '未找到 requirements.txt，跳过依赖安装',
            stage: 'webui_deps',
          ));
          controller.add(InstallerEvent.stageSuccess(
            'webui_deps',
            message: '跳过 requirements.txt',
          ));
          await controller.close();
          return;
        }

        controller.add(InstallerEvent.log(
          '运行: $py -m pip install -r requirements.txt',
          stage: 'webui_deps',
        ));

        final res = await processExecutor.run(
          py,
          ['-m', 'pip', 'install', '-r', 'requirements.txt'],
          workingDirectory: targetPath,
        );

        if (res.exitCode != 0) {
          controller.add(InstallerEvent.stageFailure(
            'webui_deps',
            'pip install 失败 (code ${res.exitCode}): ${res.stderr}',
          ));
        } else {
          controller.add(InstallerEvent.stageSuccess(
            'webui_deps',
            message: 'WebUI 依赖安装成功',
          ));
        }
      } catch (e) {
        controller.add(InstallerEvent.stageFailure(
          'webui_deps',
          '执行 pip 命令异常: $e',
        ));
      } finally {
        await controller.close();
      }
    }());

    return controller.stream;
  }

  @override
  Future<void> startServer({
    String? webuiPath,
    String? pythonPath,
    int port = WebuiBootstrap.defaultPort,
    String? logFilePath,
  }) async {
    final targetPath = webuiPath ?? _defaultWebuiPath;
    var py = pythonPath ?? resolvePythonPath();

    // 在 Windows 下优先使用 pythonw 以无黑窗口后台常驻启动
    if (fileSystem.isWindows && py.endsWith('python.exe')) {
      final pythonw = py.replaceAll('python.exe', 'pythonw.exe');
      if (fileSystem.fileExists(pythonw)) {
        py = pythonw;
      }
    }

    final args = <String>['server.py', '--port', port.toString()];

    try {
      await processExecutor.start(
        py,
        args,
        workingDirectory: targetPath,
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      throw WebuiBootstrapException('启动 WebUI server.py 进程失败: $e');
    }
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
