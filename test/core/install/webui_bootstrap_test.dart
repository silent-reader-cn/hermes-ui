
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';

class _FakeFileSystemAdapter implements FileSystemAdapter {
  _FakeFileSystemAdapter({
    this.existingFiles = const {},
  });

  final Set<String> existingDirs = {} ;
  final Set<String> existingFiles;
  @override
  String localAppData = r'C:\Users\Admin\AppData\Local';
  @override
  bool isWindows = true;
  @override
  String executablePath = r'C:\Program Files\Hermes\hermes.exe';

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
