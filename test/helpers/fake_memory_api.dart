import 'dart:async';

import 'package:hermex_flutter/core/models/memory.dart';
import 'package:hermex_flutter/features/memory/memory_api.dart';

/// 可配置的 [MemoryApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空 [MemoryResponse]；测试可按需配置 [response] / [fetchError] /
/// [fetchGate]，并通过 [fetchCount] 断言调用次数。
class FakeMemoryApi implements MemoryApi {
  FakeMemoryApi({this.response = const MemoryResponse()});

  /// `fetchMemory` 返回的响应。
  MemoryResponse response;

  /// `fetchMemory` 抛出的异常（非 null 时优先于 [response]）。
  Object? fetchError;

  /// 非 null 时 `fetchMemory` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// `fetchMemory` 调用次数。
  int fetchCount = 0;

  @override
  Future<MemoryResponse> fetchMemory() async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return response;
  }
}
