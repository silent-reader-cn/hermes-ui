import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/upload_response.dart';

void main() {
  group('UploadResponse', () {
    test('规格示例正常解析', () {
      final response = UploadResponse.fromJson({
        'filename': 'a.png',
        'path': '/uploads/a.png',
        'size': 204800,
        'mime': 'image/png',
        'is_image': true,
      });
      expect(response.filename, 'a.png');
      expect(response.path, '/uploads/a.png');
      expect(response.size, 204800);
      expect(response.mime, 'image/png');
      expect(response.isImage, true);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final response = UploadResponse.fromJson({
        'filename': 1,
        'size': 'big',
        'is_image': 'yes',
        'error': 2,
      });
      expect(response.filename, '1');
      expect(response.size, isNull);
      expect(response.isImage, true);
      expect(response.error, '2');
      expect(UploadResponse.fromJson(const {}).path, isNull);
    });
  });

  group('PendingAttachment（本地模型）', () {
    test('toJsonValue 输出 {name, path, mime, size, is_image}', () {
      final attachment = PendingAttachment(
        name: 'a.png',
        path: '/tmp/a.png',
        mime: 'image/png',
        size: 204800,
        isImage: true,
      );
      final decoded = jsonDecode(jsonEncode(attachment.toJsonValue().toJson()));
      expect(decoded, {
        'name': 'a.png',
        'path': '/tmp/a.png',
        'mime': 'image/png',
        'size': 204800.0,
        'is_image': true,
      });
      expect(attachment.id, isNotEmpty);
    });

    test('chatReference / chatMessageText / 上传上限', () {
      final attachment = PendingAttachment(
        name: 'a.png',
        path: '/tmp/a.png',
        mime: 'image/png',
      );
      expect(attachment.chatReference, '/tmp/a.png');
      expect(
        PendingAttachment(name: 'a.png', path: '', mime: 'x').chatReference,
        'a.png',
      );
      expect(
        PendingAttachment.chatMessageText('draft', [attachment]),
        'draft\n\n[Attached files: /tmp/a.png]',
      );
      expect(PendingAttachment.chatMessageText('draft', const []), 'draft');
      expect(PendingAttachment.maximumUploadBytes, 20 * 1024 * 1024);
      expect(
        PendingAttachment.uploadTooLargeMessage('big.mp4'),
        'big.mp4 is too large. Attachments must be 20 MB or smaller.',
      );
    });

    test('无 size 时 toJsonValue 省略 size', () {
      final attachment = PendingAttachment(
        name: 'a',
        path: '/p/a',
        mime: 'text/plain',
      );
      final decoded = jsonDecode(jsonEncode(attachment.toJsonValue().toJson()));
      expect(decoded.containsKey('size'), false);
      expect(decoded['is_image'], false);
    });
  });

  test('== / hashCode', () {
    final a = UploadResponse.fromJson({'filename': 'x'});
    final b = UploadResponse.fromJson({'filename': 'x'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
