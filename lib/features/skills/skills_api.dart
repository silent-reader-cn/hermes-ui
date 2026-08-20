import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_memory_skills.dart';
import '../../core/models/skills.dart';

/// 技能浏览所需的最小服务器 API 面（skills 域 3 个端点中的 1 个：
/// `GET /api/skills`；详情为本地元数据展开，无需额外请求）。
///
/// 生产实现 [SkillsApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络（对齐 session_list 的
/// `SessionListApi` 模式）。
abstract interface class SkillsApi {
  /// GET /api/skills → 技能列表。
  Future<SkillsResponse> fetchSkills();
}

/// [SkillsApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class SkillsApiClient implements SkillsApi {
  SkillsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<SkillsResponse> fetchSkills() async {
    return _client.skills();
  }
}

/// 构建 [SkillsApi] 的工厂（测试可 override 注入 fake）。
typedef SkillsApiFactory = SkillsApi Function(ApiClient client);

final skillsApiFactoryProvider = Provider<SkillsApiFactory>(
  (ref) => SkillsApiClient.new,
);
