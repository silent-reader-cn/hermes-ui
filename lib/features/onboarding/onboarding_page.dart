import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import 'onboarding_providers.dart';

/// 健康检查状态（URL 失焦/提交时自动触发）。
enum _HealthState { idle, checking, ok, failed }

/// 认证模式（由 GET /api/auth/status 决定）。
enum _AuthState { checking, notRequired, required }

/// 密码验证进行状态（密码失焦/提交时试探性登录）。
enum _LoginState { idle, verifying, ok, failed }

/// 单页「连接服务器」页（替代原三步向导）。
///
/// 结构与交互：
/// 1. 服务器地址：失焦即格式校验 + 健康检查（GET /health），成功后再查
///    auth 状态（GET /api/auth/status），结果即时显示在输入框下方。
/// 2. 认证：服务端启用密码时显示密码框，失焦即试探登录（POST /api/auth/login），
///    成功/失败就地提示（不跳转）；未启用密码则显示「无需密码」文案。
/// 3. 底部「连接并保存」：校验 URL（+ 必填密码）后保存
///    [ServerConnection] 并跳转 `/`。
///
/// 后端 hermes-webui 只认密码（无用户名），保存连接时 username 恒为 null。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  _HealthState _health = _HealthState.idle;
  String _healthMessage = '';
  _AuthState _auth = _AuthState.checking;
  _LoginState _loginState = _LoginState.idle;
  String _loginMessage = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 失焦即时校验：FocusNode listener（输入框 blur 时触发）。
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _passwordFocusNode.addListener(_onPasswordFocusChanged);
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _passwordFocusNode.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 根据已填 URL 构建 onboarding API 客户端（测试经 factory Provider 注入 fake）。
  OnboardingServerApi _buildClient() {
    final factory = ref.read(onboardingApiFactoryProvider);
    return factory(_urlController.text.trim(), const []);
  }

  String? _validateUrl(String raw) {
    final l10n = AppLocalizations.of(context);
    final url = raw.trim();
    if (url.isEmpty) return l10n.pleaseEnterServerUrl;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return l10n.pleaseEnterValidServerUrl;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 失焦即时校验
  // ---------------------------------------------------------------------------

  void _onUrlFocusChanged() {
    if (!_urlFocusNode.hasFocus) {
      // 等当前帧（含焦点切换/输入连接交接）完全结束后再触发健康检查：
      // 失焦后立刻 setState 重建仍持焦的输入框会打断框架的键盘焦点交接，
      // 导致后续输入落到错误的输入框。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runHealthCheck());
      });
    }
  }

  void _onPasswordFocusChanged() {
    if (!_passwordFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_verifyPassword());
      });
    }
  }

  /// 健康检查：格式校验 → GET /health → 成功后刷新 auth 状态。
  Future<void> _runHealthCheck() async {
    if (_health == _HealthState.checking) return;
    final l10n = AppLocalizations.of(context);
    final error = _validateUrl(_urlController.text);
    if (error != null) {
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error;
        _auth = _AuthState.checking; // 地址无效时认证区一并隐藏重置
      });
      return;
    }
    setState(() {
      _health = _HealthState.checking;
      _healthMessage = '';
    });
    try {
      final result = await _buildClient().health();
      if (!mounted) return;
      final ok = result.status == 'ok';
      setState(() {
        _health = ok ? _HealthState.ok : _HealthState.failed;
        _healthMessage = ok
            ? l10n.connectionSuccessful
            : l10n.serverReturnedAbnormalStatus;
      });
      if (ok) await _checkAuth();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = error.message;
        _auth = _AuthState.checking;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _health = _HealthState.failed;
        _healthMessage = l10n.cannotConnectToServer;
        _auth = _AuthState.checking;
      });
    }
  }

  /// 查询服务端认证模式（auth_enabled）；失败按需认证处理（保守）。
  Future<void> _checkAuth() async {
    setState(() => _auth = _AuthState.checking);
    try {
      final result = await _buildClient().authStatus();
      if (!mounted) return;
      final enabled = result.authEnabled == true;
      setState(() {
        _auth = enabled ? _AuthState.required : _AuthState.notRequired;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _auth = _AuthState.required);
    }
  }

  /// 密码失焦试探性登录：成功显示「密码正确」，失败就地报错（不跳转）。
  Future<void> _verifyPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty || _auth != _AuthState.required) return;
    if (_loginState == _LoginState.verifying) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loginState = _LoginState.verifying;
      _loginMessage = '';
    });
    try {
      await _buildClient().login(password);
      if (!mounted) return;
      setState(() {
        _loginState = _LoginState.ok;
        _loginMessage = l10n.passwordVerified;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loginState = _LoginState.failed;
        _loginMessage = l10n.loginFailedWithMessage(error.message);
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loginState = _LoginState.failed;
        _loginMessage = l10n.cannotConnectRetryLater;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 自定义 Headers + 完成
  // ---------------------------------------------------------------------------

  Future<void> _finish() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final urlError = _validateUrl(_urlController.text);
    final passwordMissing =
        _auth == _AuthState.required && _passwordController.text.isEmpty;
    if (urlError != null || passwordMissing) {
      setState(() {
        _healthMessage = urlError ?? _healthMessage;
        if (urlError != null) _health = _HealthState.failed;
        if (passwordMissing) {
          _loginState = _LoginState.failed;
          _loginMessage = l10n.passwordRequiredOnServer;
        }
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
      username: null, // hermes-webui 认证只认密码，无用户名概念
      password: _passwordController.text.isEmpty
          ? null
          : _passwordController.text,
      customHeaders: const {},
      createdAt: DateTime.now().toUtc(),
    );

    final saved = await ref
        .read(connectionsProvider.notifier)
        .upsert(connection);
    await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
    if (!mounted) return;
    context.go('/');
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.connectServer)),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildForm()),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  key: const ValueKey('onboarding-connect'),
                  onPressed: _saving ? null : () => unawaited(_finish()),
                  child: Text(l10n.connectAndSave),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l10n.connectYourHermexServer,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.inputServerAddressHint,
          style: TextStyle(
            fontSize: 15,
            color: secondaryText.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 24),
        CupertinoTextField(
          key: const ValueKey('onboarding-url'),
          controller: _urlController,
          focusNode: _urlFocusNode,
          placeholder: 'https://hermes.example.com:30002',
          autocorrect: false,
          keyboardType: TextInputType.url,
          onEditingComplete: () => unawaited(_runHealthCheck()),
          padding: const EdgeInsets.all(12),
        ),
        const SizedBox(height: 8),
        _buildHealthStatus(),
        if (_health == _HealthState.ok) ...[
          const SizedBox(height: 20),
          _buildAuthSection(),
        ],
      ],
    );
  }

  /// URL 下方的健康检查状态（成功绿勾 / 失败红文案 / 检查中进度）。
  Widget _buildHealthStatus() {
    final l10n = AppLocalizations.of(context);
    switch (_health) {
      case _HealthState.idle:
        return const SizedBox.shrink();
      case _HealthState.checking:
        return Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 8),
            Text(
              l10n.checking,
              style: TextStyle(
                fontSize: 14,
                color: secondaryText.resolveFrom(context),
              ),
            ),
          ],
        );
      case _HealthState.ok:
        return Text(
          l10n.connectionSuccessfulWithCheck,
          style: TextStyle(
            fontSize: 14,
            color: statusGreenText.resolveFrom(context),
            fontWeight: FontWeight.w600,
          ),
        );
      case _HealthState.failed:
        return Text(
          '❌ $_healthMessage',
          style: TextStyle(fontSize: 14, color: statusRedText.resolveFrom(context)),
        );
    }
  }

  /// 认证区：仅在健康检查通过后展示（检测中 / 无需密码 / 需密码+输入框）。
  Widget _buildAuthSection() {
    final l10n = AppLocalizations.of(context);
    switch (_auth) {
      case _AuthState.checking:
        return Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 8),
            Text(
              l10n.detectingServerAuth,
              style: TextStyle(
                fontSize: 14,
                color: secondaryText.resolveFrom(context),
              ),
            ),
          ],
        );
      case _AuthState.notRequired:
        return Row(
          children: [
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 16,
              color: statusGreenText.resolveFrom(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.serverNoPasswordRequired,
                style: TextStyle(
                  fontSize: 14,
                  color: statusGreenText.resolveFrom(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      case _AuthState.required:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.serverPasswordRequired,
              style: TextStyle(
                fontSize: 15,
                color: secondaryText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              key: const ValueKey('onboarding-password'),
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              placeholder: l10n.password,
              obscureText: true,
              onEditingComplete: () => unawaited(_verifyPassword()),
              padding: const EdgeInsets.all(12),
            ),
            const SizedBox(height: 8),
            _buildPasswordStatus(),
          ],
        );
    }
  }

  /// 密码框下方的验证状态（验证中 / 密码正确 / 错误原因）。
  Widget _buildPasswordStatus() {
    final l10n = AppLocalizations.of(context);
    switch (_loginState) {
      case _LoginState.idle:
        return const SizedBox.shrink();
      case _LoginState.verifying:
        return Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 8),
            Text(
              l10n.verifyingPassword,
              style: TextStyle(
                fontSize: 14,
                color: secondaryText.resolveFrom(context),
              ),
            ),
          ],
        );
      case _LoginState.ok:
        return Text(
          _loginMessage,
          style: TextStyle(
            fontSize: 14,
            color: statusGreenText.resolveFrom(context),
            fontWeight: FontWeight.w600,
          ),
        );
      case _LoginState.failed:
        return Text(
          '❌ $_loginMessage',
          style: TextStyle(fontSize: 14, color: statusRedText.resolveFrom(context)),
        );
    }
  }
}
