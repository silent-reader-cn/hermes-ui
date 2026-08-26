import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// 在 Web 平台使用 driftDatabase 创建临时/Web 缓存数据库。
QueryExecutor openConnectionInMemory() => driftDatabase(
      name: 'hermes_memory',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
