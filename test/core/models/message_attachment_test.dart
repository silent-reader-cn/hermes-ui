import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/message_attachment.dart';

void main() {
  group('MessageAttachment.fromJson 正常解析', () {
    test('对象形态（规格示例）', () {
      final attachment = MessageAttachment.fromJson({
        'name': 'photo.png',
        'path': '/uploads/photo.png',
        'mime': 'image/png',
        'size': 204800,
        'is_image': true,
      });
      expect(attachment.name, 'photo.png');
      expect(attachment.path, '/uploads/photo.png');
      expect(attachment.mime, 'image/png');
      expect(attachment.size, 204800);
      expect(attachment.isImage, true);
    });

    test('裸字符串形态（旧服务器）', () {
      final attachment = MessageAttachment.fromJson('legacy_file.txt');
      expect(attachment.name, 'legacy_file.txt');
      expect(attachment.path, isNull);
      expect(attachment.mime, isNull);
      expect(attachment.size, isNull);
      expect(attachment.isImage, isNull);
    });

    test('filename 双键 + lossy 转换', () {
      final attachment = MessageAttachment.fromJson({
        'filename': 'a.txt',
        'size': '1024',
        'is_image': 1,
      });
      expect(attachment.name, 'a.txt');
      expect(attachment.size, 1024);
      expect(attachment.isImage, true);
    });
  });

  group('MessageAttachment.fromJson 畸形输入', () {
    test('字段缺失 → 全 null', () {
      final attachment = MessageAttachment.fromJson(const <String, Object?>{});
      expect(attachment.name, isNull);
      expect(attachment.path, isNull);
      expect(attachment.mime, isNull);
      expect(attachment.size, isNull);
      expect(attachment.isImage, isNull);
    });

    test('类型不符 → lossy 容错，绝不 throw', () {
      final attachment = MessageAttachment.fromJson({
        'name': 42,
        'path': false,
        'size': 'oops',
        'is_image': {'x': 1},
      });
      expect(attachment.name, '42');
      // lossyString 把 bool 转 'true'/'false'
      expect(attachment.path, 'false');
      expect(attachment.size, isNull);
      expect(attachment.isImage, isNull);
    });

    test('非对象非字符串（数字/列表）→ 空附件', () {
      final attachment = MessageAttachment.fromJson(123);
      expect(attachment.name, isNull);
      expect(attachment.path, isNull);
    });
  });

  group('identityKey', () {
    test('name/path 第一个非空值的 basename 小写', () {
      expect(
        const MessageAttachment(name: 'Photo.PNG', path: '/x/y.png').identityKey,
        'photo.png',
      );
      expect(
        const MessageAttachment(path: '/uploads/voice.m4a').identityKey,
        'voice.m4a',
      );
      expect(const MessageAttachment(name: '  ').identityKey, isNull);
    });
  });

  group('Attached files 标记', () {
    test('inferredFromAttachedFilesMarker：推断附件并补 isImage', () {
      final attachments = MessageAttachment.inferredFromAttachedFilesMarker(
        '看这个\n\n[Attached files: /tmp/photo.png, notes.txt]',
      );
      expect(attachments, isNotNull);
      expect(attachments!.length, 2);
      expect(attachments[0].name, 'photo.png');
      expect(attachments[0].path, '/tmp/photo.png');
      expect(attachments[0].isImage, true);
      // 非图片引用不补推断路径（对齐 Swift：仅图片引用用 fallbackDirectory）
      expect(attachments[1].name, 'notes.txt');
      expect(attachments[1].path, isNull);
      expect(attachments[1].isImage, false);
    });

    test('无标记 / 标记后还有内容 → null', () {
      expect(MessageAttachment.inferredFromAttachedFilesMarker('普通文本'), isNull);
      expect(
        MessageAttachment.inferredFromAttachedFilesMarker(
          '[Attached files: a.txt] 后面还有字',
        ),
        isNull,
      );
    });

    test('contentWithoutAttachedFilesMarker：移除标记与前置空白', () {
      expect(
        MessageAttachment.contentWithoutAttachedFilesMarker(
          '你好\n\n[Attached files: a.png]',
        ),
        '你好',
      );
      expect(
        MessageAttachment.contentWithoutAttachedFilesMarker('没有标记'),
        '没有标记',
      );
    });

    test('isImageReference 扩展名判定', () {
      expect(MessageAttachment.isImageReference('a.png'), true);
      expect(MessageAttachment.isImageReference('a.JPG'), true);
      expect(MessageAttachment.isImageReference('a.tiff'), true);
      expect(MessageAttachment.isImageReference('a.txt'), false);
    });
  });

  group('序列化与拼接', () {
    test('toJsonValue 输出 {name, path, mime, size, is_image}', () {
      final value = const MessageAttachment(
        name: 'a.png',
        path: '/tmp/a.png',
        mime: 'image/png',
        size: 10,
        isImage: true,
      ).toJsonValue();
      final decoded = jsonDecode(jsonEncode(value.toJson()));
      expect(decoded, {
        'name': 'a.png',
        'path': '/tmp/a.png',
        'mime': 'image/png',
        'size': 10.0,
        'is_image': true,
      });
    });

    test('chatMessageText 拼接 [Attached files: …]', () {
      final text = MessageAttachment.chatMessageText(
        'draft',
        const [
          MessageAttachment(name: 'a.png', path: '/x/a.png'),
          MessageAttachment(name: 'b.txt'),
        ],
      );
      expect(text, 'draft\n\n[Attached files: /x/a.png, b.txt]');
      expect(
        MessageAttachment.chatMessageText('draft', const []),
        'draft',
      );
    });
  });

  test('== / hashCode', () {
    const a = MessageAttachment(name: 'a.png', size: 1);
    const b = MessageAttachment(name: 'a.png', size: 1);
    const c = MessageAttachment(name: 'b.png');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
