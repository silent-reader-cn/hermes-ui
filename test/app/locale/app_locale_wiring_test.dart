import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_secure_storage.dart';

class FakeLocaleModeController extends LocaleModeController {
  FakeLocaleModeController(this.initialMode);
  final AppLocaleMode initialMode;

  @override
  AppLocaleMode build() => initialMode;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    enableSessionAutoRefresh = false;
  });

  tearDown(() {
    enableSessionAutoRefresh = true;
  });

  Widget buildAppWithMode(AppLocaleMode mode) {
    final storage = InMemorySecureStorage();
    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: storage),
        ),
        localeModeProvider.overrideWith(() => FakeLocaleModeController(mode)),
      ],
      child: const HermesApp(),
    );
  }

  testWidgets('app.dart 接线：override mode=zh → Localizations.localeOf 得 zh',
      (tester) async {
    await tester.pumpWidget(buildAppWithMode(AppLocaleMode.zh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final navElement = tester.element(find.byType(Navigator).first);
    final locale = Localizations.localeOf(navElement);
    expect(locale.languageCode, 'zh');
  });

  testWidgets('app.dart 接线：override mode=en → Localizations.localeOf 得 en',
      (tester) async {
    await tester.pumpWidget(buildAppWithMode(AppLocaleMode.en));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final navElement = tester.element(find.byType(Navigator).first);
    final locale = Localizations.localeOf(navElement);
    expect(locale.languageCode, 'en');
  });

  testWidgets(
      'app.dart 接线：override mode=system + 模拟 platform locale en → Localizations.localeOf 得 en',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(() => tester.platformDispatcher.clearLocalesTestValue());

    await tester.pumpWidget(buildAppWithMode(AppLocaleMode.system));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final navElement = tester.element(find.byType(Navigator).first);
    final locale = Localizations.localeOf(navElement);
    expect(locale.languageCode, 'en');
  });

  testWidgets(
      'app.dart 接线：override mode=system + 模拟 platform locale zh → Localizations.localeOf 得 zh',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('zh', 'CN')];
    addTearDown(() => tester.platformDispatcher.clearLocalesTestValue());

    await tester.pumpWidget(buildAppWithMode(AppLocaleMode.system));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final navElement = tester.element(find.byType(Navigator).first);
    final locale = Localizations.localeOf(navElement);
    expect(locale.languageCode, 'zh');
  });
}
