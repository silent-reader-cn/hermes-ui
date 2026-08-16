import 'api_client.dart';
import 'endpoints.dart';

/// models/commands/设置/更新（1.9，9 个端点）+ profiles（1.10，5 个）+
/// insights（1.11，1 个）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientServerPanels on ApiClient {
  // -------------------------------------------------------------------------
  // models（1.9）
  // -------------------------------------------------------------------------

  /// GET /api/models（缓存目录）。
  Future<Object?> models() => sendJson(Endpoint.models);

  /// GET /api/models/live（实时未缓存，服务端回显 provider）。
  Future<Object?> modelsLive() => sendJson(Endpoint.modelsLive);

  /// GET /api/commands。
  Future<Object?> commands() => sendJson(Endpoint.commands);

  /// POST /api/default-model {model}。
  Future<Object?> saveDefaultModel(String model) =>
      sendJson(Endpoint.defaultModel, method: 'POST', body: {'model': model});

  /// GET /api/reasoning（model/provider 非空才发 query）。
  Future<Object?> reasoning({String? model, String? provider}) =>
      sendJson(Endpoint.reasoning(model: model, provider: provider));

  /// POST /api/reasoning {effort}。
  Future<Object?> saveReasoningEffort(String effort) =>
      sendJson(Endpoint.reasoning(), method: 'POST', body: {'effort': effort});

  /// POST /api/reasoning {display}。
  Future<Object?> saveReasoningDisplay(String display) => sendJson(
    Endpoint.reasoning(),
    method: 'POST',
    body: {'display': display},
  );

  /// GET /api/providers。
  Future<Object?> providers() => sendJson(Endpoint.providers);

  /// GET /api/settings。
  Future<Object?> settings() => sendJson(Endpoint.settings);

  /// POST /api/settings {show_cli_sessions}（服务端按发送的键合并）。
  Future<Object?> updateSettingsShowCliSessions(bool value) => sendJson(
    Endpoint.settings,
    method: 'POST',
    body: {'show_cli_sessions': value},
  );

  /// POST /api/settings {show_claude_code_sessions}。
  Future<Object?> updateSettingsShowClaudeCodeSessions(bool value) => sendJson(
    Endpoint.settings,
    method: 'POST',
    body: {'show_claude_code_sessions': value},
  );

  /// GET /api/updates/check（缓存状态）。
  Future<Object?> updatesCheck() => sendJson(Endpoint.updatesCheck);

  /// POST /api/updates/check {force: true}（触发真实 git fetch）。
  Future<Object?> updatesCheckForced() =>
      sendJson(Endpoint.updatesCheck, method: 'POST', body: {'force': true});

  /// POST /api/updates/apply {target: "webui"}（默认 webui，无 agent/force/
  /// summary）；**服务端会重启**，调用方需容忍短暂断连并事后重轮询。
  Future<Object?> applyUpdate({String target = 'webui'}) =>
      sendJson(Endpoint.updatesApply, method: 'POST', body: {'target': target});

  // -------------------------------------------------------------------------
  // profiles（1.10）
  // -------------------------------------------------------------------------

  /// GET /api/personalities。
  Future<Object?> personalities() => sendJson(Endpoint.personalities);

  /// POST /api/personality/set {session_id, name}。
  Future<Object?> setPersonality({
    required String sessionId,
    required String name,
  }) => sendJson(
    Endpoint.setPersonality,
    method: 'POST',
    body: {'session_id': sessionId, 'name': name},
  );

  /// GET /api/profiles。
  Future<Object?> profiles() => sendJson(Endpoint.profiles);

  /// POST /api/profile/switch {name}。
  Future<Object?> switchProfile(String name) =>
      sendJson(Endpoint.switchProfile, method: 'POST', body: {'name': name});

  /// POST /api/profile/create — `clone_config` 总是发；`clone_from` 故意不发
  /// （=从当前 profile 克隆）；单 profile 模式 403。
  Future<Object?> createProfile({
    required String name,
    bool cloneConfig = false,
    String? defaultModel,
    String? modelProvider,
    String? baseUrl,
    String? apiKey,
  }) => sendJson(
    Endpoint.createProfile,
    method: 'POST',
    body: {
      'name': name,
      'clone_config': cloneConfig,
      'default_model': ?defaultModel,
      'model_provider': ?modelProvider,
      'base_url': ?baseUrl,
      'api_key': ?apiKey,
    },
  );

  // -------------------------------------------------------------------------
  // insights（1.11）
  // -------------------------------------------------------------------------

  /// GET /api/insights?days=。
  Future<Object?> insights(int days) => sendJson(Endpoint.insights(days));
}
