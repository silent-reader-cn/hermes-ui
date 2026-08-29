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

/// 健康检查状态（提交按钮阶段一触发，随后刷新认证模式）。
enum _HealthState { idle, checking, ok, failed }

/// 认证模式（由 GET /api/auth/status 决定）。
enum _AuthState { checking, notRequired, required }

/// 密码验证进行状态（提交按钮阶段二触发）。
enum _LoginState { idle, verifying, ok, failed }

/// 单页「连接服务器」页（替代原三步向导）。
///
/// 结构与交互（提交按钮单入口，两阶段事件流）：
/// 1. 底部「连接并保存」按钮是唯一触发入口：点击后按钮转 loading（不可重复
///    点击），依次执行 GET /health → GET /api/auth/status（顺序保持）。
/// 2. 检查有问题（格式错 / 连不上 / 非 Hermes）→ CupertinoAlertDialog 弹窗
///    提示具体原因（网络 / 非 Hermes / 格式错误区分），同时就地红字展示。
/// 3. 检查通过且服务端需要密码：就地显示密码框并自动聚焦（不强校验、不
///    保存），用户输入密码后再次点击提交进入阶段二。
/// 4. 阶段二：POST /api/auth/login 校验通过 → 保存 [ServerConnection]
///    （upsert）→ `context.go('/')` 跳会话列表；密码错误 → 弹窗 + 就地红字。
/// 5. 无需密码（auth_enabled=false）：检查通过后直接保存成功，密码框不出现。
/// 6. 校验只由提交按钮驱动，输入框失焦/回车均不再触发任何隐式检查。
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
  // 仅保留密码框焦点节点：阶段一结束后自动聚焦密码框（不再注册失焦监听）。
  final _passwordFocusNode = FocusNode();

  _HealthState _health = _HealthState.idle;
  String _healthMessage = '';
  _AuthState _auth = _AuthState.checking;
  _LoginState _loginState = _LoginState.idle;
  String _loginMessage = '';
  // 提交按钮 loading / 防重入锁：阶段一检查、阶段二验证、保存共用。
  bool _busy = false;

  @override
  void dispose() {
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
  // 提交按钮统一入口（两阶段）
  // ---------------------------------------------------------------------------

  /// 提交入口：按当前认证阶段分流到「阶段一检查」或「阶段二验密保存」。
  Future<void> _onSubmit() async {
    if (_busy) return;
    if (_auth == _AuthState.required) {
      await _verifyPasswordAndSave();
    } else if (_auth == _AuthState.notRequired) {
      // 检查已通过且确认无需密码：直接保存（密码框不出现）。
      await _saveConnection();
    } else {
      await _checkConnection();
    }
  }

  /// 阶段一：格式校验 → GET /health → GET /api/auth/status（顺序保持）。
  ///
  /// 有问题一律弹窗提示具体原因（格式/网络/非 Hermes 区分）+ 就地红字；
  /// 检查通过且需密码 → 就地显示密码框并自动聚焦；无需密码 → 直接保存。
  Future<void> _checkConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final error = _validateUrl(_urlController.text);
    if (error != null) {
      setState(() {
        _busy = false;
        _health = _HealthState.failed;
        _healthMessage = error;
        _auth = _AuthState.checking; // 地址无效时认证区一并隐藏重置
      });
      await _showErrorDialog(l10n.connectionFailed, error);
      return;
    }
    setState(() {
      _health = _HealthState.checking;
      _healthMessage = '';
      _auth = _AuthState.checking;
    });
    try {
      final result = await _buildClient().health();
      if (!mounted) return;
      final ok = result.status == 'ok';
      if (!ok) {
        // 非 Hermes：health 返回非 ok 状态。
        setState(() {
          _busy = false;
          _health = _HealthState.failed;
          _healthMessage = l10n.serverReturnedAbnormalStatus;
          _auth = _AuthState.checking;
        });
        await _showErrorDialog(
          l10n.connectionFailed,
          l10n.serverReturnedAbnormalStatus,
        );
        return;
      }
      setState(() {
        _health = _HealthState.ok;
        _healthMessage = l10n.connectionSuccessful;
      });
      await _resolveAuth();
    } on ApiException catch (error) {
      // 网络类（NetworkException.message 为具体原因）/ HTTP 非 2xx
      // （HttpException.message 为状态码）：弹窗展示具体原因。
      if (!mounted) return;
      setState(() {
        _busy = false;
        _health = _HealthState.failed;
        _healthMessage = error.message;
        _auth = _AuthState.checking;
      });
      await _showErrorDialog(l10n.connectionFailed, error.message);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _health = _HealthState.failed;
        _healthMessage = l10n.cannotConnectToServer;
        _auth = _AuthState.checking;
      });
      await _showErrorDialog(l10n.connectionFailed, l10n.cannotConnectToServer);
    }
  }

  /// 查询服务端认证模式（auth_enabled）；失败按需认证处理（保守）。
  Future<void> _resolveAuth() async {
    try {
      final result = await _buildClient().authStatus();
      if (!mounted) return;
      final enabled = result.authEnabled == true;
      setState(() {
        _auth = enabled ? _AuthState.required : _AuthState.notRequired;
        _busy = false;
      });
      if (enabled) {
        // 阶段一完成：就地显示密码框并自动聚焦，等待用户阶段二提交。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _passwordFocusNode.requestFocus();
        });
      } else {
        await _saveConnection();
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _auth = _AuthState.required;
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocusNode.requestFocus();
      });
    }
  }

  /// 阶段二：POST /api/auth/login 校验 → 通过则保存并跳转；失败弹窗 + 就地红字并存。
  Future<void> _verifyPasswordAndSave() async {
    final l10n = AppLocalizations.of(context);
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _loginState = _LoginState.failed;
        _loginMessage = l10n.passwordRequiredOnServer;
      });
      return;
    }
    setState(() {
      _busy = true;
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
      await _saveConnection();
    } on ApiException catch (error) {
      if (!mounted) return;
      final message = l10n.loginFailedWithMessage(error.message);
      setState(() {
        _busy = false;
        _loginState = _LoginState.failed;
        _loginMessage = message;
      });
      await _showErrorDialog(l10n.loginFailed, message);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loginState = _LoginState.failed;
        _loginMessage = l10n.cannotConnectRetryLater;
      });
      await _showErrorDialog(
        l10n.connectionFailed,
        l10n.cannotConnectRetryLater,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 保存 + 完成
  // ---------------------------------------------------------------------------

  /// 保存连接（upsert + setActive）并跳转会话列表 `/`。
  Future<void> _saveConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);

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

    try {
      final saved = await ref
          .read(connectionsProvider.notifier)
          .upsert(connection);
      await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
      if (!mounted) return;
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showErrorDialog(l10n.connectionFailed, '$error');
    }
  }

  /// CupertinoAlertDialog 错误弹窗（对齐 #19 确认框模式；红色正文）。
  Future<void> _showErrorDialog(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            color: statusRedText.resolveFrom(context),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
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
                  onPressed: _busy ? null : () => unawaited(_onSubmit()),
                  child: _busy
                      ? const CupertinoActivityIndicator()
                      : Text(l10n.connectAndSave),
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
          placeholder: 'https://hermes.example.com:30002',
          autocorrect: false,
          keyboardType: TextInputType.url,
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
          style: TextStyle(
            fontSize: 14,
            color: statusRedText.resolveFrom(context),
          ),
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
          style: TextStyle(
            fontSize: 14,
            color: statusRedText.resolveFrom(context),
          ),
        );
    }
  }
}
