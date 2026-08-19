import 'api_client.dart';
import 'endpoints.dart';
import '../models/insights.dart';
import '../models/server_catalog.dart';

/// models/commands/设置/更新（1.9，9 个端点）+ profiles（1.10，5 个）+
/// insights（1.11，1 个）。
extension ApiClientServerPanels on ApiClient {
  // -------------------------------------------------------------------------
  // models（1.9）
  // -------------------------------------------------------------------------

  /// GET /api/models（缓存目录）。
  Future<ModelsResponse> models() async {
    final json = await sendJson(Endpoint.models);
    return ModelsResponse.fromJson(_asMap(json));
  }

  /// GET /api/models/live（实时未缓存，服务端回显 provider）。
  Future<ModelsLiveResponse> modelsLive() async {
    final json = await sendJson(Endpoint.modelsLive);
    return ModelsLiveResponse.fromJson(_asMap(json));
  }

  /// GET /api/commands。
  Future<CommandsResponse> commands() async {
    final json = await sendJson(Endpoint.commands);
    return CommandsResponse.fromJson(_asMap(json));
  }

  /// POST /api/default-model {model}。
  Future<DefaultModelResponse> saveDefaultModel(String model) async {
    final json = await sendJson(
      Endpoint.defaultModel,
      method: 'POST',
      body: {'model': model},
    );
    return DefaultModelResponse.fromJson(_asMap(json));
  }

  /// GET /api/reasoning（model/provider 非空才发 query）。
  Future<ReasoningStatusResponse> reasoning({
    String? model,
    String? provider,
  }) async {
    final json = await sendJson(
      Endpoint.reasoning(model: model, provider: provider),
    );
    return ReasoningStatusResponse.fromJson(_asMap(json));
  }

  /// POST /api/reasoning {effort}。
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort) async {
    final json = await sendJson(
      Endpoint.reasoning(),
      method: 'POST',
      body: {'effort': effort},
    );
    return ReasoningStatusResponse.fromJson(_asMap(json));
  }

  /// POST /api/reasoning {display}。
  Future<ReasoningStatusResponse> saveReasoningDisplay(String display) async {
    final json = await sendJson(
      Endpoint.reasoning(),
      method: 'POST',
      body: {'display': display},
    );
    return ReasoningStatusResponse.fromJson(_asMap(json));
  }

  /// GET /api/providers。
  Future<ProvidersResponse> providers() async {
    final json = await sendJson(Endpoint.providers);
    return ProvidersResponse.fromJson(_asMap(json));
  }

  /// GET /api/settings。
  Future<SettingsResponse> settings() async {
    final json = await sendJson(Endpoint.settings);
    return SettingsResponse.fromJson(_asMap(json));
  }

  /// POST /api/settings {show_cli_sessions}（服务端按发送的键合并）。
  Future<SettingsResponse> updateSettingsShowCliSessions(bool value) async {
    final json = await sendJson(
      Endpoint.settings,
      method: 'POST',
      body: {'show_cli_sessions': value},
    );
    return SettingsResponse.fromJson(_asMap(json));
  }

  /// POST /api/settings {show_claude_code_sessions}。
  Future<SettingsResponse> updateSettingsShowClaudeCodeSessions(
    bool value,
  ) async {
    final json = await sendJson(
      Endpoint.settings,
      method: 'POST',
      body: {'show_claude_code_sessions': value},
    );
    return SettingsResponse.fromJson(_asMap(json));
  }

  /// GET /api/updates/check（缓存状态）。
  Future<UpdatesCheckResponse> updatesCheck() async {
    final json = await sendJson(Endpoint.updatesCheck);
    return UpdatesCheckResponse.fromJson(_asMap(json));
  }

  /// POST /api/updates/check {force: true}（触发真实 git fetch）。
  Future<UpdatesCheckResponse> updatesCheckForced() async {
    final json = await sendJson(
      Endpoint.updatesCheck,
      method: 'POST',
      body: {'force': true},
    );
    return UpdatesCheckResponse.fromJson(_asMap(json));
  }

  /// POST /api/updates/apply {target: "webui"}（默认 webui，无 agent/force/
  /// summary）；**服务端会重启**，调用方需容忍短暂断连并事后重轮询。
  Future<UpdatesApplyResponse> applyUpdate({String target = 'webui'}) async {
    final json = await sendJson(
      Endpoint.updatesApply,
      method: 'POST',
      body: {'target': target},
    );
    return UpdatesApplyResponse.fromJson(_asMap(json));
  }

  // -------------------------------------------------------------------------
  // profiles（1.10）
  // -------------------------------------------------------------------------

  /// GET /api/personalities。
  Future<PersonalitiesResponse> personalities() async {
    final json = await sendJson(Endpoint.personalities);
    return PersonalitiesResponse.fromJson(_asMap(json));
  }

  /// POST /api/personality/set {session_id, name}。
  Future<PersonalitySetResponse> setPersonality({
    required String sessionId,
    required String name,
  }) async {
    final json = await sendJson(
      Endpoint.setPersonality,
      method: 'POST',
      body: {'session_id': sessionId, 'name': name},
    );
    return PersonalitySetResponse.fromJson(_asMap(json));
  }

  /// GET /api/profiles。
  Future<ProfilesResponse> profiles() async {
    final json = await sendJson(Endpoint.profiles);
    return ProfilesResponse.fromJson(_asMap(json));
  }

  /// POST /api/profile/switch {name}。
  Future<ProfileSwitchResponse> switchProfile(String name) async {
    final json = await sendJson(
      Endpoint.switchProfile,
      method: 'POST',
      body: {'name': name},
    );
    return ProfileSwitchResponse.fromJson(_asMap(json));
  }

  /// POST /api/profile/create — `clone_config` 总是发；`clone_from` 故意不发
  /// （=从当前 profile 克隆）；单 profile 模式 403。
  Future<ProfileCreateResponse> createProfile({
    required String name,
    bool cloneConfig = false,
    String? defaultModel,
    String? modelProvider,
    String? baseUrl,
    String? apiKey,
  }) async {
    final json = await sendJson(
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
    return ProfileCreateResponse.fromJson(_asMap(json));
  }

  // -------------------------------------------------------------------------
  // insights（1.11）
  // -------------------------------------------------------------------------

  /// GET /api/insights?days=。
  Future<InsightsResponse> insights(int days) async {
    final json = await sendJson(Endpoint.insights(days));
    return InsightsResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
