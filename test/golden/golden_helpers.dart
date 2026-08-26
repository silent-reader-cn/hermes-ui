import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';

/// 截图逻辑尺寸（iPhone 12/13/14 尺寸 390x844，2x 物理像素）。
const Size goldenSurfaceSize = Size(780, 1688);

/// 截图物理像素比（2x 保证放大查对比度/溢出时文字清晰）。
const double goldenDevicePixelRatio = 2.0;

/// 注册真实字体：flutter_test 默认全部走 Ahem 方块字，截图无法人工核对。
///
/// - [loadAppFonts]：应用 FontManifest（MaterialIcons + CupertinoIcons）；
/// - Roboto：引擎默认字族（fontFamily 缺省文本）英文 + 粗体；
/// - SimHei（simhei.ttf）：中文字形回退（Roboto 无 CJK 字形），
///   同时覆盖 CupertinoTextThemeData 默认的 CupertinoSystemText/Display 字族。
///
/// 字体文件缺失的环境（如 CI Linux）静默跳过：中文退化为方块，测试仍可运行，
/// 只是截图不具人工核对价值（符合「无字体环境不稳」的预期）。
Future<void> loadHermesGoldenFonts() async {
  await loadAppFonts();
  // flutter_tester.exe → <flutter>/bin/cache/artifacts/engine/<platform>/，
  // 向上 6 级即 Flutter SDK 根目录。
  final exe = File(Platform.resolvedExecutable);
  final flutterRoot = exe.parent.parent.parent.parent.parent.parent.path;
  final materialFontsDir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _registerFontFile('Roboto', '$materialFontsDir/roboto-regular.ttf');
  await _registerFontFile('Roboto', '$materialFontsDir/roboto-bold.ttf');
  await _registerFontFile('Roboto', r'C:\Windows\Fonts\simhei.ttf');
  await _registerFontFile('CupertinoSystemText', r'C:\Windows\Fonts\simhei.ttf');
  await _registerFontFile(
    'CupertinoSystemDisplay',
    r'C:\Windows\Fonts\simhei.ttf',
  );
  // 注册全局字体 MiSans（保证无论环境是否加载 asset bundle，字族都完整注册）
  await _registerFontFile('MiSans', 'assets/fonts/MiSans-Regular.ttf');
  await _registerFontFile('MiSans', 'assets/fonts/MiSans-Medium.ttf');
  // 注册等宽字体 monospace（用于代码块、git diff 等）
  await _registerFontFile('monospace', r'C:\Windows\Fonts\consola.ttf');
  await _registerFontFile('monospace', r'C:\Windows\Fonts\cour.ttf');
  await _registerFontFile('monospace', 'assets/fonts/MiSans-Regular.ttf');
}

/// 把某字体文件注册进 [family]（文件不存在时静默跳过）。
Future<void> _registerFontFile(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// 以 [brightness] 主题挂载 [page]（注入 [overrides]），等异步加载与入场动画
/// 结算后返回（适合接 matchesGoldenFile 截图）。
///
/// [size] 缺省为竖屏 [goldenSurfaceSize]；需要横屏的页面（如 workspace）
/// 可传 [goldenLandscapeSize]。
Future<void> pumpHermesPage(
  WidgetTester tester, {
  required Widget page,
  required Brightness brightness,
  List<Override> overrides = const [],
  Size size = goldenSurfaceSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = goldenDevicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: page,
      ),
    ),
  );
  // 首帧（AsyncLoading）→ 异步 build 完成（AsyncData）→ 入场动画/图表动画结算
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 卸载页面并释放 ProviderScope（让控制器 dispose 取消定时器，避免 pending timer）。
Future<void> unmountHermesPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}