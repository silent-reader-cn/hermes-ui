import 'package:flutter/cupertino.dart';

/// 聊天页（Phase 3 实现；当前为占位）。
///
/// `/chat/:sessionId`，sessionId 为空串表示新会话。
class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.sessionId});

  /// 会话 id；空串 = 新会话。
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(sessionId.isEmpty ? '新会话' : '会话'),
      ),
      child: const Center(
        child: Text(
          '聊天功能即将上线',
          style: TextStyle(
            fontSize: 17,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ),
    );
  }
}
