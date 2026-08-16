import 'package:flutter/cupertino.dart';

/// 会话列表页（Phase 3 实现；当前为占位空态，见 DoD「配置后 → SessionList 空态」）。
class SessionListPage extends StatelessWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Hermex'),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_2,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            SizedBox(height: 12),
            Text(
              '暂无会话',
              style: TextStyle(
                fontSize: 17,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
