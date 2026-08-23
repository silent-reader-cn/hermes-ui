import '../../core/models/chat_message.dart';

/// 对比本地消息列表与服务端消息列表，执行 diff-merge（类 VDOM 调和）。
///
/// - 以 [serverMessages] 窗口为权威基准，匹配并原地更新 [localMessages] 中已有项；
/// - 补入服务端存在但本地缺失的消息；
/// - 保留本地历史分页消息（头部）及未落库乐观消息（尾部），不做删除；
/// - 兼容 `messageId == null` 或 `local-` 前缀的乐观消息指纹匹配。
List<ChatMessage> diffMergeMessages({
  required List<ChatMessage> localMessages,
  required List<ChatMessage> serverMessages,
}) {
  if (localMessages.isEmpty) {
    return List<ChatMessage>.of(serverMessages);
  }
  if (serverMessages.isEmpty) {
    return List<ChatMessage>.of(localMessages);
  }

  final matchedLocalIndices = <int>{};
  final serverToLocal = <int, int>{};

  for (var sIdx = 0; sIdx < serverMessages.length; sIdx++) {
    final sMsg = serverMessages[sIdx];
    for (var lIdx = 0; lIdx < localMessages.length; lIdx++) {
      if (matchedLocalIndices.contains(lIdx)) continue;
      if (isMessageMatch(localMessages[lIdx], sMsg)) {
        matchedLocalIndices.add(lIdx);
        serverToLocal[sIdx] = lIdx;
        break;
      }
    }
  }

  if (matchedLocalIndices.isEmpty) {
    // 双方无交集：比较时间戳确定前后关系
    final firstServerTs = serverMessages.first.timestamp;
    final lastLocalTs = localMessages.last.timestamp;
    if (firstServerTs != null &&
        lastLocalTs != null &&
        firstServerTs >= lastLocalTs) {
      return [...localMessages, ...serverMessages];
    }
    final lastServerTs = serverMessages.last.timestamp;
    final firstLocalTs = localMessages.first.timestamp;
    if (lastServerTs != null &&
        firstLocalTs != null &&
        lastServerTs <= firstLocalTs) {
      return [...serverMessages, ...localMessages];
    }
    final combined = [...localMessages, ...serverMessages];
    _stableSortMessages(combined);
    return combined;
  }

  final firstMatchedLocalIdx =
      matchedLocalIndices.reduce((a, b) => a < b ? a : b);
  final lastMatchedLocalIdx =
      matchedLocalIndices.reduce((a, b) => a > b ? a : b);

  final result = <ChatMessage>[];

  // 头部保留：早于首个命中项的本地历史消息（分页加载的更早记录）
  for (var i = 0; i < firstMatchedLocalIdx; i++) {
    result.add(localMessages[i]);
  }

  // 中部窗口：以服务端顺序为主，原地 patch 命中项，补入缺失项，并保留本地夹在中间未命中的项
  var currentLocalIdx = firstMatchedLocalIdx;

  for (var sIdx = 0; sIdx < serverMessages.length; sIdx++) {
    final sMsg = serverMessages[sIdx];
    final matchedLIdx = serverToLocal[sIdx];

    if (matchedLIdx != null) {
      while (currentLocalIdx < matchedLIdx) {
        if (!matchedLocalIndices.contains(currentLocalIdx)) {
          result.add(localMessages[currentLocalIdx]);
        }
        currentLocalIdx++;
      }
      final localOrig = localMessages[matchedLIdx];
      result.add(_patchMessage(localOrig, sMsg));
      if (matchedLIdx + 1 > currentLocalIdx) {
        currentLocalIdx = matchedLIdx + 1;
      }
    } else {
      result.add(sMsg);
    }
  }

  while (currentLocalIdx <= lastMatchedLocalIdx) {
    if (!matchedLocalIndices.contains(currentLocalIdx)) {
      result.add(localMessages[currentLocalIdx]);
    }
    currentLocalIdx++;
  }

  // 尾部保留：晚于最后一个命中项的本地未落库项（如发送中的乐观消息）
  for (var i = lastMatchedLocalIdx + 1; i < localMessages.length; i++) {
    if (!matchedLocalIndices.contains(i)) {
      result.add(localMessages[i]);
    }
  }

  return result;
}

/// 判断本地消息与服务端消息是否匹配。
bool isMessageMatch(ChatMessage local, ChatMessage server) {
  final localId = local.messageId;
  final serverId = server.messageId;

  // 1. 精确 ID 匹配
  if (localId != null &&
      serverId != null &&
      localId.isNotEmpty &&
      localId == serverId) {
    return true;
  }

  // 若双方都有非本地生成的权威 ID 且不相等，则判定为不同消息
  final localIsAuthoritative = !_isTempId(localId);
  final serverIsAuthoritative = !_isTempId(serverId);
  if (localIsAuthoritative && serverIsAuthoritative) {
    return false;
  }

  // 2. 角色校验
  if (local.role != server.role) return false;

  // 3. 工具调用 ID 匹配
  if (local.toolCallId != null &&
      server.toolCallId != null &&
      local.toolCallId == server.toolCallId) {
    return true;
  }
  if (local.toolUseId != null &&
      server.toolUseId != null &&
      local.toolUseId == server.toolUseId) {
    return true;
  }

  // 4. 指纹匹配：content + timestamp（容差 120s）
  final localContent = local.content ?? '';
  final serverContent = server.content ?? '';
  if (localContent == serverContent) {
    final localTs = local.timestamp;
    final serverTs = server.timestamp;
    if (localTs != null && serverTs != null && localTs > 0 && serverTs > 0) {
      return (localTs - serverTs).abs() <= 120.0;
    }
    return true;
  }

  // 5. 本地流式临时 assistant 消息与服务端 assistant 消息匹配（替换占位）
  if (local.role == 'assistant' && _isTempId(localId)) {
    final localTs = local.timestamp;
    final serverTs = server.timestamp;
    if (localTs != null && serverTs != null && localTs > 0 && serverTs > 0) {
      return (localTs - serverTs).abs() <= 120.0;
    }
    return true;
  }

  return false;
}

bool _isTempId(String? id) {
  if (id == null || id.isEmpty) return true;
  return id.startsWith('local-') || id.startsWith('stream-');
}

ChatMessage _patchMessage(ChatMessage local, ChatMessage server) {
  return server.copyWith(
    turnTps: server.turnTps ?? local.turnTps,
  );
}

void _stableSortMessages(List<ChatMessage> list) {
  final hasTs = list.any((m) => m.timestamp != null && m.timestamp! > 0);
  if (hasTs) {
    list.sort((a, b) {
      final tsA = a.timestamp ?? 0;
      final tsB = b.timestamp ?? 0;
      return tsA.compareTo(tsB);
    });
  }
}
