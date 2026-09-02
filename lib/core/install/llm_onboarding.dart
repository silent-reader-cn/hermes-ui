import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// LLM 模型服务商选项配置。
class LlmProviderOption {
  const LlmProviderOption({
    required this.id,
    required this.name,
    required this.description,
    this.defaultBaseUrl = '',
    this.defaultModel = '',
    this.requiresApiKey = true,
    this.keyPlaceholder = '请输入 API Key',
  });

  final String id;
  final String name;
  final String description;
  final String defaultBaseUrl;
  final String defaultModel;
  final bool requiresApiKey;
  final String keyPlaceholder;

  static const List<LlmProviderOption> builtinProviders = [
    LlmProviderOption(
      id: 'openrouter',
      name: 'OpenRouter',
      description: '推荐 · 多模型统一网关 (Claude, GPT, Llama 等)',
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'anthropic/claude-3.5-sonnet',
      requiresApiKey: true,
      keyPlaceholder: 'sk-or-v1-...',
    ),
    LlmProviderOption(
      id: 'anthropic',
      name: 'Anthropic (Claude)',
      description: '官方 Anthropic Claude 模型 API',
      defaultBaseUrl: 'https://api.anthropic.com',
      defaultModel: 'claude-3-5-sonnet-20241022',
      requiresApiKey: true,
      keyPlaceholder: 'sk-ant-...',
    ),
    LlmProviderOption(
      id: 'openai',
      name: 'OpenAI (GPT-4o)',
      description: '官方 OpenAI GPT 系列模型 API',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o',
      requiresApiKey: true,
      keyPlaceholder: 'sk-...',
    ),
    LlmProviderOption(
      id: 'google',
      name: 'Google Gemini',
      description: 'Google AI Studio Gemini 系列模型 API',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com',
      defaultModel: 'gemini-1.5-pro',
      requiresApiKey: true,
      keyPlaceholder: 'AIzaSy...',
    ),
    LlmProviderOption(
      id: 'ollama',
      name: 'Ollama (Local)',
      description: '本地运行的开源模型服务 (http://127.0.0.1:11434)',
      defaultBaseUrl: 'http://127.0.0.1:11434',
      defaultModel: 'llama3.1',
      requiresApiKey: false,
      keyPlaceholder: '（本地服务无需填写 API Key）',
    ),
    LlmProviderOption(
      id: 'custom',
      name: '自定义 OpenAI 兼容接口',
      description: '第三方中转网关或自建兼容 API',
      defaultBaseUrl: '',
      defaultModel: '',
      requiresApiKey: true,
      keyPlaceholder: 'API Key',
    ),
  ];
}

/// LLM 用户配置输入模型。
class LlmOnboardingConfig {
  const LlmOnboardingConfig({
    required this.provider,
    this.apiKey,
    this.baseUrl,
    this.model,
  });

  final String provider;
  final String? apiKey;
  final String? baseUrl;
  final String? model;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        if (apiKey != null && apiKey!.isNotEmpty) 'api_key': apiKey,
        if (baseUrl != null && baseUrl!.isNotEmpty) 'base_url': baseUrl,
        if (model != null && model!.isNotEmpty) 'model': model,
      };
}

/// LLM 向导保存与配置接口（测试中可注入 Fake）。
abstract interface class LlmOnboardingApi {
  /// 提交配置到 WebUI 的 /api/onboarding 或 /api/model/set。
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  });
}

/// 生产环境默认 [LlmOnboardingApi] 实现。
class DefaultLlmOnboardingApi implements LlmOnboardingApi {
  const DefaultLlmOnboardingApi();

  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      var base = serverBaseUrl.trim();
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final uri = Uri.parse('$base/api/onboarding');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(config.toJson()));
      final res = await req.close();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

/// [LlmOnboardingApi] Provider。
final llmOnboardingApiProvider = Provider<LlmOnboardingApi>(
  (ref) => const DefaultLlmOnboardingApi(),
);
