import 'dart:async';
import 'dart:typed_data';

import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/workspace/workspace_api.dart';

/// 可配置的 [WorkspaceApi] fake（测试注入，彻底绕开网络）。
///
/// 目录内容按路径配置在 [directories]（`'.'` = 根目录）；导航/刷新读取对应
/// 路径；上传成功后自动把新文件追加到最近一次请求的目录（模拟服务端落盘），
/// 便于断言「上传后刷新列表出现新文件」。所有方法带调用记录与错误注入。
class FakeWorkspaceApi implements WorkspaceApi {
  FakeWorkspaceApi({Map<String, List<WorkspaceEntry>>? directories})
    : directories = directories ?? {};

  /// path → 目录条目（`'.'` = 根目录）。
  final Map<String, List<WorkspaceEntry>> directories;

  /// 最近一次 `fetchDirectory` 请求的路径（上传落盘目标）。
  String? lastFetchedPath;

  /// `fetchDirectory` 抛出的异常（非 null 时优先于目录内容）。
  Object? fetchError;

  /// 非 null 时 `fetchDirectory` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// 各方法抛出的异常（非 null 时模拟失败）。
  Object? uploadError;
  Object? downloadError;
  Object? deleteError;
  Object? renameError;

  /// `downloadFile` 返回的字节。
  Uint8List downloadBytes = Uint8List.fromList([1, 2, 3, 4]);

  int fetchCount = 0;
  int uploadCount = 0;

  /// 调用记录（`sessionId|path` 或 `sessionId|path|newName` 形式）。
  final List<String> fetchCalls = [];
  final List<String> uploadCalls = [];
  final List<String> downloadCalls = [];
  final List<String> deleteCalls = [];
  final List<String> renameCalls = [];

  @override
  Future<DirectoryListResponse> fetchDirectory({
    required String sessionId,
    required String path,
  }) async {
    fetchCount++;
    fetchCalls.add('$sessionId|$path');
    final error = fetchError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    lastFetchedPath = path;
    return DirectoryListResponse(
      entries: directories[path] ?? const [],
      path: path,
    );
  }

  @override
  Future<WorkspaceUploadResult> uploadFile({
    required String sessionId,
    required String filename,
    required Uint8List data,
  }) async {
    uploadCount++;
    uploadCalls.add('$sessionId|$filename|${data.length}');
    final error = uploadError;
    if (error != null) throw error;
    // 模拟服务端把文件写入当前目录：追加条目，刷新列表即可见。
    final target = lastFetchedPath ?? '.';
    final path = target == '.' ? filename : '$target/$filename';
    final list = directories.putIfAbsent(target, () => []);
    list.add(
      WorkspaceEntry(
        name: filename,
        path: path,
        size: data.length,
        isDirectory: false,
      ),
    );
    return WorkspaceUploadResult(
      filename: filename,
      path: path,
      size: data.length,
    );
  }

  @override
  Future<Uint8List> downloadFile({
    required String sessionId,
    required String path,
  }) async {
    downloadCalls.add('$sessionId|$path');
    final error = downloadError;
    if (error != null) throw error;
    return downloadBytes;
  }

  @override
  Future<void> deleteFile({
    required String sessionId,
    required String path,
    bool recursive = false,
  }) async {
    deleteCalls.add('$sessionId|$path');
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<void> renameFile({
    required String sessionId,
    required String path,
    required String newName,
  }) async {
    renameCalls.add('$sessionId|$path|$newName');
    final error = renameError;
    if (error != null) throw error;
  }
}
