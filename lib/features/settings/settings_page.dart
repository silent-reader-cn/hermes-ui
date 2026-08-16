import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme_provider.dart';

/// 设置页（Phase 3 扩展；当前含主题三态切换，服务器管理后续补充）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('设置'),
      ),
      child: CupertinoListSection(
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
      ),
    );
  }
}
