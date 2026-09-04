import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';

class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor({this.exitCode = 0, this.stdout = '', this.throwError = false});

  int exitCode;
  String stdout;
  bool throwError;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    if (throwError) throw const SocketException('Command not found');
    return ProcessResult(1234, exitCode, stdout, '');
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    throw UnimplementedError();
  }
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    this.existingDirs = const {},
    this.existingFiles = const {},
    this.localAppData = r'C:\Users\Admin\AppData\Local',
    this.isWindows = true,
    this.executablePath = r'C:\Program Files\Hermes\hermes.exe',
  });

  Set<String> existingDirs;
  Set<String> existingFiles;
  final Set<String> _files = {};
  @override
  String localAppData;
  @override
  bool isWindows;
  @override
  String executablePath;

  @override
  bool directoryExists(String path) => existingDirs.contains(path);

  @override
  bool fileExists(String path) =>
      existingFiles.contains(path) || _files.contains(path);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    existingDirs.add(path);
  }

  @override
  Future<String> readString(String path) async => '';

  @override
  Future<void> writeString(String path, String content) async {
    _files.add(path);
  }
}

void main() {
  group('DefaultInstallDetector', () {
    test('路径生成：基于 localAppData 正确拼装 hermesHomePath/hermesAgentPath/webuiPath', () {
      final fs = _FakeFileSystemAdapter(
        localAppData: r'C:\Users\Tester\AppData\Local',
        isWindows: true,
      );
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: _FakeProcessExecutor(),
      );

      expect(detector.localAppDataPath, r'C:\Users\Tester\AppData\Local');
      expect(detector.hermesHomePath, r'C:\Users\Tester\AppData\Local\hermes');
      expect(
        detector.hermesAgentPath,
        r'C:\Users\Tester\AppData\Local\hermes\hermes-agent',
      );
      expect(
        detector.webuiPath,
        r'C:\Users\Tester\AppData\Local\hermes\webui',
      );
    });

    test('检测：hermes-agent 目录存在 → 判定为已安装 (true)', () async {
      final fs = _FakeFileSystemAdapter(
        existingDirs: {r'C:\Users\Admin\AppData\Local\hermes\hermes-agent'},
      );
      final proc = _FakeProcessExecutor(exitCode: 1, stdout: '');
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: proc,
      );

      final installed = await detector.isInstalled();
      expect(installed, isTrue);
    });

    test('检测：hermes-agent 目录不存在但 where.exe hermes 存在 → 判定为已安装 (true)', () async {
      final fs = _FakeFileSystemAdapter(existingDirs: {});
      final proc = _FakeProcessExecutor(
        exitCode: 0,
        stdout: r'C:\Users\Admin\.hermes\bin\hermes.cmd',
      );
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: proc,
      );

      final installed = await detector.isInstalled();
      expect(installed, isTrue);
    });

    test('检测：目录不存在且命令不存在 → 判定为未安装 (false)', () async {
      final fs = _FakeFileSystemAdapter(existingDirs: {});
      final proc = _FakeProcessExecutor(exitCode: 1, stdout: '');
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: proc,
      );

      final installed = await detector.isInstalled();
      expect(installed, isFalse);
    });

    test('检测：执行命令异常 → 优雅降级返回 false', () async {
      final fs = _FakeFileSystemAdapter(existingDirs: {});
      final proc = _FakeProcessExecutor(throwError: true);
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: proc,
      );

      final installed = await detector.isInstalled();
      expect(installed, isFalse);
    });

    test('agentInstalled 与 isInstalled 语义一致', () async {
      final fs = _FakeFileSystemAdapter(
        existingDirs: {r'C:\Users\Admin\AppData\Local\hermes\hermes-agent'},
      );
      final detector = DefaultInstallDetector(
        fileSystem: fs,
        processExecutor: _FakeProcessExecutor(),
      );

      expect(await detector.agentInstalled(), isTrue);
      expect(await detector.isInstalled(), isTrue);
    });

    test('bundledWebuiAvailable：Windows 且 server.py 存在 → 返回 true', () {
      final fs = _FakeFileSystemAdapter(
        isWindows: true,
        executablePath: r'C:\Program Files\Hermes\hermes.exe',
        existingFiles: {
          r'C:\Program Files\Hermes\webui\server\server.py',
        },
      );
      final detector = DefaultInstallDetector(fileSystem: fs);

      expect(detector.bundledWebuiAvailable(), isTrue);
    });

    test('bundledWebuiAvailable：Windows 但 server.py 不存在 → 返回 false', () {
      final fs = _FakeFileSystemAdapter(
        isWindows: true,
        executablePath: r'C:\Program Files\Hermes\hermes.exe',
        existingFiles: {},
      );
      final detector = DefaultInstallDetector(fileSystem: fs);

      expect(detector.bundledWebuiAvailable(), isFalse);
    });

    test('bundledWebuiAvailable：非 Windows 平台 → 恒返回 false', () {
      final fs = _FakeFileSystemAdapter(
        isWindows: false,
        executablePath: r'/opt/hermes/hermes',
        existingFiles: {
          r'/opt/hermes/webui/server/server.py',
        },
      );
      final detector = DefaultInstallDetector(fileSystem: fs);

      expect(detector.bundledWebuiAvailable(), isFalse);
    });
  });
}
