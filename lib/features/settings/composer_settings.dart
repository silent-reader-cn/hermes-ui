import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 两段式输入栏持久化键。
const String kComposerTwoPaneKey = 'settings.composerTwoPane';

/// 两段式输入栏偏好设置 Provider（持久化到 shared_preferences）。
///
/// 开启：聊天输入栏为两段式 composer（多行文本区 + 独立工具行）；
/// 关闭（默认）：经典单行布局（按钮在两侧、回车即发送）。
final composerTwoPaneProvider =
    NotifierProvider<ComposerTwoPaneController, bool>(
  ComposerTwoPaneController.new,
);

/// 两段式输入栏控制器。
class ComposerTwoPaneController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keyTwoPane = kComposerTwoPaneKey;

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true; // 默认开启：全新安装使用两段式输入栏
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ?? true：无历史值（新装）默认开；已显式 false 的老用户尊重其选择。
      final value = prefs.getBool(keyTwoPane) ?? true;
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 更新两段式输入栏开关并持久化到 [SharedPreferences]。
  Future<void> setTwoPane(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyTwoPane, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
