import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../app/theme/theme_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/models/server_catalog.dart';
import '../../core/utils/accessibility.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../onboarding/onboarding_providers.dart';
import '../session_list/session_list_providers.dart';
import '../shared/app_back_button.dart';
import 'cron_visibility_settings.dart';
import 'injected_notice_settings.dart';
import 'settings_providers.dart';
import 'settings_subpages.dart';
import 'tool_group_settings.dart';

/// 设置页（app_shell_spec.md §3 `/settings`）。
///
/// 首页分组：外观 / 对话 / 服务器 / 模型 / 定时会话 / 二级入口组（辅助模型、MCP、扩展、
/// 会话列表入口、会话行信息、桌面）/ 关于。
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
          _ChatSection(),
          _ServerSection(),
          _ModelSection(),
          _CronSection(),
          _AdvancedSettingsSection(),
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
        CupertinoListTile(
          key: const ValueKey('settings-collapse-injected-notices'),
          title: Text(l10n.collapseInjectedNoticesLabel),
          subtitle: Text(l10n.collapseInjectedNoticesDescription),
          trailing: CupertinoSwitch(
            value: ref.watch(injectedNoticeSettingsProvider).collapseInjectedNotices,
            onChanged: (value) {
              unawaited(
                ref.read(injectedNoticeSettingsProvider.notifier).setCollapse(value),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 对话
// ---------------------------------------------------------------------------

/// 对话设置分组：工具调用按回合聚合开关。
class _ChatSection extends ConsumerWidget {
  const _ChatSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final coalesce = ref.watch(toolGroupCoalesceProvider);
    return CupertinoListSection(
      header: Text(l10n.chatSection),
      children: [
        CupertinoListTile(
          key: const ValueKey('settings-group-tools-by-turn'),
          title: Text(l10n.groupToolsByTurn),
          subtitle: Text(l10n.groupToolsByTurnDesc),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-switch-group-tools-by-turn'),
            value: coalesce,
            onChanged: (value) {
              unawaited(
                ref.read(toolGroupCoalesceProvider.notifier).setCoalesce(value),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 二级入口组（高级设置）
// ---------------------------------------------------------------------------

/// 二级入口分组：辅助模型 / MCP 服务器 / 扩展 / 会话列表入口 / 会话行信息 / 桌面。
class _AdvancedSettingsSection extends StatelessWidget {
  const _AdvancedSettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection(
      header: Text(l10n.advancedSettingsSection),
      children: [
        CupertinoListTile(
          key: const ValueKey('settings-entry-auxiliary'),
          title: Text(l10n.auxiliaryModelsSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const AuxiliaryModelsPage(),
            ),
          ),
        ),
        CupertinoListTile(
          key: const ValueKey('settings-entry-mcp'),
          title: Text(l10n.mcpSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const McpPage(),
            ),
          ),
        ),
        CupertinoListTile(
          key: const ValueKey('settings-entry-extensions'),
          title: Text(l10n.extensionsSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const ExtensionsPage(),
            ),
          ),
        ),
        CupertinoListTile(
          key: const ValueKey('settings-entry-session-list-entries'),
          title: Text(l10n.sessionListEntriesSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const SessionListEntriesPage(),
            ),
          ),
        ),
        CupertinoListTile(
          key: const ValueKey('settings-entry-session-row-subtitle'),
          title: Text(l10n.sessionRowSubtitleSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const SessionRowSubtitlePage(),
            ),
          ),
        ),
        CupertinoListTile(
          key: const ValueKey('settings-entry-desktop'),
          title: Text(l10n.desktopSection),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const DesktopSettingsPage(),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 定时会话
// ---------------------------------------------------------------------------

/// 定时会话显隐设置分组（TASK W3）。
class _CronSection extends ConsumerWidget {
  const _CronSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final showCron = ref.watch(cronVisibilityProvider).showCron;
    return CupertinoListSection(
      children: [
        CupertinoListTile(
          key: const ValueKey('settings-show-cron-sessions'),
          title: Text(l10n.showCronSessionsTitle),
          subtitle: Text(l10n.showCronSessionsSubtitle),
          trailing: CupertinoSwitch(
            key: const ValueKey('settings-switch-show-cron'),
            value: showCron,
            onChanged: (value) {
              unawaited(
                ref.read(cronVisibilityProvider.notifier).setShowCron(value),
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

/// 服务器新增 / 编辑表单（复用 onboarding 的连接字段：名称 / 地址 / 密码 + Profile 管理）。
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

  ProfilesResponse? _profiles;
  Object? _profileError;
  bool _loadingProfiles = false;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null && widget.connection!.baseUrl.isNotEmpty) {
      unawaited(_loadProfiles());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ApiClient _getClient() {
    final active = ref.read(activeConnectionProvider);
    if (widget.connection != null && widget.connection!.id == active?.id) {
      return ref.read(apiClientProvider);
    }
    final url = widget.connection?.baseUrl ?? _urlController.text.trim();
    final headers = [
      for (final entry
          in (widget.connection?.customHeaders ?? const <String, String>{})
              .entries)
        CustomHeader(name: entry.key, value: entry.value),
    ];
    final factory = ref.read(serverEditorApiClientFactoryProvider);
    return factory(url, headers);
  }

  Future<void> _loadProfiles() async {
    final url = widget.connection?.baseUrl ?? _urlController.text.trim();
    if (url.isEmpty || !mounted) return;
    setState(() {
      _loadingProfiles = true;
      _profileError = null;
    });
    try {
      final client = _getClient();
      final response = await client.profiles();
      if (mounted) setState(() => _profiles = response);
    } catch (error) {
      if (mounted) setState(() => _profileError = error);
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  Future<void> _switchProfile(ProfileSummary profile) async {
    final name = profile.name ?? '';
    if (name.isEmpty || name == _profiles?.active) return;
    setState(() => _loadingProfiles = true);
    try {
      final client = _getClient();
      final response = await client.switchProfile(name);
      if (mounted) {
        setState(() => _profiles = response.toProfilesResponse(name));
        final active = ref.read(activeConnectionProvider);
        if (widget.connection != null && widget.connection!.id == active?.id) {
          ref.invalidate(sessionListControllerProvider);
        }
      }
    } catch (error) {
      if (mounted) await _showProfileError(error);
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  Future<void> _showProfileError(Object error) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.profileSwitchFailed),
        content: Text(
          error is ApiException ? error.message : '$error',
          style: TextStyle(color: statusRedText.resolveFrom(context)),
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

  Future<void> _showProfilePicker(List<ProfileSummary> profiles) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showCupertinoModalPopup<ProfileSummary>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l10n.selectProfile),
        actions: [
          for (final profile in profiles)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, profile),
              child: Text(profile.name ?? l10n.unnamed),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (selected != null) await _switchProfile(selected);
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
    final profiles = _profiles?.profiles ?? const <ProfileSummary>[];
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const _PopBackButton(),
        middle: Text(isEditing ? l10n.editServer : l10n.addServer),
        trailing: Align(
          alignment: Alignment.centerRight,
          child: CupertinoButton(
            key: const ValueKey('server-editor-save'),
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onPressed: _saving ? null : () => unawaited(_save()),
            child: Text(
              l10n.save,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection(
              header: Text(l10n.serverBasicInfoSection),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.serverNameLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CupertinoTextField(
                        key: const ValueKey('server-editor-name'),
                        controller: _nameController,
                        placeholder: l10n.serverNamePlaceholder,
                        autocorrect: false,
                        padding: const EdgeInsets.all(12),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.serverUrlLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CupertinoTextField(
                        key: const ValueKey('server-editor-url'),
                        controller: _urlController,
                        placeholder: 'https://hermes.example.com:30002',
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        padding: const EdgeInsets.all(12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.serverUrlExampleHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.serverPasswordLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
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
                            style: TextStyle(color: statusRedText.resolveFrom(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            CupertinoListSection(
              header: Text(l10n.profile),
              children: [
                CupertinoListTile(
                  key: const ValueKey('server-editor-profile-tile'),
                  title: Text(
                    _profiles?.active ??
                        (_loadingProfiles
                            ? l10n.loadingEllipsis
                            : l10n.notRead),
                  ),
                  leading: const Icon(CupertinoIcons.person_2),
                  trailing: const CupertinoListTileChevron(),
                  onTap: profiles.isEmpty
                      ? _loadProfiles
                      : () => _showProfilePicker(profiles),
                ),
                if (_profileError != null)
                  CupertinoListTile(
                    key: const ValueKey('server-editor-profile-retry'),
                    title: Text(l10n.readFailed),
                    subtitle: Text(l10n.clickToRetry),
                    onTap: _loadProfiles,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on ProfileSwitchResponse {
  ProfilesResponse toProfilesResponse(String fallback) => ProfilesResponse(
        profiles: profiles,
        active: active ?? fallback,
      );
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
          trailing: Text(
            appVersion,
            style: TextStyle(color: secondaryText.resolveFrom(context)),
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
