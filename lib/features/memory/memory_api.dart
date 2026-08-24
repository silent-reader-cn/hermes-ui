import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_memory_skills.dart';
import '../../core/models/memory.dart';

/// 记忆查看所需的最小服务器 API 面（memory 域 2 个端点中的 1 个：
/// `GET /api/memory`；写入为后续编辑能力，不在本页范围）。
///
/// 生产实现 [MemoryApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络（对齐 session_list 的
/// `SessionListApi` 模式）。
abstract interface class MemoryApi {
  /// GET /api/memory → 记忆分区内容。
  Future<MemoryResponse> fetchMemory();

  /// POST /api/memory/write {section, content} → 记忆写入响应。
  Future<MemoryWriteResponse> writeMemory({
    required String section,
    required String content,
  });
}

/// [MemoryApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class MemoryApiClient implements MemoryApi {
  MemoryApiClient(this._client);

  final ApiClient _client;

  @override
  Future<MemoryResponse> fetchMemory() async {
    return _client.memory();
  }

  @override
  Future<MemoryWriteResponse> writeMemory({
    required String section,
    required String content,
  }) async {
    return _client.writeMemory(section: section, content: content);
  }
}

/// 构建 [MemoryApi] 的工厂（测试可 override 注入 fake）。
typedef MemoryApiFactory = MemoryApi Function(ApiClient client);

final memoryApiFactoryProvider = Provider<MemoryApiFactory>(
  (ref) => MemoryApiClient.new,
);
