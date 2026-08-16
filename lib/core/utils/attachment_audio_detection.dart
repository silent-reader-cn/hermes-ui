import '../models/message_attachment.dart';

/// 音频附件检测（Swift `AttachmentAudioDetection`）。纯逻辑，无 JSON。
class AttachmentAudioDetection {
  const AttachmentAudioDetection._();

  /// 视为音频的文件扩展名。
  static const Set<String> audioExtensions = {
    'm4a',
    'mp3',
    'wav',
    'aac',
    'caf',
    'ogg',
    'oga',
    'opus',
    'flac',
  };

  /// 判定顺序照抄 Swift：isImage==true 直接 false → mime 前缀 audio/ →
  /// name 扩展名 → path 扩展名。
  static bool isAudio({
    bool? isImage,
    String? mime,
    String? name,
    String? path,
  }) {
    if (isImage == true) return false;

    final normalizedMime = mime?.toLowerCase();
    if (normalizedMime != null && normalizedMime.startsWith('audio/')) {
      return true;
    }

    for (final candidate in [name, path]) {
      final ext = _extensionOf(candidate ?? '');
      if (audioExtensions.contains(ext)) return true;
    }
    return false;
  }

  static String _extensionOf(String value) {
    final lastSlash = value.lastIndexOf('/');
    final last = lastSlash == -1 ? value : value.substring(lastSlash + 1);
    final dot = last.lastIndexOf('.');
    if (dot == -1 || dot == last.length - 1) return '';
    return last.substring(dot + 1).toLowerCase();
  }
}

/// 音频时长格式化（Swift `AudioDurationFormatter`）：m:ss / h:mm:ss，
/// 非有限/负数 → 0:00。
class AudioDurationFormatter {
  const AudioDurationFormatter._();

  static String string(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';

    final total = seconds.floor();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;

    if (hours > 0) {
      return '$hours:${_two(minutes)}:${_two(secs)}';
    }
    return '$minutes:${_two(secs)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// MessageAttachment 扩展：是否应渲染为可播放音频片段。
extension MessageAttachmentAudioX on MessageAttachment {
  bool get inferredIsAudio {
    return AttachmentAudioDetection.isAudio(
      isImage: isImage,
      mime: mime,
      name: name,
      path: path,
    );
  }
}
