import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'custom_header.dart';
import 'sse_client.dart';

// ---------------------------------------------------------------------------
// Kanban 事件流帧（KanbanEventStreamClient.swift 等价物）
//
// 注意：尽管本文件名为 ws_client.dart（任务命名），Kanban 事件流实际是
// **SSE 独立帧协议**（api_spec.md §3，参考 KanbanEventStreamClient.swift 用
// LDSwiftEventSource 实现），并非 WebSocket。事件名只有 `hello` 与 `events`，
// 其余事件类型 → ignored，畸形帧 → malformed。web_socket_channel 依赖保留给
// 未来真正的 WS 通道。
// ---------------------------------------------------------------------------

/// Kanban 事件流帧（Equatable 语义：==/hashCode 已实现）。
sealed class KanbanStreamFrame {
  const KanbanStreamFrame();
}

/// `hello` → `{cursor, board}`（cursor ≥ 0，board 非空）。
class KanbanHelloFrame extends KanbanStreamFrame {
  const KanbanHelloFrame({required this.cursor, required this.board});

  final int cursor;
  final String board;

  @override
  bool operator ==(Object other) =>
      other is KanbanHelloFrame &&
      other.cursor == cursor &&
      other.board == board;

  @override
  int get hashCode => Object.hash(cursor, board);
}

/// `events` → `{events[], cursor}`（帧 id 取 SSE lastEventId）。
class KanbanEventsFrame extends KanbanStreamFrame {
  const KanbanEventsFrame({
    required this.events,
    required this.cursor,
    this.frameId,
  });

  /// TODO(merge)：模型就绪后改为 `List<KanbanEvent>`。
  final List<Map<String, Object?>> events;
  final int cursor;

  /// SSE `id:` 行解析出的帧 id（缺失为 null）。
  final int? frameId;

  @override
  bool operator ==(Object other) =>
      other is KanbanEventsFrame &&
      other.cursor == cursor &&
      other.frameId == frameId &&
      _sameEvents(other.events);

  @override
  int get hashCode => Object.hash(events.length, cursor, frameId);

  bool _sameEvents(List<Map<String, Object?>> other) {
    if (other.length != events.length) return false;
    for (var i = 0; i < events.length; i++) {
      if (!_mapsEqual(events[i], other[i])) return false;
    }
    return true;
  }

  bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return _mapsEqual(
        Map<String, Object?>.from(a),
        Map<String, Object?>.from(b),
      );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// 未知事件类型（静默丢弃）。
class KanbanIgnoredFrame extends KanbanStreamFrame {
  const KanbanIgnoredFrame();

  @override
  bool operator ==(Object other) => other is KanbanIgnoredFrame;

  @override
  int get hashCode => 0;
}

/// 畸形帧（载荷/游标/帧 id 不合法）。
class KanbanMalformedFrame extends KanbanStreamFrame {
  const KanbanMalformedFrame();

  @override
  bool operator ==(Object other) => other is KanbanMalformedFrame;

  @override
  int get hashCode => 1;
}

/// 帧解码器（KanbanStreamFrameDecoder.swift 等价物）。
///
/// - `hello`：`{cursor, board}`，cursor ≥ 0 且 board trim 后非空，否则 malformed。
/// - `events`：`{events[], cursor}`，events 为数组、cursor ≥ 0；SSE id 存在时
///   必须能解析为 int，否则 malformed。
/// - 其他事件名 → ignored。
class KanbanStreamFrameDecoder {
  const KanbanStreamFrameDecoder._();

  static KanbanStreamFrame decode({
    required String eventType,
    required String data,
    String? frameId,
  }) {
    switch (eventType) {
      case 'hello':
        final map = _jsonMap(data);
        final cursor = _int(map['cursor']);
        final board = _string(map['board'])?.trim();
        if (cursor == null || cursor < 0 || board == null || board.isEmpty) {
          return const KanbanMalformedFrame();
        }
        return KanbanHelloFrame(cursor: cursor, board: board);
      case 'events':
        final map = _jsonMap(data);
        final rawEvents = map['events'];
        final cursor = _int(map['cursor']);
        if (rawEvents is! List || cursor == null || cursor < 0) {
          return const KanbanMalformedFrame();
        }
        int? parsedFrameId;
        if (frameId != null) {
          parsedFrameId = int.tryParse(frameId);
          if (parsedFrameId == null) return const KanbanMalformedFrame();
        }
        final events = <Map<String, Object?>>[];
        for (final item in rawEvents) {
          if (item is Map) events.add(Map<String, Object?>.from(item));
        }
        return KanbanEventsFrame(
          events: events,
          cursor: cursor,
          frameId: parsedFrameId,
        );
      default:
        return const KanbanIgnoredFrame();
    }
  }
}

/// Kanban 事件流客户端（SSE 传输，hello/events 帧）。
///
/// 连接错误/流关闭 → [onFailure]（不做重连，由上层决定）；
/// 连接错误消息可选经 [onTransportError] 透出。
class KanbanEventStreamClient {
  KanbanEventStreamClient({
    required this.dio,
    required this.baseUrl,
    List<CustomHeader> Function()? customHeaderProvider,
    this.cookieProvider,
  }) : _customHeaderProvider = customHeaderProvider ?? (() => const []);

  /// 传输用 dio；传入 [ApiClient.dio] 时自动继承其自定义头/cookie 拦截器。
  final Dio dio;

  /// 服务器 base URL（构造流 URL 用）。
  final String baseUrl;

  final List<CustomHeader> Function() _customHeaderProvider;

  /// 按目标 URL 提供 Cookie 头（null 表示无 cookie）；传 [ApiClient.dio] 时
  /// 可省略（拦截器已处理）。
  final String? Function(Uri uri)? cookieProvider;
  CancelToken? _cancelToken;

  Future<void> start(
    Uri url, {
    required void Function(KanbanStreamFrame frame) onFrame,
    required void Function() onFailure,
    void Function(String message)? onTransportError,
  }) async {
    _cancelToken = CancelToken();
    await connectSse(
      dio: dio,
      url: url,
      customHeaderProvider: _customHeaderProvider,
      cookieProvider: cookieProvider,
      cancelToken: _cancelToken,
      onEvent: (wire) {
        if (wire.heartbeat) return; // 注释行不是帧
        final frame = KanbanStreamFrameDecoder.decode(
          eventType: wire.eventType,
          data: wire.data,
          frameId: wire.id,
        );
        onFrame(frame);
      },
      onTransportError: (message) {
        onTransportError?.call(message);
        onFailure();
      },
      onClosed: onFailure,
    );
  }

  void stop() => _cancelToken?.cancel();
}

// ---------------------------------------------------------------------------
// 容错 JSON 读取辅助
// ---------------------------------------------------------------------------

Map<String, Object?> _jsonMap(String data) {
  if (data.isEmpty) return const {};
  try {
    final json = jsonDecode(data);
    if (json is Map) return Map<String, Object?>.from(json);
  } catch (_) {
    // 畸形 JSON → 空 map（上层判 malformed）。
  }
  return const {};
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
