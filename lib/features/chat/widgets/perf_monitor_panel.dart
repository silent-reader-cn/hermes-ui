import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_popover.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../core/api/api_client_server_panels.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/system_health.dart';
import '../../../features/settings/composer_settings.dart';
import '../../../features/settings/perf_monitor_settings.dart';
import '../../../l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// 折线图 CustomPainter
// ---------------------------------------------------------------------------

/// 折线图画笔：按 20-30 点环形缓冲绘制折线。
class _LinePainter extends CustomPainter {
  _LinePainter({required this.points, required this.color});

  /// 数据点，每点为 0-100 的百分比值。
  final List<double> points;

  /// 线条颜色。
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final stepX = size.width / (points.length - 1);
    for (var i = 0; i < points.length; i++) {
      final x = i * stepX;
      // 百分比越高点越高（y 轴反转）
      final y = size.height * (1 - points[i] / 100.0);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// PerfMonitorPanel
// ---------------------------------------------------------------------------

/// 性能监控面板，置于两段式 composer 底部工具行左侧（紧跟左簇控件，Flexible 自适应）。
///
/// - 紧凑态：`CPU xx% · MEM xx%`，点击以气泡形式向上弹出悬浮卡片（不撑高输入栏文档流）。
/// - 悬浮卡片：CPU/MEM 折线图 + DISK 数字行，点击监控或外部收起。
/// - 后台暂停轮询（[AppLifecycleState] 监听）。
/// - 接口不可用或无数据时静默隐藏，不报错。
class PerfMonitorPanel extends ConsumerStatefulWidget {
  const PerfMonitorPanel({super.key});

  @override
  ConsumerState<PerfMonitorPanel> createState() => _PerfMonitorPanelState();
}

class _PerfMonitorPanelState extends ConsumerState<PerfMonitorPanel>
    with WidgetsBindingObserver {
  static const int _maxPoints = 25;
  static const Duration _pollInterval = Duration(seconds: 12);

  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<int> _dataVersion = ValueNotifier<int>(0);

  Timer? _timer;
  SystemHealthResponse? _lastData;
  bool _paused = false;
  VoidCallback? _popoverCloser;

  /// CPU 历史点（0-100）。
  final List<double> _cpuPoints = [];

  /// MEM 历史点（0-100）。
  final List<double> _memPoints = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // 立即采样一次
    unawaited(_poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _popoverCloser?.call();
    _popoverCloser = null;
    _dataVersion.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_paused) {
        _paused = false;
        _startTimer();
        unawaited(_poll());
      }
    } else {
      _paused = true;
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (!_paused) {
        unawaited(_poll());
      }
    });
  }

  Future<void> _poll() async {
    if (_paused) return;
    // 仅两段式+性能监控开启且有激活连接时才轮询，避免在测试或无连接时产生额外请求。
    if (!ref.read(composerTwoPaneProvider) ||
        !ref.read(perfMonitorProvider)) {
      return;
    }
    // 无激活连接（测试环境或未配置时）不轮询。
    try {
      ref.read(apiClientProvider);
    } catch (_) {
      return;
    }
    try {
      final client = ref.read(apiClientProvider);
      final data = await client.systemHealth();
      if (mounted) {
        setState(() {
          _lastData = data;
          _cpuPoints.add(data.cpu.percent);
          if (_cpuPoints.length > _maxPoints) _cpuPoints.removeAt(0);
          _memPoints.add(data.memory.percent);
          if (_memPoints.length > _maxPoints) _memPoints.removeAt(0);
        });
        _dataVersion.value++;
      }
    } catch (e) {
      // 接口不可用时静默处理，不弹错
      developer.log('PerfMonitorPanel: systemHealth failed: $e');
      // 保持 _lastData == null → 面板隐藏
    }
  }

  void _togglePopover() {
    if (_popoverCloser != null) {
      _popoverCloser!();
      _popoverCloser = null;
      return;
    }
    if (_lastData == null) return;
    _showPopover();
  }

  void _showPopover() {
    unawaited(
      showCupertinoPopover(
        context: context,
        anchorKey: _anchorKey,
        preferredWidth: 220,
        preferredHeight: 85,
        maxHeight: 130,
        placement: PopoverPlacement.top,
        align: PopoverAlign.start,
        builder: (popoverContext, close) {
          _popoverCloser = () {
            close();
            _popoverCloser = null;
          };
          return _PerfMonitorPopoverContent(
            dataVersion: _dataVersion,
            getData: () => _lastData,
            cpuPoints: _cpuPoints,
            memPoints: _memPoints,
            onClose: () {
              _popoverCloser = null;
            },
          );
        },
      ),
    );
  }

  /// 格式化字节数为人性化 GB 或 MB。
  static String _formatBytes(int bytes) {
    const double gb = 1073741824;
    const double mb = 1048576;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)}GB';
    }
    return '${(bytes / mb).toStringAsFixed(0)}MB';
  }

  /// 阈值颜色：≥85 红，≥75 橙，否则 secondaryLabel。
  static Color _thresholdColor(double percent, BuildContext ctx) {
    if (percent >= 85) return CupertinoColors.systemRed.resolveFrom(ctx);
    if (percent >= 75) return CupertinoColors.systemOrange.resolveFrom(ctx);
    return CupertinoColors.secondaryLabel.resolveFrom(ctx);
  }

  @override
  Widget build(BuildContext context) {
    // 两段式或性能监控关闭时不显示
    final twoPane = ref.watch(composerTwoPaneProvider);
    final showPerf = ref.watch(perfMonitorProvider);
    if (!twoPane || !showPerf) return const SizedBox.shrink();

    final data = _lastData;
    // 无数据时静默隐藏
    if (data == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final secondaryColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);

    return GestureDetector(
      key: const ValueKey('perf-monitor-panel'),
      behavior: HitTestBehavior.opaque,
      onTap: _togglePopover,
      child: Container(
        key: _anchorKey,
        child: _buildCompact(context, data, l10n, secondaryColor),
      ),
    );
  }

  /// 紧凑态：`CPU xx% · MEM xx%`。
  Widget _buildCompact(
    BuildContext context,
    SystemHealthResponse data,
    AppLocalizations l10n,
    Color secondaryColor,
  ) {
    final cpuColor = _thresholdColor(data.cpu.percent, context);
    final memColor = _thresholdColor(data.memory.percent, context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11.5, color: secondaryColor),
            children: [
              TextSpan(
                text: '${l10n.perfMonitorCpu} ',
                style: TextStyle(color: secondaryColor),
              ),
              TextSpan(
                text: '${data.cpu.percent.toStringAsFixed(0)}%',
                style: TextStyle(color: cpuColor),
              ),
              TextSpan(
                text: ' · ',
                style: TextStyle(color: secondaryColor),
              ),
              TextSpan(
                text: '${l10n.perfMonitorMem} ',
                style: TextStyle(color: secondaryColor),
              ),
              TextSpan(
                text: '${data.memory.percent.toStringAsFixed(0)}%',
                style: TextStyle(color: memColor),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  static Widget _buildChartRow({
    required String label,
    required double percent,
    required List<double> points,
    required Color lineColor,
    required Color valueColor,
    required Color secondaryColor,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(fontSize: 10, color: secondaryColor),
          ),
          Text(
            '${percent.toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 10, color: valueColor),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 60,
            height: 18,
            child: points.length >= 2
                ? CustomPaint(
                    painter: _LinePainter(
                      points: List<double>.from(points),
                      color: lineColor,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 悬浮卡片内容
// ---------------------------------------------------------------------------

class _PerfMonitorPopoverContent extends StatelessWidget {
  const _PerfMonitorPopoverContent({
    required this.dataVersion,
    required this.getData,
    required this.cpuPoints,
    required this.memPoints,
    this.onClose,
  });

  final ValueNotifier<int> dataVersion;
  final SystemHealthResponse? Function() getData;
  final List<double> cpuPoints;
  final List<double> memPoints;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dataVersion,
      builder: (context, _) {
        final data = getData();
        if (data == null) return const SizedBox.shrink();

        final l10n = AppLocalizations.of(context);
        final secondaryColor =
            CupertinoColors.secondaryLabel.resolveFrom(context);
        final cpuColor = _PerfMonitorPanelState._thresholdColor(
          data.cpu.percent,
          context,
        );
        final memColor = _PerfMonitorPanelState._thresholdColor(
          data.memory.percent,
          context,
        );
        final diskColor = _PerfMonitorPanelState._thresholdColor(
          data.disk.percent,
          context,
        );

        return Padding(
          key: const ValueKey('perf-monitor-popover-card'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CPU 折线 + 标签
              _PerfMonitorPanelState._buildChartRow(
                label: l10n.perfMonitorCpu,
                percent: data.cpu.percent,
                points: cpuPoints,
                lineColor: cpuColor,
                valueColor: cpuColor,
                secondaryColor: secondaryColor,
              ),
              const SizedBox(height: 4),
              // MEM 折线 + 标签
              _PerfMonitorPanelState._buildChartRow(
                label: l10n.perfMonitorMem,
                percent: data.memory.percent,
                points: memPoints,
                lineColor: memColor,
                valueColor: memColor,
                secondaryColor: secondaryColor,
              ),
              const SizedBox(height: 4),
              // DISK 仅数字，不画折线（FittedBox 自适应）
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l10n.perfMonitorDisk} ',
                      style: TextStyle(fontSize: 10, color: secondaryColor),
                    ),
                    Text(
                      '${data.disk.percent.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 10, color: diskColor),
                    ),
                    Text(
                      ' ${_PerfMonitorPanelState._formatBytes(data.disk.usedBytes)}/${_PerfMonitorPanelState._formatBytes(data.disk.totalBytes)}',
                      style: TextStyle(fontSize: 10, color: secondaryColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
