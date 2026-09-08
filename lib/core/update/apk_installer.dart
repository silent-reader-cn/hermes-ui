import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// 原生 FileProvider 与权限通道。
const MethodChannel updateFileShareChannel = MethodChannel(
  'com.silentreader.hermes_ui/file_share',
);

/// 检查 Android 是否已被授予「安装未知应用」权限（#96）。
Future<bool> canRequestInstall({
  MethodChannel channel = updateFileShareChannel,
}) async {
  try {
    return await channel.invokeMethod<bool>('canRequestInstall') ?? false;
  } catch (_) {
    return false;
  }
}

/// 跳转系统「安装未知应用」授权设置页（#96）。
Future<void> openInstallPermissionSettings({
  MethodChannel channel = updateFileShareChannel,
}) async {
  try {
    await channel.invokeMethod('openInstallPermissionSettings');
  } catch (_) {}
}

/// 经 MainActivity 的 FileProvider 生成 content:// URI（#96）。
Future<String?> androidContentUriFor(
  String path, {
  MethodChannel channel = updateFileShareChannel,
}) async {
  try {
    return await channel.invokeMethod<String>('getShareUri', {'path': path});
  } catch (_) {
    return null;
  }
}

/// APK 文件安装：引导安装权限后发起系统包安装器（#96 / #101）。
Future<bool> installApkWithPermissionGate(
  BuildContext context,
  String path, {
  MethodChannel channel = updateFileShareChannel,
  Future<void> Function(AndroidIntent intent)? launchIntent,
}) async {
  final l10n = AppLocalizations.of(context);
  if (!await canRequestInstall(channel: channel)) {
    if (!context.mounted) return false;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.installPermissionTitle),
        content: Text(l10n.installPermissionBody),
        actions: [
          CupertinoDialogAction(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(l10n.installPermissionGoSettings),
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(openInstallPermissionSettings(channel: channel));
            },
          ),
        ],
      ),
    );
    if (!context.mounted) return false;
    // 从设置页返回后复查
    if (!await canRequestInstall(channel: channel)) return false;
  }

  final contentUri = await androidContentUriFor(path, channel: channel);
  final intent = AndroidIntent(
    action: 'android.intent.action.VIEW',
    data: contentUri ?? Uri.encodeFull('file://$path'),
    type: 'application/vnd.android.package-archive',
    flags: const [
      0x10000000, // FLAG_ACTIVITY_NEW_TASK
      0x00000001, // FLAG_GRANT_READ_URI_PERMISSION
    ],
  );

  if (launchIntent != null) {
    await launchIntent(intent);
  } else {
    await intent.launch();
  }
  return true;
}
