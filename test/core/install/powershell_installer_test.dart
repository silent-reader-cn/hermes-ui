import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';

class _FakeProcess implements Process {
  _FakeProcess({
    required List<String> stdoutLines,
    List<String> stderrLines = const [],
    this.exitCodeValue = 0,
  })  : _stdoutController = StreamController<List<int>>(),
        _stderrController = StreamController<List<int>>() {
    unawaited(Future.microtask(() async {
      for (final line in stdoutLines) {
        _stdoutController.add(utf8.encode('$line\n'));
      }
      await _stdoutController.close();
      for (final line in stderrLines) {
        _stderrController.add(utf8.encode('$line\n'));
      }
      await _stderrController.close();
    }));
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final int exitCodeValue;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode async => exitCodeValue;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 4321;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor({
    this.runExitCode = 0,
    this.runStdout = '',
    this.processToReturn,
    this.throwOnStart = false,
  });

  int runExitCode;
  String runStdout;
  Process? processToReturn;
  bool throwOnStart;
  final List<List<String>> executedArgs = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    executedArgs.add([executable, ...arguments]);
    return ProcessResult(1234, runExitCode, runStdout, '');
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
    executedArgs.add([executable, ...arguments]);
    if (throwOnStart) throw const ProcessException('powershell', [], 'Process start failed');
    return processToReturn ??
        _FakeProcess(stdoutLines: ['{"ok": true, "stage": "test"}']);
  }
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    this.existingFiles = const {},
  });

  final Set<String> existingFiles;
  final Map<String, String> fileContents = {};
  @override
  String localAppData = r'C:\Users\Admin\AppData\Local';
  @override
  bool isWindows = true;

  @override
  bool directoryExists(String path) => false;

  @override
  bool fileExists(String path) => existingFiles.contains(path);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  Future<String> readString(String path) async => fileContents[path] ?? '';

  @override
  Future<void> writeString(String path, String content) async {
    existingFiles.add(path);
    fileContents[path] = content;
  }
}

class _FakeScriptDownloader implements ScriptDownloader {
  _FakeScriptDownloader({this.contentToReturn = '# mock install.ps1', this.throwError = false});

  String contentToReturn;
  bool throwError;

  @override
  Future<String> downloadScript(String url) async {
    if (throwError) throw const HttpException('Network unreachable');
    return contentToReturn;
  }
}

void main() {
  group('InstallerEvent.parseLine', () {
    test('解析 manifest 帧', () {
      const line = '{"event": "manifest", "stages": ["prereqs", "agent", "deps"]}';
      final event = InstallerEvent.parseLine(line);
      expect(event.type, InstallerEventType.manifest);
      expect(event.stages, ['prereqs', 'agent', 'deps']);
    });

    test('解析 stage_start / start 帧', () {
      const line = '{"event": "stage_start", "stage": "prereqs", "title": "环境检查"}';
      final event = InstallerEvent.parseLine(line);
      expect(event.type, InstallerEventType.stageStart);
      expect(event.stage, 'prereqs');
      expect(event.title, '环境检查');
    });

    test('解析 progress 进度帧 (百分比 0-100 及 0.0-1.0 归一化)', () {
      const line1 = '{"event": "progress", "stage": "clone", "percent": 50, "message": "Downloading"}';
      final event1 = InstallerEvent.parseLine(line1);
      expect(event1.type, InstallerEventType.progress);
      expect(event1.progress, 0.5);
      expect(event1.message, 'Downloading');

      const line2 = '{"event": "progress", "stage": "clone", "progress": 0.8}';
      final event2 = InstallerEvent.parseLine(line2);
      expect(event2.type, InstallerEventType.progress);
      expect(event2.progress, 0.8);
    });

    test('解析 stage_success 及 {ok: true} 帧', () {
      const line1 = '{"event": "stage_success", "stage": "agent"}';
      final event1 = InstallerEvent.parseLine(line1);
      expect(event1.type, InstallerEventType.stageSuccess);
      expect(event1.stage, 'agent');

      const line2 = '{"ok": true, "stage": "deps"}';
      final event2 = InstallerEvent.parseLine(line2);
      expect(event2.type, InstallerEventType.stageSuccess);
      expect(event2.stage, 'deps');
    });

    test('解析 stage_failure 及 {ok: false, stage, reason} 错误帧', () {
      const line1 = '{"ok": false, "stage": "deps", "reason": "Failed to install wheel"}';
      final event1 = InstallerEvent.parseLine(line1);
      expect(event1.type, InstallerEventType.stageFailure);
      expect(event1.stage, 'deps');
      expect(event1.reason, 'Failed to install wheel');

      const line2 = '{"event": "stage_failure", "stage": "agent", "message": "Git clone timed out"}';
      final event2 = InstallerEvent.parseLine(line2);
      expect(event2.type, InstallerEventType.stageFailure);
      expect(event2.stage, 'agent');
      expect(event2.reason, 'Git clone timed out');
    });

    test('非 JSON 字符串 / 异常行 → 优雅降级为 log 事件', () {
      const line = 'Cloning into C:\\Users\\Admin\\AppData\\Local\\hermes\\agent...';
      final event = InstallerEvent.parseLine(line);
      expect(event.type, InstallerEventType.log);
      expect(event.message, line);
    });

    test('空行 → 降级为 log 事件 (空 message)', () {
      final event = InstallerEvent.parseLine('   ');
      expect(event.type, InstallerEventType.log);
      expect(event.message, '');
    });
  });

  group('DefaultPowershellInstaller', () {
    test('ensureScriptCached：文件已存在时不重复下载', () async {
      final fs = _FakeFileSystemAdapter(
        existingFiles: {r'C:\Users\Admin\AppData\Local\hermes\install.ps1'},
      );
      final downloader = _FakeScriptDownloader();
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: downloader,
      );

      final path = await installer.ensureScriptCached();
      expect(path, r'C:\Users\Admin\AppData\Local\hermes\install.ps1');
      expect(fs.fileContents, isEmpty); // 未写新文件
    });

    test('ensureScriptCached：文件不存在时自动下载并落盘', () async {
      final fs = _FakeFileSystemAdapter(existingFiles: {});
      final downloader = _FakeScriptDownloader(contentToReturn: '# custom script');
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: downloader,
      );

      final path = await installer.ensureScriptCached();
      expect(path, r'C:\Users\Admin\AppData\Local\hermes\install.ps1');
      expect(fs.fileExists(path), isTrue);
      expect(fs.fileContents[path], '# custom script');
    });

    test('ensureScriptCached：下载失败抛出带指引信息的 Exception', () async {
      final fs = _FakeFileSystemAdapter(existingFiles: {});
      final downloader = _FakeScriptDownloader(throwError: true);
      final installer = DefaultPowershellInstaller(
        fileSystem: fs,
        downloader: downloader,
      );

      expect(
        () => installer.ensureScriptCached(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('下载官方 install.ps1 失败'),
        )),
      );
    });

    test('getManifest：正常解析 -Manifest 输出的阶段列表', () async {
      final proc = _FakeProcessExecutor(
        runExitCode: 0,
        runStdout: '{"event": "manifest", "stages": ["prereqs", "agent", "deps", "webui"]}',
      );
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final stages = await installer.getManifest();
      expect(stages, ['prereqs', 'agent', 'deps', 'webui']);
    });

    test('getManifest：异常时降级返回默认 stages', () async {
      final proc = _FakeProcessExecutor(runExitCode: 1, runStdout: 'error');
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final stages = await installer.getManifest();
      expect(stages, ['prereqs', 'agent', 'deps']);
    });

    test('runStage：流式产生事件帧并正常完成', () async {
      final fakeProc = _FakeProcess(
        stdoutLines: [
          '{"event": "progress", "stage": "prereqs", "percent": 50}',
          'Checking python version...',
          '{"ok": true, "stage": "prereqs"}',
        ],
        exitCodeValue: 0,
      );
      final proc = _FakeProcessExecutor(processToReturn: fakeProc);
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final events = await installer.runStage('prereqs').toList();

      expect(events.first.type, InstallerEventType.stageStart);
      expect(events.any((e) => e.type == InstallerEventType.progress), isTrue);
      expect(events.any((e) => e.type == InstallerEventType.log && e.message == 'Checking python version...'), isTrue);
      expect(events.last.type, InstallerEventType.stageSuccess);
    });

    test('runStage：进程异常退出时产生 stageFailure 事件', () async {
      final fakeProc = _FakeProcess(
        stdoutLines: ['Starting check...'],
        exitCodeValue: 1,
      );
      final proc = _FakeProcessExecutor(processToReturn: fakeProc);
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final events = await installer.runStage('prereqs').toList();

      final failure = events.firstWhere((e) => e.type == InstallerEventType.stageFailure);
      expect(failure.reason, contains('退出码: 1'));
    });

    test('runStage：启动进程抛出异常时返回 stageFailure 事件', () async {
      final proc = _FakeProcessExecutor(throwOnStart: true);
      final installer = DefaultPowershellInstaller(processExecutor: proc);

      final events = await installer.runStage('prereqs').toList();

      final failure = events.firstWhere((e) => e.type == InstallerEventType.stageFailure);
      expect(failure.reason, contains('无法启动 PowerShell 进程'));
    });
  });
}
