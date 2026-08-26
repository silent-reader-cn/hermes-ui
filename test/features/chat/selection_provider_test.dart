import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/selection_provider.dart';

void main() {
  group('selection_provider', () {
    test('add increments id and names Context N', () {
      final n = SelectionNotifier();
      n.add('hello');
      n.add('world');
      expect(n.state.length, 2);
      expect(n.state[0].id, 'ctx-1');
      expect(n.state[0].name, 'Context 1');
      expect(n.state[1].id, 'ctx-2');
      expect(n.state[1].name, 'Context 2');
    });

    test('rename trims, caps 120, empty falls back', () {
      final n = SelectionNotifier()..add('t');
      final id = n.state.first.id;
      n.rename(id, '  new name  ');
      expect(n.state.first.name, 'new name');
      n.rename(id, '   ');
      expect(n.state.first.name, 'new name');
      final long = 'a' * 200;
      n.rename(id, long);
      expect(n.state.first.name.length, 120);
    });

    test('remove and clear reset counter when empty', () {
      final n = SelectionNotifier()
        ..add('a')
        ..add('b');
      final id1 = n.state[0].id;
      n.remove(id1);
      expect(n.state.length, 1);
      expect(n.state.first.id, 'ctx-2');
      n.remove(n.state.first.id);
      expect(n.state, isEmpty);
      n.add('c');
      expect(n.state.first.id, 'ctx-1');
      n.add('d');
      n.clear();
      expect(n.state, isEmpty);
      n.add('e');
      expect(n.state.first.id, 'ctx-1');
    });

    test('selectedContextPreview normalization and 360 truncation', () {
      expect(selectedContextPreview(''), '');
      expect(selectedContextPreview('a\r\nb\rc'), 'a\nb\nc');
      final long = 'x' * 400;
      final p = selectedContextPreview(long);
      expect(p.endsWith('…'), isTrue);
      expect(p.length, 361);
      expect(selectedContextPreview('x' * 360).endsWith('…'), isFalse);
    });

    test('buildMessageForApi single block + current', () {
      final pending = [
        const PendingSelection(id: 'ctx-1', name: 'Context 1', text: 'hello\nworld'),
      ];
      expect(
        buildMessageForApiWithPending(pending, '请解释一下'),
        '请解释一下\n\n**Context 1:**\n<!-- hermes-selected-context -->\n> hello\n> world\n\n',
      );
    });

    test('buildMessageForApi multi blocks with empty current', () {
      final pending = [
        const PendingSelection(id: 'ctx-1', name: '报错', text: 'Null check'),
        const PendingSelection(id: 'ctx-2', name: 'Context 2', text: 'lib/main.dart:42'),
      ];
      const want =
          '**报错:**\n<!-- hermes-selected-context -->\n> Null check\n\n**Context 2:**\n<!-- hermes-selected-context -->\n> lib/main.dart:42\n\n';
      expect(buildMessageForApiWithPending(pending, ''), want);
      expect(buildMessageForApiWithPending(pending, '  '), want);
    });

    test('buildMessageForApi skips empty normalized blocks', () {
      final pending = [const PendingSelection(id: 'ctx-1', name: 'Context 1', text: '   \n  ')];
      expect(buildMessageForApiWithPending(pending, 'hi'), 'hi');
      expect(buildMessageForApiWithPending(pending, ''), '');
    });

    test('buildMessageForApi current trailing trim + blocks', () {
      final pending = [const PendingSelection(id: 'ctx-1', name: 'Context 1', text: 'q')];
      expect(
        buildMessageForApiWithPending(pending, 'hello   \n\n  '),
        'hello\n\n**Context 1:**\n<!-- hermes-selected-context -->\n> q\n\n',
      );
    });

    test('SelectionNotifier.buildMessageForApi delegates', () {
      final n = SelectionNotifier()..add('a');
      expect(n.buildMessageForApi('hi'), buildMessageForApiWithPending(n.state, 'hi'));
    });

    test('pending empty returns current as-is', () {
      expect(buildMessageForApiWithPending(const [], ' hi '), ' hi ');
      expect(buildMessageForApiWithPending(const [], ''), '');
    });
  });
}
