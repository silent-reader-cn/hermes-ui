import 'package:flutter/cupertino.dart';

import '../../features/session_list/session_list_page.dart';
import 'sidebar_utility_toolbar.dart';

/// 宽屏自适应外壳的左侧常驻侧栏（TASK W2）。
///
/// 包含顶部工具入口行（任务/看板/技能/记忆/统计/设置）与下方完整的会话列表。
class SessionSidebar extends StatelessWidget {
  const SessionSidebar({super.key, required this.currentLocation});

  /// 当前激活的路由路径。
  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('adaptive-session-sidebar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarUtilityToolbar(currentLocation: currentLocation),
        // 侧栏顶部已有 SidebarUtilityToolbar 提供工具入口，内部会话
        // 列表不再重复渲染工具行，避免宽屏双层入口重叠；设置图标同样由
        // 工具条承担，隐藏列表头部右侧齿轮避免双设置入口。
        const Expanded(
          child: SessionListPage(
            showUtilityRows: false,
            showSettingsTrailing: false,
            showFab: false,
          ),
        ),
      ],
    );
  }
}
