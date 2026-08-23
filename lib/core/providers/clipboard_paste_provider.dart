import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/clipboard_paste.dart';

/// 全局剪贴板附件粘贴服务（生产绑定 [PlatformClipboardPasteService]；测试 override）。
final clipboardPasteServiceProvider = Provider<ClipboardPasteService>((ref) {
  return const PlatformClipboardPasteService();
});
