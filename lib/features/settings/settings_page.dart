import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme_provider.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/utils/uuid.dart';
import '../../app/theme/status_colors.dart';
import '../onboarding/onboarding_providers.dart';
import 'settings_providers.dart';

/// 设置页（app_shell_spec.md §3 `/settings`）。
///
/// 四个分组：外观（主题三态）、服务器（当前服务器 + 列表增删改切换）、
/// 模型（默认模型选择 + 推理强度）、关于（版本号）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('设置'),
      ),
      child: ListView(
        children: const [
          _AppearanceSection(),
          _ServerSection(),
          _ModelSection(),
          _AboutSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 外观
// ---------------------------------------------------------------------------

/// 外观分组：主题三态（跟随系统 / 浅色 / 深色，接 [themeModeProvider]）。
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return CupertinoListSection(
      header: const Text('外观'),
      children: [
        CupertinoListTile(
          title: const Text('主题'),
          trailing: CupertinoSlidingSegmentedControl<AppThemeMode>(
            groupValue: mode,
            onValueChanged: (value) {
              if (value != null) {
                unawaited(ref.read(themeModeProvider.notifier).setMode(value));
              }
            },
            children: const {
              AppThemeMode.system: Text('跟随系统'),
              AppThemeMode.light: Text('浅色'),
              AppThemeMode.dark: Text('深色'),
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 服务器
// ---------------------------------------------------------------------------

/// 服务器分组：当前服务器信息 + 服务器列表（切换 / 编辑 / 删除 / 新增）。
class _ServerSection extends ConsumerWidget {
  const _ServerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider);
    final active = ref.watch(activeConnectionProvider);
    return CupertinoListSection(
      header: Text(active == null ? '服务器（未连接）' : '服务器'),
      children: [
        if (connections.isEmpty)
          const CupertinoListTile(
            title: Text('尚未配置服务器'),
            subtitle: Text('点击下方「添加服务器」或从引导页配置'),
          ),
        for (final connection in connections)
          _buildServerRow(context, ref, connection, connection.id == active?.id),
        CupertinoListTile(
          key: const ValueKey('server-add'),
          leading: const Icon(CupertinoIcons.add_circled),
          title: const Text('添加服务器'),
          onTap: () => unawaited(_openServerEditor(context, ref)),
        ),
      ],
    );
  }

  Widget _buildServerRow(
    BuildContext context,
    WidgetRef ref,
    ServerConnection connection,
    bool isActive,
  ) {
    final name = connection.name.isEmpty ? connection.baseUrl : connection.name;
    return CupertinoListTile(
      key: ValueKey('server-row-${connection.id}'),
      title: Text(name),
      subtitle: Text(connection.baseUrl),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            const Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: CupertinoColors.systemBlue,
            ),
          CupertinoButton(
            key: ValueKey('server-edit-${connection.id}'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: () => unawaited(
              _openServerEditor(context, ref, connection: connection),
            ),
            child: const Icon(CupertinoIcons.pencil, size: 18),
          ),
          CupertinoButton(
            key: ValueKey('server-delete-${connection.id}'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: () => unawaited(_confirmDeleteServer(
              context,
              ref,
              connection,
            )),
            child: const Icon(
              CupertinoIcons.trash,
              size: 18,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
      onTap: isActive
          ? null
          : () => unawaited(
                ref.read(activeConnectionProvider.notifier).setActive(
                      connection.id,
                    ),
              ),
    );
  }

  Future<void> _openServerEditor(
    BuildContext context,
    WidgetRef ref, {
    ServerConnection? connection,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => _ServerEditorPage(connection: connection),
      ),
    );
  }

  Future<void> _confirmDeleteServer(
    BuildContext context,
    WidgetRef ref,
    ServerConnection connection,
  ) {
    final name = connection.name.isEmpty ? connection.baseUrl : connection.name;
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除「$name」吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('server-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(
                ref.read(connectionsProvider.notifier).remove(connection.id),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 服务器新增 / 编辑表单（复用 onboarding 的连接字段：名称 / 地址 / 密码）。
class _ServerEditorPage extends ConsumerStatefulWidget {
  const _ServerEditorPage({this.connection});

  /// 非 null = 编辑模式（保留 id / username / customHeaders / createdAt）。
  final ServerConnection? connection;

  @override
  ConsumerState<_ServerEditorPage> createState() => _ServerEditorPageState();
}

class _ServerEditorPageState extends ConsumerState<_ServerEditorPage> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.connection?.name ?? '',
  );
  late final TextEditingController _urlController = TextEditingController(
    text: widget.connection?.baseUrl ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.connection?.password ?? '',
  );

  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validate() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return '请输入服务器地址';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入有效的服务器地址，例如 https://hermes.example.com:30002';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    final url = _urlController.text.trim();
    final host = Uri.tryParse(url)?.host;
    final existing = widget.connection;
    // 编辑时密码留空 = 保留原密码；新增时留空 = 无密码。
    final password =
        _passwordController.text.isEmpty ? existing?.password : _passwordController.text;
    // 有密码 → 先登录种会话 cookie（否则保存后会话列表必 401「密码被拒绝」）；
    // 登录失败 → 报错并停留，不保存无效配置。
    if (password != null && password.isNotEmpty) {
      final loginError = await _tryLogin(url, password, existing);
      if (loginError != null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = loginError;
        });
        return;
      }
    }
    final connection = ServerConnection(
      id: existing?.id ?? uuidV4(),
      name: _nameController.text.trim().isEmpty
          ? (host == null || host.isEmpty ? url : host)
          : _nameController.text.trim(),
      baseUrl: url,
      username: existing?.username,
      password: password,
      customHeaders: existing?.customHeaders ?? const {},
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
    );
    await ref.read(connectionsProvider.notifier).upsert(connection);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 用 [url] + [password] 调登录接口种 cookie；返回错误文案，null = 成功。
  Future<String?> _tryLogin(
    String url,
    String password,
    ServerConnection? existing,
  ) async {
    final factory = ref.read(onboardingApiFactoryProvider);
    final api = factory(url, [
      for (final entry in (existing?.customHeaders ?? const <String, String>{}).entries)
        CustomHeader(name: entry.key, value: entry.value),
    ]);
    try {
      await api.login(password);
      return null;
    } on ApiException catch (error) {
      return '登录失败：${error.message}';
    } on Exception {
      return '无法连接到服务器，请稍后重试';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.connection != null;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        middle: Text(isEditing ? '编辑服务器' : '添加服务器'),
        trailing: CupertinoButton(
          key: const ValueKey('server-editor-save'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CupertinoTextField(
              key: const ValueKey('server-editor-name'),
              controller: _nameController,
              placeholder: '名称（可选，默认使用主机名）',
              autocorrect: false,
              padding: const EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              key: const ValueKey('server-editor-url'),
              controller: _urlController,
              placeholder: 'https://hermes.example.com:30002',
              autocorrect: false,
              keyboardType: TextInputType.url,
              padding: const EdgeInsets.all(12),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              key: const ValueKey('server-editor-password'),
              controller: _passwordController,
              placeholder: '密码（可选；编辑时留空保持原密码）',
              obscureText: true,
              padding: const EdgeInsets.all(12),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error,
                  style: const TextStyle(color: statusRedText),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 模型
// ---------------------------------------------------------------------------

/// 模型分组：默认模型（选择器）+ 推理强度（服务器支持时显示）。
class _ModelSection extends ConsumerWidget {
  const _ModelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return settings.when(
      loading: () => CupertinoListSection(
        header: const Text('模型'),
        children: const [
          CupertinoListTile(
            title: Text('正在加载模型…'),
            trailing: CupertinoActivityIndicator(),
          ),
        ],
      ),
      error: (error, _) => CupertinoListSection(
        header: const Text('模型'),
        children: [
          CupertinoListTile(
            title: const Text('模型加载失败'),
            subtitle: Text(_describeError(error)),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-models-retry'),
            title: const Text('重试'),
            trailing: const Icon(CupertinoIcons.refresh),
            onTap: () => unawaited(
              ref.read(settingsControllerProvider.notifier).refresh(),
            ),
          ),
        ],
      ),
      data: (state) => CupertinoListSection(
        header: const Text('模型'),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-default-model'),
            title: const Text('默认模型'),
            subtitle: Text(state.defaultModelLabel ?? '未设置'),
            trailing: const Icon(CupertinoIcons.chevron_right),
            onTap: () => unawaited(_openModelPicker(context, ref, state)),
          ),
          if (state.supportsReasoningEffort &&
              state.supportedEfforts.isNotEmpty)
            CupertinoListTile(
              key: const ValueKey('settings-reasoning'),
              title: const Text('推理强度'),
              subtitle: Text(state.reasoningEffort ?? '未设置'),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: () => unawaited(
                _openReasoningPicker(context, ref, state),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openModelPicker(
    BuildContext context,
    WidgetRef ref,
    SettingsState state,
  ) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => _ModelPickerPage(state: state),
      ),
    );
  }

  Future<void> _openReasoningPicker(
    BuildContext context,
    WidgetRef ref,
    SettingsState state,
  ) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('推理强度'),
        actions: [
          for (final effort in state.supportedEfforts)
            CupertinoActionSheetAction(
              key: ValueKey('reasoning-$effort'),
              isDefaultAction: effort == state.reasoningEffort,
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  ref
                      .read(settingsControllerProvider.notifier)
                      .setReasoningEffort(effort),
                );
              },
              child: Text(effort),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 默认模型选择页：按 provider 分组列出全部模型，选中即保存并返回。
class _ModelPickerPage extends ConsumerWidget {
  const _ModelPickerPage({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = state.modelGroups;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        leading: _PopBackButton(),
        middle: Text('默认模型'),
      ),
      child: groups.isEmpty
          ? const Center(child: Text('暂无可用模型'))
          : ListView(
              children: [
                for (final group in groups)
                  CupertinoListSection(
                    header: Text(group.name),
                    children: [
                      for (final model in [...group.models, ...group.extraModels])
                        CupertinoListTile(
                          key: ValueKey('model-option-${model.id}'),
                          title: Text(model.displayName),
                          trailing: model.id == state.defaultModel
                              ? const Icon(CupertinoIcons.checkmark)
                              : null,
                          onTap: () {
                            Navigator.of(context).pop();
                            unawaited(
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .setDefaultModel(model.id),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 关于
// ---------------------------------------------------------------------------

/// 返回按钮：显式 [CupertinoNavigationBarBackButton.onPressed]，
/// 避免框架「仅可用于可 pop 路由」断言在首帧/测试环境误触发。
class _PopBackButton extends StatelessWidget {
  const _PopBackButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBarBackButton(
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

/// 关于分组：应用名 + 版本号。
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection(
      header: const Text('关于'),
      children: const [
        CupertinoListTile(
          title: Text('Hermex'),
          subtitle: Text('Hermes WebUI 客户端'),
        ),
        CupertinoListTile(
          title: Text('版本'),
          trailing: Text(
            appVersion,
            style: TextStyle(color: CupertinoColors.secondaryLabel),
          ),
        ),
      ],
    );
  }
}

/// 统一错误文案：ApiException 展示其消息，其余给通用提示。
String _describeError(Object error) {
  if (error is ApiException) return error.message;
  return '加载失败，请重试';
}
