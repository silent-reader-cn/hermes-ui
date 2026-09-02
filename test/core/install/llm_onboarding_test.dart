import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/llm_onboarding.dart';

class _FakeLlmOnboardingApi implements LlmOnboardingApi {
  _FakeLlmOnboardingApi();

  LlmOnboardingConfig? savedConfig;
  String? savedBaseUrl;

  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async {
    savedBaseUrl = serverBaseUrl;
    savedConfig = config;
    return true;
  }
}

void main() {
  group('LlmProviderOption & LlmOnboardingConfig', () {
    test('内置 providers 覆盖 OpenRouter/Anthropic/OpenAI/Google/Ollama/Custom', () {
      final providers = LlmProviderOption.builtinProviders;
      expect(providers.map((p) => p.id), containsAll([
        'openrouter',
        'anthropic',
        'openai',
        'google',
        'ollama',
        'custom',
      ]));

      final openrouter = providers.firstWhere((p) => p.id == 'openrouter');
      expect(openrouter.defaultBaseUrl, 'https://openrouter.ai/api/v1');
      expect(openrouter.requiresApiKey, isTrue);

      final ollama = providers.firstWhere((p) => p.id == 'ollama');
      expect(ollama.requiresApiKey, isFalse);
    });

    test('LlmOnboardingConfig.toJson 序列化正确', () {
      const config1 = LlmOnboardingConfig(
        provider: 'openrouter',
        apiKey: 'sk-or-v1-12345',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'anthropic/claude-3.5-sonnet',
      );

      expect(config1.toJson(), {
        'provider': 'openrouter',
        'api_key': 'sk-or-v1-12345',
        'base_url': 'https://openrouter.ai/api/v1',
        'model': 'anthropic/claude-3.5-sonnet',
      });

      const config2 = LlmOnboardingConfig(
        provider: 'ollama',
      );
      expect(config2.toJson(), {
        'provider': 'ollama',
      });
    });

    test('FakeLlmOnboardingApi 记录并验证保存配置', () async {
      final api = _FakeLlmOnboardingApi();
      const config = LlmOnboardingConfig(
        provider: 'anthropic',
        apiKey: 'sk-ant-123',
      );

      final ok = await api.saveConfig(
        serverBaseUrl: 'http://127.0.0.1:8787',
        config: config,
      );

      expect(ok, isTrue);
      expect(api.savedBaseUrl, 'http://127.0.0.1:8787');
      expect(api.savedConfig?.provider, 'anthropic');
      expect(api.savedConfig?.apiKey, 'sk-ant-123');
    });
  });
}
