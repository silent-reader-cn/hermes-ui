import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/model_favorite.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';

void main() {
  group('Chat 流控制 / 后台任务 / 命令', () {
    test('ChatStartResponse / ChatCancelResponse / ChatStreamStatusResponse', () {
      final start = ChatStartResponse.fromJson(
        {'stream_id': 's_9', 'session_id': 'abc123'},
      );
      expect(start.streamId, 's_9');
      expect(start.sessionId, 'abc123');
      expect(ChatStartResponse.fromJson(const {}).streamId, isNull);

      final cancel = ChatCancelResponse.fromJson(
        {'ok': true, 'cancelled': true, 'stream_id': 's_9', 'error': null},
      );
      expect(cancel.cancelled, true);
      expect(ChatCancelResponse.fromJson({'ok': 'yes'}).ok, true);

      final status = ChatStreamStatusResponse.fromJson({
        'active': true,
        'stream_id': 's_9',
        'replay_available': false,
        'journal': {'terminal': true, 'terminal_state': 'completed'},
      });
      expect(status.active, true);
      expect(status.journal!.terminalState, 'completed');
      expect(ChatStreamStatusResponse.fromJson({'journal': 'bad'}).journal, isNull);
    });

    test('ChatSteerResponse / BtwStartResponse / Background 家族', () {
      final steer = ChatSteerResponse.fromJson(
        {'accepted': true, 'fallback': null, 'stream_id': 's_9', 'error': null},
      );
      expect(steer.accepted, true);
      expect(ChatSteerResponse.fromJson({'accepted': 'no'}).accepted, false);

      final btw = BtwStartResponse.fromJson({
        'stream_id': 's_10',
        'session_id': 'abc124',
        'parent_session_id': 'abc123',
      });
      expect(btw.parentSessionId, 'abc123');

      final background = BackgroundStartResponse.fromJson(
        {'task_id': 't_1', 'stream_id': 's_11', 'session_id': 'abc125'},
      );
      expect(background.taskId, 't_1');

      final results = BackgroundStatusResponse.fromJson({
        'results': [
          {'task_id': 't_1', 'prompt': '…', 'answer': '…', 'completed_at': 1723700000.0},
        ],
      });
      expect(results.results!.single.completedAt, 1723700000.0);
      expect(
        BackgroundStatusResponse.fromJson({'results': 'bad'}).results,
        isNull,
      );
    });

    test('CommandsResponse / AgentCommand', () {
      final response = CommandsResponse.fromJson({
        'commands': [
          {
            'name': 'skill',
            'description': '…',
            'category': 'skills',
            'aliases': ['/s'],
            'args_hint': '<name>',
            'subcommands': ['list'],
            'cli_only': false,
            'gateway_only': false,
          },
        ],
      });
      final command = response.commands!.single;
      expect(command.name, 'skill');
      expect(command.aliases, ['/s']);
      expect(command.argsHint, '<name>');
      expect(command.id, 'skill');
      final broken = AgentCommand.fromJson({
        'name': 1,
        'aliases': 'bad',
        'cli_only': 'yes',
      });
      expect(broken.name, '1');
      expect(broken.aliases, isNull);
      expect(broken.cliOnly, true);
    });
  });

  group('Providers / Models', () {
    test('ProviderSummary 规格示例正常解析', () {
      final provider = ProviderSummary.fromJson({
        'id': 'openai',
        'display_name': 'OpenAI',
        'has_key': true,
        'configurable': true,
        'is_self_hosted': false,
        'base_url': null,
        'is_plugin_provider': false,
        'is_oauth': false,
        'is_custom': false,
        'key_source': 'env_file',
        'auth_error': null,
        'models': [
          {'id': 'gpt-4o', 'label': 'GPT-4o'},
        ],
        'models_total': 12,
      });
      expect(provider.id, 'openai');
      expect(provider.displayName, 'OpenAI');
      expect(provider.hasKey, true);
      expect(provider.models!.single.id, 'gpt-4o');
      expect(provider.modelsTotal, 12);

      final response = ProvidersResponse.fromJson({
        'providers': [{'id': 'openai'}],
        'active_provider': 'openai',
      });
      expect(response.activeProvider, 'openai');
    });

    test('ProviderModel 裸字符串 + 畸形', () {
      final bare = ProviderModel.fromJson('gpt-4o');
      expect(bare.id, 'gpt-4o');
      expect(bare.label, 'gpt-4o');
      expect(ProviderModel.fromJson(42).id, isNull);
      expect(
        ProviderSummary.fromJson({'models': 'bad'}).models,
        isNull,
      );
    });

    test('DefaultModelResponse / ModelsLiveResponse', () {
      final defaultModel = DefaultModelResponse.fromJson(
        {'ok': true, 'model': 'gpt-4o'},
      );
      expect(defaultModel.model, 'gpt-4o');

      final live = ModelsLiveResponse.fromJson({
        'provider': 'openai',
        'models': [
          {'id': 'gpt-4o', 'label': 'GPT-4o'},
        ],
        'count': 12,
      });
      expect(live.count, 12);
      expect(live.liveOptions, hasLength(1));
      expect(live.liveOptions.single.id, 'gpt-4o');
      expect(live.liveOptions.single.displayName, 'GPT-4o');
      expect(ModelsLiveResponse.fromJson({'count': 'many'}).count, isNull);
    });

    test('ModelsResponse 正常 + catalogGroups 解析', () {
      final response = ModelsResponse.fromJson({
        'groups': [
          {
            'provider_id': 'openai',
            'name': 'OpenAI',
            'models': [
              {'id': 'gpt-4o', 'name': 'GPT-4o', 'provider_id': 'openai'},
            ],
            'extra_models': [],
          },
        ],
        'models': [],
        'default_model': 'gpt-4o',
        'active_provider': 'openai',
      });
      expect(response.defaultModel, 'gpt-4o');
      expect(response.activeProvider, 'openai');
      final groups = response.catalogGroups;
      expect(groups, hasLength(1));
      expect(groups.single.id, 'openai');
      expect(groups.single.name, 'OpenAI');
      expect(groups.single.models.single.id, 'gpt-4o');
      expect(groups.single.models.single.displayName, 'GPT-4o');
      expect(groups.single.models.single.favoriteKey,
          const ModelFavoriteKey(modelID: 'gpt-4o', providerID: 'openai'));
      expect(ModelsResponse.fromJson(const {}).groups, isNull);
    });

    test('ModelsRefreshResponse 正常解析 + equality', () {
      final res1 = ModelsRefreshResponse.fromJson({'ok': true, 'provider': 'custom:cpa'});
      final res2 = ModelsRefreshResponse.fromJson({'ok': true, 'provider': 'custom:cpa'});
      expect(res1.ok, true);
      expect(res1.provider, 'custom:cpa');
      expect(res1, equals(res2));
      expect(res1.hashCode, equals(res2.hashCode));
      expect(res1.toString(), contains('ModelsRefreshResponse(ok: true, provider: custom:cpa)'));

      final empty = ModelsRefreshResponse.fromJson(const {});
      expect(empty.ok, false);
      expect(empty.provider, isNull);
    });
  });

  group('设置 / 更新 / 推理 / 人格 / 档案', () {
    test('SettingsResponse（附录 A.4）', () {
      final response = SettingsResponse.fromJson({
        'bot_name': 'Hermes',
        'webui_version': '1.2.3',
        'agent_version': '0.9.0',
        'theme': 'dark',
        'check_for_updates': true,
        'show_cli_sessions': false,
        'show_claude_code_sessions': true,
        'max_tokens': 8192,
        'max_tokens_effective': 4096,
        'auth_enabled': true,
        'password_auth_enabled': true,
        'passkeys_enabled': false,
        'passwordless_enabled': false,
      });
      expect(response.botName, 'Hermes');
      expect(response.maxTokens, 8192);
      expect(response.passwordAuthEnabled, true);
      expect(SettingsResponse.fromJson(const {}).theme, isNull);
    });

    test('UpdatesCheckResponse / UpdateTargetInfo / UpdatesApplyResponse', () {
      final check = UpdatesCheckResponse.fromJson({
        'webui': {
          'name': 'hermes-webui',
          'behind': 3,
          'current_sha': 'a',
          'latest_sha': 'b',
          'branch': 'main',
          'repo_url': 'https://github.com/nesquena/hermes-webui',
          'compare_url': '…',
          'error': null,
          'stale_check': false,
        },
        'agent': null,
        'checked_at': 1723700000.0,
        'disabled': false,
      });
      expect(check.webui!.behind, 3);
      expect(check.webui!.repoUrl, 'https://github.com/nesquena/hermes-webui');
      expect(check.agent, isNull);
      expect(check.checkedAt, 1723700000.0);

      final apply = UpdatesApplyResponse.fromJson({
        'ok': true,
        'message': '重启中',
        'target': 'webui',
        'conflict': false,
        'diverged': false,
        'restart_blocked': false,
        'restart_scheduled': true,
        'stash_conflict': false,
        'active_streams': 0,
        'active_runs': 0,
      });
      expect(apply.outcome, UpdatesApplyOutcome.applying);
      expect(apply.restartScheduled, true);
      expect(
        UpdatesApplyResponse.fromJson({'restart_blocked': true, 'ok': true})
            .outcome,
        UpdatesApplyOutcome.restartBlocked,
      );
      expect(
        UpdatesApplyResponse.fromJson({'ok': false}).outcome,
        UpdatesApplyOutcome.failed,
      );
    });

    test('ReasoningStatusResponse（含 effectiveEffort / normalizedSupportedEfforts）', () {
      final response = ReasoningStatusResponse.fromJson({
        'ok': true,
        'show_reasoning': true,
        'reasoning_effort': 'medium',
        'effort': 'low',
        'supported_efforts': [' LOW ', 'medium', 'low', ''],
        'supports_reasoning_effort': true,
        'error': null,
      });
      expect(response.showReasoning, true);
      expect(response.effectiveEffort, 'medium');
      expect(response.normalizedSupportedEfforts, ['low', 'medium']);
      expect(
        ReasoningStatusResponse.fromJson({'effort': 'high'}).effectiveEffort,
        'high',
      );
      expect(
        ReasoningStatusResponse.fromJson({'supported_efforts': 'bad'})
            .supportedEfforts,
        isNull,
      );
    });

    test('PersonalitiesResponse / PersonalitySummary / PersonalitySetResponse', () {
      final response = PersonalitiesResponse.fromJson({
        'personalities': [
          {'name': 'default', 'description': '…'},
        ],
      });
      expect(response.personalities!.single.id, 'default');
      expect(PersonalitiesResponse.fromJson(const {}).personalities, isNull);

      final set = PersonalitySetResponse.fromJson(
        {'ok': true, 'personality': 'default', 'prompt': '…', 'error': null},
      );
      expect(set.personality, 'default');
    });

    test('ProfilesResponse / ProfileSummary / ProfileCreateResponse / ProfileSwitchResponse', () {
      final response = ProfilesResponse.fromJson({
        'profiles': [
          {
            'name': 'work',
            'path': '/home/u/.hermes/profiles/work',
            'is_default': false,
            'is_active': true,
            'gateway_running': true,
            'model': 'gpt-4o',
            'provider': 'openai',
            'has_env': false,
            'skill_count': 5,
          },
        ],
        'active': 'work',
        'single_profile_mode': false,
      });
      final profile = response.profiles!.single;
      expect(profile.id, 'work');
      expect(profile.displayName, 'work');
      expect(profile.isActive, true);
      expect(profile.skillCount, 5);
      expect(profile.normalizedName, 'work');
      expect(ProfileSummary.fromJson(const {}).displayName, 'Profile');
      expect(
        ProfileSummary.fromJson({'name': 'default'}).displayName,
        'Default',
      );

      final create = ProfileCreateResponse.fromJson(
        {'ok': true, 'profile': {'name': 'work'}, 'error': null},
      );
      expect(create.profile!.name, 'work');

      final switchResponse = ProfileSwitchResponse.fromJson({
        'profiles': [],
        'active': 'work',
        'default_model': 'gpt-4o',
        'default_workspace': 'default',
        'error': null,
      });
      expect(switchResponse.defaultModel, 'gpt-4o');
      expect(switchResponse.defaultWorkspace, 'default');
    });
  });

  group('ModelCatalogParser', () {
    test('parseGroups：空 models 组丢弃 / 缺省 id / 缺省 name', () {
      final groups = ModelCatalogParser.parseGroups([
        const JsonObject({
          'provider_id': JsonString('p1'),
          'models': JsonArray([]),
        }),
        const JsonObject({
          'provider_id': JsonString('p2'),
          'models': JsonArray([
            JsonObject({'id': JsonString('m1')}),
          ]),
        }),
        const JsonObject({
          'name': JsonString('  '),
          'models': JsonArray([
            JsonObject({
              'id': JsonString('m2'),
              'label': JsonString('M2'),
            }),
          ]),
        }),
      ]);
      expect(groups, hasLength(2));
      expect(groups[0].id, 'p2');
      expect(groups[0].name, 'p2');
      expect(groups[0].models.single.displayName, 'm1');
      // 无 provider 组：id = name-index
      expect(groups[1].id, 'Models-2');
      expect(groups[1].models.single.displayName, 'M2');
    });

    test('parseOptions：非对象项跳过 / id 必填', () {
      final options = ModelCatalogParser.parseOptions([
        const JsonString('nope'),
        const JsonObject({'id': JsonString('a'), 'name': JsonString('A')}),
        const JsonObject({'label': JsonString('no-id')}),
      ]);
      expect(options, hasLength(1));
      expect(options.single.id, 'a');
      expect(options.single.providerID, isNull);
    });

    test('parseOptions：大小写与分隔符归一去重（保留首项）', () {
      final options = ModelCatalogParser.parseOptions([
        const JsonObject({
          'id': JsonString('gpt-5.6-luna'),
          'name': JsonString('GPT 5.6 Luna Lower'),
        }),
        const JsonObject({
          'id': JsonString('GPT-5.6 Luna'),
          'name': JsonString('GPT 5.6 Luna Upper'),
        }),
        const JsonObject({
          'id': JsonString('deepseek-v4-flash'),
          'name': JsonString('DeepSeek V4 Flash'),
        }),
      ]);
      expect(options, hasLength(2));
      expect(options[0].id, 'gpt-5.6-luna');
      expect(options[0].displayName, 'GPT 5.6 Luna Lower');
      expect(options[1].id, 'deepseek-v4-flash');
    });
  });

  test('== / hashCode / toString', () {
    final a = ProviderSummary.fromJson({'id': 'openai'});
    final b = ProviderSummary.fromJson({'id': 'openai'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('ProviderSummary'));
  });
}
