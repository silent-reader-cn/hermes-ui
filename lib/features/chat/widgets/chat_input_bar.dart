import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import '../../chat/pending_attachments_provider.dart';
import '../../chat/selection_provider.dart';
import '../../chat/widgets/attachment_pending_bar.dart';
import '../../chat/widgets/context_window_indicator.dart';
import '../../chat/widgets/context_window_popover.dart';
import '../../chat/widgets/selection_chips.dart';
import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/widgets/cupertino_popover.dart';
import '../../../core/api/api_client_upload.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/upload_response.dart';
import '../../../core/providers/clipboard_paste_provider.dart';
import '../../../core/providers/file_picker_provider.dart';
import '../../../core/utils/accessibility.dart';
import '../../../core/utils/clipboard_paste.dart';
import '../../../core/utils/file_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../prompts/widgets/saved_prompts_sheet.dart';

/// 触发附件/图片粘贴意图（快捷键或右键菜单触发）。
class PasteAttachmentIntent extends Intent {
  const PasteAttachmentIntent();
}

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
  late GlobalKey _bookmarkKey;
  late GlobalKey _contextIndicatorKey;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _bookmarkKey = GlobalKey(debugLabel: 'chat-bookmark-${widget.sessionId}');
    _contextIndicatorKey = GlobalKey(
      debugLabel: 'chat-context-${widget.sessionId}',
    );
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _bookmarkKey = GlobalKey(debugLabel: 'chat-bookmark-${widget.sessionId}');
      _contextIndicatorKey = GlobalKey(
        debugLabel: 'chat-context-${widget.sessionId}',
      );
    }
  }

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
    final raw = _textController.text;
    final repo = ref.read(pendingSelectionsProvider(widget.sessionId).notifier);
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final extra = repo.buildMessageForApi(raw);
    // 附件引用后缀（对齐 Swift PendingAttachment.chatMessageText）
    final message = PendingAttachment.chatMessageText(
      extra.trim(),
      pendingAttachments,
    );
    if (message.trim().isEmpty) return;
    _textController.clear();
    setState(() => _hasText = false);
    final sent = await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(message, attachments: pendingAttachments);
    if (sent) {
      if (extra != raw) {
        ref.read(pendingSelectionsProvider(widget.sessionId).notifier).clear();
      }
      ref.read(pendingAttachmentsProvider(widget.sessionId).notifier).clear();
    } else if (!sent) {
      _textController.text = raw;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      setState(() => _hasText = raw.trim().isNotEmpty);
    }
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
      final resp = await client.uploadFile(
        sessionId: widget.sessionId,
        data: picked.bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      // 只入待发附件列表，不直接发送；点发送时随消息一并提交。
      ref
          .read(pendingAttachmentsProvider(widget.sessionId).notifier)
          .add(
            PendingAttachment(
              name: picked.name,
              path: resp.path ?? picked.name,
              mime: resp.mime ?? '',
              size: resp.size ?? picked.bytes.length,
              isImage: resp.isImage ?? false,
              thumbnailData: picked.bytes,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.uploadFailed, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 粘贴得到的图片/文件：上传完成后进入待发附件列表（发送由用户点按钮触发）。
  Future<void> _handlePasteBytes(Uint8List bytes, String filename) async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _uploading = true);
    try {
      final client = ref.read(apiClientProvider);
      final resp = await client.uploadFile(
        sessionId: widget.sessionId,
        data: bytes,
        filename: filename,
      );
      if (!mounted) return;
      ref
          .read(pendingAttachmentsProvider(widget.sessionId).notifier)
          .add(
            PendingAttachment(
              name: filename,
              path: resp.path ?? filename,
              mime: resp.mime ?? '',
              size: resp.size ?? bytes.length,
              isImage: resp.isImage ?? false,
              thumbnailData: bytes,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.uploadFailed, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _handlePaste() async {
    final phase = ref.read(chatPhaseProvider(widget.sessionId));
    final isSending = phase == ChatPhase.sending;
    if (!widget.enabled || isSending || _uploading) return;

    // 对话框复制文本后右键粘贴闪退的主因：纯文本也先走 FFI 的
    // ClipboardReader.readClipboard()（super_clipboard），在 Windows 上
    // Dart 3.13 + irondash 0.1.1 会直接 abort。
    // 修复：附件探测与纯文本路径彻底解耦——任意一边异常都不影响另一边。
    PastedAttachment? attachment;
    try {
      attachment = await ref
          .read(clipboardPasteServiceProvider)
          .readPastedAttachment();
    } catch (_) {
      attachment = null;
    }

    if (attachment != null && attachment.bytes.isNotEmpty) {
      await _handlePasteBytes(attachment.bytes, attachment.filename);
      return;
    }

    // 无附件或探测超时/失败：回落到纯文本粘贴（引擎通道，Windows 安全）
    try {
      await _pastePlainText();
    } catch (_) {}
  }

  Future<void> _pastePlainText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final textToInsert = data?.text;
    if (textToInsert == null || textToInsert.isEmpty) return;

    final currentText = _textController.text;
    final selection = _textController.selection;
    final int start = selection.isValid ? selection.start : currentText.length;
    final int end = selection.isValid ? selection.end : currentText.length;
    final int min = start < end ? start : end;
    final int max = start > end ? start : end;

    final int clampedMin = min.clamp(0, currentText.length);
    final int clampedMax = max.clamp(0, currentText.length);

    final newText = currentText.replaceRange(
      clampedMin,
      clampedMax,
      textToInsert,
    );
    final newOffset = clampedMin + textToInsert.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    final pending = ref.read(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.read(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final canSendWithPending =
        pending.isNotEmpty || pendingAttachments.isNotEmpty;
    final hasText = newText.trim().isNotEmpty || canSendWithPending;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _showError(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: TextStyle(color: statusRedText.resolveFrom(context)),
        ),
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

  Future<void> _showContextPopover() async {
    final snapshot = ref
        .read(chatControllerProvider(widget.sessionId))
        .contextWindowSnapshot;
    if (snapshot == null) return;
    final currentModel = ref
        .read(chatControllerProvider(widget.sessionId))
        .model;
    await showCupertinoPopover(
      context: context,
      anchorKey: _contextIndicatorKey,
      preferredWidth: 260,
      maxHeight: 520,
      preferredHeight: 520,
      builder: (popoverContext, close) => ContextWindowPopover(
        sessionId: widget.sessionId,
        snapshot: snapshot,
        currentModel: currentModel,
        onClose: close,
      ),
    );
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
    final pending = ref.watch(pendingSelectionsProvider(widget.sessionId));
    final pendingAttachments = ref.watch(
      pendingAttachmentsProvider(widget.sessionId),
    );
    final canSendWithPending =
        pending.isNotEmpty || pendingAttachments.isNotEmpty;
    final snapshot = ref
        .watch(chatControllerProvider(widget.sessionId))
        .contextWindowSnapshot;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionChipPanel(sessionId: widget.sessionId),
        AttachmentPendingBar(sessionId: widget.sessionId),
        Container(
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
                          size: 22,
                          color: CupertinoColors.systemGrey,
                        ),
                ),
                Container(
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
                      size: 22,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
                Expanded(
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.keyV, control: true):
                          PasteAttachmentIntent(),
                      SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                          PasteAttachmentIntent(),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        PasteAttachmentIntent:
                            CallbackAction<PasteAttachmentIntent>(
                              onInvoke: (intent) {
                                unawaited(_handlePaste());
                                return null;
                              },
                            ),
                        PasteTextIntent: CallbackAction<PasteTextIntent>(
                          onInvoke: (intent) {
                            unawaited(_handlePaste());
                            return null;
                          },
                        ),
                      },
                      child: CupertinoTextField(
                        key: const ValueKey('chat-input-field'),
                        controller: _textController,
                        placeholder: !interactive
                            ? l10n.readOnlySessionPlaceholder
                            : (isStreaming
                                  ? l10n.steerPromptPlaceholder
                                  : l10n.sendMessagePlaceholder),
                        enabled: !isSending && !_uploading && interactive,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        contextMenuBuilder: (context, editableTextState) {
                          final buttonItems = editableTextState
                              .contextMenuButtonItems
                              .map((item) {
                                if (item.type == ContextMenuButtonType.paste) {
                                  return ContextMenuButtonItem(
                                    type: item.type,
                                    label: item.label,
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      unawaited(_handlePaste());
                                    },
                                  );
                                }
                                return item;
                              })
                              .toList();
                          return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                            buttonItems: buttonItems,
                            anchors: editableTextState.contextMenuAnchors,
                          );
                        },
                        onChanged: (value) {
                          final hasText =
                              value.trim().isNotEmpty || canSendWithPending;
                          if (hasText != _hasText) {
                            setState(() => _hasText = hasText);
                          }
                        },
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
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
                      size: 22,
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
                      size: 22,
                      color: CupertinoColors.systemRed,
                    ),
                  ),
                ] else if (!isSending)
                  AccessibleButton(
                    key: const ValueKey('chat-send-button'),
                    label: l10n.sendMessage,
                    onPressed: (interactive && (_hasText || canSendWithPending))
                        ? _submit
                        : null,
                    padding: EdgeInsets.zero,
                    child: const Icon(
                      CupertinoIcons.arrow_up_circle,
                      size: 22,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                Container(
                  key: _contextIndicatorKey,
                  child: ContextWindowIndicator(
                    snapshot: snapshot,
                    onTap: _showContextPopover,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
