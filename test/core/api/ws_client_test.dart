import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/custom_header.dart';
import 'package:hermex_flutter/core/api/ws_client.dart';
import 'package:hermex_flutter/core/models/kanban.dart';

void main() {
  group('KanbanStreamFrame 数据结构与 Equality', () {
    test('KanbanHelloFrame 相等性与 hashCode', () {
      const h1 = KanbanHelloFrame(cursor: 1, board: 'dev');
      const h2 = KanbanHelloFrame(cursor: 1, board: 'dev');
      const h3 = KanbanHelloFrame(cursor: 2, board: 'dev');
      const h4 = KanbanHelloFrame(cursor: 1, board: 'prod');

      expect(h1, equals(h2));
      expect(h1.hashCode, equals(h2.hashCode));
      expect(h1 == h3, isFalse);
      expect(h1 == h4, isFalse);
    });

    test('KanbanEventsFrame 强类型事件相等性与 _sameEvents 比对', () {
      const e1 = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
          KanbanEvent(eventID: 2, cardID: 'c2', kind: 'status_changed'),
        ],
        cursor: 10,
        frameId: 42,
      );

      const e2 = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
          KanbanEvent(eventID: 2, cardID: 'c2', kind: 'status_changed'),
        ],
        cursor: 10,
        frameId: 42,
      );

      const eDifferentEvents = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
          KanbanEvent(eventID: 3, cardID: 'c2', kind: 'status_changed'),
        ],
        cursor: 10,
        frameId: 42,
      );

      const eDifferentLength = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
        ],
        cursor: 10,
        frameId: 42,
      );

      const eDifferentCursor = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
        ],
        cursor: 11,
      );

      const eDifferentFrameId = KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 1, cardID: 'c1', kind: 'created'),
        ],
        cursor: 10,
        frameId: 99,
      );

      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));
      expect(e1 == eDifferentEvents, isFalse);
      expect(e1 == eDifferentLength, isFalse);
      expect(e1 == eDifferentCursor, isFalse);
      expect(e1 == eDifferentFrameId, isFalse);
    });

    test('KanbanIgnoredFrame 与 KanbanMalformedFrame 相等性', () {
      expect(const KanbanIgnoredFrame(), equals(const KanbanIgnoredFrame()));
      expect(const KanbanIgnoredFrame().hashCode, 0);

      expect(const KanbanMalformedFrame(), equals(const KanbanMalformedFrame()));
      expect(const KanbanMalformedFrame().hashCode, 1);
    });
  });

  group('KanbanStreamFrameDecoder 解码器', () {
    test('hello 帧正常解码', () {
      final frame = KanbanStreamFrameDecoder.decode(
        eventType: 'hello',
        data: '{"cursor": 5, "board": "engineering"}',
      );
      expect(frame, isA<KanbanHelloFrame>());
      final hello = frame as KanbanHelloFrame;
      expect(hello.cursor, 5);
      expect(hello.board, 'engineering');
    });

    test('hello 帧畸形（cursor<0、board 为空/缺失）→ KanbanMalformedFrame', () {
      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'hello',
          data: '{"cursor": -1, "board": "dev"}',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'hello',
          data: '{"cursor": 0, "board": "   "}',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'hello',
          data: '{"board": "dev"}',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'hello',
          data: 'not a json',
        ),
        isA<KanbanMalformedFrame>(),
      );
    });

    test('events 帧正常解码为 List<KanbanEvent> 强类型', () {
      final frame = KanbanStreamFrameDecoder.decode(
        eventType: 'events',
        data: '''
        {
          "cursor": 15,
          "events": [
            {
              "id": 101,
              "taskId": "task_A",
              "runId": "run_9",
              "kind": "status_changed",
              "created_at": 1723700000
            },
            {
              "event_id": 102,
              "card_id": "card_B",
              "kind": "comment_added",
              "timestamp": 1723700500
            }
          ]
        }
        ''',
        frameId: '888',
      );

      expect(frame, isA<KanbanEventsFrame>());
      final eventsFrame = frame as KanbanEventsFrame;
      expect(eventsFrame.cursor, 15);
      expect(eventsFrame.frameId, 888);
      expect(eventsFrame.events, hasLength(2));

      final ev1 = eventsFrame.events[0];
      expect(ev1.eventID, 101);
      expect(ev1.cardID, 'task_A');
      expect(ev1.runID, 'run_9');
      expect(ev1.kind, 'status_changed');
      expect(ev1.createdAt, 1723700000);

      final ev2 = eventsFrame.events[1];
      expect(ev2.eventID, 102);
      expect(ev2.cardID, 'card_B');
      expect(ev2.kind, 'comment_added');
      expect(ev2.createdAt, 1723700500);
    });

    test('events 帧非对象元素容错跳过', () {
      final frame = KanbanStreamFrameDecoder.decode(
        eventType: 'events',
        data: '{"cursor": 2, "events": ["string_item", null, {"id": 5, "taskId": "c5"}]}',
      );
      expect(frame, isA<KanbanEventsFrame>());
      final eventsFrame = frame as KanbanEventsFrame;
      expect(eventsFrame.events, hasLength(1));
      expect(eventsFrame.events.single.eventID, 5);
      expect(eventsFrame.events.single.cardID, 'c5');
    });

    test('events 帧畸形（cursor<0、events 非数组、frameId 非 int）→ KanbanMalformedFrame', () {
      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'events',
          data: '{"cursor": -1, "events": []}',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'events',
          data: '{"cursor": 0, "events": "not-a-list"}',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'events',
          data: '{"cursor": 5, "events": []}',
          frameId: 'not_an_int',
        ),
        isA<KanbanMalformedFrame>(),
      );

      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'events',
          data: 'invalid-json',
        ),
        isA<KanbanMalformedFrame>(),
      );
    });

    test('未知事件名 → KanbanIgnoredFrame', () {
      expect(
        KanbanStreamFrameDecoder.decode(
          eventType: 'unknown_kind',
          data: '{}',
        ),
        isA<KanbanIgnoredFrame>(),
      );
    });
  });

  group('KanbanEvent 模型扩展', () {
    test('KanbanEvent.fromJson 兼容多种 key 格式', () {
      final ev = KanbanEvent.fromJson({
        'eventId': 77,
        'card_id': 'c77',
        'run_id': 'r77',
        'kind': 'updated',
        'createdAt': 123456789,
      });
      expect(ev.eventID, 77);
      expect(ev.cardID, 'c77');
      expect(ev.runID, 'r77');
      expect(ev.kind, 'updated');
      expect(ev.createdAt, 123456789);

      final json = ev.toJson();
      expect(json['id'], 77);
      expect(json['taskId'], 'c77');
      expect(json['runId'], 'r77');
      expect(json['kind'], 'updated');
      expect(json['created_at'], 123456789);
    });
  });

  group('KanbanEventStreamClient 传输层', () {
    test('正常接收 hello 与 events 帧', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          'event: hello\ndata: {"cursor":0,"board":"main"}\n\n'
          'event: events\nid: 10\ndata: {"cursor":1,"events":[{"id":1,"taskId":"c1","kind":"created"}]}\n\n',
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;

      final client = KanbanEventStreamClient(
        dio: dio,
        baseUrl: 'https://example.com',
        customHeaderProvider: () => const [
          CustomHeader(name: 'X-App-Ver', value: '1.0'),
        ],
      );

      final frames = <KanbanStreamFrame>[];
      var failureCalled = false;

      await client.start(
        Uri.parse('https://example.com/api/v1/kanban/stream?board=main&since=0'),
        onFrame: (frame) => frames.add(frame),
        onFailure: () => failureCalled = true,
      );

      expect(frames, hasLength(2));
      expect(frames[0], isA<KanbanHelloFrame>());
      expect((frames[0] as KanbanHelloFrame).board, 'main');
      expect(frames[1], isA<KanbanEventsFrame>());
      final eventsFrame = frames[1] as KanbanEventsFrame;
      expect(eventsFrame.frameId, 10);
      expect(eventsFrame.events.single.cardID, 'c1');
      expect(failureCalled, isTrue); // 流结束调用 onFailure
    });

    test('传输层错误通过 onTransportError 透出', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          'bad gateway',
          502,
          headers: {'content-type': ['text/plain']},
        ),
      );
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;

      final client = KanbanEventStreamClient(
        dio: dio,
        baseUrl: 'https://example.com',
      );

      String? transportErrorMsg;
      var failureCalled = false;

      await client.start(
        Uri.parse('https://example.com/stream'),
        onFrame: (_) {},
        onFailure: () => failureCalled = true,
        onTransportError: (msg) => transportErrorMsg = msg,
      );

      expect(failureCalled, isTrue);
      expect(transportErrorMsg, isNotNull);
      expect(transportErrorMsg, contains('502'));
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}
