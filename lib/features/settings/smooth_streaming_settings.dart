import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

/// 平滑输出持久化键。
const String kSmoothStreamingKey = 'settings.smoothStreaming';

/// 平滑打字机速度档位持久化键。
const String kSmoothStreamingSpeedKey = 'settings.smoothStreamingSpeed';

/// 平滑打字机速度档位。
enum SmoothStreamingSpeedPreset {
  /// 逐字：100ms interval, 1 unit/tick, 1 CJK/chunk, 8s max lag, 固定。
  charByChar(
    id: 'charByChar',
    displayName: '逐字',
    revealInterval: Duration(milliseconds: 100),
    wordUnitsPerTick: 1,
    cjkChunkSize: 1,
    maxRevealLag: Duration(seconds: 8),
    isAdaptive: false,
  ),

  /// 慢：80ms interval, 1 unit/tick, 2 CJK/chunk, 5s max lag, 固定。
  slow(
    id: 'slow',
    displayName: '慢',
    revealInterval: Duration(milliseconds: 80),
    wordUnitsPerTick: 1,
    cjkChunkSize: 2,
    maxRevealLag: Duration(seconds: 5),
    isAdaptive: false,
  ),

  /// 标准（默认）：64ms interval, 2 units/tick, 2 CJK/chunk, 3s max lag, 固定。
  standard(
    id: 'standard',
    displayName: '标准',
    revealInterval: Duration(milliseconds: 64),
    wordUnitsPerTick: 2,
    cjkChunkSize: 2,
    maxRevealLag: Duration(seconds: 3),
    isAdaptive: false,
  ),

  /// 快：48ms interval, 3 units/tick (base), 4 CJK/chunk, 2s max lag, 自适应。
  fast(
    id: 'fast',
    displayName: '快',
    revealInterval: Duration(milliseconds: 48),
    wordUnitsPerTick: 3,
    cjkChunkSize: 4,
    maxRevealLag: Duration(seconds: 2),
    isAdaptive: true,
  ),

  /// 极快：48ms interval, 5 units/tick (base), 8 CJK/chunk, 1s max lag, 自适应。
  veryFast(
    id: 'veryFast',
    displayName: '极快',
    revealInterval: Duration(milliseconds: 48),
    wordUnitsPerTick: 5,
    cjkChunkSize: 8,
    maxRevealLag: Duration(seconds: 1),
    isAdaptive: true,
  );

  const SmoothStreamingSpeedPreset({
    required this.id,
    required this.displayName,
    required this.revealInterval,
    required this.wordUnitsPerTick,
    required this.cjkChunkSize,
    required this.maxRevealLag,
    required this.isAdaptive,
  });

  /// 档位唯一标识。
  final String id;

  /// 默认显示名（中文）。
  final String displayName;

  /// 打字机 tick 间隔。
  final Duration revealInterval;

  /// 每 tick 吐出的词单元数（固定档为固定值，自适应档为 base 起始值）。
  final int wordUnitsPerTick;

  /// CJK 切分粒度（无空格连续 CJK 字符分词长度）。
  final int cjkChunkSize;

  /// reveal 最大滞后（积压超过该时长一次性排空）。
  final Duration maxRevealLag;

  /// 是否启用积压自适应加速。
  final bool isAdaptive;

  /// 本地化显示名。
  String localizedName(AppLocalizations l10n) {
    switch (this) {
      case SmoothStreamingSpeedPreset.charByChar:
        return l10n.smoothStreamingSpeedCharByChar;
      case SmoothStreamingSpeedPreset.slow:
        return l10n.smoothStreamingSpeedSlow;
      case SmoothStreamingSpeedPreset.standard:
        return l10n.smoothStreamingSpeedStandard;
      case SmoothStreamingSpeedPreset.fast:
        return l10n.smoothStreamingSpeedFast;
      case SmoothStreamingSpeedPreset.veryFast:
        return l10n.smoothStreamingSpeedVeryFast;
    }
  }

  /// 根据持久化 ID 或名称解析档位，容错回退为 [standard]。
  static SmoothStreamingSpeedPreset fromId(String? id) {
    if (id == null || id.isEmpty) return SmoothStreamingSpeedPreset.standard;
    for (final preset in SmoothStreamingSpeedPreset.values) {
      if (preset.id == id || preset.name == id) {
        return preset;
      }
    }
    return SmoothStreamingSpeedPreset.standard;
  }
}

/// 平滑打字机输出偏好设置 Provider（持久化到 shared_preferences，默认开启）。
final smoothStreamingProvider =
    NotifierProvider<SmoothStreamingController, bool>(
      SmoothStreamingController.new,
    );

/// 平滑打字机速度档位 Provider（持久化到 shared_preferences，默认 standard）。
final smoothStreamingSpeedProvider =
    NotifierProvider<
      SmoothStreamingSpeedController,
      SmoothStreamingSpeedPreset
    >(SmoothStreamingSpeedController.new);

/// 平滑打字机输出控制器。
class SmoothStreamingController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keySmoothStreaming = kSmoothStreamingKey;

  /// 读取平滑输出偏好设置的静态辅助（默认 true）。
  static Future<bool> loadSmoothStreamingPref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keySmoothStreaming) ?? true;
    } catch (_) {
      return true;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final value = await loadSmoothStreamingPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 外部手动触发加载。
  Future<void> load() => _load();

  /// 更新平滑输出开关并持久化到 [SharedPreferences]。
  Future<void> setSmoothStreaming(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keySmoothStreaming, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}

/// 平滑打字机速度档位控制器。
class SmoothStreamingSpeedController
    extends Notifier<SmoothStreamingSpeedPreset> {
  /// 持久化 Key。
  static const String keySmoothStreamingSpeed = kSmoothStreamingSpeedKey;

  /// 读取平滑打字机速度偏好设置的静态辅助（默认 standard）。
  static Future<SmoothStreamingSpeedPreset> loadSmoothStreamingSpeedPref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      final id = prefs.getString(keySmoothStreamingSpeed);
      return SmoothStreamingSpeedPreset.fromId(id);
    } catch (_) {
      return SmoothStreamingSpeedPreset.standard;
    }
  }

  bool _hasCustomState = false;

  @override
  SmoothStreamingSpeedPreset build() {
    _hasCustomState = false;
    unawaited(_load());
    return SmoothStreamingSpeedPreset.standard;
  }

  Future<void> _load() async {
    try {
      final value = await loadSmoothStreamingSpeedPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 外部手动触发加载。
  Future<void> load() => _load();

  /// 更新平滑输出速度档位并持久化到 [SharedPreferences]。
  Future<void> setSpeed(SmoothStreamingSpeedPreset speed) async {
    _hasCustomState = true;
    state = speed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keySmoothStreamingSpeed, speed.id);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
