library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
// ignore: depend_on_referenced_packages
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../../l10n/app_localizations.dart';

/// 全屏查看 Mermaid 图表页面。
class MermaidFullscreenPage extends StatelessWidget {
  const MermaidFullscreenPage({
    super.key,
    required this.source,
    required this.theme,
  });

  /// Mermaid 图表源码。
  final String source;

  /// 图表主题。
  final core.MermaidTheme theme;

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).mermaidDiagramTitle;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: const Color(0xCC1C1C1E),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark),
        ),
      ),
      child: SafeArea(
        child: MermaidView(
          key: const ValueKey('mermaid-fullscreen-view'),
          source: source,
          theme: theme,
          showControls: true,
          allowFullscreen: false,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
