import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../core/api/api_client_server_panels.dart';
import '../../../core/api/api_client_upload.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/providers/file_picker_provider.dart';
import '../../../core/utils/accessibility.dart';
import '../../../core/utils/file_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../prompts/widgets/saved_prompts_sheet.dart';

/// 输入栏（chat_spec.md §4.2：idle 发送；流式期间 steer/停止；模型选择；附件）。
///
/// - idle：附件按钮 + 输入框 + 发送；
/// - 流式：附件按钮 + 输入框 + steer 发送 + 停止；
/// - sending：输入禁用（发送请求在途）。
class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, required this.sessionId, this.enabled = true});

  final String sessionId;

  /// 输入栏可用性（只读会话传 false：输入/附件/模型/发送全部禁用）。
  final bool enabled;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();
  final GlobalKey _bookmarkKey = GlobalKey();
  bool _hasText = false;

  bool _uploading = false;

  /// 已消费的 composerPrefill 值（去重，避免重复写入输入框）。
  String? _appliedPrefill;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 重试上一轮：controller 写入 composerPrefill，这里同步到输入框并清除。
    final prefill = ref
        .watch(chatControllerProvider(widget.sessionId))
        .composerPrefill;
    if (prefill != null && prefill != _appliedPrefill) {
      _appliedPrefill = prefill;
      _textController.text = prefill;
      _hasText = prefill.trim().isNotEmpty;
      ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .clearComposerPrefill();
    } else if (prefill == null) {
      _appliedPrefill = null;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() => _hasText = false);
    // 控制器自动分派：idle → 普通发送；流式 → steer。
    await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(text);
  }

  Future<void> _handleAttachment() async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    final picker = ref.read(filePickerServiceProvider);
    final FilePickerResult? picked;
    try {
      picked = await picker.pickFile();
    } catch (error) {
      await _showError(l10n.selectFileFailed, _errorMessage(error));
      return;
    }
    if (picked == null) return; // 用户取消

    setState(() => _uploading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.uploadFile(
        sessionId: widget.sessionId,
        data: picked.bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      // 上传成功后把附件作为本地消息追加进聊天流
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .send('📎 ${picked.name}');
      await _showNotice(
        l10n.uploadSuccess,
        l10n.attachmentUploaded(picked.name),
      );
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.uploadFailed, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showNotice(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _showError(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(color: statusRedText)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }

  Future<void> _stop() async {
    await ref.read(chatControllerProvider(widget.sessionId).notifier).stop();
  }

  void _insertPromptText(String text) {
    final current = _textController.text;
    final next = current.trim().isEmpty
        ? text
        : '${current.replaceAll(RegExp(r'\s+$'), '')}\n\n$text';
    _textController.text = next;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    final hasText = next.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  Future<void> _showSavedPromptsSheet() async {
    // 宽屏（桌面/平板双栏）：在按钮上方弹出局部气泡，避免底部弹层遮蔽内容区；
    // 窄屏（手机）：保持系统底部 Sheet 体验。
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (isWide) {
      await showCupertinoPopover(
        context: context,
        anchorKey: _bookmarkKey,
        builder: (popoverContext, close) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(popoverContext).savedPromptsTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(popoverContext),
            ),
            SavedPromptsPanel(
              onInsert: _insertPromptText,
              getCurrentInput: () => _textController.text,
              onInserted: close,
            ),
          ],
        ),
      );
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => SavedPromptsSheet(
        onInsert: _insertPromptText,
        getCurrentInput: () => _textController.text,
      ),
    );
  }

  Future<void> _showModelPicker() async {
    final l10n = AppLocalizations.of(context);
    var models = ref.read(chatAvailableModelsProvider);
    try {
      final raw = await ref.read(apiClientProvider).modelsLive();
      final liveModels = _extractModelIDs(raw);
      if (liveModels.isNotEmpty) models = liveModels;
    } catch (_) {
      // Keep the cached/test catalog when the live endpoint fails.
    }
    if (!mounted) return;
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(l10n.selectModel),
          actions: [
            CupertinoActionSheetAction(
              key: const ValueKey('chat-model-default'),
              onPressed: () {
                ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .selectModel(null);
                Navigator.of(context).pop();
              },
              child: Text(l10n.followServerDefault),
            ),
            for (final model in models)
              CupertinoActionSheetAction(
                key: ValueKey('chat-model-$model'),
                onPressed: () {
                  ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .selectModel(model);
                  Navigator.of(context).pop();
                },
                child: Text(model),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ),
      ),
    );
  }

  List<String> _extractModelIDs(Object? raw) {
    if (raw is! Map) return const [];
    final values = <String>[];
    void add(Object? value) {
      if (value is String &&
          value.trim().isNotEmpty &&
          !values.contains(value)) {
        values.add(value.trim());
      } else if (value is Map) {
        final id = value['id'] ?? value['model'] ?? value['name'];
        if (id is String &&
            id.trim().isNotEmpty &&
            !values.contains(id.trim())) {
          values.add(id.trim());
        }
      }
    }

    final map = Map<Object?, Object?>.from(raw);
    final models = map['models'];
    if (models is List) {
      for (final value in models) {
        add(value);
      }
    }
    final groups = map['groups'];
    if (groups is List) {
      for (final group in groups) {
        if (group is Map && group['models'] is List) {
          for (final value in group['models'] as List) {
            add(value);
          }
        }
      }
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phase = ref.watch(chatPhaseProvider(widget.sessionId));
    final isStreaming =
        phase == ChatPhase.streaming ||
        phase == ChatPhase.steered ||
        phase == ChatPhase.approvalPending ||
        phase == ChatPhase.clarifyPending ||
        phase == ChatPhase.recovering;
    final isSending = phase == ChatPhase.sending;
    final interactive = widget.enabled;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.systemGrey4.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AccessibleButton(
              key: const ValueKey('chat-attach-button'),
              label: l10n.addAttachment,
              onPressed: (!interactive || isSending || _uploading)
                  ? null
                  : _handleAttachment,
              padding: EdgeInsets.zero,
              child: _uploading
                  ? const CupertinoActivityIndicator()
                  : const Icon(
                      CupertinoIcons.plus_circle,
                      color: CupertinoColors.systemGrey,
                    ),
            ),
            KeyedSubtree(
              key: _bookmarkKey,
              child: AccessibleButton(
                key: const ValueKey('chat-saved-prompts-button'),
                label: l10n.bookmarkPrompt,
                onPressed: (!interactive || isSending || _uploading)
                    ? null
                    : _showSavedPromptsSheet,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.bookmark,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                key: const ValueKey('chat-input-field'),
                controller: _textController,
                placeholder: !interactive
                    ? l10n.readOnlySessionPlaceholder
                    : (isStreaming
                          ? l10n.steerPromptPlaceholder
                          : l10n.sendMessagePlaceholder),
                enabled: !isSending && interactive,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                onChanged: (value) {
                  final hasText = value.trim().isNotEmpty;
                  if (hasText != _hasText) setState(() => _hasText = hasText);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (isStreaming) ...[
              AccessibleButton(
                key: const ValueKey('chat-steer-button'),
                label: l10n.steerPrompt,
                onPressed: (interactive && _hasText) ? _submit : null,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.arrow_right_circle,
                  color: CupertinoColors.activeBlue,
                ),
              ),
              AccessibleButton(
                key: const ValueKey('chat-stop-button'),
                label: l10n.stopGenerating,
                onPressed: _stop,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.stop_circle,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ] else if (!isSending)
              AccessibleButton(
                key: const ValueKey('chat-send-button'),
                label: l10n.sendMessage,
                onPressed: (interactive && _hasText) ? _submit : null,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.arrow_up_circle,
                  color: CupertinoColors.activeBlue,
                ),
              ),
            AccessibleButton(
              key: const ValueKey('chat-model-button'),
              label: l10n.selectModel,
              onPressed: interactive ? _showModelPicker : null,
              padding: EdgeInsets.zero,
              child: const Icon(
                CupertinoIcons.slider_horizontal_3,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
