import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale/locale_resolver.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/endpoints.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import '../../l10n/app_localizations.dart';
import '../downloads/download_confirm_dialog.dart';
import '../downloads/download_providers.dart';
import 'workspace_api.dart';

/// 构建 [WorkspaceApi] 的工厂（测试可 override 注入 fake）。
typedef WorkspaceApiFactory = WorkspaceApi Function(ApiClient client);

final workspaceApiFactoryProvider = Provider<WorkspaceApiFactory>(
  (ref) => WorkspaceApiClient.new,
);

/// 「根目录」面包屑标题（按 LocaleResolver 当前语言解析）。
String _rootCrumbTitle() =>
    AppLocalizations(LocaleResolver.resolve()).rootDir;

/// 面包屑（对齐 Swift `FileBreadcrumb`：title + path，path 即跳转目标）。
class WorkspaceBreadcrumb {
  const WorkspaceBreadcrumb({required this.title, required this.path});

  final String title;
  final String path;

  String get id => path;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceBreadcrumb &&
      other.title == title &&
      other.path == path;

  @override
  int get hashCode => Object.hash(title, path);

  @override
  String toString() => 'WorkspaceBreadcrumb($title @ $path)';
}

/// 文件浏览状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// 导航语义对齐 Swift `FileBrowserViewModel`：进入子目录/返回/跳面包屑都保留
/// 旧列表 + `isRefreshing` 横幅；导航失败不改变列表，只设置 [actionError]
/// 供横幅/弹窗展示（重试走 [WorkspaceController.retryLastLoad]）。初始加载与
/// 下拉刷新失败 → `AsyncError`（UI 展示全屏错误态 + 重试）。
class WorkspaceState {
  const WorkspaceState({
    this.entries = const [],
    this.currentPath = '.',
    this.isRefreshing = false,
    this.isUploading = false,
    this.isFolderDownloading = false,
    this.busyPaths = const {},
    this.actionError,
    this.notice,
  });

  /// 当前目录条目（服务端顺序）。
  final List<WorkspaceEntry> entries;

  /// 当前目录路径（`.` = 根目录）。
  final String currentPath;

  /// 目录加载中（导航/刷新在途，保留旧列表供 UI 展示横幅）。
  final bool isRefreshing;

  /// 上传请求在途（UI 用 ActivityIndicator 替换上传按钮）。
  final bool isUploading;

  /// 当前目录打包下载在途（UI 用 ActivityIndicator 替换下载按钮）。
  final bool isFolderDownloading;

  /// 正在执行变更（下载/删除/重命名）的条目路径（UI 用 ActivityIndicator
  /// 替换对应行的操作按钮，防止并发变更竞态）。
  final Set<String> busyPaths;

  /// 最近一次行操作/导航错误（UI 弹窗展示后调用
  /// [WorkspaceController.clearActionError] 清除）。
  final String? actionError;

  /// 成功提示（如下载完成；UI 弹窗展示后调用
  /// [WorkspaceController.clearNotice] 清除）。
  final String? notice;

  /// 是否在根目录。
  bool get isAtRoot => currentPath == '.';

  /// 展示路径（根目录显示「根目录」，对齐 Swift `displayPath`）。
  String get displayPath => isAtRoot ? '根目录' : currentPath;

  /// 父路径；已在根目录时为 null。
  String? get parentPath {
    if (isAtRoot) return null;
    final parts = currentPath.split('/');
    if (parts.length <= 1) return '.';
    return parts.sublist(0, parts.length - 1).join('/');
  }

  /// 面包屑链（恒以「根目录」开头，逐级到当前目录）。
  List<WorkspaceBreadcrumb> get breadcrumbs {
    if (isAtRoot) {
      return [WorkspaceBreadcrumb(title: _rootCrumbTitle(), path: '.')];
    }
    final parts = currentPath.split('/');
    final crumbs = <WorkspaceBreadcrumb>[
      WorkspaceBreadcrumb(title: _rootCrumbTitle(), path: '.'),
    ];
    for (var i = 0; i < parts.length; i++) {
      crumbs.add(
        WorkspaceBreadcrumb(
          title: parts[i],
          path: parts.sublist(0, i + 1).join('/'),
        ),
      );
    }
    return crumbs;
  }

  /// 指定路径的条目是否正在执行变更。
  bool isBusy(String path) => busyPaths.contains(path);

  WorkspaceState copyWith({
    List<WorkspaceEntry>? entries,
    String? currentPath,
    bool? isRefreshing,
    bool? isUploading,
    bool? isFolderDownloading,
    Set<String>? busyPaths,
    String? Function()? actionError,
    String? Function()? notice,
  }) {
    return WorkspaceState(
      entries: entries ?? this.entries,
      currentPath: currentPath ?? this.currentPath,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isUploading: isUploading ?? this.isUploading,
      isFolderDownloading: isFolderDownloading ?? this.isFolderDownloading,
      busyPaths: busyPaths ?? this.busyPaths,
      actionError: actionError != null ? actionError() : this.actionError,
      notice: notice != null ? notice() : this.notice,
    );
  }

  @override
  String toString() =>
      'WorkspaceState(entries: ${entries.length}, currentPath: $currentPath, '
      'isRefreshing: $isRefreshing, isUploading: $isUploading, '
      'busy: ${busyPaths.length}, actionError: $actionError)';
}

/// 文件浏览控制器（family by sessionId）：加载 / 刷新 / 导航 / 上传 / 下载 /
/// 删除 / 重命名。
///
/// AsyncValue 语义：`AsyncData` 携带 [WorkspaceState]；初始加载与下拉刷新失败
/// → `AsyncError`（UI 展示错误态 + 重试）；导航/行操作失败不改变列表，只设置
/// [WorkspaceState.actionError] 供弹窗提示。
final workspaceControllerProvider =
    AsyncNotifierProvider.family<WorkspaceController, WorkspaceState, String>(
      WorkspaceController.new,
    );

class WorkspaceController extends FamilyAsyncNotifier<WorkspaceState, String> {
  /// 会话 ID（family 参数；空串视为未提供）。
  String get sessionId => arg;

  WorkspaceApi get _api =>
      ref.read(workspaceApiFactoryProvider)(ref.read(apiClientProvider));

  /// 最近一次请求的目录路径（导航失败后「重试」的目标）。
  String _lastRequestedPath = '.';

  @override
  Future<WorkspaceState> build(String sessionId) async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(workspaceApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    _lastRequestedPath = '.';
    return _load(api, '.');
  }

  /// 请求目录并组装新状态（携带当前 busyPaths/actionError/notice）。
  Future<WorkspaceState> _load(WorkspaceApi api, String path) async {
    final response = await api.fetchDirectory(sessionId: sessionId, path: path);
    final resolvedPath = response.path ?? path;
    _lastRequestedPath = resolvedPath;
    final current = state.valueOrNull;
    return WorkspaceState(
      entries: response.entries ?? const <WorkspaceEntry>[],
      currentPath: resolvedPath,
      isRefreshing: false,
      busyPaths: current?.busyPaths ?? const {},
      actionError: current?.actionError,
      notice: current?.notice,
    );
  }

  /// 下拉刷新 / 错误态重试：重新加载当前目录；失败 → `AsyncError`。
  Future<void> refresh() async {
    try {
      final api = _api;
      final current = state.valueOrNull;
      state = AsyncData(await _load(api, current?.currentPath ?? '.'));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 重试最近一次失败的目录加载（导航失败后旧列表仍在，仅横幅提示 + 重试）。
  Future<void> retryLastLoad() async {
    await _navigate(_lastRequestedPath);
  }

  /// 导航到目录（目录行点击 / 面包屑跳转 / 根目录按钮）。
  Future<void> navigateTo(String path) async {
    await _navigate(path);
  }

  /// 返回上一级目录（已在根目录时无操作）。
  Future<void> navigateUp() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final parent = current.parentPath;
    if (parent == null) return;
    await _navigate(parent);
  }

  /// 回到根目录。
  Future<void> navigateToRoot() async {
    await _navigate('.');
  }

  Future<void> _navigate(String path) async {
    final current = state.valueOrNull;
    if (current == null) return;
    _lastRequestedPath = path;
    state = AsyncData(
      current.copyWith(isRefreshing: true, actionError: () => null),
    );
    try {
      final api = _api;
      state = AsyncData(await _load(api, path));
    } on Exception catch (error) {
      // 导航失败保留旧列表，仅提示错误（对齐 Swift FileBrowserViewModel）。
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          actionError: () => _messageOf(error),
        ),
      );
    }
  }

  /// 上传文件到会话工作区；成功后刷新当前目录（新文件出现在列表）。
  Future<bool> uploadFile({
    required String filename,
    required Uint8List data,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(
      current.copyWith(isUploading: true, actionError: () => null),
    );
    try {
      final api = _api;
      await api.uploadFile(
        sessionId: sessionId,
        filename: filename,
        data: data,
      );
      final loaded = await _load(api, current.currentPath);
      state = AsyncData(loaded.copyWith(isUploading: false));
      return true;
    } on Exception catch (error) {
      state = AsyncData(
        current.copyWith(
          isUploading: false,
          actionError: () => _messageOf(error),
        ),
      );
      return false;
    }
  }

  /// 下载文件原始字节；统一接入下载中心（弹确认框后 enqueue）。
  Future<bool> download(WorkspaceEntry entry, {BuildContext? context}) async {
    final path = entry.path;
    if (path == null || path.isEmpty) {
      await _setActionError('服务器未提供该条目路径');
      return false;
    }

    final fileName = entry.name ?? path.split('/').last;
    if (context != null) {
      final confirmed = await showDownloadConfirmationDialog(
        context,
        fileName: fileName,
        mimeType: entry.type,
        expectedBytes: entry.size,
        sessionId: sessionId,
        sourceDescription: '$sessionId/$path',
      );
      if (confirmed != true) return false;
    }

    try {
      final client = ref.read(apiClientProvider);
      final rawUrl = Endpoint.rawFile(
        sessionId: sessionId,
        path: path,
      ).url(client.baseUrl).toString();

      await ref.read(downloadControllerProvider.notifier).enqueue(
        sourceUrl: rawUrl,
        fileName: fileName,
        mimeType: entry.type,
        expectedBytes: entry.size,
        sessionId: sessionId,
      );
      return true;
    } on Exception catch (error) {
      await _setActionError(_messageOf(error));
      return false;
    }
  }

  /// 下载当前目录打包 zip；统一接入下载中心（弹确认框后 enqueue）。
  Future<bool> downloadFolder({BuildContext? context}) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    final targetPath = current.currentPath;
    final folderName = (current.isAtRoot || targetPath == '.')
        ? (sessionId.isNotEmpty ? 'workspace_$sessionId' : 'workspace')
        : targetPath.split('/').last;
    final zipFileName = '$folderName.zip';

    if (context != null) {
      final confirmed = await showDownloadConfirmationDialog(
        context,
        fileName: zipFileName,
        mimeType: 'application/zip',
        sessionId: sessionId,
        sourceDescription: '$sessionId/$targetPath',
      );
      if (confirmed != true) return false;
    }

    try {
      final client = ref.read(apiClientProvider);
      final folderUrl = Endpoint.folderDownload(
        sessionId: sessionId,
        path: (current.isAtRoot || targetPath == '.') ? null : targetPath,
      ).url(client.baseUrl).toString();

      await ref.read(downloadControllerProvider.notifier).enqueue(
        sourceUrl: folderUrl,
        fileName: zipFileName,
        mimeType: 'application/zip',
        sessionId: sessionId,
      );
      return true;
    } on Exception catch (error) {
      await _setActionError(_messageOf(error));
      return false;
    }
  }

  /// 删除文件/目录；成功后从当前列表移除。
  Future<bool> delete(WorkspaceEntry entry) async {
    final path = entry.path;
    if (path == null || path.isEmpty) {
      await _setActionError('服务器未提供该条目路径');
      return false;
    }
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(
      current.copyWith(busyPaths: {...current.busyPaths, path}),
    );
    try {
      await _api.deleteFile(
        sessionId: sessionId,
        path: path,
        recursive: entry.isDirectory ?? false,
      );
      final after = state.valueOrNull;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            entries: after.entries.where((e) => e.path != path).toList(),
            busyPaths: {...after.busyPaths}..remove(path),
          ),
        );
      }
      return true;
    } on Exception catch (error) {
      await _clearBusy(path);
      await _setActionError(_messageOf(error));
      return false;
    }
  }

  /// 重命名文件/目录；成功后本地更新该行（新路径 = 父路径 + 新名）。
  Future<bool> rename(WorkspaceEntry entry, String newName) async {
    final path = entry.path;
    final trimmed = newName.trim();
    if (path == null || path.isEmpty) {
      await _setActionError('服务器未提供该条目路径');
      return false;
    }
    if (trimmed.isEmpty) {
      await _setActionError('名称不能为空');
      return false;
    }
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(
      current.copyWith(busyPaths: {...current.busyPaths, path}),
    );
    try {
      await _api.renameFile(sessionId: sessionId, path: path, newName: trimmed);
      final after = state.valueOrNull;
      if (after != null) {
        final parent = _parentOf(path);
        final newPath = parent == null ? trimmed : '$parent/$trimmed';
        state = AsyncData(
          after.copyWith(
            entries: [
              for (final e in after.entries)
                if (e.path == path)
                  WorkspaceEntry(
                    name: trimmed,
                    path: newPath,
                    type: e.type,
                    size: e.size,
                    modified: e.modified,
                    isDirectory: e.isDirectory,
                  )
                else
                  e,
            ],
            busyPaths: {...after.busyPaths}..remove(path),
          ),
        );
      }
      return true;
    } on Exception catch (error) {
      await _clearBusy(path);
      await _setActionError(_messageOf(error));
      return false;
    }
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  /// 清除成功提示（UI 展示完弹窗后调用）。
  Future<void> clearNotice() async {
    final current = state.valueOrNull;
    if (current == null || current.notice == null) return;
    state = AsyncData(current.copyWith(notice: () => null));
  }

  // -------------------------------------------------------------------------
  // 本地状态更新原语
  // -------------------------------------------------------------------------

  Future<void> _clearBusy(String path) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(busyPaths: {...current.busyPaths}..remove(path)),
    );
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  static String _messageOf(Object error) =>
      error is ApiException ? error.message : error.toString();

  static String? _parentOf(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return null;
    return parts.sublist(0, parts.length - 1).join('/');
  }
}

/// 当前目录面包屑（根目录恒为第一项）。
final workspaceBreadcrumbsProvider =
    Provider.family<List<WorkspaceBreadcrumb>, String>((ref, sessionId) {
      return ref
              .watch(workspaceControllerProvider(sessionId))
              .valueOrNull
              ?.breadcrumbs ??
          [WorkspaceBreadcrumb(title: _rootCrumbTitle(), path: '.')];
    });

/// 当前目录的父路径（null = 已在根目录）。
final workspaceParentPathProvider = Provider.family<String?, String>((
  ref,
  sessionId,
) {
  return ref
      .watch(workspaceControllerProvider(sessionId))
      .valueOrNull
      ?.parentPath;
});

/// 当前目录展示路径（根目录显示「根目录」）。
final workspaceDisplayPathProvider = Provider.family<String, String>((
  ref,
  sessionId,
) {
  return ref
          .watch(workspaceControllerProvider(sessionId))
          .valueOrNull
          ?.displayPath ??
      '根目录';
});
