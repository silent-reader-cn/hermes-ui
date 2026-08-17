import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/server_catalog.dart';
import '../session_list/session_list_providers.dart';

/// Profile 管理区块：服务端 profile 与本地服务器是两个独立概念。
class ProfileSection extends ConsumerStatefulWidget {
  const ProfileSection({super.key});

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  ProfilesResponse? _profiles;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await ref.read(apiClientProvider).profiles();
      final map = raw is Map<String, Object?> ? raw : <String, Object?>{};
      if (mounted) setState(() => _profiles = ProfilesResponse.fromJson(map));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switch(ProfileSummary profile) async {
    final name = profile.name ?? '';
    if (name.isEmpty || name == _profiles?.active) return;
    setState(() => _loading = true);
    try {
      final raw = await ref.read(apiClientProvider).switchProfile(name);
      final map = raw is Map<String, Object?> ? raw : <String, Object?>{};
      if (mounted) {
        setState(() => _profiles = ProfileSwitchResponse.fromJson(map).toProfilesResponse(name));
        ref.invalidate(sessionListControllerProvider);
      }
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showError(Object error) => showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Profile 切换失败'),
          content: Text(
            error is ApiException ? error.message : '$error',
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('好'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles?.profiles ?? const <ProfileSummary>[];
    return CupertinoListSection(
      header: const Text('Profile'),
      children: [
        CupertinoListTile(
          title: Text(_profiles?.active ?? (_loading ? '加载中…' : '未读取')),
          leading: const Icon(CupertinoIcons.person_2),
          trailing: const CupertinoListTileChevron(),
          onTap: profiles.isEmpty ? _load : () => _showPicker(profiles),
        ),
        if (_error != null)
          CupertinoListTile(
            title: const Text('读取失败'),
            subtitle: const Text('点击重试'),
            onTap: _load,
          ),
      ],
    );
  }

  Future<void> _showPicker(List<ProfileSummary> profiles) async {
    final selected = await showCupertinoModalPopup<ProfileSummary>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('选择 Profile'),
        actions: [
          for (final profile in profiles)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, profile),
              child: Text(profile.name ?? '未命名'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) await _switch(selected);
  }
}

extension on ProfileSwitchResponse {
  ProfilesResponse toProfilesResponse(String fallback) => ProfilesResponse(
        profiles: profiles,
        active: active ?? fallback,
      );
}
