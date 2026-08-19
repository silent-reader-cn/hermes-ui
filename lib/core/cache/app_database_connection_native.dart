import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// 在 Native 平台使用 NativeDatabase.memory() 创建内存数据库。
QueryExecutor openConnectionInMemory() => NativeDatabase.memory();
