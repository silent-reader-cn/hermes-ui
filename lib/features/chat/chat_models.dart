import 'dart:convert';

import '../../core/models/chat_message.dart';
import '../../core/models/json_value.dart';
import '../../core/models/tool_call.dart';

/// 展示层转录消息（chat_spec.md §6.2；只读派生，不存状态）。
class TranscriptMessage {
  const TranscriptMessage({
    required this.loadedIndex,
    required this.renderId,
    required this.anchorId,
    required this.message,
  });

  /// 在 messages 中的下标。
  final int loadedIndex;

  /// `transcript:<offset+loadedIndex>`（ListView key，必须稳定）。
  final String renderId;

  /// TranscriptTurnClassifier.anchorID。
  final String anchorId;

  final ChatMessage message;
}

/// 已归档推理段（按 assistant turn 分组渲染折叠块）。
class ReasoningGroup {
  const ReasoningGroup({this.anchorMessageId, required this.text});

  final String? anchorMessageId;
  final String text;

  /// 从消息列表提取全部已归档推理段（按 assistant anchor 关联）。
  static List<ReasoningGroup> groups({
    required List<ChatMessage> messages,
    int? messageOffset,
  }) {
    final groups = <ReasoningGroup>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != 'assistant') continue;
      final text = message.reasoning?.trim();
      if (text == null || text.isEmpty) continue;
      final anchor = TranscriptTurnClassifier.anchorID(
        message,
        at: i,
        messageOffset: messageOffset,
      );
      groups.add(ReasoningGroup(anchorMessageId: anchor, text: text));
    }
    return groups;
  }

  /// 主推理组 + 兜底推理组按 anchorMessageId 合并。
  static List<ReasoningGroup> merging({
    required List<ReasoningGroup> primaryGroups,
    required List<ReasoningGroup> fallbackGroups,
  }) {
    final merged = List<ReasoningGroup>.from(primaryGroups);
    final groupIndexesByAnchor = <String, int>{};
    for (var i = 0; i < primaryGroups.length; i++) {
      final anchor = primaryGroups[i].anchorMessageId;
      if (anchor != null) groupIndexesByAnchor[anchor] = i;
    }

    for (final fallbackGroup in fallbackGroups) {
      final anchor = fallbackGroup.anchorMessageId;
      final groupIndex = anchor == null ? null : groupIndexesByAnchor[anchor];
      if (groupIndex == null) {
        if (anchor != null) {
          groupIndexesByAnchor[anchor] = merged.length;
        }
        merged.add(fallbackGroup);
        continue;
      }

      final existingGroup = merged[groupIndex];
      if (existingGroup.text.trim().isEmpty &&
          fallbackGroup.text.trim().isNotEmpty) {
        merged[groupIndex] = fallbackGroup;
      }
    }
    return merged;
  }

  @override
  bool operator ==(Object other) {
    return other is ReasoningGroup &&
        other.anchorMessageId == anchorMessageId &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(anchorMessageId, text);

  @override
  String toString() =>
      'ReasoningGroup(anchorMessageId: $anchorMessageId, text: $text)';
}

// ---------------------------------------------------------------------------
// 工具调用展示格式化（chat_spec.md §3.5 ToolCallDisplayFormatter → Dart）
// ---------------------------------------------------------------------------

/// 工具调用卡片渲染内容的纯函数格式化器。
class ToolCallDisplayFormatter {
  const ToolCallDisplayFormatter._();

  /// 参数行：args（Map）按键名排序，值转显示文本。
  static String argumentsLine(ToolCall call) {
    final args = call.args;
    if (args == null || args.isEmpty) return '';
    final keys = args.keys.toList()..sort();
    return keys.map((key) => '$key: ${toolDisplayText(args[key])}').join('\n');
  }

  /// 单值显示文本：对象 → 缩进树；数组 → "- " 列表；字符串 → 换行归一化。
  static String toolDisplayText(JsonValue? value) {
    if (value == null) return '';
    return switch (value) {
      JsonNull() => 'null',
      JsonBool(:final value) => '$value',
      JsonNumber(:final value) => _formatNumber(value),
      JsonString(:final value) => _normalizeNewlines(value),
      JsonArray(:final value) => value
          .map((e) => '- ${toolDisplayText(e)}')
          .join('\n'),
      JsonObject(:final value) => _objectTree(value),
    };
  }

  static String _objectTree(Map<String, JsonValue> object) {
    final buffer = StringBuffer();
    final keys = object.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final child = toolDisplayText(object[key]);
      final childLines = child.split('\n');
      buffer.write('$key: ${childLines.first}');
      for (final line in childLines.skip(1)) {
        buffer.write('\n  $line');
      }
      if (i != keys.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _normalizeNewlines(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // -------------------------------------------------------------------------
  // 结果（preview）格式化：JSON 解析 → 终端信封 → 可读值 → JSON 树
  // -------------------------------------------------------------------------

  /// 终端工具名集合。
  static const terminalToolNames = {
    'terminal',
    'shell',
    'bash',
    'zsh',
    'command',
    'exec',
    'cmd',
    'powershell',
  };

  /// 结果展示（preview 非空才渲染；空 → ''）。
  static String resultText(ToolCall call, {bool monospaced = false}) {
    final preview = call.preview;
    if (preview == null || preview.trim().isEmpty) return '';

    // 1) 尝试把 preview 当 JSON 解析（含去转义、嵌套解包最多 3 层）。
    final parsed = _tryParseJsonTree(preview);
    if (parsed != null) {
      if (_isTerminalEnvelope(call, parsed)) {
        return _terminalEnvelopeText(parsed);
      }
      final readable = _firstReadableValue(parsed);
      if (readable != null) return readable;
      if (parsed is Map<String, Object?>) {
        return _jsonTreeText(parsed);
      }
      return _scalarText(parsed);
    }

    // 2) 非 JSON：原样展示（等宽由调用方按换行判定）。
    return _normalizeNewlines(preview);
  }

  /// 等宽字体条件：terminal 工具 或 文本含换行 或 由 JSON 解析得出。
  static bool usesMonospace(ToolCall call, {required String resultText}) {
    if (terminalToolNames.contains((call.name ?? '').trim().toLowerCase())) {
      return true;
    }
    if (resultText.contains('\n')) return true;
    return _tryParseJsonTree(call.preview ?? '') != null;
  }

  /// 终端信封格式（output/stdout 优先、接 stderr、Error、非 0 exit_code）。
  /// [parsed] 非 Map（如 terminal 工具名的裸字符串 preview）时按原样返回。
  static String _terminalEnvelopeText(Object? parsed) {
    if (parsed is! Map<String, Object?>) {
      return _scalarText(parsed);
    }
    final object = parsed;
    final buffer = StringBuffer();
    final stdout = _firstNonEmptyString(object, const ['output', 'stdout']);
    final stderr = _firstNonEmptyString(object, const ['stderr']);
    final error = _firstNonEmptyString(object, const ['error']);
    final exitCode = _intField(object, const ['exit_code', 'exitCode']);
    if (stdout != null) buffer.write(stdout);
    if (stderr != null && stderr.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(stderr);
    }
    if (error != null && error.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Error: $error');
    }
    if (exitCode != null && exitCode != 0) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Exit code: $exitCode');
    }
    return buffer.toString();
  }

  /// 终端信封判定：terminal 工具名 或 对象含 output/stdout/stderr/exit_code/
  /// exitCode/error 键。
  static bool _isTerminalEnvelope(ToolCall call, Object? parsed) {
    final name = (call.name ?? '').trim().toLowerCase();
    if (terminalToolNames.contains(name)) return true;
    if (parsed is Map<String, Object?>) {
      const keys = {
        'output',
        'stdout',
        'stderr',
        'exit_code',
        'exitCode',
        'error',
      };
      return parsed.keys.any(keys.contains);
    }
    return false;
  }

  /// 可读值：result/results/preview/content/text/message/summary/data/items
  /// 顺序取第一个可读值；再试 error；都没有 → null。
  static String? _firstReadableValue(Object? parsed) {
    if (parsed is Map<String, Object?>) {
      const keys = [
        'result',
        'results',
        'preview',
        'content',
        'text',
        'message',
        'summary',
        'data',
        'items',
      ];
      for (final key in keys) {
        final value = parsed[key];
        if (value == null) continue;
        if (value is String && value.trim().isNotEmpty) {
          return _normalizeNewlines(value);
        }
        if (value is num || value is bool) return _scalarText(value);
      }
      final error = parsed['error'];
      if (error is String && error.trim().isNotEmpty) {
        return 'Error: ${_normalizeNewlines(error)}';
      }
    }
    return null;
  }

  /// 对象 JSON 树文本。
  static String _jsonTreeText(Map<String, Object?> object) {
    final buffer = StringBuffer();
    final keys = object.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final value = object[key];
      final line = _scalarText(value);
      final lines = line.split('\n');
      buffer.write('$key: ${lines.first}');
      for (final rest in lines.skip(1)) {
        buffer.write('\n  $rest');
      }
      if (i != keys.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _scalarText(Object? value) {
    if (value == null) return 'null';
    if (value is String) return _normalizeNewlines(value);
    if (value is num) return _formatNumber(value.toDouble());
    if (value is bool) return '$value';
    if (value is Map) return jsonEncode(value);
    if (value is List) {
      return value.map(_scalarText).map((e) => '- $e').join('\n');
    }
    return value.toString();
  }

  static String? _firstNonEmptyString(
    Map<String, Object?> object,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = object[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static int? _intField(Map<String, Object?> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is int) return value;
      if (value is double) return value.truncate();
      if (value is String) return int.tryParse(value.trim());
    }
    return null;
  }

  /// 尝试把 preview 当 JSON 解析（含去转义、嵌套解包最多 3 层）。
  /// 解析成功返回解包后的值；失败返回 null。
  static Object? _tryParseJsonTree(String preview) {
    var candidate = preview.trim();
    for (var depth = 0; depth < 3; depth++) {
      final decoded = _decodeJson(candidate);
      if (decoded == null) return null;
      // 嵌套解包：JSON 字符串里再包 JSON → 继续解。
      if (decoded is String) {
        final inner = decoded.trim();
        final again = _decodeJson(inner);
        if (again == null) return decoded;
        candidate = inner;
        continue;
      }
      return decoded;
    }
    return _decodeJson(candidate);
  }

  static Object? _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

/// 工具调用展示内容（名称行 + 参数行 + 结果文本 + 等宽判定）。
class ToolCallDisplayContent {
  const ToolCallDisplayContent({
    required this.arguments,
    required this.result,
    required this.monospaced,
  });

  final String arguments;
  final String result;
  final bool monospaced;

  factory ToolCallDisplayContent.of(ToolCall call) {
    final arguments = ToolCallDisplayFormatter.argumentsLine(call);
    final result = ToolCallDisplayFormatter.resultText(call);
    final monospaced = ToolCallDisplayFormatter.usesMonospace(
      call,
      resultText: result,
    );
    return ToolCallDisplayContent(
      arguments: arguments,
      result: result,
      monospaced: monospaced,
    );
  }
}
