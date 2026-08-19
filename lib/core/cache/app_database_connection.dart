import 'package:drift/drift.dart';

/// 在未识别平台上打开内存数据库的桩实现。
QueryExecutor openConnectionInMemory() =>
    throw UnsupportedError('Unsupported platform for in-memory database');
