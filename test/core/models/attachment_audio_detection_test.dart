import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/message_attachment.dart';
import 'package:hermex_flutter/core/utils/attachment_audio_detection.dart';

void main() {
  group('AttachmentAudioDetection.isAudio', () {
    test('isImage == true 直接 false（判定顺序 1）', () {
      expect(
        AttachmentAudioDetection.isAudio(
          isImage: true,
          mime: 'audio/mp3',
          name: 'x.mp3',
        ),
        false,
      );
    });

    test('mime 前缀 audio/ → true（判定顺序 2）', () {
      expect(
        AttachmentAudioDetection.isAudio(mime: 'audio/mpeg', name: 'voice'),
        true,
      );
      expect(
        AttachmentAudioDetection.isAudio(mime: 'AUDIO/wav'),
        true,
      );
      expect(
        AttachmentAudioDetection.isAudio(mime: 'video/mp4', name: 'clip.mp4'),
        false,
      );
    });

    test('name 扩展名 → true（判定顺序 3）', () {
      expect(
        AttachmentAudioDetection.isAudio(name: 'voice note.m4a'),
        true,
      );
      // 显示名无扩展名时回退 path（判定顺序 4）
      expect(
        AttachmentAudioDetection.isAudio(
          name: 'Voice note',
          path: '/uploads/voice.m4a',
        ),
        true,
      );
      expect(
        AttachmentAudioDetection.isAudio(name: 'pic.png'),
        false,
      );
    });

    test('audioExtensions 集合覆盖', () {
      for (final ext in [
        'm4a', 'mp3', 'wav', 'aac', 'caf', 'ogg', 'oga', 'opus', 'flac',
      ]) {
        expect(
          AttachmentAudioDetection.isAudio(name: 'a.$ext'),
          true,
          reason: '$ext 应识别为音频',
        );
      }
      expect(AttachmentAudioDetection.isAudio(name: 'a.txt'), false);
    });

    test('全空 → false', () {
      expect(AttachmentAudioDetection.isAudio(), false);
    });
  });

  group('AudioDurationFormatter', () {
    test('m:ss 格式', () {
      expect(AudioDurationFormatter.string(0), '0:00');
      expect(AudioDurationFormatter.string(59.9), '0:59');
      expect(AudioDurationFormatter.string(60), '1:00');
      expect(AudioDurationFormatter.string(65), '1:05');
      expect(AudioDurationFormatter.string(600), '10:00');
    });

    test('h:mm:ss 格式', () {
      expect(AudioDurationFormatter.string(3600), '1:00:00');
      expect(AudioDurationFormatter.string(3661), '1:01:01');
    });

    test('非有限 / 负数 → 0:00', () {
      expect(AudioDurationFormatter.string(double.nan), '0:00');
      expect(AudioDurationFormatter.string(double.infinity), '0:00');
      expect(AudioDurationFormatter.string(-5), '0:00');
    });
  });

  group('MessageAttachment.inferredIsAudio 扩展', () {
    test('音频附件识别', () {
      const attachment = MessageAttachment(
        name: 'voice.m4a',
        path: '/uploads/voice.m4a',
        mime: 'audio/mp4',
      );
      expect(attachment.inferredIsAudio, true);
      const image = MessageAttachment(
        name: 'pic.png',
        isImage: true,
        mime: 'image/png',
      );
      expect(image.inferredIsAudio, false);
    });
  });
}
