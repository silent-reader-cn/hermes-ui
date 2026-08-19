import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_settings.dart';

/// 屏幕边界约束辅助函数：限制窗口在可用屏幕区域内，防止移出可视范围。
Rect clampWindowBounds({
  required Rect target,
  required List<Rect> displayBounds,
  Size minSize = const Size(400, 300),
}) {
  if (displayBounds.isEmpty) {
    final width = math.max(target.width, minSize.width);
    final height = math.max(target.height, minSize.height);
    final left = math.max(0.0, target.left);
    final top = math.max(0.0, target.top);
    return Rect.fromLTWH(left, top, width, height);
  }

  // 1. 寻找与目标窗口重叠最大的显示器
  Rect? matchedDisplay;
  double maxIntersectionArea = 0;

  for (final display in displayBounds) {
    final intersection = target.intersect(display);
    if (!intersection.isEmpty) {
      final area = intersection.width * intersection.height;
      if (area > maxIntersectionArea) {
        maxIntersectionArea = area;
        matchedDisplay = display;
      }
    }
  }

  // 若窗口脱离所有显示器（例如拔出外接显示器），回退至主屏幕
  matchedDisplay ??= displayBounds.first;

  // 2. 限制窗口尺寸不超过屏幕尺寸，且不小于最小尺寸
  final width = (target.width.clamp(
    math.min(minSize.width, matchedDisplay.width),
    matchedDisplay.width,
  )).toDouble();
  final height = (target.height.clamp(
    math.min(minSize.height, matchedDisplay.height),
    matchedDisplay.height,
  )).toDouble();

  // 3. 限制坐标在屏幕可视范围内
  final maxLeft = matchedDisplay.right - width;
  final minLeft = matchedDisplay.left;
  final left = minLeft >= maxLeft
      ? minLeft
      : (target.left.clamp(minLeft, maxLeft)).toDouble();

  final maxTop = matchedDisplay.bottom - height;
  final minTop = matchedDisplay.top;
  final top = minTop >= maxTop
      ? minTop
      : (target.top.clamp(minTop, maxTop)).toDouble();

  return Rect.fromLTWH(left, top, width, height);
}

/// 窗口位置与尺寸记忆服务。
///
/// 职责：
/// 1. 启动时恢复上次窗口位置与尺寸（经屏幕边界 Clamp）；
/// 2. 监听窗口移动（move）与缩放（resize）事件，通过防抖持久化到 shared_preferences；
/// 3. 支持「记住窗口位置」与「最小化到托盘」开关联动；
/// 4. 非桌面平台安全 no-op。
class WindowMemoryService with WindowListener {
  /// 窗口 X 坐标 Key。
  static const String keyWindowX = 'window_x';

  /// 窗口 Y 坐标 Key。
  static const String keyWindowY = 'window_y';

  /// 窗口宽度 Key。
  static const String keyWindowWidth = 'window_width';

  /// 窗口高度 Key。
  static const String keyWindowHeight = 'window_height';

  /// 防抖时间间隔。
  final Duration debounceDuration;

  /// 是否为桌面平台。
  final bool isDesktop;

  /// 获取是否记住窗口位置配置。
  final bool Function()? getRememberSetting;

  /// 获取是否最小化到托盘配置。
  final bool Function()? getMinimizeToTraySetting;

  Timer? _debounceTimer;
  bool _initialized = false;

  /// 构造窗口记忆服务。
  WindowMemoryService({
    this.debounceDuration = const Duration(milliseconds: 500),
    bool? isDesktop,
    this.getRememberSetting,
    this.getMinimizeToTraySetting,
  }) : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 是否已初始化。
  bool get isInitialized => _initialized;

  /// 获取系统显示器区域列表。
  List<Rect> getSystemDisplayBounds() {
    try {
      final displays = WidgetsBinding.instance.platformDispatcher.displays;
      if (displays.isNotEmpty) {
        return displays.map((d) {
          final dpr = d.devicePixelRatio > 0 ? d.devicePixelRatio : 1.0;
          return Rect.fromLTWH(
            0,
            0,
            d.size.width / dpr,
            d.size.height / dpr,
          );
        }).toList();
      }
    } catch (_) {
      // 忽略异常，降级到默认
    }
    return const [Rect.fromLTWH(0, 0, 1920, 1080)];
  }

  /// 初始化窗口监听器与关闭拦截。
  Future<void> initialize() async {
    if (!isDesktop || _initialized) return;

    try {
      windowManager.addListener(this);
      _initialized = true;
      final preventClose = getMinimizeToTraySetting?.call() ?? true;
      await windowManager.setPreventClose(preventClose);
    } catch (e, st) {
      developer.log(
        'Failed to initialize WindowMemoryService',
        name: 'WindowMemoryService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 恢复持久化的窗口位置与尺寸。
  Future<bool> restoreWindowBounds({
    SharedPreferences? customPrefs,
    List<Rect>? customDisplayBounds,
  }) async {
    if (!isDesktop) return false;

    final remember = getRememberSetting?.call() ?? true;
    if (!remember) return false;

    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      final x = prefs.getDouble(keyWindowX);
      final y = prefs.getDouble(keyWindowY);
      final w = prefs.getDouble(keyWindowWidth);
      final h = prefs.getDouble(keyWindowHeight);

      if (x == null || y == null || w == null || h == null) {
        return false;
      }

      final savedRect = Rect.fromLTWH(x, y, w, h);
      final displayBounds = customDisplayBounds ?? getSystemDisplayBounds();

      final clamped = clampWindowBounds(
        target: savedRect,
        displayBounds: displayBounds,
      );

      await windowManager.setSize(clamped.size);
      await windowManager.setPosition(clamped.topLeft);
      return true;
    } catch (e, st) {
      developer.log(
        'Failed to restore window bounds',
        name: 'WindowMemoryService',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// 保存当前窗口位置与尺寸到 [SharedPreferences]。
  Future<void> saveCurrentBounds([SharedPreferences? customPrefs]) async {
    if (!isDesktop) return;

    final remember = getRememberSetting?.call() ?? true;
    if (!remember) return;

    try {
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      await prefs.setDouble(keyWindowX, pos.dx);
      await prefs.setDouble(keyWindowY, pos.dy);
      await prefs.setDouble(keyWindowWidth, size.width);
      await prefs.setDouble(keyWindowHeight, size.height);
    } catch (e, st) {
      developer.log(
        'Failed to save window bounds',
        name: 'WindowMemoryService',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _onBoundsChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(saveCurrentBounds());
    });
  }

  @override
  void onWindowMove() => _onBoundsChanged();

  @override
  void onWindowMoved() => _onBoundsChanged();

  @override
  void onWindowResize() => _onBoundsChanged();

  @override
  void onWindowResized() => _onBoundsChanged();

  @override
  void onWindowClose() async {
    final minimizeToTray = getMinimizeToTraySetting?.call() ?? true;
    try {
      if (minimizeToTray) {
        await windowManager.hide();
      } else {
        await windowManager.destroy();
      }
    } catch (e, st) {
      developer.log(
        'Failed to handle onWindowClose',
        name: 'WindowMemoryService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 销毁窗口记忆服务。
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    if (!isDesktop) return;

    try {
      windowManager.removeListener(this);
    } catch (e) {
      developer.log(
        'Failed to dispose window memory listener',
        name: 'WindowMemoryService',
        error: e,
      );
    }
    _initialized = false;
  }
}

/// 窗口位置与尺寸记忆服务 Provider。
final windowMemoryServiceProvider = Provider<WindowMemoryService>((ref) {
  final service = WindowMemoryService(
    getRememberSetting: () =>
        ref.read(desktopSettingsProvider).rememberWindowPosition,
    getMinimizeToTraySetting: () =>
        ref.read(desktopSettingsProvider).minimizeToTray,
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
