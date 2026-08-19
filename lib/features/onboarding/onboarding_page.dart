import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/uuid.dart';
import '../../app/theme/status_colors.dart';
import 'onboarding_providers.dart';

/// 健康检查状态。
enum _HealthState { idle, checking, ok, failed }

/// 认证模式（由 GET /api/auth/status 决定）。
enum _AuthState { checking, notRequired, required }

/// 登录进行状态。
enum _LoginState { idle, loggingIn, failed }

/// 三步 onboarding 向导（app_shell_spec.md §6）。
///
/// 1. 服务器地址 + 健康检查（GET /health）
/// 2. 认证（无密码跳过 / 密码登录 POST /api/auth/login）
/// 3. 自定义 Headers（可选）→ 保存连接并跳转 `/`
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

/// 单行自定义头输入（key + value 各自持有控制器，便于增删行）。
class _HeaderField {
  _HeaderField() : nameController = TextEditingController(),
                   valueController = TextEditingController();

  final TextEditingController nameController;
  final TextEditingController valueController;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _stepCount = 3;

  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final List<_HeaderField> _headers = [_HeaderField()];

  int _step = 1;
  _HealthState _health = _HealthState.idle;
  String _healthMessage = '';
  _AuthState _auth = _AuthState.checking;
  _LoginState _loginState = _LoginState.idle;
  String _headerError = '';
  bool _saving = false;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    for (final field in _headers) {
      field.dispose();
    }
    super.dispose();
  }

  /// 根据已填 URL 构建 onboarding API 客户端（测试经 factory Provider 注入 fake）。
  OnboardingServerApi _buildClient() {
    final factory = ref.read(onboardingApiFactoryProvider);
    return factory(
      _urlController.text.trim(),
      [
        for (final field in _headers)
          if (field.nameController.text.trim().isNotEmpty)
            CustomHeader(
              name: field.nameController.text.trim(),
              value: field.valueController.text,
            ),
      ],
    );
  }

  String? _validateUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '请输入服务器地址';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入有效的服务器地址，例如 https://hermes.example.com:30002';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 步骤 1：服务器地址 + 健康检查
  // ---------------------------------------------------------------------------

  Future<void> _runHealthCheck() async {
    final error = _validateUrl(_urlController.text);
    if (error != null) {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error;
      });
      return;
    }
    setState(() {
      _health = _HealthState.checking;
      _healthMessage = '';
    });
    try {
      final result = await _buildClient().health();
      final ok = result is Map && result['status'] == 'ok';
      setState(() {
        _health = ok ? _HealthState.ok : _HealthState.failed;
        _healthMessage = ok ? '连接成功' : '服务器返回异常状态';
      });
    } on ApiException catch (error) {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error.message;
      });
    } on Exception {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = '无法连接到服务器';
      });
    }
  }

  Future<void> _nextFromStep1() async {
    final error = _validateUrl(_urlController.text);
    if (error != null) {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error;
      });
      return;
    }
    _goToStep(2);
    await _checkAuth();
  }

  // ---------------------------------------------------------------------------
  // 步骤 2：认证
  // ---------------------------------------------------------------------------

  Future<void> _checkAuth() async {
    setState(() => _auth = _AuthState.checking);
    try {
      final result = await _buildClient().authStatus();
      final enabled = result is Map && result['auth_enabled'] == true;
      setState(() {
        _auth = enabled ? _AuthState.required : _AuthState.notRequired;
      });
    } on Exception {
      // 查询失败按需认证处理（保守），仍允许用户跳过。
      setState(() => _auth = _AuthState.required);
    }
  }

  Future<void> _login() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    setState(() => _loginState = _LoginState.loggingIn);
    try {
      await _buildClient().login(password);
      if (!mounted) return;
      setState(() => _loginState = _LoginState.idle);
      _goToStep(3);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loginState = _LoginState.failed);
      await _showAlert('登录失败', error.message);
    } on Exception {
      if (!mounted) return;
      setState(() => _loginState = _LoginState.failed);
      await _showAlert('登录失败', '无法连接到服务器，请稍后重试');
    }
  }

  // ---------------------------------------------------------------------------
  // 步骤 3：自定义 Headers + 完成
  // ---------------------------------------------------------------------------

  void _addHeaderField() {
    setState(() {
      _headers.add(_HeaderField());
      _headerError = '';
    });
  }

  void _removeHeaderField(int index) {
    setState(() {
      _headers.removeAt(index).dispose();
      _headerError = '';
      if (_headers.isEmpty) _headers.add(_HeaderField());
    });
  }

  /// Header 校验：空行跳过；非空行必须 name 为合法 token 且 value 无换行。
  String? _headerErrorText() {
    for (final field in _headers) {
      final name = field.nameController.text.trim();
      final value = field.valueController.text;
      if (name.isEmpty && value.trim().isEmpty) continue;
      if (!CustomHeader(name: name, value: value).isApplicable) {
        return 'Header 名必须是合法 token，值不能包含换行';
      }
    }
    return null;
  }

  Future<void> _finish() async {
    if (_saving) return;
    final urlError = _validateUrl(_urlController.text);
    final headerError = _headerErrorText();
    if (urlError != null || headerError != null) {
      setState(() {
        _headerError = headerError ?? urlError ?? '';
      });
      return;
    }
    setState(() => _saving = true);

    final url = _urlController.text.trim();
    final host = Uri.tryParse(url)?.host;
    final connection = ServerConnection(
      id: uuidV4(),
      name: host == null || host.isEmpty ? url : host,
      baseUrl: url,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password: _passwordController.text.isEmpty
          ? null
          : _passwordController.text,
      customHeaders: {
        for (final field in _headers)
          if (field.nameController.text.trim().isNotEmpty)
            field.nameController.text.trim(): field.valueController.text,
      },
      createdAt: DateTime.now().toUtc(),
    );

    final saved = await ref.read(connectionsProvider.notifier).upsert(connection);
    await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
    if (!mounted) return;
    context.go('/');
  }

  // ---------------------------------------------------------------------------
  // 通用
  // ---------------------------------------------------------------------------

  void _goToStep(int step) {
    setState(() {
      _step = step.clamp(1, _stepCount);
      _headerError = '';
    });
  }

  Future<void> _showAlert(String title, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: _step > 1
            ? CupertinoNavigationBarBackButton(
                onPressed: () => _goToStep(_step - 1),
              )
            : null,
        middle: const Text('连接服务器'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildStepBody()),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(width: double.infinity, child: _buildFooter()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      default:
        return _buildStep3();
    }
  }

  Widget _buildStep1() {
    final checking = _health == _HealthState.checking;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '连接你的 Hermex 服务器',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '输入 hermes-webui 的地址（含端口），例如 https://hermes.example.com:30002',
          style: TextStyle(fontSize: 15, color: CupertinoColors.secondaryLabel),
        ),
        const SizedBox(height: 24),
        CupertinoTextField(
          key: const ValueKey('onboarding-url'),
          controller: _urlController,
          placeholder: 'https://hermes.example.com:30002',
          autocorrect: false,
          keyboardType: TextInputType.url,
          padding: const EdgeInsets.all(12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CupertinoButton(
              key: const ValueKey('onboarding-health-check'),
              onPressed: checking ? null : () => unawaited(_runHealthCheck()),
              child: const Text('连接测试'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildHealthStatus(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: CupertinoButton(
            key: const ValueKey('onboarding-skip-wizard'),
            onPressed: () => unawaited(_skipToHeaders()),
            child: const Text(
              '已有 API Key？跳过向导',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthStatus() {
    switch (_health) {
      case _HealthState.idle:
        return const SizedBox.shrink();
      case _HealthState.checking:
        return const Row(
          children: [
            CupertinoActivityIndicator(),
            SizedBox(width: 8),
            Text('正在检查…'),
          ],
        );
      case _HealthState.ok:
        return const Text('✅ 连接成功');
      case _HealthState.failed:
        return Text(
          '❌ $_healthMessage',
          style: const TextStyle(color: statusRedText),
        );
    }
  }

  Future<void> _skipToHeaders() async {
    final error = _validateUrl(_urlController.text);
    if (error != null) {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error;
      });
      return;
    }
    _goToStep(3);
  }

  Widget _buildStep2() {
    final checking = _auth == _AuthState.checking;
    final loggingIn = _loginState == _LoginState.loggingIn;
    final notRequired = _auth == _AuthState.notRequired;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '认证',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (checking)
          const Row(
            children: [
              CupertinoActivityIndicator(),
              SizedBox(width: 8),
              Text('正在检测服务器认证…'),
            ],
          )
        else if (notRequired)
          const Text(
            '该服务器未启用密码认证，可直接继续',
            style: TextStyle(fontSize: 15, color: CupertinoColors.systemGreen),
          )
        else
          const Text(
            '该服务器需要密码认证，请登录',
            style: TextStyle(fontSize: 15, color: CupertinoColors.secondaryLabel),
          ),
        const SizedBox(height: 24),
        CupertinoTextField(
          key: const ValueKey('onboarding-username'),
          controller: _usernameController,
          placeholder: '用户名（可选）',
          autocorrect: false,
          padding: const EdgeInsets.all(12),
        ),
        const SizedBox(height: 12),
        CupertinoTextField(
          key: const ValueKey('onboarding-password'),
          controller: _passwordController,
          placeholder: '密码',
          obscureText: true,
          padding: const EdgeInsets.all(12),
        ),
        const SizedBox(height: 24),
        Center(
          child: CupertinoButton(
            key: const ValueKey('onboarding-skip-auth'),
            onPressed: () => _goToStep(3),
            child: const Text(
              '跳过认证（无密码模式）',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
        if (loggingIn)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CupertinoActivityIndicator()),
          ),
      ],
    );
  }

  Widget _buildStep3() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '自定义 Headers（可选）',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '反向代理场景可添加自定义请求头，如 Authorization: Bearer xxx',
          style: TextStyle(fontSize: 15, color: CupertinoColors.secondaryLabel),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _headers.length; i++) _buildHeaderRow(i),
        if (_headerError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _headerError,
              style: const TextStyle(color: statusRedText),
            ),
          ),
        const SizedBox(height: 8),
        CupertinoButton(
          key: const ValueKey('onboarding-add-header'),
          onPressed: _addHeaderField,
          child: const Text('添加 Header'),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(int index) {
    final field = _headers[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              key: ValueKey('onboarding-header-name-$index'),
              controller: field.nameController,
              placeholder: 'Header 名',
              autocorrect: false,
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoTextField(
              key: ValueKey('onboarding-header-value-$index'),
              controller: field.valueController,
              placeholder: '值',
              autocorrect: false,
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 4),
          AccessibleButton(
            key: ValueKey('onboarding-header-remove-$index'),
            label: '删除 Header',
            padding: EdgeInsets.zero,
            onPressed: () => _removeHeaderField(index),
            child: const Icon(
              CupertinoIcons.delete,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final (String label, VoidCallback? onPressed) = switch (_step) {
      1 => (
        '下一步',
        () => unawaited(_nextFromStep1()),
      ),
      2 => _auth == _AuthState.notRequired
          ? ('继续', () => _goToStep(3))
          : (
              '登录并继续',
              _loginState == _LoginState.loggingIn
                  ? null
                  : () => unawaited(_login()),
            ),
      _ => (
        '完成',
        _saving ? null : () => unawaited(_finish()),
      ),
    };
    return CupertinoButton.filled(
      key: ValueKey('onboarding-footer-${_step == 3 ? 'finish' : 'next'}'),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
