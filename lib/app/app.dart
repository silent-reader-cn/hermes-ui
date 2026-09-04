import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/desktop/desktop_lifecycle_observer.dart';
import '../features/notifications/notification_lifecycle_observer.dart';
import '../features/session_list/session_auto_refresh.dart';
import '../l10n/app_localizations.dart';
import 'locale/locale_provider.dart';
import 'router.dart';
import 'theme/cupertino_theme.dart';
import 'theme/theme_provider.dart';

/// 根 Widget（app_shell_spec.md §2.2）。
///
/// 纯 Cupertino 壳：深浅色主题（跟随系统 + 手动三态）、go_router 路由表、
/// 中英本地化。桌面端窗口标题 'Hermes'，移动端状态栏样式随系统。
///
/// 注：CupertinoApp 不支持 `darkTheme`/`themeMode` 参数（MaterialApp 专属），
/// 深浅色在这里按三态模式 + 系统亮度手工解析出单一 [CupertinoThemeData]。
class HermesApp extends ConsumerWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final localeMode = ref.watch(localeModeProvider);
    final router = ref.watch(routerProvider);
    final brightness = switch (themeMode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final locale = switch (localeMode) {
      AppLocaleMode.system => null,
      AppLocaleMode.zh => const Locale('zh'),
      AppLocaleMode.en => const Locale('en'),
    };
    return DesktopLifecycleObserver(
      child: WindowFocusObserver(
        child: NotificationLifecycleObserver(
          child: CupertinoApp.router(
          title: 'Hermes',
          theme: buildCupertinoTheme(brightness),
          routerConfig: router,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          ),
        ),
      ),
    );
  }
}
