import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';

class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor({
    this.runExitCode = 0,
    this.runStderr = '',
  });

  int runExitCode;
  String runStderr;
  final List<List<String>> runCalls = [];
  final List<List<String>> startCalls = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    runCalls.add([executable, ...arguments]);
    return ProcessResult(1234, runExitCode, '', runStderr);
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    startCalls.add([executable, ...arguments]);
    return _MockProcess();
  }
}

class _MockProcess implements Process {
  @override
  Future<int> get exitCode async => 0;
  @override
  int get pid => 5678;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    this.existingDirs = const {},
    this.existingFiles = const {},
  });

  final Set<String> existingDirs;
  final Set<String> existingFiles;
  @override
  String localAppData = r'C:\Users\Admin\AppData\Local';
  @override
  bool isWindows = true;

  @override
  bool directoryExists(String path) => existingDirs.contains(path);

  @override
  bool fileExists(String path) => existingFiles.contains(path);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    existingDirs.add(path);
  }

  @override
  Future<String> readString(String path) async => '';

  @override
  Future<void> writeString(String path, String content) async {
    existingFiles.add(path);
  }
}

class _FakeHealthChecker implements HealthChecker {
  _FakeHealthChecker({this.healthyAfterAttempts = 1});

  int healthyAfterAttempts;
  int checkCalls = 0;

  @override
  Future<bool> checkHealth(String url) async {
    checkCalls++;
    return checkCalls >= healthyAfterAttempts;
  }
}

void main() {
  group('DefaultWebuiBootstrap', () {
    test('cloneOrPull：全新目录执行 git clone', () async {
      final fs = _FakeFileSystemAdapter(existingDirs: {});
      final proc = _FakeProcessExecutor(runExitCode: 0);
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      final events = await bootstrap.cloneOrPull(
        webuiPath: r'C:\Users\Admin\AppData\Local\hermes\webui',
      ).toList();

      expect(proc.runCalls.first, [
        'git',
        'clone',
        '--depth=1',
        WebuiBootstrap.upstreamRepoUrl,
        r'C:\Users\Admin\AppData\Local\hermes\webui',
      ]);
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('cloneOrPull：已有 .git 目录执行 git pull', () async {
      final fs = _FakeFileSystemAdapter(
        existingDirs: {r'C:\Users\Admin\AppData\Local\hermes\webui\.git'},
      );
      final proc = _FakeProcessExecutor(runExitCode: 0);
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      final events = await bootstrap.cloneOrPull(
        webuiPath: r'C:\Users\Admin\AppData\Local\hermes\webui',
      ).toList();

      expect(proc.runCalls.first, ['git', 'pull']);
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('cloneOrPull：git 命令失败返回 stageFailure', () async {
      final fs = _FakeFileSystemAdapter(existingDirs: {});
      final proc = _FakeProcessExecutor(runExitCode: 128, runStderr: 'Fatal: repo not found');
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      final events = await bootstrap.cloneOrPull().toList();
      final failure = events.firstWhere((e) => e.type == InstallerEventType.stageFailure);
      expect(failure.reason, contains('Git 操作失败'));
    });

    test('installDependencies：requirements.txt 存在时执行 pip install', () async {
      final fs = _FakeFileSystemAdapter(
        existingFiles: {r'C:\Users\Admin\AppData\Local\hermes\webui\requirements.txt'},
      );
      final proc = _FakeProcessExecutor(runExitCode: 0);
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      final events = await bootstrap.installDependencies(
        pythonPath: 'python.exe',
        webuiPath: r'C:\Users\Admin\AppData\Local\hermes\webui',
      ).toList();

      expect(proc.runCalls.first, [
        'python.exe',
        '-m',
        'pip',
        'install',
        '-r',
        'requirements.txt',
      ]);
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('installDependencies：requirements.txt 不存在时优雅跳过', () async {
      final fs = _FakeFileSystemAdapter(existingFiles: {});
      final proc = _FakeProcessExecutor(runExitCode: 0);
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      final events = await bootstrap.installDependencies().toList();
      expect(proc.runCalls, isEmpty);
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('startServer：以 detached 模式启动 server.py 进程', () async {
      final fs = _FakeFileSystemAdapter(
        existingFiles: {r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\pythonw.exe'},
      );
      final proc = _FakeProcessExecutor();
      final bootstrap = DefaultWebuiBootstrap(
        fileSystem: fs,
        processExecutor: proc,
      );

      await bootstrap.startServer(
        webuiPath: r'C:\Users\Admin\AppData\Local\hermes\webui',
        pythonPath: r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe',
        port: 8787,
      );

      expect(proc.startCalls.first, [
        r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\pythonw.exe',
        'server.py',
        '--port',
        '8787',
      ]);
    });

    test('waitForHealth：健康检查通过返回 true', () async {
      final checker = _FakeHealthChecker(healthyAfterAttempts: 2);
      final bootstrap = DefaultWebuiBootstrap(healthChecker: checker);

      final ok = await bootstrap.waitForHealth(
        baseUrl: 'http://127.0.0.1:8787',
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(seconds: 1),
      );

      expect(ok, isTrue);
      expect(checker.checkCalls, 2);
    });

    test('waitForHealth：超时抛出 WebuiBootstrapException', () async {
      final checker = _FakeHealthChecker(healthyAfterAttempts: 9999);
      final bootstrap = DefaultWebuiBootstrap(healthChecker: checker);

      expect(
        () => bootstrap.waitForHealth(
          baseUrl: 'http://127.0.0.1:8787',
          interval: const Duration(milliseconds: 10),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<WebuiBootstrapException>()),
      );
    });

    test('resolvePythonPath：优先识别 agent 虚拟环境 python', () {
      final fs = _FakeFileSystemAdapter(
        existingFiles: {
          r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe',
        },
      );
      final bootstrap = DefaultWebuiBootstrap(fileSystem: fs);

      final py = bootstrap.resolvePythonPath();
      expect(py, r'C:\Users\Admin\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe');
    });
  });
}
