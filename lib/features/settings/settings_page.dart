import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/status_colors.dart';
import '../../app/theme/theme_provider.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../desktop/desktop_settings.dart';
import '../onboarding/onboarding_providers.dart';
import '../session_list/session_entry_visibility.dart';
import '../session_list/session_row_subtitle_settings.dart';
import '../shared/app_back_button.dart';
import 'profile_section.dart';
import 'settings_providers.dart';

/// 设置页（app_shell_spec.md §3 `/settings`）。
///
/// 分组：外观（主题三态）、会话列表入口（功能入口显隐）、桌面（平台能力开关）、
/// 服务器（当前服务器 + 列表增删改切换）、模型（默认模型选择 + 推理强度）、关于（版本号）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const AppBackButton(),
        middle: Text(l10n.settingsTitle),
      ),
      child: ListView(
        children: const [
          _AppearanceSection(),
          _ServerSection(),
          ProfileSection(),
          _ModelSection(),
          _DesktopSection(),
          _SessionListEntriesSection(),
          _SessionRowSubtitleSection(),
          _MemoryEntrySection(),
          _WorkspacesEntrySection(),
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
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeProvider);
    return CupertinoListSection(
      header: Text(l10n.appearanceSection),
      children: [
        CupertinoListTile(
          title: Text(l10n.themeLabel),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CupertinoSlidingSegmentedControl<AppThemeMode>(
                groupValue: mode,
                onValueChanged: (value) {
                  if (value != null) {
                    unawaited(
                      ref.read(themeModeProvider.notifier).setMode(value),
                    );
                  }
                },
                children: {
                  AppThemeMode.system: Text(l10n.themeSystem),
                  AppThemeMode.light: Text(l10n.themeLight),
                  AppThemeMode.dark: Text(l10n.themeDark),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 会话列表入口
// ---------------------------------------------------------------------------

/// 会话列表入口显隐分组（TASK W5 / 蓝本 SidebarSectionVisibility）。
class _SessionListEntriesSection extends ConsumerWidget {
  const _SessionListEntriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    final controller = ref.read(sessionEntryVisibilityProvider.notifier);

    return CupertinoListSection(
      header: Text(l10n.sessionListEntriesSection),
      children: [
        CupertinoListTile(
          title: Text(l10n.tasksTitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-visibility-tasks'),
            value: visibility.tasks,
            onChanged: (value) {
              unawaited(controller.setVisible('tasks', value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.kanbanTitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-visibility-kanban'),
            value: visibility.kanban,
            onChanged: (value) {
              unawaited(controller.setVisible('kanban', value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.skillsTitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-visibility-skills'),
            value: visibility.skills,
            onChanged: (value) {
              unawaited(controller.setVisible('skills', value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.insightsTitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-visibility-insights'),
            value: visibility.insights,
            onChanged: (value) {
              unawaited(controller.setVisible('insights', value));
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 会话行信息
// ---------------------------------------------------------------------------

/// 会话行信息分组：会话行副标题显示项开关（消息数 / 项目名 / 工作区 /
/// 渠道 / 预估价钱；渠道与预估价钱默认关闭）。
class _SessionRowSubtitleSection extends ConsumerWidget {
  const _SessionRowSubtitleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(sessionRowSubtitleSettingsProvider);
    final controller = ref.read(sessionRowSubtitleSettingsProvider.notifier);

    return CupertinoListSection(
      header: Text(l10n.sessionRowSubtitleSection),
      children: [
        CupertinoListTile(
          title: Text(l10n.sessionRowShowMessageCount),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-subtitle-message-count'),
            value: settings.messageCount,
            onChanged: (value) {
              unawaited(controller.setMessageCount(value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.sessionRowShowProjectName),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-subtitle-project-name'),
            value: settings.projectName,
            onChanged: (value) {
              unawaited(controller.setProjectName(value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.sessionRowShowWorkspace),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-subtitle-workspace'),
            value: settings.workspace,
            onChanged: (value) {
              unawaited(controller.setWorkspace(value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.sessionRowShowChannel),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-subtitle-channel'),
            value: settings.channel,
            onChanged: (value) {
              unawaited(controller.setChannel(value));
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.sessionRowShowEstimatedCost),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-subtitle-estimated-cost'),
            value: settings.estimatedCost,
            onChanged: (value) {
              unawaited(controller.setEstimatedCost(value));
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 记忆入口
// ---------------------------------------------------------------------------

/// 记忆入口分组：记忆页使用频率低，入口从会话工具行移至设置页
/// （2026-08 主人指示），点击进入 `/memory`。
class _MemoryEntrySection extends ConsumerWidget {
  const _MemoryEntrySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection(
      children: [
        CupertinoListTile(
          key: const ValueKey('settings-memory-entry'),
          title: Text(l10n.memoryTitle),
          subtitle: Text(l10n.memoryEntrySubtitle),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => context.go('/memory'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 工作区管理入口
// ---------------------------------------------------------------------------

/// 工作区管理入口分组：工作区注册表（添加/重命名/移除 + 文件浏览），
/// 点击进入 `/workspaces`。
class _WorkspacesEntrySection extends ConsumerWidget {
  const _WorkspacesEntrySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection(
      children: [
        CupertinoListTile(
          key: const ValueKey('settings-workspaces-entry'),
          title: Text(l10n.manageWorkspaces),
          subtitle: Text(l10n.manageWorkspacesSubtitle),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => context.push('/workspaces'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面
// ---------------------------------------------------------------------------

/// 桌面分组：最小化到托盘 / 全局快捷键 / 记住窗口位置。
class _DesktopSection extends ConsumerWidget {
  const _DesktopSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(desktopSettingsProvider);
    return CupertinoListSection(
      header: Text(l10n.desktopSection),
      children: [
        CupertinoListTile(
          title: Text(l10n.minimizeToTray),
          subtitle: Text(l10n.minimizeToTraySubtitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-desktop-minimize-to-tray'),
            value: settings.minimizeToTray,
            onChanged: (value) {
              unawaited(
                ref
                    .read(desktopSettingsProvider.notifier)
                    .setMinimizeToTray(value),
              );
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.globalShortcuts),
          subtitle: Text(l10n.globalShortcutsSubtitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-desktop-global-shortcuts'),
            value: settings.globalShortcutsEnabled,
            onChanged: (value) {
              unawaited(
                ref
                    .read(desktopSettingsProvider.notifier)
                    .setGlobalShortcutsEnabled(value),
              );
            },
          ),
        ),
        CupertinoListTile(
          title: Text(l10n.rememberWindowPosition),
          subtitle: Text(l10n.rememberWindowPositionSubtitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-desktop-remember-window'),
            value: settings.rememberWindowPosition,
            onChanged: (value) {
              unawaited(
                ref
                    .read(desktopSettingsProvider.notifier)
                    .setRememberWindowPosition(value),
              );
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
    final l10n = AppLocalizations.of(context);
    final connections = ref.watch(connectionsProvider);
    final active = ref.watch(activeConnectionProvider);
    return CupertinoListSection(
      header: Text(
        active == null ? l10n.serverSectionDisconnected : l10n.serverSection,
      ),
      children: [
        if (connections.isEmpty)
          CupertinoListTile(
            title: Text(l10n.noServerConfigured),
            subtitle: Text(l10n.noServerConfiguredSubtitle),
          ),
        for (final connection in connections)
          _buildServerRow(
            context,
            ref,
            connection,
            connection.id == active?.id,
          ),
        CupertinoListTile(
          key: const ValueKey('server-add'),
          leading: const Icon(CupertinoIcons.add_circled),
          title: Text(l10n.addServer),
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
    final l10n = AppLocalizations.of(context);
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
          AccessibleButton(
            key: ValueKey('server-edit-${connection.id}'),
            label: l10n.editServer,
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: () => unawaited(
              _openServerEditor(context, ref, connection: connection),
            ),
            child: const Icon(CupertinoIcons.pencil, size: 18),
          ),
          AccessibleButton(
            key: ValueKey('server-delete-${connection.id}'),
            label: l10n.deleteServer,
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: () =>
                unawaited(_confirmDeleteServer(context, ref, connection)),
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
              ref
                  .read(activeConnectionProvider.notifier)
                  .setActive(connection.id),
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
    final l10n = AppLocalizations.of(context);
    final name = connection.name.isEmpty ? connection.baseUrl : connection.name;
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.deleteServer),
        content: Text(l10n.confirmDeleteServer(name)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
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
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    if (url.isEmpty) return l10n.serverUrlRequired;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return l10n.serverUrlInvalid;
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
    final password = _passwordController.text.isEmpty
        ? existing?.password
        : _passwordController.text;
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
    final l10n = AppLocalizations.of(context);
    final factory = ref.read(onboardingApiFactoryProvider);
    final api = factory(url, [
      for (final entry
          in (existing?.customHeaders ?? const <String, String>{}).entries)
        CustomHeader(name: entry.key, value: entry.value),
    ]);
    try {
      await api.login(password);
      return null;
    } on ApiException catch (error) {
      return l10n.loginFailedWithMessage(error.message);
    } on Exception {
      return l10n.cannotConnectToServer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.connection != null;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        middle: Text(isEditing ? l10n.editServer : l10n.addServer),
        trailing: CupertinoButton(
          key: const ValueKey('server-editor-save'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(l10n.save),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CupertinoTextField(
              key: const ValueKey('server-editor-name'),
              controller: _nameController,
              placeholder: l10n.serverNamePlaceholder,
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
              placeholder: l10n.serverPasswordPlaceholder,
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
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    return settings.when(
      loading: () => CupertinoListSection(
        header: Text(l10n.models),
        children: [
          CupertinoListTile(
            title: Text(l10n.loadingModels),
            trailing: const CupertinoActivityIndicator(),
          ),
        ],
      ),
      error: (error, _) => CupertinoListSection(
        header: Text(l10n.models),
        children: [
          CupertinoListTile(
            title: Text(l10n.modelsLoadFailed),
            subtitle: Text(_describeError(context, error)),
          ),
          CupertinoListTile(
            key: const ValueKey('settings-models-retry'),
            title: Text(l10n.retry),
            trailing: const Icon(CupertinoIcons.refresh),
            onTap: () => unawaited(
              ref.read(settingsControllerProvider.notifier).refresh(),
            ),
          ),
        ],
      ),
      data: (state) => CupertinoListSection(
        header: Text(l10n.models),
        children: [
          CupertinoListTile(
            key: const ValueKey('settings-default-model'),
            title: Text(l10n.defaultModel),
            subtitle: Text(state.defaultModelLabel ?? l10n.notSet),
            trailing: const Icon(CupertinoIcons.chevron_right),
            onTap: () => unawaited(_openModelPicker(context, ref, state)),
          ),
          if (state.supportsReasoningEffort &&
              state.supportedEfforts.isNotEmpty)
            CupertinoListTile(
              key: const ValueKey('settings-reasoning'),
              title: Text(l10n.reasoningEffort),
              subtitle: Text(state.reasoningEffort ?? l10n.notSet),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: () => unawaited(_openReasoningPicker(context, ref, state)),
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
    final l10n = AppLocalizations.of(context);
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(l10n.reasoningEffort),
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
            child: Text(l10n.cancel),
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
    final l10n = AppLocalizations.of(context);
    final groups = state.modelGroups;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const _PopBackButton(),
        middle: Text(l10n.defaultModel),
      ),
      child: groups.isEmpty
          ? Center(child: Text(l10n.noAvailableModels))
          : ListView(
              children: [
                for (final group in groups)
                  CupertinoListSection(
                    header: Text(group.name),
                    children: [
                      for (final model in [
                        ...group.models,
                        ...group.extraModels,
                      ])
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
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection(
      header: Text(l10n.aboutSection),
      children: [
        CupertinoListTile(
          title: const Text('Hermex'),
          subtitle: Text(l10n.hermesWebUIClient),
        ),
        CupertinoListTile(
          title: Text(l10n.version),
          trailing: const Text(
            appVersion,
            style: TextStyle(color: secondaryText),
          ),
        ),
      ],
    );
  }
}

/// 统一错误文案：ApiException 展示其消息，其余给通用提示。
String _describeError(BuildContext context, Object error) {
  if (error is ApiException) return error.message;
  return AppLocalizations.of(context).loadFailedRetry;
}
