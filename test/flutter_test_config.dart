import 'dart:async';

import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';

/// 全局测试配置（Flutter 官方机制）：所有 flutter test 在跑任何用例前执行。
///
/// 钉死 [LocaleResolver] 为中文模式：L2 起托盘/通知/面包屑等服务层文案经
/// LocaleResolver 取语言，而测试环境 platform locale 随开发机/CI（多为 en_US），
/// 不钉会导致断言与金照漂移（对齐「金照须固定时钟」同款教训）。
/// locale 专项测试（app/locale、tray_locale_l2）在各自 setUp 里显式切模式，
/// 优先级高于此全局默认。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LocaleResolver.reset(mode: AppLocaleMode.zh);
  await testMain();
}
