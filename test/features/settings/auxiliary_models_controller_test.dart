import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/auxiliary_model.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';

import '../../helpers/fake_settings_api.dart';

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

void main() {
  group('AuxiliaryModelsController 加载状态机', () {
    test('加载成功：解析 tasks 列表 + main 主模型', () async {
      final api = FakeSettingsApi();
      api.auxiliaryModelsResponse = const AuxiliaryModelsResponse(
        tasks: [
          AuxiliaryTaskRow(
            task: 'vision',
            provider: 'openai',
            model: 'gpt-4o',
            label: 'Vision Understanding',
            apiKeySet: true,
          ),
          AuxiliaryTaskRow(
            task: 'compression',
            provider: 'auto',
            model: '',
            label: 'Context Compression',
            apiKeySet: false,
          ),
        ],
        main: AuxMainModel(
          provider: 'anthropic',
          model: 'claude-sonnet-4',
        ),
      );
      final container = makeContainer(api);

      await container.read(auxiliaryModelsControllerProvider.future);
      final state =
          container.read(auxiliaryModelsControllerProvider).valueOrNull!;

      expect(api.auxiliaryModelsCount, 1);
      expect(state.tasks, hasLength(2));
      expect(state.tasks.first.task, 'vision');
      expect(state.tasks.first.provider, 'openai');
      expect(state.tasks.first.model, 'gpt-4o');
      expect(state.tasks.first.apiKeySet, isTrue);
      expect(state.main.model, 'claude-sonnet-4');
    });

    test('auxiliaryModels 加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSettingsApi();
      api.auxiliaryModelsError =
          NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(auxiliaryModelsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(auxiliaryModelsControllerProvider).hasError, isTrue);

      api.auxiliaryModelsError = null;
      api.auxiliaryModelsResponse = const AuxiliaryModelsResponse(
        tasks: [AuxiliaryTaskRow(task: 'vision')],
      );
      await container.read(auxiliaryModelsControllerProvider.notifier).refresh();

      final state =
          container.read(auxiliaryModelsControllerProvider).valueOrNull!;
      expect(state.tasks, hasLength(1));
    });
  });

  group('AuxiliaryModelsController 操作方法', () {
    test('setAuxiliaryModel 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(auxiliaryModelsControllerProvider.future);

      final controller =
          container.read(auxiliaryModelsControllerProvider.notifier);
      final ok = await controller.setAuxiliaryModel(
        task: 'vision',
        provider: 'custom:cpa',
        model: 'deepseek-v4-flash',
      );

      expect(ok, isTrue);
      expect(api.setAuxiliaryModelCalls, [
        (
          task: 'vision',
          provider: 'custom:cpa',
          model: 'deepseek-v4-flash',
          advanced: null,
        ),
      ]);
      expect(api.auxiliaryModelsCount, 2);
    });

    test('resetAllToAuto 成功：调用 __reset__ 任务并刷新', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(auxiliaryModelsControllerProvider.future);

      final controller =
          container.read(auxiliaryModelsControllerProvider.notifier);
      final ok = await controller.resetAllToAuto();

      expect(ok, isTrue);
      expect(api.setAuxiliaryModelCalls, [
        (
          task: '__reset__',
          provider: 'auto',
          model: '',
          advanced: null,
        ),
      ]);
      expect(api.auxiliaryModelsCount, 2);
    });

    test('操作失败：设置 actionError 并可通过 clearActionError 清除', () async {
      final api = FakeSettingsApi();
      api.setAuxiliaryModelError = HttpException(500, null, message: '设置失败');
      final container = makeContainer(api);
      await container.read(auxiliaryModelsControllerProvider.future);

      final controller =
          container.read(auxiliaryModelsControllerProvider.notifier);
      final ok = await controller.setAuxiliaryModel(
        task: 'vision',
        provider: 'openai',
        model: 'gpt-4o',
      );

      expect(ok, isFalse);
      var state =
          container.read(auxiliaryModelsControllerProvider).valueOrNull!;
      expect(state.actionError, contains('设置失败'));

      await controller.clearActionError();
      state = container.read(auxiliaryModelsControllerProvider).valueOrNull!;
      expect(state.actionError, isNull);
    });

    test('切换服务器（apiClientProvider 重建）→ auxiliary models 自动重载', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(auxiliaryModelsControllerProvider.future);
      expect(api.auxiliaryModelsCount, 1);

      container.invalidate(apiClientProvider);
      await container.pump();
      await container.read(auxiliaryModelsControllerProvider.future);
      expect(api.auxiliaryModelsCount, 2);
    });
  });
}
