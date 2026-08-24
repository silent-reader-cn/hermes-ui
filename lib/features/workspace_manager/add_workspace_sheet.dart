import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import 'workspace_manager_providers.dart';

/// 新建工作区表单（全高 bottom sheet，键盘可避让）。
///
/// 对齐 Hermes WebUI `openWorkspaceCreate`（panels.js:6149-6183）：名称可选 +
/// 路径必填 + 路径输入 250ms 防抖请求 `/api/workspaces/suggest` 内联补全 +
/// 「目录不存在时自动创建」开关；提交错误以 statusRedText 内联展示（不弹窗
/// 打断）；path 空白/提交中禁用「添加」按钮。
class AddWorkspaceSheet extends ConsumerStatefulWidget {
  const AddWorkspaceSheet({super.key});

  @override
  ConsumerState<AddWorkspaceSheet> createState() => _AddWorkspaceSheetState();
}

class _AddWorkspaceSheetState extends ConsumerState<AddWorkspaceSheet> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _create = false;
  bool _submitting = false;
  String? _inlineError;
  List<String> _suggestions = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onPathChanged(String value) {
    _debounce?.cancel();
    setState(() => _inlineError = null);
    if (value.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_loadSuggestions(value.trim()));
    });
  }

  Future<void> _loadSuggestions(String prefix) async {
    final suggestions = await ref
        .read(workspaceManagerControllerProvider.notifier)
        .loadSuggestions(prefix);
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _submit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final name = _nameController.text.trim();
    final error = await ref
        .read(workspaceManagerControllerProvider.notifier)
        .addWorkspace(
          path: path,
          name: name.isEmpty ? null : name,
          create: _create,
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _inlineError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final canSubmit = _pathController.text.trim().isNotEmpty && !_submitting;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.addWorkspace,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.workspacePathLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 6),
              CupertinoTextField(
                key: const ValueKey('workspace-add-path'),
                controller: _pathController,
                placeholder: l10n.workspacePathHint,
                autocorrect: false,
                onChanged: _onPathChanged,
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SuggestionList(
                  suggestions: _suggestions,
                  onPick: (value) {
                    _pathController.text = value;
                    setState(() {
                      _suggestions = const [];
                      _inlineError = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.workspaceNameOptionalLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 6),
              CupertinoTextField(
                key: const ValueKey('workspace-add-name'),
                controller: _nameController,
                placeholder: l10n.workspaceNamePlaceholder,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CupertinoSwitch(
                    key: const ValueKey('workspace-add-create'),
                    value: _create,
                    onChanged: (value) => setState(() => _create = value),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.createDirectoryIfMissing,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: 14),
                Text(
                  _inlineError!,
                  key: const ValueKey('workspace-add-error'),
                  style: TextStyle(
                    fontSize: 13,
                    color: statusRedText.resolveFrom(context),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('workspace-add-submit'),
                onPressed: canSubmit ? () => unawaited(_submit()) : null,
                child: Text(l10n.addWorkspaceButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 路径补全建议列表（点击填入路径）。
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onPick});

  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 16),
          color: CupertinoColors.separator.resolveFrom(context),
        ),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return CupertinoButton(
            key: ValueKey('workspace-add-suggestion-$index'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: BorderRadius.circular(0),
            onPressed: () => onPick(suggestion),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                suggestion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          );
        },
      ),
    );
  }
}
