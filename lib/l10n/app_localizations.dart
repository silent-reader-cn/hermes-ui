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
