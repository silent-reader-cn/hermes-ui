import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

void main() {
  group('AppLocalizationsUpdate101', () {
    test('zh locale returns correct Chinese strings', () {
      const l10n = AppLocalizations(Locale('zh'));
      expect(l10n.updateSectionTitle, '软件更新');
      expect(l10n.currentVersionLabel, '当前版本');
      expect(l10n.autoCheckUpdateLabel, '自动检查更新');
      expect(l10n.checkUpdateNowLabel, '检查更新');
      expect(l10n.checkingForUpdate, '正在检查更新…');
      expect(l10n.updateAlreadyLatest, '已是最新版本');
      expect(l10n.updateCheckFailed, '检查更新失败，请稍后重试');
      expect(l10n.updateDialogTitle('v0.1.31'), '发现新版本 v0.1.31');
      expect(l10n.updateGoToDownload, '前往下载');
      expect(l10n.updateDownloadingStarted, '已加入下载队列，可在下载管理中查看进度');
      expect(l10n.updateInstallNow, '立即安装');
      expect(l10n.updateReadyToInstall, '新版本已下载完成，是否立即安装？');
    });

    test('en locale returns correct English strings', () {
      const l10n = AppLocalizations(Locale('en'));
      expect(l10n.updateSectionTitle, 'Software Update');
      expect(l10n.currentVersionLabel, 'Current Version');
      expect(l10n.autoCheckUpdateLabel, 'Auto-check for Updates');
      expect(l10n.checkUpdateNowLabel, 'Check for Updates');
      expect(l10n.checkingForUpdate, 'Checking for updates…');
      expect(l10n.updateAlreadyLatest, 'Already up to date');
      expect(l10n.updateCheckFailed, 'Failed to check for updates, please try again later');
      expect(l10n.updateDialogTitle('v0.1.31'), 'New Version Available v0.1.31');
      expect(l10n.updateGoToDownload, 'Download');
      expect(l10n.updateDownloadingStarted, 'Download added to queue');
      expect(l10n.updateInstallNow, 'Install Now');
      expect(l10n.updateReadyToInstall, 'Update download completed. Install now?');
    });
  });
}
