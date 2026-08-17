import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/file_picker.dart';

/// 全局文件选择器服务（生产绑定 [PlatformFilePickerService]；测试 override）。
final filePickerServiceProvider = Provider<FilePickerService>((ref) {
  return const PlatformFilePickerService();
});