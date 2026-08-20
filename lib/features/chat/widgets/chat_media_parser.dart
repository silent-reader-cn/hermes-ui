import '../../../core/models/message_attachment.dart';

/// 聊天媒体标记解析器与 URL 解析工具。
///
/// 对齐 Hermes WebUI (static/ui.js) 的媒体标记处理逻辑：
/// 1. `MEDIA:<ref>` 标记解析为 Markdown 内联图片或媒体芯片链接；
/// 2. 裸 `file://` 引用解析为对应媒体 Markdown；
/// 3. 代码块及行内反引号内容受保护不被错误转换；
/// 4. 将本地路径或服务端相对路径解析为 `/api/media` 完整 URL。
class ChatMediaParser {
  const ChatMediaParser._();

  /// 匹配 `MEDIA:<ref>` 标记（非空白、非右括号或右中括号）。
  static final RegExp _mediaTokenRegex = RegExp(r'MEDIA:([^\s\)\]]+)');

  /// 匹配行首、空白或标点符号后的裸 `file://` 链接。
  static final RegExp _bareFileUriRegex = RegExp(
    r'(^|\s|[\p{P}\p{S}])(file:\/\/[^\s<>"'
    "'"
    r'\)\]]+)',
    unicode: true,
  );

  /// 匹配多行围栏代码块。
  static final RegExp _fencedBlockRegex = RegExp(
    r'(^|\n)[ ]{0,3}(`{3,})[^\n`]*\n[\s\S]*?\n[ ]{0,3}\2`*(?=\n|$)',
  );

  /// 匹配行内代码反引号跨度。
  static final RegExp _inlineCodeRegex = RegExp(r'`[^`\n]+`');

  /// 解析消息文本中的媒体标记并转换为标准 Markdown 语法。
  static String parseMediaMarkers(String text) {
    if (text.isEmpty) return text;
    if (!text.contains('MEDIA:') && !text.contains('file://')) {
      return text;
    }

    final codeStash = <String>[];

    // 1. 暂存多行代码块
    var processed = text.replaceAllMapped(_fencedBlockRegex, (match) {
      final matchedText = match.group(0)!;
      codeStash.add(matchedText);
      return '\x00FENCE_${codeStash.length - 1}\x00';
    });

    // 2. 暂存行内代码
    processed = processed.replaceAllMapped(_inlineCodeRegex, (match) {
      final matchedText = match.group(0)!;
      codeStash.add(matchedText);
      return '\x00CODE_${codeStash.length - 1}\x00';
    });

    // 3. 处理 MEDIA: 标记
    processed = processed.replaceAllMapped(_mediaTokenRegex, (match) {
      final rawRef = match.group(1)!;
      return _formatMediaMarkdown(rawRef);
    });

    // 4. 处理裸 file:// 链接
    processed = processed.replaceAllMapped(_bareFileUriRegex, (match) {
      final lead = match.group(1)!;
      final rawRef = match.group(2)!;
      return '$lead${_formatMediaMarkdown(rawRef)}';
    });

    // 5. 还原暂存代码块
    processed = processed.replaceAllMapped(
      RegExp(r'\x00(?:FENCE|CODE)_(\d+)\x00'),
      (match) {
        final index = int.tryParse(match.group(1) ?? '') ?? -1;
        if (index >= 0 && index < codeStash.length) {
          return codeStash[index];
        }
        return match.group(0)!;
      },
    );

    return processed;
  }

  static String _formatMediaMarkdown(String rawRef) {
    var ref = rawRef.trim();
    final trailingMatch = RegExp(r'[.,;:!?]+$').firstMatch(ref);
    var trailing = '';
    if (trailingMatch != null) {
      trailing = trailingMatch.group(0)!;
      ref = ref.substring(0, ref.length - trailing.length);
    }

    final displayName = _displayNameForRef(ref);
    final safeUrl = _safeMarkdownUrl(ref);
    final kind = MessageAttachment.mediaKindForName(ref);

    String md;
    switch (kind) {
      case MessageMediaKind.image:
        md = '![$displayName]($safeUrl)';
      case MessageMediaKind.audio:
        md = '[🎵 $displayName]($safeUrl)';
      case MessageMediaKind.video:
        md = '[🎬 $displayName]($safeUrl)';
      case MessageMediaKind.document:
      case MessageMediaKind.file:
        md = '[📎 $displayName]($safeUrl)';
    }
    return '$md$trailing';
  }

  static String _displayNameForRef(String rawRef) {
    if (rawRef.startsWith('data:image/')) return 'image';
    var clean = rawRef.split('?').first.split('#').first;
    if (clean.startsWith('file://')) {
      try {
        clean = Uri.decodeFull(clean.substring(7));
      } catch (_) {
        clean = clean.substring(7);
      }
    }
    while (clean.endsWith('/') || clean.endsWith(r'\')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final forwardSlash = clean.lastIndexOf('/');
    final backSlash = clean.lastIndexOf(r'\');
    final idx = forwardSlash > backSlash ? forwardSlash : backSlash;
    final name = idx == -1 ? clean : clean.substring(idx + 1);
    return name.isEmpty ? 'media' : name;
  }

  static String _safeMarkdownUrl(String rawRef) {
    return rawRef.replaceAll(r'\', '/');
  }
}

/// 媒体资源 URL 解析器。
class ChatMediaResolver {
  const ChatMediaResolver._();

  /// 将各种形式的媒体引用（http/https/data:image/file:///相对路径/绝对路径）解析为可访问的完整 URL。
  static String resolveMediaUrl(
    String rawUrl, {
    String? baseUrl,
    String? sessionId,
  }) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    // data:image/* 直接使用
    if (trimmed.startsWith('data:image/')) {
      return trimmed;
    }

    // http/https 网络地址
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    var path = trimmed;

    // file:// 解包
    if (path.startsWith('file://')) {
      try {
        final uri = Uri.parse(path);
        path = uri.toFilePath();
      } catch (_) {
        path = path.substring(7);
        try {
          path = Uri.decodeFull(path);
        } catch (_) {}
      }
    }

    final normalizedBase = _normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) return path;

    // 已经是 api/media 相对路径
    if (path.startsWith('api/media') || path.startsWith('/api/media')) {
      final sep = path.startsWith('/') ? '' : '/';
      return '$normalizedBase$sep$path';
    }

    // 本地文件路径或服务器相对路径 -> 拼接 /api/media
    final encodedPath = Uri.encodeComponent(path);
    var apiUrl = '$normalizedBase/api/media?path=$encodedPath';
    if (sessionId != null && sessionId.isNotEmpty) {
      apiUrl += '&session_id=${Uri.encodeComponent(sessionId)}';
    }
    return apiUrl;
  }

  static String _normalizeBaseUrl(String? baseUrl) {
    if (baseUrl == null) return '';
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }
}
