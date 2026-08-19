import 'package:flutter/widgets.dart';

/// Lightweight localization facade for business text.
///
/// The initial catalog keeps Chinese as the product default and provides
/// English fallbacks without forcing a generated-l10n migration on every page.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;
  bool get isEnglish => locale.languageCode == 'en';

  String get settings => isEnglish ? 'Settings' : '设置';
  String get profile => isEnglish ? 'Profile' : 'Profile';
  String get export => isEnglish ? 'Export' : '导出';
  String get cancel => isEnglish ? 'Cancel' : '取消';
  String get ok => isEnglish ? 'OK' : '好';
  String get loading => isEnglish ? 'Loading…' : '加载中…';
  String get offlineCache => isEnglish ? 'Offline cache' : '离线缓存';
  String get desktop => isEnglish ? 'Desktop' : '桌面';
  String get minimizeToTray => isEnglish ? 'Minimize to Tray' : '最小化到托盘';
  String get minimizeToTraySubtitle => isEnglish
      ? 'Hide to tray instead of quitting when closing window'
      : '关闭窗口时隐藏到托盘而非退出';
  String get globalShortcuts => isEnglish ? 'Global Shortcuts' : '全局快捷键';
  String get globalShortcutsSubtitle => isEnglish
      ? 'Ctrl+Shift+H show window, Ctrl+Shift+N new session'
      : 'Ctrl+Shift+H 唤起主窗口，Ctrl+Shift+N 新建会话';
  String get rememberWindowPosition =>
      isEnglish ? 'Remember Window Position' : '记住窗口位置';
  String get rememberWindowPositionSubtitle =>
      isEnglish ? 'Restore window size and position on startup' : '启动时恢复上次窗口位置与尺寸';

  static AppLocalizations of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return AppLocalizations(locale);
  }
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => const ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
