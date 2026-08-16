import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';

import '../../helpers/fake_settings_api.dart';

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeSettingsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      settingsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 构造带分组的模型目录响应（groups 形状对齐 /api/models）。
ModelsResponse buildModelsResponse({
  String? defaultModel,
  String? activeProvider,
  List<Map<String, Object?>> groups = const [],
}) {
  return ModelsResponse.fromJson({
    'default_model': ?defaultModel,
    'active_provider': ?activeProvider,
    'groups': groups,
  });
}

/// 两个 provider 分组 + 一个 extra model 的样例目录。
const sampleGroups = <Map<String, Object?>>[
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-4o', 'name': 'GPT-4o'},
      {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
    ],
    'extra_models': [
      {'id': 'o3', 'name': 'o3'},
    ],
  },
  {
    'provider_id': 'anthropic',
    'name': 'Anthropic',
    'models': [
      {'id': 'claude-sonnet-4', 'name': 'Claude Sonnet 4'},
    ],
  },
];

void main() {
  group('SettingsController 加载状态机', () {
    test('加载成功：解析模型分组 + 默认模型 + 推理状态 + 派生数据', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        activeProvider: 'openai',
        groups: sampleGroups,
      );
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        reasoningEffort: 'medium',
        supportedEfforts: ['low', 'medium', 'high'],
        supportsReasoningEffort: true,
      );
      final container = makeContainer(api);

      await container.read(settingsControllerProvider.future);
      final state = container.read(settingsControllerProvider).valueOrNull!;

      expect(api.modelsCount, 1);
      expect(api.reasoningCount, 1);
      expect(state.modelGroups, hasLength(2));
      expect(state.modelGroups.first.name, 'OpenAI');
      expect(state.defaultModel, 'gpt-4o');
      expect(state.activeProvider, 'openai');
      expect(state.reasoningEffort, 'medium');
      expect(state.supportedEfforts, ['low', 'medium', 'high']);
      expect(state.supportsReasoningEffort, isTrue);

      // 派生：全部模型选项（含 extra_models，展平保序）
      final options = container.read(settingsModelOptionsProvider);
      expect(
        options.map((o) => o.id).toList(),
        ['gpt-4o', 'gpt-4o-mini', 'o3', 'claude-sonnet-4'],
      );
      expect(options.first.displayName, 'GPT-4o');
      expect(options.first.providerID, 'openai');

      // 派生：默认模型显示名
      expect(state.defaultModelLabel, 'GPT-4o');
    });

    test('默认模型不在目录中 → defaultModelLabel 回退为 id 本身', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'custom-model-xyz',
        groups: sampleGroups,
      );
      final container = makeContainer(api);

      await container.read(settingsControllerProvider.future);
      final state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.defaultModelLabel, 'custom-model-xyz');
    });

    test('reasoning 端点失败 → 不阻断整体加载，隐藏推理设置', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      api.reasoningError = HttpException(404, null, message: '接口不存在');
      final container = makeContainer(api);

      await container.read(settingsControllerProvider.future);
      final state = container.read(settingsControllerProvider).valueOrNull!;

      expect(api.modelsCount, 1);
      expect(state.modelGroups, hasLength(2));
      expect(state.defaultModel, 'gpt-4o');
      expect(state.supportsReasoningEffort, isFalse);
      expect(state.reasoningEffort, isNull);
    });

    test('models 加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      api.modelsError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(settingsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(settingsControllerProvider).hasError, isTrue);
      expect(container.read(settingsControllerProvider).valueOrNull, isNull);

      api.modelsError = null;
      await container.read(settingsControllerProvider.notifier).refresh();

      final state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.modelGroups, hasLength(2));
      expect(state.defaultModel, 'gpt-4o');
    });

    test('空模型目录 → 空分组 + 空选项，不崩溃', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);

      await container.read(settingsControllerProvider.future);
      final state = container.read(settingsControllerProvider).valueOrNull!;

      expect(state.modelGroups, isEmpty);
      expect(state.allModels, isEmpty);
      expect(state.defaultModelLabel, isNull);
      expect(container.read(settingsModelOptionsProvider), isEmpty);
    });
  });

  group('SettingsController 保存操作', () {
    test('setDefaultModel 成功：调 API + 更新状态', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      final ok = await controller.setDefaultModel('claude-sonnet-4');
      expect(ok, isTrue);
      expect(api.defaultModelCalls, ['claude-sonnet-4']);
      expect(
        container.read(settingsControllerProvider).valueOrNull!.defaultModel,
        'claude-sonnet-4',
      );
    });

    test('setDefaultModel：服务器回显缺失 → 用请求值兜底', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(groups: sampleGroups);
      // fake 默认 saveDefaultModel 返回 model: null。
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      final ok = await controller.setDefaultModel('o3');
      expect(ok, isTrue);
      expect(
        container.read(settingsControllerProvider).valueOrNull!.defaultModel,
        'o3',
      );
    });

    test('setDefaultModel 失败：actionError + 状态不变；clearActionError 清除',
        () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      api.saveDefaultModelError = HttpException(500, null, message: '保存失败');
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      final ok = await controller.setDefaultModel('o3');
      expect(ok, isFalse);
      var state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.actionError, contains('保存失败'));
      expect(state.defaultModel, 'gpt-4o'); // 未变化

      await controller.clearActionError();
      state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.actionError, isNull);
    });

    test('setReasoningEffort 成功：调 API + 更新 effort 与能力标记', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        reasoningEffort: 'medium',
        supportedEfforts: ['low', 'medium', 'high'],
        supportsReasoningEffort: true,
      );
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      // fake 的 saveReasoningEffort 回显 effort 为空 → 用请求值兜底。
      final ok = await controller.setReasoningEffort('high');
      expect(ok, isTrue);
      expect(api.reasoningEffortCalls, ['high']);
      final state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.reasoningEffort, 'high');
      expect(state.supportedEfforts, ['low', 'medium', 'high']);
      expect(state.supportsReasoningEffort, isTrue);
    });

    test('setReasoningEffort 失败：actionError + effort 不变', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        reasoningEffort: 'low',
        supportsReasoningEffort: true,
      );
      api.saveReasoningEffortError = NetworkException(
        NetworkExceptionKind.timedOut,
      );
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      final ok = await controller.setReasoningEffort('high');
      expect(ok, isFalse);
      final state = container.read(settingsControllerProvider).valueOrNull!;
      expect(state.actionError, isNotNull);
      expect(state.reasoningEffort, 'low'); // 未变化
    });

    test('切换服务器（apiClientProvider 重建）→ settings 自动重载', () async {
      final api = FakeSettingsApi();
      api.modelsResponse = buildModelsResponse(
        defaultModel: 'gpt-4o',
        groups: sampleGroups,
      );
      final container = makeContainer(api);
      await container.read(settingsControllerProvider.future);
      expect(api.modelsCount, 1);

      // 触发 apiClientProvider 重建（watch 依赖变化 → build 重跑）。
      container.invalidate(apiClientProvider);
      await container.pump();
      await container.read(settingsControllerProvider.future);
      expect(api.modelsCount, 2);
    });
  });
}
