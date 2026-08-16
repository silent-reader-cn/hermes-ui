import 'dart:convert';

import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'chat_message.dart';
import 'json_value.dart';

/// 实时工具调用（Swift: ToolCall.swift）。**非 JSON 模型**（纯客户端/流式状态），
/// 无 fromJson；提供命名构造。
class ToolCall {
  ToolCall({
    String? id,
    this.name,
    this.preview,
    this.args,
    this.duration,
    this.isError,
    this.isCompleted = false,
    double? startedAt,
  })  : id = id ?? 'live-tool-${uuidV4()}',
        startedAt = startedAt ??
            DateTime.now().millisecondsSinceEpoch / 1000;

  final String id;
  String? name;
  String? preview;
  Map<String, JsonValue>? args;
  double? duration;
  bool? isError;
  bool isCompleted;
  final double startedAt;

  /// trim 后非空 name 否则 'Tool'。
  String get displayName {
    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return 'Tool';
    return trimmedName;
  }

  @override
  bool operator ==(Object other) {
    return other is ToolCall &&
        other.id == id &&
        other.name == name &&
        other.preview == preview &&
        deepEquals(other.args, args) &&
        other.duration == duration &&
        other.isError == isError &&
        other.isCompleted == isCompleted &&
        other.startedAt == startedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      preview,
      deepHash(args),
      duration,
      isError,
      isCompleted,
      startedAt,
    );
  }

  @override
  String toString() {
    return 'ToolCall(id: $id, name: $name, preview: $preview, '
        'isCompleted: $isCompleted, isError: $isError)';
  }
}

/// 服务端存档工具调用（Swift: ToolCall.swift `PersistedToolCall`）。有 fromJson。
class PersistedToolCall {
  const PersistedToolCall({
    this.name,
    this.snippet,
    this.tid,
    this.assistantMsgIdx,
    this.args,
  });

  factory PersistedToolCall.fromJson(Map<String, Object?> json) {
    final argsValue = optModel<JsonValue>(
      json,
      'args',
      (m) => JsonValue.fromJson(m),
    );
    return PersistedToolCall(
      name: lossyString(json, 'name'),
      snippet: lossyString(json, 'snippet'),
      tid: lossyString(json, 'tid'),
      assistantMsgIdx: firstKey(json, ['assistant_msg_idx', 'assistantMsgIdx'], lossyInt),
      args: argsValue is JsonObject ? argsValue.value : null,
    );
  }

  final String? name;
  final String? snippet;
  final String? tid;
  final int? assistantMsgIdx;
  final Map<String, JsonValue>? args;

  Map<String, Object?> toJson() {
    return {
      if (name != null) 'name': name,
      if (snippet != null) 'snippet': snippet,
      if (tid != null) 'tid': tid,
      if (assistantMsgIdx != null) 'assistant_msg_idx': assistantMsgIdx,
      if (args != null) 'args': JsonObject(args!).toJson(),
    };
  }

  /// → ToolCall(id: tid 非空 ? tid : `persisted-tool-$fallbackIndex`, …)。
  ToolCall toolCall(int fallbackIndex) {
    final trimmedID = tid?.trim();
    final id = (trimmedID != null && trimmedID.isNotEmpty)
        ? trimmedID
        : 'persisted-tool-$fallbackIndex';
    return ToolCall(
      id: id,
      name: name,
      preview: snippet,
      args: args,
      isCompleted: true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PersistedToolCall &&
        other.name == name &&
        other.snippet == snippet &&
        other.tid == tid &&
        other.assistantMsgIdx == assistantMsgIdx &&
        deepEquals(other.args, args);
  }

  @override
  int get hashCode =>
      Object.hash(name, snippet, tid, assistantMsgIdx, deepHash(args));

  @override
  String toString() {
    return 'PersistedToolCall(name: $name, snippet: $snippet, '
        'tid: $tid, assistantMsgIdx: $assistantMsgIdx)';
  }
}

/// 工具调用组（Swift: ToolCall.swift `ToolCallGroup`）。纯客户端模型，无 JSON。
class ToolCallGroup {
  ToolCallGroup({
    String? id,
    this.anchorMessageID,
    required this.toolCalls,
  }) : id = id ?? uuidV4();

  final String id;
  final String? anchorMessageID;
  final List<ToolCall> toolCalls;

  /// `Activity: N tools`。
  String get activityTitle => 'Activity: ${toolCalls.length} tools';

  /// 全部工具已完成。
  bool get isComplete => toolCalls.every((t) => t.isCompleted);

  /// 任一工具报错。
  bool get hasFailedTool => toolCalls.any((t) => t.isError == true);

  /// 实时组：id = `live-tools-<anchor ?? unanchored>`。
  static ToolCallGroup live({
    String? anchorMessageID,
    required List<ToolCall> toolCalls,
  }) {
    return ToolCallGroup(
      id: 'live-tools-${anchorMessageID ?? 'unanchored'}',
      anchorMessageID: anchorMessageID,
      toolCalls: toolCalls,
    );
  }

  /// 聚合入口：优先持久化工具调用，缺失时用消息元数据兜底，再按 assistant 回合合并。
  static List<ToolCallGroup> groups({
    required List<PersistedToolCall> persistedToolCalls,
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    final derivedGroups = _groupsFromMessageMetadata(messages, messageOffset);
    if (persistedToolCalls.isEmpty) {
      return coalescingByAssistantTurn(derivedGroups, messages: messages, messageOffset: messageOffset);
    }
    return coalescingByAssistantTurn(
      merging(
        primaryGroups: _groupsFromPersistedToolCalls(
          persistedToolCalls,
          messages,
          messageOffset,
        ),
        fallbackGroups: derivedGroups,
      ),
      messages: messages,
      messageOffset: messageOffset,
    );
  }

  /// 主组 + 兜底组按 anchor 合并（Swift `merging`）。
  static List<ToolCallGroup> merging({
    required List<ToolCallGroup> primaryGroups,
    required List<ToolCallGroup> fallbackGroups,
  }) {
    final merged = List<ToolCallGroup>.from(primaryGroups);
    final groupIndexesByAnchor = <String, int>{};
    for (var i = 0; i < primaryGroups.length; i++) {
      final anchor = primaryGroups[i].anchorMessageID;
      if (anchor != null) groupIndexesByAnchor[anchor] = i;
    }

    for (final fallbackGroup in fallbackGroups) {
      final anchorMessageID = fallbackGroup.anchorMessageID;
      final groupIndex = anchorMessageID == null ? null : groupIndexesByAnchor[anchorMessageID];
      if (groupIndex == null) {
        if (anchorMessageID != null) {
          groupIndexesByAnchor[anchorMessageID] = merged.length;
        }
        merged.add(fallbackGroup);
        continue;
      }

      final existingGroup = merged[groupIndex];
      merged[groupIndex] = ToolCallGroup(
        id: existingGroup.id,
        anchorMessageID: existingGroup.anchorMessageID,
        toolCalls: _mergingToolCalls(
          primaryToolCalls: existingGroup.toolCalls,
          fallbackToolCalls: fallbackGroup.toolCalls,
        ),
      );
    }
    return merged;
  }

  /// 按 assistant 回合合并相邻组（Swift `coalescingByAssistantTurn`）。
  static List<ToolCallGroup> coalescingByAssistantTurn(
    List<ToolCallGroup> groups, {
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    if (groups.length <= 1) {
      return groups.map((group) {
        return ToolCallGroup(
          id: group.id,
          anchorMessageID: group.anchorMessageID,
          toolCalls: _uniqueToolCalls(group.toolCalls),
        );
      }).toList();
    }

    final messageIndexesByID = <String, int>{};
    for (var i = 0; i < messages.length; i++) {
      messageIndexesByID[TranscriptTurnClassifier.anchorID(
        messages[i],
        at: i,
        messageOffset: messageOffset,
      )] = i;
    }
    final turnKeysByAssistantMessageID = TranscriptTurnClassifier
        .assistantTurnKeysByAnchorID(messages, messageOffset: messageOffset);

    final mergedGroups = <_TurnGroupBuilder>[];
    final builderIndexesByTurnKey = <String, int>{};

    for (var groupOrder = 0; groupOrder < groups.length; groupOrder++) {
      final group = groups[groupOrder];
      final anchorIndex = group.anchorMessageID == null
          ? (1 << 62) - groupOrder
          : (messageIndexesByID[group.anchorMessageID] ?? (1 << 62) - groupOrder);
      final turnKey = group.anchorMessageID == null
          ? 'group:${group.id}'
          : (turnKeysByAssistantMessageID[group.anchorMessageID] ?? 'group:${group.id}');

      final builderIndex = builderIndexesByTurnKey[turnKey];
      if (builderIndex != null) {
        mergedGroups[builderIndex].append(group, anchorIndex: anchorIndex);
      } else {
        builderIndexesByTurnKey[turnKey] = mergedGroups.length;
        mergedGroups.add(_TurnGroupBuilder(
          turnKey: turnKey,
          group: group,
          anchorIndex: anchorIndex,
        ));
      }
    }

    mergedGroups.sort((lhs, rhs) {
      if (lhs.anchorIndex == rhs.anchorIndex) {
        return lhs.turnKey.compareTo(rhs.turnKey);
      }
      return lhs.anchorIndex.compareTo(rhs.anchorIndex);
    });

    return mergedGroups.map((builder) {
      return ToolCallGroup(
        id: builder.id,
        anchorMessageID: builder.anchorMessageID,
        toolCalls: _uniqueToolCalls(builder.toolCalls),
      );
    }).toList();
  }

  // MARK: - 内部聚合

  static List<ToolCallGroup> _groupsFromPersistedToolCalls(
    List<PersistedToolCall> persistedToolCalls,
    List<ChatMessage> messages,
    int? messageOffset,
  ) {
    final offset = messageOffset ?? 0;
    final groups = <ToolCallGroup>[];
    final groupIndexesByAnchor = <String, int>{};

    for (var toolIndex = 0; toolIndex < persistedToolCalls.length; toolIndex++) {
      final persistedToolCall = persistedToolCalls[toolIndex];
      final assistantMsgIdx = persistedToolCall.assistantMsgIdx;
      if (assistantMsgIdx == null) continue;

      final loadedMessageIndex = assistantMsgIdx - offset;
      if (loadedMessageIndex < 0 || loadedMessageIndex >= messages.length) continue;

      final anchorMessageID = TranscriptTurnClassifier.assistantAnchorID(
        loadedMessageIndex,
        messages,
        messageOffset: messageOffset,
      );
      if (anchorMessageID == null) continue;

      final toolCall = persistedToolCall.toolCall(toolIndex);
      final existingIndex = groupIndexesByAnchor[anchorMessageID];
      if (existingIndex != null) {
        final existingGroup = groups[existingIndex];
        groups[existingIndex] = ToolCallGroup(
          id: existingGroup.id,
          anchorMessageID: existingGroup.anchorMessageID,
          toolCalls: [...existingGroup.toolCalls, toolCall],
        );
      } else {
        groupIndexesByAnchor[anchorMessageID] = groups.length;
        groups.add(ToolCallGroup(
          id: 'persisted-tools-$anchorMessageID',
          anchorMessageID: anchorMessageID,
          toolCalls: [toolCall],
        ));
      }
    }
    return groups;
  }

  static List<ToolCallGroup> _groupsFromMessageMetadata(
    List<ChatMessage> messages,
    int? messageOffset,
  ) {
    final resultsByToolID = _toolResultSnippetsByID(messages);
    final groups = <ToolCallGroup>[];
    String? currentAnchorMessageID;
    var currentToolCalls = <ToolCall>[];

    void flushCurrentGroup() {
      if (currentToolCalls.isEmpty) {
        currentAnchorMessageID = null;
        return;
      }
      groups.add(ToolCallGroup(
        id: 'persisted-tools-${currentAnchorMessageID ?? 'unanchored-${groups.length}'}',
        anchorMessageID: currentAnchorMessageID,
        toolCalls: _uniqueToolCalls(currentToolCalls),
      ));
      currentAnchorMessageID = null;
      currentToolCalls = [];
    }

    for (var messageIndex = 0; messageIndex < messages.length; messageIndex++) {
      final message = messages[messageIndex];
      if (TranscriptTurnClassifier.isUserTurnBoundary(message)) {
        flushCurrentGroup();
        continue;
      }
      if (message.role != 'assistant') continue;

      final toolCalls = _openAIToolCalls(
        message,
        messageIndex: messageIndex,
        resultsByToolID: resultsByToolID,
      ) + _anthropicToolCalls(
        message,
        messageIndex: messageIndex,
        resultsByToolID: resultsByToolID,
      );
      if (toolCalls.isEmpty) continue;

      currentAnchorMessageID ??= TranscriptTurnClassifier.anchorID(
        message,
        at: messageIndex,
        messageOffset: messageOffset,
      );
      currentToolCalls += toolCalls;
    }

    flushCurrentGroup();
    return groups;
  }

  static Map<String, String> _toolResultSnippetsByID(List<ChatMessage> messages) {
    final result = <String, String>{};
    for (final message in messages) {
      if (message.role == 'tool') {
        final toolCallID = _nonEmpty(message.toolCallId) ?? _nonEmpty(message.toolUseId);
        final content = _nonEmpty(message.content);
        if (toolCallID != null && content != null) {
          result[toolCallID] = content;
        }
      }
      for (final part in message.contentParts ?? const <JsonValue>[]) {
        final toolResult = _toolResult(from: part);
        if (toolResult != null) {
          result[toolResult.id] = toolResult.content;
        }
      }
    }
    return result;
  }

  static List<ToolCall> _openAIToolCalls(
    ChatMessage message, {
    required int messageIndex,
    required Map<String, String> resultsByToolID,
  }) {
    final result = <ToolCall>[];
    final toolCalls = message.toolCalls ?? const <JsonValue>[];
    for (var toolIndex = 0; toolIndex < toolCalls.length; toolIndex++) {
      final call = _toolCall(
        fromOpenAIToolCall: toolCalls[toolIndex],
        messageIndex: messageIndex,
        toolIndex: toolIndex,
        resultsByToolID: resultsByToolID,
      );
      if (call != null) result.add(call);
    }
    return result;
  }

  static ToolCall? _toolCall({
    required JsonValue fromOpenAIToolCall,
    required int messageIndex,
    required int toolIndex,
    required Map<String, String> resultsByToolID,
  }) {
    if (fromOpenAIToolCall is! JsonObject) return null;
    final object = fromOpenAIToolCall.value;

    final function = object['function']?.objectValue;
    final name = _nonEmpty(function?['name']?.stringValue) ??
        _nonEmpty(object['name']?.stringValue) ??
        'tool';
    final toolID = _nonEmpty(object['id']?.stringValue) ??
        _nonEmpty(object['call_id']?.stringValue) ??
        _nonEmpty(object['tool_call_id']?.stringValue) ??
        'message-tool-$messageIndex-$toolIndex';
    final argumentValue = function?['arguments'] ??
        object['arguments'] ??
        object['args'] ??
        object['input'];
    final preview = _nonEmpty(resultsByToolID[toolID]) ??
        _nonEmpty(object['snippet']?.stringValue) ??
        _nonEmpty(object['preview']?.stringValue);

    return ToolCall(
      id: toolID,
      name: name,
      preview: preview,
      args: _arguments(argumentValue),
      isCompleted: true,
    );
  }

  static List<ToolCall> _anthropicToolCalls(
    ChatMessage message, {
    required int messageIndex,
    required Map<String, String> resultsByToolID,
  }) {
    final result = <ToolCall>[];
    final parts = message.contentParts ?? const <JsonValue>[];
    for (var toolIndex = 0; toolIndex < parts.length; toolIndex++) {
      final value = parts[toolIndex];
      if (value is! JsonObject) continue;
      final object = value.value;
      if (object['type']?.stringValue != 'tool_use') continue;

      final name = _nonEmpty(object['name']?.stringValue) ?? 'tool';
      final toolID = _nonEmpty(object['id']?.stringValue) ??
          'message-tool-$messageIndex-$toolIndex';
      final argumentValue = object['input'] ?? object['arguments'] ?? object['args'];

      result.add(ToolCall(
        id: toolID,
        name: name,
        preview: _nonEmpty(resultsByToolID[toolID]) ??
            _nonEmpty(object['snippet']?.stringValue) ??
            _nonEmpty(object['preview']?.stringValue),
        args: _arguments(argumentValue),
        isCompleted: true,
      ));
    }
    return result;
  }

  static ({String id, String content})? _toolResult({required JsonValue from}) {
    if (from is! JsonObject) return null;
    final object = from.value;
    if (object['type']?.stringValue != 'tool_result') return null;
    final id = _nonEmpty(object['tool_use_id']?.stringValue) ??
        _nonEmpty(object['tool_call_id']?.stringValue) ??
        _nonEmpty(object['id']?.stringValue);
    final content = _resultContent(object['content']);
    if (id == null || content == null) return null;
    return (id: id, content: content);
  }

  static String? _resultContent(JsonValue? value) {
    if (value == null) return null;
    switch (value) {
      case JsonString(:final value):
        return _nonEmpty(value);
      case JsonArray(:final value):
        final text = value.map((item) {
          if (item is JsonString) return item.value;
          if (item is JsonObject) {
            return item.value['text']?.stringValue ??
                item.value['content']?.stringValue;
          }
          return null;
        }).whereType<String>().join();
        return _nonEmpty(text);
      case JsonObject() || JsonNumber() || JsonBool() || JsonNull():
        return _nonEmpty(value.compactJsonString);
    }
  }

  static List<ToolCall> _uniqueToolCalls(List<ToolCall> toolCalls) {
    final stableIDIndexes = <String, int>{};
    final fingerprintIndexes = <String, int>{};
    final uniqueToolCalls = <ToolCall>[];
    final isGeneratedByIndex = <bool>[];

    for (final toolCall in toolCalls) {
      final isGenerated = _isGeneratedToolID(toolCall.id);
      final fingerprint = _toolCallFingerprint(toolCall);
      final stableIDIndex = isGenerated ? null : stableIDIndexes[toolCall.id];
      final fingerprintIndex = fingerprintIndexes[fingerprint];
      final resolvedFingerprintIndex = fingerprintIndex == null
          ? null
          : (isGenerated || isGeneratedByIndex[fingerprintIndex] ? fingerprintIndex : null);

      final existingIndex = stableIDIndex ?? resolvedFingerprintIndex;
      if (existingIndex != null) {
        uniqueToolCalls[existingIndex] = _mergingToolCall(
          uniqueToolCalls[existingIndex],
          fallbackCall: toolCall,
        );
        isGeneratedByIndex[existingIndex] = _isGeneratedToolID(uniqueToolCalls[existingIndex].id);
        if (!isGenerated) {
          stableIDIndexes[toolCall.id] = existingIndex;
        }
        fingerprintIndexes[fingerprint] = existingIndex;
      } else {
        if (!isGenerated) {
          stableIDIndexes[toolCall.id] = uniqueToolCalls.length;
        }
        if (fingerprintIndexes[fingerprint] == null || isGenerated) {
          fingerprintIndexes[fingerprint] = uniqueToolCalls.length;
        }
        isGeneratedByIndex.add(isGenerated);
        uniqueToolCalls.add(toolCall);
      }
    }
    return uniqueToolCalls;
  }

  static List<ToolCall> _mergingToolCalls({
    required List<ToolCall> primaryToolCalls,
    required List<ToolCall> fallbackToolCalls,
  }) {
    final mergedToolCalls = _uniqueToolCalls(primaryToolCalls);
    final fallbackNameOrdinals = <String, int>{};

    for (final fallbackToolCall in fallbackToolCalls) {
      final nameKey = _toolCallNameKey(fallbackToolCall);
      final nameOrdinal = (fallbackNameOrdinals[nameKey] ?? 0) + 1;
      fallbackNameOrdinals[nameKey] = nameOrdinal;

      final existingIndex = _matchingToolCallIndex(
        fallbackToolCall,
        nameOrdinal: nameOrdinal,
        toolCalls: mergedToolCalls,
      );
      if (existingIndex != null) {
        mergedToolCalls[existingIndex] = _mergingToolCall(
          mergedToolCalls[existingIndex],
          fallbackCall: fallbackToolCall,
        );
      } else {
        mergedToolCalls.add(fallbackToolCall);
      }
    }
    return _uniqueToolCalls(mergedToolCalls);
  }

  static int? _matchingToolCallIndex(
    ToolCall fallbackToolCall, {
    required int nameOrdinal,
    required List<ToolCall> toolCalls,
  }) {
    final fallbackIsGenerated = _isGeneratedToolID(fallbackToolCall.id);

    if (!fallbackIsGenerated) {
      for (var i = 0; i < toolCalls.length; i++) {
        final toolCall = toolCalls[i];
        if (!_isGeneratedToolID(toolCall.id) && toolCall.id == fallbackToolCall.id) {
          return i;
        }
      }
    }

    final fallbackFingerprint = _toolCallFingerprint(fallbackToolCall);
    for (var i = 0; i < toolCalls.length; i++) {
      final toolCall = toolCalls[i];
      if ((fallbackIsGenerated || _isGeneratedToolID(toolCall.id)) &&
          _toolCallFingerprint(toolCall) == fallbackFingerprint) {
        return i;
      }
    }

    return _matchingToolCallNameOrdinalIndex(
      fallbackToolCall,
      fallbackIsGenerated: fallbackIsGenerated,
      nameOrdinal: nameOrdinal,
      toolCalls: toolCalls,
    );
  }

  static int? _matchingToolCallNameOrdinalIndex(
    ToolCall fallbackToolCall, {
    required bool fallbackIsGenerated,
    required int nameOrdinal,
    required List<ToolCall> toolCalls,
  }) {
    final fallbackNameKey = _toolCallNameKey(fallbackToolCall);
    var currentOrdinal = 0;

    for (var index = 0; index < toolCalls.length; index++) {
      final toolCall = toolCalls[index];
      if (_toolCallNameKey(toolCall) != fallbackNameKey) continue;
      if (!fallbackIsGenerated && !_isGeneratedToolID(toolCall.id)) continue;

      currentOrdinal += 1;
      if (currentOrdinal == nameOrdinal) {
        return index;
      }
    }
    return null;
  }

  static String _toolCallNameKey(ToolCall toolCall) => toolCall.displayName.trim();

  static String _argumentsKey(Map<String, JsonValue>? args) {
    if (args == null || args.isEmpty) return '';
    final keys = args.keys.toList()..sort();
    final sortedObject = <String, JsonValue>{
      for (final key in keys) key: args[key]!,
    };
    return JsonObject(sortedObject).compactJsonString ?? '';
  }

  static String _toolCallFingerprint(ToolCall toolCall) {
    return ['fallback', toolCall.displayName, _argumentsKey(toolCall.args)]
        .join(':');
  }

  static bool _isGeneratedToolID(String id) {
    return id.startsWith('live-tool-') ||
        id.startsWith('message-tool-') ||
        id.startsWith('persisted-tool-');
  }

  static ToolCall _mergingToolCall(
    ToolCall existing, {
    required ToolCall fallbackCall,
  }) {
    final id = _isGeneratedToolID(existing.id) && !_isGeneratedToolID(fallbackCall.id)
        ? fallbackCall.id
        : existing.id;
    return ToolCall(
      id: id,
      name: existing.name ?? fallbackCall.name,
      preview: existing.preview ?? fallbackCall.preview,
      args: existing.args ?? fallbackCall.args,
      duration: existing.duration ?? fallbackCall.duration,
      isError: _mergedErrorState(existing.isError, fallbackCall.isError),
      isCompleted: existing.isCompleted || fallbackCall.isCompleted,
      startedAt: existing.startedAt < fallbackCall.startedAt
          ? existing.startedAt
          : fallbackCall.startedAt,
    );
  }

  static bool? _mergedErrorState(bool? existing, bool? fallback) {
    if (existing == true || fallback == true) return true;
    return existing ?? fallback;
  }

  static Map<String, JsonValue>? _arguments(JsonValue? value) {
    if (value == null) return null;
    if (value is JsonObject) {
      return value.value.isEmpty ? null : value.value;
    }
    if (value is JsonString) {
      final decoded = _tryDecodeJson(value.value);
      if (decoded is JsonObject) {
        return decoded.value.isEmpty ? null : decoded.value;
      }
    }
    return null;
  }

  static JsonValue? _tryDecodeJson(String source) {
    try {
      return JsonValue.fromJson(jsonDecode(source));
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is ToolCallGroup &&
        other.id == id &&
        other.anchorMessageID == anchorMessageID &&
        deepEquals(other.toolCalls, toolCalls);
  }

  @override
  int get hashCode => Object.hash(id, anchorMessageID, deepHash(toolCalls));

  @override
  String toString() {
    return 'ToolCallGroup(id: $id, anchorMessageID: $anchorMessageID, '
        'toolCalls: ${toolCalls.length})';
  }
}

/// 按 anchor 分组查找表（Swift `ToolCallGroupAnchorLookup`）。
class ToolCallGroupAnchorLookup {
  ToolCallGroupAnchorLookup({List<ToolCallGroup> groups = const []}) {
    for (final group in groups) {
      _groupsByAnchor.putIfAbsent(group.anchorMessageID, () => []).add(group);
    }
  }

  final Map<String?, List<ToolCallGroup>> _groupsByAnchor = {};

  List<ToolCallGroup> groups({String? anchorMessageID}) {
    return _groupsByAnchor[anchorMessageID] ?? const [];
  }
}

/// 回合组构建器（Swift 私有 `TurnGroupBuilder`）。
class _TurnGroupBuilder {
  _TurnGroupBuilder({
    required this.turnKey,
    required ToolCallGroup group,
    required this.anchorIndex,
  })  : id = group.id,
        anchorMessageID = group.anchorMessageID,
        toolCalls = List<ToolCall>.from(group.toolCalls);

  final String turnKey;
  String id;
  String? anchorMessageID;
  int anchorIndex;
  List<ToolCall> toolCalls;

  void append(ToolCallGroup group, {required int anchorIndex}) {
    if (anchorIndex < this.anchorIndex) {
      id = group.id;
      anchorMessageID = group.anchorMessageID;
      this.anchorIndex = anchorIndex;
    }
    toolCalls += group.toolCalls;
  }
}
