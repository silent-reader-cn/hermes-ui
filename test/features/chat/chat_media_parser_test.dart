import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/message_attachment.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_media_parser.dart';

void main() {
  group('ChatMediaParser 媒体标记解析单元测试', () {
    test('图片 MEDIA: 标记转换为 Markdown 图片语法', () {
      const input = '这是生成的截图：MEDIA:https://example.com/screenshot.png 请查看。';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '这是生成的截图：![screenshot.png](https://example.com/screenshot.png) 请查看。',
      );
    });

    test('本地绝对路径图片 MEDIA: 标记转换', () {
      const input = '图片已保存至 MEDIA:/tmp/output_plot.jpg';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '图片已保存至 ![output_plot.jpg](/tmp/output_plot.jpg)',
      );
    });

    test('Windows 路径反斜杠转为 Markdown 安全 URL', () {
      const input = r'保存路径：MEDIA:C:\Users\Admin\Desktop\photo.png';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '保存路径：![photo.png](C:/Users/Admin/Desktop/photo.png)',
      );
    });

    test('Data URI base64 图片 MEDIA: 标记转换', () {
      const input = 'MEDIA:data:image/png;base64,iVBORw0KGgo=';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '![image](data:image/png;base64,iVBORw0KGgo=)',
      );
    });

    test('音频 MEDIA: 标记转换为音频芯片链接', () {
      const input = '生成的录音：MEDIA:/music/voice_note.mp3';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '生成的录音：[🎵 voice_note.mp3](/music/voice_note.mp3)',
      );
    });

    test('视频 MEDIA: 标记转换为视频芯片链接', () {
      const input = '生成的视频：MEDIA:/videos/render.mp4';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '生成的视频：[🎬 render.mp4](/videos/render.mp4)',
      );
    });

    test('文档/文件 MEDIA: 标记转换为附件链接', () {
      const input = '报告已生成：MEDIA:/docs/annual_report.pdf';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '报告已生成：[📎 annual_report.pdf](/docs/annual_report.pdf)',
      );
    });

    test('多行代码块内部的 MEDIA: 标记受保护不被转换', () {
      const input = '```python\nprint("MEDIA:/tmp/secret.png")\n```\n外部 MEDIA:/tmp/public.png';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '```python\nprint("MEDIA:/tmp/secret.png")\n```\n外部 ![public.png](/tmp/public.png)',
      );
    });

    test('行内反引号内部的 MEDIA: 标记受保护', () {
      const input = '使用 `MEDIA:/path/to/img.png` 作为指令。实际图片：MEDIA:/path/to/real.png';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '使用 `MEDIA:/path/to/img.png` 作为指令。实际图片：![real.png](/path/to/real.png)',
      );
    });

    test('裸 file:// 图片链接解析为 Markdown 图片', () {
      const input = '查看本地文件 file:///tmp/figure.png 进行确认';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '查看本地文件 ![figure.png](file:///tmp/figure.png) 进行确认',
      );
    });

    test('裸 file:// 非图片链接解析为附件芯片', () {
      const input = '附带日志：file:///var/log/app.log';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '附带日志：[📎 app.log](file:///var/log/app.log)',
      );
    });

    test('末尾句号标点不被误作为扩展名一部分', () {
      const input = '请查看 MEDIA:/tmp/chart.png.';
      final output = ChatMediaParser.parseMediaMarkers(input);
      expect(
        output,
        '请查看 ![chart.png](/tmp/chart.png).',
      );
    });
  });

  group('ChatMediaResolver URL 解析单元测试', () {
    test('Data URI 原样返回', () {
      const dataUri = 'data:image/png;base64,iVBORw0KGgo=';
      final resolved = ChatMediaResolver.resolveMediaUrl(dataUri);
      expect(resolved, dataUri);
    });

    test('http/https URL 原样返回', () {
      const httpUrl = 'https://example.com/images/cat.jpg';
      final resolved = ChatMediaResolver.resolveMediaUrl(
        httpUrl,
        baseUrl: 'http://localhost:30002',
      );
      expect(resolved, httpUrl);
    });

    test('本地路径拼接 /api/media 与 session_id', () {
      const localPath = '/tmp/screenshot.png';
      final resolved = ChatMediaResolver.resolveMediaUrl(
        localPath,
        baseUrl: 'http://localhost:30002',
        sessionId: 'sess_123',
      );
      expect(
        resolved,
        'http://localhost:30002/api/media?path=%2Ftmp%2Fscreenshot.png&session_id=sess_123',
      );
    });

    test('Windows 本地路径编码为合法 query 参数', () {
      const winPath = r'C:\Users\Admin\Desktop\photo.jpg';
      final resolved = ChatMediaResolver.resolveMediaUrl(
        winPath,
        baseUrl: 'http://localhost:30002/',
      );
      expect(
        resolved,
        'http://localhost:30002/api/media?path=C%3A%5CUsers%5CAdmin%5CDesktop%5Cphoto.jpg',
      );
    });

    test('已经是 /api/media 相对路径时直接拼接 baseUrl', () {
      const apiRel = 'api/media?path=test.png&session_id=s1';
      final resolved = ChatMediaResolver.resolveMediaUrl(
        apiRel,
        baseUrl: 'http://localhost:30002',
      );
      expect(
        resolved,
        'http://localhost:30002/api/media?path=test.png&session_id=s1',
      );
    });
  });

  group('MessageAttachment 媒体类型判定单测', () {
    test('扩展媒体扩展名识别', () {
      expect(MessageAttachment.isImageReference('test.svg'), isTrue);
      expect(MessageAttachment.isImageReference('icon.ico'), isTrue);
      expect(MessageAttachment.isImageReference('pic.avif'), isTrue);
      expect(MessageAttachment.isImageReference('data:image/png;base64,...'), isTrue);

      expect(MessageAttachment.isAudioReference('song.mp3'), isTrue);
      expect(MessageAttachment.isAudioReference('track.flac'), isTrue);
      expect(MessageAttachment.isAudioReference('voice.ogg'), isTrue);

      expect(MessageAttachment.isVideoReference('clip.mp4'), isTrue);
      expect(MessageAttachment.isVideoReference('movie.mkv'), isTrue);

      expect(MessageAttachment.isDocumentReference('doc.pdf'), isTrue);
      expect(MessageAttachment.isDocumentReference('data.csv'), isTrue);
      expect(MessageAttachment.isDocumentReference('diff.patch'), isTrue);
    });

    test('mediaKindForName 分类准确', () {
      expect(MessageAttachment.mediaKindForName('a.png'), MessageMediaKind.image);
      expect(MessageAttachment.mediaKindForName('a.wav'), MessageMediaKind.audio);
      expect(MessageAttachment.mediaKindForName('a.webm'), MessageMediaKind.video);
      expect(MessageAttachment.mediaKindForName('a.json'), MessageMediaKind.document);
      expect(MessageAttachment.mediaKindForName('a.unknown_binary'), MessageMediaKind.file);
    });
  });
}
