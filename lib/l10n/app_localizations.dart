import 'package:flutter/widgets.dart';

/// Lightweight localization facade for business text across Hermex.
///
/// The catalog keeps Chinese as the product default and provides English
/// fallbacks without requiring generated code.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;
  bool get isEnglish => locale.languageCode == 'en';

  // ---------------------------------------------------------------------------
  // Common / General
  // ---------------------------------------------------------------------------
  String get ok => isEnglish ? 'OK' : '好';
  String get cancel => isEnglish ? 'Cancel' : '取消';
  String get save => isEnglish ? 'Save' : '保存';
  String get create => isEnglish ? 'Create' : '创建';
  String get delete => isEnglish ? 'Delete' : '删除';
  String get edit => isEnglish ? 'Edit' : '编辑';
  String get close => isEnglish ? 'Close' : '关闭';
  String get filterSessions => isEnglish ? 'Filter sessions' : '筛选会话';
  String get channels => isEnglish ? 'Channels' : '渠道';
  String get projects => isEnglish ? 'Projects' : '项目';
  String get retry => isEnglish ? 'Retry' : '重试';
  String get loading => isEnglish ? 'Loading…' : '加载中…';
  String get loadingEllipsis => isEnglish ? 'Loading…' : '加载中…';
  String get export => isEnglish ? 'Export' : '导出';
  String get rename => isEnglish ? 'Rename' : '重命名';
  String get notice => isEnglish ? 'Notice' : '提示';
  String get unknown => isEnglish ? 'Unknown' : '未知';
  String get unnamed => isEnglish ? 'Unnamed' : '未命名';
  String get unknownError => isEnglish ? 'Unknown error' : '未知错误';
  String get loadFailed => isEnglish ? 'Failed to load' : '加载失败';
  String get loadFailedRetry => isEnglish ? 'Loading failed, please retry' : '加载失败，请重试';
  String get loadFailedPleaseRetry => isEnglish ? 'Loading failed, please retry' : '加载失败，请重试';
  String get actionFailed => isEnglish ? 'Action Failed' : '操作失败';
  String get dismissNotice => isEnglish ? 'Dismiss notice' : '关闭提示';
  String get closeNotice => isEnglish ? 'Dismiss notice' : '关闭提示';
  String get dismissError => isEnglish ? 'Dismiss error' : '关闭错误提示';
  String get offlineCache => isEnglish ? 'Offline cache' : '离线缓存';
  String get all => isEnglish ? 'All' : '全部';
  String get name => isEnglish ? 'Name' : '名称';
  String get value => isEnglish ? 'Value' : '值';
  String get info => isEnglish ? 'Info' : '信息';
  String get description => isEnglish ? 'Description' : '描述';
  String get noDescription => isEnglish ? 'No description' : '暂无描述';
  String get copiedToClipboard => isEnglish ? 'Copied to clipboard' : '已复制到剪贴板';

  // ---------------------------------------------------------------------------
  // 1. Onboarding
  // ---------------------------------------------------------------------------
  String get connectServer => isEnglish ? 'Connect Server' : '连接服务器';
  String get connectYourHermexServer =>
      isEnglish ? 'Connect your Hermex server' : '连接你的 Hermex 服务器';
  String get inputServerAddressHint => isEnglish
      ? 'Enter the hermes-webui address (with port), e.g. https://hermes.example.com:30002'
      : '输入 hermes-webui 的地址（含端口），例如 https://hermes.example.com:30002';
  String get testConnection => isEnglish ? 'Test Connection' : '连接测试';
  String get haveApiKeySkipWizard => isEnglish ? 'Have an API Key? Skip wizard' : '已有 API Key？跳过向导';
  String get checking => isEnglish ? 'Checking…' : '正在检查…';
  String get connectionSuccessful => isEnglish ? 'Connection successful' : '连接成功';
  String get connectionSuccessfulWithCheck => isEnglish ? '✅ Connection successful' : '✅ 连接成功';
  String get serverReturnedAbnormalStatus =>
      isEnglish ? 'Server returned abnormal status' : '服务器返回异常状态';
  String get cannotConnectToServer => isEnglish ? 'Cannot connect to server' : '无法连接到服务器';
  String get authentication => isEnglish ? 'Authentication' : '认证';
  String get detectingServerAuth => isEnglish ? 'Detecting server authentication…' : '正在检测服务器认证…';
  String get serverNoPasswordRequired => isEnglish
      ? 'Password authentication is not enabled on this server, you can proceed directly'
      : '该服务器未启用密码认证，可直接继续';
  String get serverPasswordRequired => isEnglish
      ? 'Password authentication is required on this server, please log in'
      : '该服务器需要密码认证，请登录';
  String get usernameOptional => isEnglish ? 'Username (optional)' : '用户名（可选）';
  String get password => isEnglish ? 'Password' : '密码';
  String get skipAuthNoPasswordMode =>
      isEnglish ? 'Skip authentication (no-password mode)' : '跳过认证（无密码模式）';
  String get loginFailed => isEnglish ? 'Login Failed' : '登录失败';
  String loginFailedWithReason(String reason) =>
      isEnglish ? 'Login failed: $reason' : '登录失败：$reason';
  String loginFailedWithMessage(String msg) => isEnglish ? 'Login failed: $msg' : '登录失败：$msg';
  String get cannotConnectRetryLater =>
      isEnglish ? 'Cannot connect to server, please try again later' : '无法连接到服务器，请稍后重试';
  String get customHeadersOptional => isEnglish ? 'Custom Headers (optional)' : '自定义 Headers（可选）';
  String get customHeadersDescription => isEnglish
      ? 'Add custom request headers for reverse proxy setups, e.g. Authorization: Bearer xxx'
      : '反向代理场景可添加自定义请求头，如 Authorization: Bearer xxx';
  String get addHeader => isEnglish ? 'Add Header' : '添加 Header';
  String get headerName => isEnglish ? 'Header Name' : 'Header 名';
  String get deleteHeader => isEnglish ? 'Delete Header' : '删除 Header';
  String get nextStep => isEnglish ? 'Next' : '下一步';
  String get continueAction => isEnglish ? 'Continue' : '继续';
  String get loginAndContinue => isEnglish ? 'Log in & Continue' : '登录并继续';
  String get finish => isEnglish ? 'Finish' : '完成';
  String get pleaseEnterServerUrl => isEnglish ? 'Please enter the server address' : '请输入服务器地址';
  String get serverUrlRequired => isEnglish ? 'Please enter the server address' : '请输入服务器地址';
  String get pleaseEnterValidServerUrl => isEnglish
      ? 'Please enter a valid server address, e.g. https://hermes.example.com:30002'
      : '请输入有效的服务器地址，例如 https://hermes.example.com:30002';
  String get serverUrlInvalid => isEnglish
      ? 'Please enter a valid server address, e.g. https://hermes.example.com:30002'
      : '请输入有效的服务器地址，例如 https://hermes.example.com:30002';
  String get headerValidationFailed => isEnglish
      ? 'Header name must be a valid token, and value cannot contain newlines'
      : 'Header 名必须是合法 token，值不能包含换行';
  String get connectAndSave => isEnglish ? 'Connect & Save' : '连接并保存';
  String get passwordVerified => isEnglish ? '✅ Password correct' : '✅ 密码正确';
  String get verifyingPassword => isEnglish ? 'Verifying password…' : '正在验证密码…';
  String get passwordRequiredOnServer =>
      isEnglish ? 'This server requires a password. Enter it to connect.' : '该服务器需要密码认证，请填写密码后再连接';

  // ---------------------------------------------------------------------------
  // 2. Session List
  // ---------------------------------------------------------------------------
  String get sessions => isEnglish ? 'Sessions' : '会话';
  String get doneSelecting => isEnglish ? 'Done' : '完成选择';
  String get newSession => isEnglish ? 'New Session' : '新建会话';
  String get searchSessions => isEnglish ? 'Search sessions' : '搜索会话';
  String get archived => isEnglish ? 'Archived' : '已归档';
  String get clearFilter => isEnglish ? 'Clear filter' : '清除筛选';
  String get untitledProject => isEnglish ? 'Untitled project' : '未命名项目';
  String selectedCount(int count) => isEnglish ? 'Selected $count' : '已选 $count 个';
  String get selectAll => isEnglish ? 'Select All' : '全选';
  String get archive => isEnglish ? 'Archive' : '归档';
  String get batchMoveProject => isEnglish ? 'Move Project' : '移动项目';
  String get moveToProject => isEnglish ? 'Move to Project' : '移动到项目';
  String get pin => isEnglish ? 'Pin' : '置顶';
  String get unpin => isEnglish ? 'Unpin' : '取消置顶';
  String get unarchive => isEnglish ? 'Unarchive' : '恢复归档';
  String get branch => isEnglish ? 'Branch' : '分支';
  String get exportSession => isEnglish ? 'Export Session' : '导出会话';
  String get markdownFormat => isEnglish ? 'Markdown' : 'Markdown';
  String get jsonFormat => isEnglish ? 'JSON' : 'JSON';
  String exportSuccess(String format) =>
      isEnglish ? '$format exported successfully' : '$format 导出成功';
  String get exportContentEmpty => isEnglish ? 'Exported content is empty' : '导出内容为空';
  String get copyContent => isEnglish ? 'Copy Content' : '复制内容';
  String get exportFailed => isEnglish ? 'Export Failed' : '导出失败';
  String get deleteSession => isEnglish ? 'Delete Session' : '删除会话';
  String confirmDeleteSession(String title) => isEnglish
      ? 'Are you sure you want to delete "$title"? This action cannot be undone.'
      : '确定删除「$title」？此操作不可撤销。';
  String get batchArchiveTitle => isEnglish ? 'Batch Archive' : '批量归档';
  String get confirmBatchArchivePrompt => isEnglish ? 'Archive selected sessions?' : '归档选中的会话？';
  String get batchDeleteTitle => isEnglish ? 'Batch Delete' : '批量删除';
  String confirmBatchDeletePrompt(int count) => isEnglish
      ? 'Delete selected $count sessions? This action cannot be undone.'
      : '删除选中的 $count 个会话？此操作不可撤销。';
  String get noMore => isEnglish ? 'No more' : '没有更多了';
  String get noMatchingSessionsFound => isEnglish ? 'No matching sessions found' : '未找到相关会话';
  String get noSessions => isEnglish ? 'No sessions' : '暂无会话';
  String get tryAnotherKeyword => isEnglish ? 'Try another keyword' : '换个关键词试试';
  String get tapButtonToStartNewChat =>
      isEnglish ? 'Tap the button below to start a new chat' : '点击下方按钮开始新对话';
  String get pendingInput => isEnglish ? 'Pending input' : '待输入';
  String get sessionActions => isEnglish ? 'Session Actions' : '会话操作';
  String get untitledSession => isEnglish ? 'Untitled session' : '未命名会话';
  String messageCountLabel(int count) => isEnglish ? '$count messages' : '$count 条消息';
  String get scheduledSection => isEnglish ? 'Scheduled' : '定时';
  String get pinnedSection => isEnglish ? 'Pinned' : '置顶';
  String get todaySection => isEnglish ? 'Today' : '今天';
  String get yesterdaySection => isEnglish ? 'Yesterday' : '昨天';
  String get earlierSection => isEnglish ? 'Earlier' : '更早';
  String get searchResultsSection => isEnglish ? 'Search Results' : '搜索结果';

  // ---------------------------------------------------------------------------
  // 3. Chat & Sub-components
  // ---------------------------------------------------------------------------
  String get branchBadge => isEnglish ? 'Branch' : '分支';
  String get branchSession => isEnglish ? 'Branch Session' : '分支会话';
  String branchSessionDescription(String parentId) => isEnglish
      ? 'This session is a branch of another session.\nParent session $parentId'
      : '该会话是另一个会话的分支。\n父会话 $parentId';
  String get jumpToParentSession => isEnglish ? 'Jump to Parent Session' : '跳转父会话';
  String get renameSession => isEnglish ? 'Rename Session' : '重命名会话';
  String get compressSession => isEnglish ? 'Compress Session' : '压缩会话';
  String get focusTopicPlaceholder => isEnglish ? 'Focus topic (optional)' : '聚焦主题（可留空）';
  String get compress => isEnglish ? 'Compress' : '压缩';
  String get undoLastTurn => isEnglish ? 'Undo Last Turn' : '撤销上一轮';
  String get confirmUndoLastTurnPrompt => isEnglish
      ? 'Delete the last turn of the conversation? This action cannot be undone'
      : '删除最后一轮对话？此操作不可撤销';
  String get retryLastTurn => isEnglish ? 'Retry Last Turn' : '重试上一轮';
  String get sessionSettings => isEnglish ? 'Session Settings' : '会话设置';
  String get workspaceOptionalPlaceholder => isEnglish ? 'Workspace (optional)' : 'Workspace（可留空）';
  String get modelNameOptionalPlaceholder => isEnglish ? 'Model name (optional)' : '模型名（可留空）';
  String get enableYolo => isEnglish ? 'Enable YOLO' : '开启 YOLO';
  String get disableYolo => isEnglish ? 'Disable YOLO' : '关闭 YOLO';
  String get createBranch => isEnglish ? 'Create Branch' : '创建分支';
  String get exportSuccessDialogTitle => isEnglish ? 'Export Succeeded' : '导出成功';
  String get markdownCopiedToClipboard =>
      isEnglish ? 'Markdown copied to clipboard.' : 'Markdown 已复制到剪贴板。';
  String get approvalNeeded => isEnglish ? 'Approval Needed' : '需要审批';
  String get clarificationNeeded => isEnglish ? 'Clarification Needed' : '需要澄清';
  String queuedBannerMessage(int count) =>
      isEnglish ? '已排队 $count 条消息，将在当前回复结束后自动发送' : '已排队 $count 条消息，将在当前回复结束后自动发送';
  String get offlineCacheBanner =>
      isEnglish ? 'Offline cache mode. Content may not be up to date.' : '离线缓存模式，部分内容可能不是最新';
  String get dismissOfflineBanner => isEnglish ? 'Dismiss offline cache notice' : '关闭离线提示';
  String get pendingUserMessageBanner =>
      isEnglish ? '(This session has a pending message…)' : '（该会话有一条待处理消息…）';
  String get pickFileFailed => isEnglish ? 'Failed to Select File' : '选择文件失败';
  String get selectFileFailed => isEnglish ? 'Failed to Select File' : '选择文件失败';
  String get uploadSucceeded => isEnglish ? 'Upload Succeeded' : '上传成功';
  String get uploadSuccess => isEnglish ? 'Upload Succeeded' : '上传成功';
  String attachmentUploadedNotice(String name) =>
      isEnglish ? 'Attachment "$name" uploaded.' : '附件「$name」已上传。';
  String attachmentUploaded(String name) =>
      isEnglish ? 'Attachment "$name" uploaded.' : '附件「$name」已上传。';
  String get uploadFailed => isEnglish ? 'Upload Failed' : '上传失败';
  String get selectModel => isEnglish ? 'Select Model' : '选择模型';
  String get followServerDefault => isEnglish ? 'Follow Server Default' : '跟随服务器默认';
  String get contextWindowTitle => isEnglish ? 'Context window' : '上下文窗口';
  String get contextWindowInput => isEnglish ? 'Input' : '输入';
  String get contextWindowOutput => isEnglish ? 'Output' : '输出';
  String get contextWindowThreshold => isEnglish ? 'Threshold' : '阈值';
  String get contextWindowCost => isEnglish ? 'Cost' : '费用';
  String get compressHint =>
      isEnglish ? 'Compress when usage is high' : '上下文较高时建议压缩';
  String get compressing => isEnglish ? 'Compressing…' : '压缩中…';
  String get unavailable => isEnglish ? 'Unavailable' : '暂无数据';
  String get modelLabel => isEnglish ? 'Model' : '模型';
  String get addAttachment => isEnglish ? 'Add Attachment' : '添加附件';
  String get sessionIsReadOnly => isEnglish ? 'This session is read-only' : '此会话为只读';
  String get readOnlySessionPlaceholder => isEnglish ? 'This session is read-only' : '此会话为只读';
  String get steerCurrentReplyPlaceholder => isEnglish ? 'Steer current reply…' : '提示当前回复（steer）…';
  String get steerPromptPlaceholder => isEnglish ? 'Steer current reply…' : '提示当前回复（steer）…';
  String get sendMessagePlaceholder => isEnglish ? 'Send a message…' : '发送消息…';
  String get steerCurrentReply => isEnglish ? 'Steer current reply' : '提示当前回复';
  String get steerPrompt => isEnglish ? 'Steer current reply' : '提示当前回复';
  String get stopGenerating => isEnglish ? 'Stop generating' : '停止生成';
  String get sendMessage => isEnglish ? 'Send message' : '发送消息';
  String get copiedToClipboardNotice => isEnglish ? 'Copied to clipboard' : '已复制到剪贴板';
  String get thinking => isEnglish ? 'Thinking…' : '思考中…';
  String get thinkingIndicator => isEnglish ? 'Thinking…' : '思考中…';
  String get sending => isEnglish ? 'Sending…' : '发送中…';
  String get sendingIndicator => isEnglish ? 'Sending…' : '发送中…';
  String get messageActions => isEnglish ? 'Message Actions' : '消息操作';
  String get copyText => isEnglish ? 'Copy Text' : '复制文本';
  String get copyMarkdown => isEnglish ? 'Copy Markdown' : '复制 Markdown';
  String get editAndResend => isEnglish ? 'Edit and Resend' : '编辑并重新发送';
  String get branchFromHere => isEnglish ? 'Branch from Here' : '从此处创建分支';
  String get truncateFromHere => isEnglish ? 'Truncate from Here' : '从此处截断';
  String get confirmTruncatePrompt => isEnglish
      ? 'Delete all messages after this message? This action cannot be undone.'
      : '删除此消息之后的所有消息？此操作不可撤销。';
  String get truncate => isEnglish ? 'Truncate' : '截断';
  String get attachmentFallback => isEnglish ? 'Attachment' : '附件';
  String get thinkingBlock => isEnglish ? 'Thinking' : 'Thinking';
  String get thinkingLabel => isEnglish ? 'Thinking' : 'Thinking';
  String get runningDots => isEnglish ? 'Running…' : '运行中…';
  String get runningIndicator => isEnglish ? 'Running…' : '运行中…';
  String get failedStatus => isEnglish ? 'Failed' : '失败';
  String get runningStatus => isEnglish ? 'Running' : '运行中';
  String get toolFailedStatus => isEnglish ? 'Failed' : '失败';
  String get toolRunningStatus => isEnglish ? 'Running' : '运行中';
  String get imageLoadFailed => isEnglish ? 'Failed to load image' : '图片加载失败';
  String get mediaDownload => isEnglish ? 'Download' : '下载';
  String get mediaAudio => isEnglish ? 'Audio' : '音频';
  String get mediaVideo => isEnglish ? 'Video' : '视频';
  String get mediaDocument => isEnglish ? 'Document' : '文档';
  String get mediaImage => isEnglish ? 'Image' : '图片';

  // ---------------------------------------------------------------------------
  // 4. Tasks (Cron)
  // ---------------------------------------------------------------------------
  String get tasks => isEnglish ? 'Tasks' : '任务';
  String get cronTasks => isEnglish ? 'Scheduled Tasks' : '定时任务';
  String get tasksTitle => isEnglish ? 'Scheduled Tasks' : '定时任务';
  String get newScheduledTask => isEnglish ? 'New Scheduled Task' : '新建定时任务';
  String totalTasksHeader(int count) => isEnglish ? '$count tasks in total' : '共 $count 个任务';
  String get noTasks => isEnglish ? 'No tasks' : '暂无任务';
  String get noTasksDescription => isEnglish
      ? 'Create scheduled tasks to let the assistant run automatically'
      : '创建定时任务，让助手按调度自动执行';
  String get createTaskPrompt => isEnglish
      ? 'Create scheduled tasks to let the assistant run automatically'
      : '创建定时任务，让助手按调度自动执行';
  String get newTask => isEnglish ? 'New Task' : '新建任务';
  String get editTask => isEnglish ? 'Edit Task' : '编辑任务';
  String get run => isEnglish ? 'Run' : '运行';
  String get runTask => isEnglish ? 'Run' : '运行';
  String get resume => isEnglish ? 'Resume' : '恢复';
  String get resumeTask => isEnglish ? 'Resume' : '恢复';
  String get pause => isEnglish ? 'Pause' : '暂停';
  String get pauseTask => isEnglish ? 'Pause' : '暂停';
  String get viewOutput => isEnglish ? 'View Output' : '查看输出';
  String get deleteTask => isEnglish ? 'Delete Task' : '删除任务';
  String confirmDeleteTaskPrompt(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定删除「$name」？此操作不可撤销。';
  String confirmDeleteTask(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定删除「$name」？此操作不可撤销。';
  String get taskActions => isEnglish ? 'Task Actions' : '任务操作';
  String lastRunTime(String time) => isEnglish ? 'Last run $time' : '上次运行 $time';
  String get taskOutput => isEnglish ? 'Task Output' : '任务输出';
  String get closeOutputPanel => isEnglish ? 'Close Output Panel' : '关闭输出面板';
  String get noOutput => isEnglish ? 'No output' : '暂无输出';
  String outputNumber(int index) => isEnglish ? 'Output $index' : '输出 $index';
  String outputItemTitle(int index) => isEnglish ? 'Output $index' : '输出 $index';
  String get taskName => isEnglish ? 'Name' : '名称';
  String get taskNamePlaceholder => isEnglish ? 'Task name (optional)' : '任务名称（可选）';
  String get taskNameOptionalPlaceholder => isEnglish ? 'Task name (optional)' : '任务名称（可选）';
  String get scheduleExpression => isEnglish ? 'Schedule Expression' : '调度表达式';
  String get schedulePlaceholder =>
      isEnglish ? 'e.g. 0 9 * * * or every 2 hours' : '例如 0 9 * * * 或 every 2 hours';
  String get scheduleExpressionPlaceholder =>
      isEnglish ? 'e.g. 0 9 * * * or every 2 hours' : '例如 0 9 * * * 或 every 2 hours';
  String get promptLabel => isEnglish ? 'Prompt' : '提示词';
  String get promptField => isEnglish ? 'Prompt' : '提示词';
  String get promptPlaceholder =>
      isEnglish ? 'Prompt sent to the assistant when executed' : '定时执行时发送给助手的提示词';
  String get promptFieldPlaceholder =>
      isEnglish ? 'Prompt sent to the assistant when executed' : '定时执行时发送给助手的提示词';
  String get pushNotifications => isEnglish ? 'Push Notifications' : '推送通知';
  String get statusRunning => isEnglish ? 'Running' : '运行中';
  String get statusNormal => isEnglish ? 'Active' : '正常';
  String get statusPaused => isEnglish ? 'Paused' : '已暂停';
  String get statusDisabled => isEnglish ? 'Disabled' : '已停用';
  String get statusError => isEnglish ? 'Error' : '出错';
  String get statusNeedsAttention => isEnglish ? 'Needs Attention' : '需关注';
  String get taskStatusRunning => isEnglish ? 'Running' : '运行中';
  String get taskStatusActive => isEnglish ? 'Active' : '正常';
  String get taskStatusNormal => isEnglish ? 'Active' : '正常';
  String get taskStatusPaused => isEnglish ? 'Paused' : '已暂停';
  String get taskStatusOff => isEnglish ? 'Disabled' : '已停用';
  String get taskStatusError => isEnglish ? 'Error' : '出错';
  String get taskStatusNeedsAttention => isEnglish ? 'Needs Attention' : '需关注';

  // ---------------------------------------------------------------------------
  // 5. Skills
  // ---------------------------------------------------------------------------
  String get skills => isEnglish ? 'Skills' : '技能';
  String get skillsTitle => isEnglish ? 'Skills' : '技能';
  String get refreshSkills => isEnglish ? 'Refresh Skills' : '刷新技能';
  String get searchSkills => isEnglish ? 'Search skills' : '搜索技能';
  String get noMatchingSkillsFound => isEnglish ? 'No matching skills found' : '未找到相关技能';
  String get noSkills => isEnglish ? 'No skills' : '暂无技能';
  String get serverSkillsWillShowHere =>
      isEnglish ? 'Skills from the server will appear here' : '服务器的技能将显示在这里';
  String get disabledBadge => isEnglish ? 'Disabled' : '已禁用';
  String get skillDisabledBadge => isEnglish ? 'Disabled' : '已禁用';
  String get noMoreSkillDetails => isEnglish ? 'No further details for this skill' : '该技能没有更多详情';
  String get noMoreDetailsForSkill => isEnglish ? 'No further details for this skill' : '该技能没有更多详情';
  String get pathLabel => isEnglish ? 'Path' : '路径';
  String get skillPathLabel => isEnglish ? 'Path' : '路径';
  String get relatedSkillsLabel => isEnglish ? 'Related skills' : '相关技能';
  String get skillsGroupBuiltin => isEnglish ? 'Builtin' : '内置技能';
  String get skillsGroupProject => isEnglish ? 'Project' : '项目技能';
  String get skillsGroupGlobal => isEnglish ? 'Global' : '全局技能';
  String get skillsGroupOther => isEnglish ? 'Other' : '其他技能';

  // ---------------------------------------------------------------------------
  // 6. Memory
  // ---------------------------------------------------------------------------
  String get memory => isEnglish ? 'Memory' : '记忆';
  String get memoryTitle => isEnglish ? 'Memory' : '记忆';
  String get memoryEntrySubtitle =>
      isEnglish ? 'View notes, profile and project context' : '查看笔记、画像与项目上下文';
  String get refreshMemory => isEnglish ? 'Refresh Memory' : '刷新记忆';
  String get noMemory => isEnglish ? 'No memory' : '暂无记忆';
  String get noMemoryContentYet => isEnglish ? 'No memory content yet' : '还没有任何记忆内容';
  String get projectContext => isEnglish ? 'Project Context' : '项目上下文';
  String get projectContextTitle => isEnglish ? 'Project Context' : '项目上下文';
  String get memoryNotesTitle => isEnglish ? 'My Notes' : '我的笔记';
  String get memoryUserTitle => isEnglish ? 'User Profile' : '用户画像';
  String get memorySoulTitle => isEnglish ? 'Agent Soul' : '智能体灵魂';
  String get memoryNotesEmpty => isEnglish ? 'No notes yet' : '暂无笔记';
  String get memoryUserEmpty => isEnglish ? 'No profile yet' : '暂无画像';
  String get memorySoulEmpty => isEnglish ? 'No soul settings yet' : '暂无灵魂设定';
  String get projectContextShadowedWarning => isEnglish
      ? 'Workspace local file is overriding the global project context.'
      : '工作区本地文件正在覆盖全局项目上下文。';
  String get memoryCharUnit => isEnglish ? 'chars' : '字';
  String get expandText => isEnglish ? 'Show More' : '展开全文';
  String get collapseText => isEnglish ? 'Show Less' : '收起';

  // Injected notice collapse (agent-injected-message-cards-spec §4)
  String get collapseInjectedNoticesLabel =>
      isEnglish ? 'Collapse system notices' : '折叠系统通知';
  String get collapseInjectedNoticesDescription => isEnglish
      ? 'Fold agent-injected notices (background processes, skills, cron, MCP) into compact cards'
      : '将后台进程/技能/定时任务/MCP 等系统通知折叠为紧凑卡片';
  String get injectedNoticeTitleBackgroundProcess =>
      isEnglish ? 'Background process' : '后台进程';
  String get injectedNoticeTitleSkill => isEnglish ? 'Skill' : '技能';
  String get injectedNoticeTitleCron =>
      isEnglish ? 'Scheduled task' : '定时任务';
  String get injectedNoticeTitleMcp =>
      isEnglish ? 'MCP' : 'MCP';
  String get injectedNoticeShowOutput =>
      isEnglish ? 'Show output' : '展开';
  String get injectedNoticeHideOutput =>
      isEnglish ? 'Hide output' : '收起';
  String get injectedNoticeExpand => injectedNoticeShowOutput;
  String get injectedNoticeCollapse => injectedNoticeHideOutput;

  // ---------------------------------------------------------------------------
  // 7. Workspace (Files)
  // ---------------------------------------------------------------------------
  String get workspace => isEnglish ? 'Workspace' : '工作区';
  String get files => isEnglish ? 'Files' : '文件';
  String get workspaceFilesTitle => isEnglish ? 'Workspace Files' : '工作区文件';
  String get refreshFileList => isEnglish ? 'Refresh file list' : '刷新文件列表';
  String get uploadFile => isEnglish ? 'Upload file' : '上传文件';
  String get location => isEnglish ? 'Location' : '位置';
  String get locationLabel => isEnglish ? 'Location' : '位置';
  String get rootDir => isEnglish ? 'Root' : '根目录';
  String get rootDirectory => isEnglish ? 'Root' : '根目录';
  String get parentDir => isEnglish ? 'Up' : '上一级';
  String get parentDirectory => isEnglish ? 'Up' : '上一级';
  String get noFiles => isEnglish ? 'No files' : '暂无文件';
  String get unnamedFile => isEnglish ? 'Unnamed' : '未命名';
  String get loadingIndicator => isEnglish ? 'Loading…' : '加载中…';
  String get download => isEnglish ? 'Download' : '下载';
  String get deleteFile => isEnglish ? 'Delete File' : '删除文件';
  String confirmDeleteFilePrompt(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定要删除「$name」吗？此操作不可撤销。';
  String confirmDeleteFile(String name) => isEnglish
      ? 'Are you sure you want to delete "$name"? This action cannot be undone.'
      : '确定要删除「$name」吗？此操作不可撤销。';
  String get filePickerNotAvailable => isEnglish ? 'File picker not yet available' : '文件选择功能待接入';
  String get filePickerPendingPlatformSupport => isEnglish
      ? 'Selecting local files requires platform channel support (file picker), which will be available in a future version.'
      : '选择本地文件需要平台通道支持（file picker），将在后续版本提供。';
  String get filePickerNotAvailableDescription => isEnglish
      ? 'Selecting local files requires platform channel support (file picker), which will be available in a future version.'
      : '选择本地文件需要平台通道支持（file picker），将在后续版本提供。';
  String get fileActions => isEnglish ? 'File Actions' : '文件操作';
  String get manageWorkspaces => isEnglish ? 'Manage Workspaces' : '工作区管理';
  String get manageWorkspacesSubtitle => isEnglish
      ? 'Add, rename or remove workspaces, and browse their files'
      : '添加/重命名/移除工作区，并浏览其文件';
  String get workspacesTitle => isEnglish ? 'Workspaces' : '工作区';
  String get addWorkspace => isEnglish ? 'Add Workspace' : '添加工作区';
  String get addWorkspaceButton => isEnglish ? 'Add' : '添加';
  String get workspacePathLabel => isEnglish ? 'Path' : '路径';
  String get workspacePathHint => isEnglish
      ? 'Absolute path on disk, e.g. D:/projects/my-app'
      : '磁盘上的绝对路径，例如 D:/projects/my-app';
  String get workspaceNameOptionalLabel => isEnglish ? 'Name (optional)' : '名称（可选）';
  String get workspaceNamePlaceholder => isEnglish ? 'Display name' : '显示名称';
  String get createDirectoryIfMissing => isEnglish ? 'Create if missing' : '目录不存在时自动创建';
  String get renameWorkspaceTitle => isEnglish ? 'Rename Workspace' : '重命名工作区';
  String get removeWorkspaceTitle => isEnglish ? 'Remove Workspace' : '移除工作区';
  String confirmRemoveWorkspace(String name) => isEnglish
      ? 'Remove "$name" from the workspace list? Only the path is unregistered — no files on disk are deleted.'
      : '确定从列表移除「$name」吗？只注销路径，不会删除磁盘上的任何文件。';
  String get removeWorkspaceFooter => isEnglish
      ? 'Removing a workspace only unregisters its path from the server list. No files are deleted.'
      : '移除工作区只是从列表注销路径，不会删除磁盘上的文件。';
  String get noWorkspacesYet => isEnglish ? 'No workspaces yet' : '还没有工作区';
  String get addWorkspaceHint =>
      isEnglish ? 'Tap + at the top right to add a workspace.' : '点右上角 + 添加工作区。';
  String get currentWorkspaceBadge => isEnglish ? 'Current' : '当前';
  String get browseWorkspaceFiles => isEnglish ? 'Browse files' : '浏览文件';
  String get noSessionForWorkspaceTitle => isEnglish ? 'Cannot browse this workspace' : '无法浏览该工作区';
  String noSessionForWorkspaceBody(String path) => isEnglish
      ? 'No session is using this workspace ($path) yet. Open it from a session first, or create a new session.'
      : '当前没有会话使用该工作区（$path）。请先从会话进入该工作区的文件页，或新建会话后重试。';
  String get preview => isEnglish ? 'Preview' : '预览';
  String get previewUnavailable => isEnglish ? 'Preview not available' : '无法预览该文件';
  String get previewUnavailableHint => isEnglish
      ? 'This file type is not supported for preview yet. Download it instead.'
      : '暂不支持预览该文件类型，请改用下载。';
  String get downloadFolderZip => isEnglish ? 'Download folder as ZIP' : '打包下载当前目录';
  String get emptyFile => isEnglish ? '(empty file)' : '（空文件）';
  String get linesShort => isEnglish ? 'lines' : '行';
  String get previewTruncated => isEnglish ? 'Truncated: file too large' : '已截断：文件过大';

  // ---------------------------------------------------------------------------
  // 8. Kanban
  // ---------------------------------------------------------------------------
  String get kanban => isEnglish ? 'Kanban' : '看板';
  String get kanbanTitle => isEnglish ? 'Kanban' : '看板';
  String get newCard => isEnglish ? 'New Card' : '新建卡片';
  String get unnamedBoard => isEnglish ? 'Untitled board' : '未命名看板';
  String get untitledBoard => isEnglish ? 'Untitled board' : '未命名看板';
  String get kanbanEmptyContent => isEnglish ? 'Board has no content' : '看板暂无内容';
  String get boardEmpty => isEnglish ? 'Board has no content' : '看板暂无内容';
  String get clickPlusToCreateFirstCard =>
      isEnglish ? 'Tap the + button at the top right to create the first card' : '点击右上角 + 创建第一张卡片';
  String get tapPlusToCreateFirstCard =>
      isEnglish ? 'Tap the + button at the top right to create the first card' : '点击右上角 + 创建第一张卡片';
  String get noKanbanBoards => isEnglish ? 'No boards' : '暂无看板';
  String get noBoards => isEnglish ? 'No boards' : '暂无看板';
  String get createBoardOnServerPrompt =>
      isEnglish ? 'Pull down to refresh after creating a board on the server' : '在服务器端创建看板后下拉刷新';
  String get noCards => isEnglish ? 'No cards' : '暂无卡片';
  String get unnamedCard => isEnglish ? 'Untitled card' : '未命名卡片';
  String get untitledCard => isEnglish ? 'Untitled card' : '未命名卡片';
  String get unassigned => isEnglish ? 'Unassigned' : '未指派';
  String parentsDependency(int count) => isEnglish ? 'Parents $count' : '前驱 $count';
  String childrenDependency(int count) => isEnglish ? 'Children $count' : '后继 $count';
  String parentsCount(int count) => isEnglish ? 'Parents $count' : '前驱 $count';
  String childrenCount(int count) => isEnglish ? 'Children $count' : '后继 $count';
  String get cardDetail => isEnglish ? 'Card Detail' : '卡片详情';
  String get cardDoesNotExist => isEnglish ? 'Card does not exist' : '卡片不存在';
  String get cardNotFound => isEnglish ? 'Card not found' : '卡片不存在';
  String get statusLabel => isEnglish ? 'Status' : '状态';
  String get assigneeLabel => isEnglish ? 'Assignee' : '负责人';
  String get priorityLabel => isEnglish ? 'Priority' : '优先级';
  String get createdAtLabel => isEnglish ? 'Created at' : '创建时间';
  String get updatedAtLabel => isEnglish ? 'Updated at' : '更新时间';
  String get status => isEnglish ? 'Status' : '状态';
  String get assignee => isEnglish ? 'Assignee' : '负责人';
  String get priority => isEnglish ? 'Priority' : '优先级';
  String get createdAt => isEnglish ? 'Created at' : '创建时间';
  String get updatedAt => isEnglish ? 'Updated at' : '更新时间';
  String get changeStatus => isEnglish ? 'Change Status' : '变更状态';
  String commentsHeader(int count) => isEnglish ? 'Comments ($count)' : '评论（$count）';
  String get noComments => isEnglish ? 'No comments' : '暂无评论';
  String get addCommentPlaceholder => isEnglish ? 'Add a comment…' : '添加评论…';
  String get sendComment => isEnglish ? 'Send comment' : '发送评论';
  String boardPrefix(String name) => isEnglish ? 'Board: $name' : '看板：$name';
  String get titleLabel => isEnglish ? 'Title' : '标题';
  String get title => isEnglish ? 'Title' : '标题';
  String get cardTitlePlaceholder => isEnglish ? 'Card title' : '卡片标题';
  String get cardDescriptionPlaceholder => isEnglish ? 'Card description (optional)' : '卡片描述（可选）';
  String get assignProfilePlaceholder => isEnglish ? 'Assign profile (optional)' : '指派 profile（可选）';
  String get initialStatus => isEnglish ? 'Initial Status' : '初始状态';
  String get kanbanStatusTriage => isEnglish ? 'Triage' : '待分类';
  String get kanbanStatusTodo => isEnglish ? 'To Do' : '待办';
  String get kanbanStatusReady => isEnglish ? 'Ready' : '就绪';
  String get kanbanStatusRunning => isEnglish ? 'Running' : '运行中';
  String get kanbanStatusBlocked => isEnglish ? 'Blocked' : '受阻';
  String get kanbanStatusDone => isEnglish ? 'Done' : '完成';
  String get kanbanStatusArchived => isEnglish ? 'Archived' : '已归档';
  String get kanbanStatusUnknown => isEnglish ? 'Unknown Status' : '未知状态';
  String kanbanStatusUnsupported(String? raw) => isEnglish ? 'Unsupported: $raw' : '不支持: $raw';

  // ---------------------------------------------------------------------------
  // 9. Insights
  // ---------------------------------------------------------------------------
  String get insights => isEnglish ? 'Insights' : '统计';
  String get insightsTitle => isEnglish ? 'Usage Insights' : '用量统计';
  String get refreshInsights => isEnglish ? 'Refresh Usage Insights' : '刷新用量统计';
  String get timeframeToday => isEnglish ? 'Today' : '今天';
  String get timeframeLast7Days => isEnglish ? 'Last 7 Days' : '近 7 天';
  String get timeframeLast30Days => isEnglish ? 'Last 30 Days' : '近 30 天';
  String get timeframeAll => isEnglish ? 'All Time' : '全部';
  String recentDaysHeader(int days) => isEnglish ? 'Last $days Days' : '最近 $days 天';
  String periodRecentDays(int days) => isEnglish ? 'Last $days Days' : '最近 $days 天';
  String get metricSessions => isEnglish ? 'Sessions' : '会话';
  String get metricMessages => isEnglish ? 'Messages' : '消息';
  String get metricInputTokens => isEnglish ? 'Input Tokens' : '输入令牌';
  String get metricOutputTokens => isEnglish ? 'Output Tokens' : '输出令牌';
  String get metricTotalTokens => isEnglish ? 'Total Tokens' : '总令牌';
  String get metricEstimatedCost => isEnglish ? 'Estimated Cost' : '估算费用';
  String get metricCacheHitRate => isEnglish ? 'Cache Hit Rate' : '缓存命中率';
  String get metricCacheReadTokens => isEnglish ? 'Cache Read Tokens' : '缓存读取令牌';
  String get models => isEnglish ? 'Models' : '模型';
  String get modelsSection => isEnglish ? 'Models' : '模型';
  String get tokensLast14Days => isEnglish ? 'Tokens in Last 14 Days' : '近 14 天令牌';
  String get recent14DaysTokens => isEnglish ? 'Tokens in Last 14 Days' : '近 14 天令牌';
  String get tokensTodayChartTitle => isEnglish ? 'Today\'s Tokens' : '今日令牌';
  String tokensDailyChartTitle(int days) => isEnglish ? 'Tokens in Last $days Days' : '近 $days 天令牌';
  String get tokensAllTimeChartTitle => isEnglish ? 'All Tokens' : '全部令牌';
  String get activity => isEnglish ? 'Activity' : '活动';
  String get activitySection => isEnglish ? 'Activity' : '活动';
  String get mostActiveDay => isEnglish ? 'Most Active Day' : '最活跃的一天';
  String peakDaySessions(String day, int count) =>
      isEnglish ? '$day · $count sessions' : '$day · $count 个会话';
  String get mostActiveHour => isEnglish ? 'Peak Activity Hour' : '最活跃时段';
  String peakHourSessions(String hour, int count) =>
      isEnglish ? '$hour · $count sessions' : '$hour · $count 个会话';
  String insightsSourceFooter(int days) =>
      isEnglish ? 'Source: Server statistics over the last $days days.' : '来源：服务器按最近 $days 天统计。';
  String insightsSourceDisclaimer(int days) =>
      isEnglish ? 'Source: Server statistics over the last $days days.' : '来源：服务器按最近 $days 天统计。';
  String get noInsights => isEnglish ? 'No Statistics' : '暂无统计';
  String get insightsWillShowHere =>
      isEnglish ? 'Usage data will appear here once you have conversations.' : '有对话后这里会显示用量数据。';
  String get unknownModel => isEnglish ? 'Unknown model' : '未知模型';
  String modelTokensSubtitle(String tokens) => isEnglish ? '$tokens tokens' : '$tokens 令牌';

  // ---------------------------------------------------------------------------
  // 10. Git
  // ---------------------------------------------------------------------------
  String get git => isEnglish ? 'Git' : 'Git';
  String get gitPanel => isEnglish ? 'Git Panel' : 'Git 面板';
  String get gitPanelTitle => isEnglish ? 'Git Panel' : 'Git 面板';
  String get refreshGitStatus => isEnglish ? 'Refresh Git Status' : '刷新 Git 状态';
  String get notAGitRepo => isEnglish ? 'Not a Git Repository' : '不是 Git 仓库';
  String get notAGitRepoDetail => isEnglish
      ? 'This workspace is not a git repository and Git features cannot be used.'
      : '该工作区不是 git 仓库，无法使用 Git 功能。';
  String get notAGitRepository => isEnglish ? 'Not a Git Repository' : '不是 Git 仓库';
  String get stagedSection => isEnglish ? 'Staged' : '已暂存';
  String get unstagedSection => isEnglish ? 'Unstaged' : '未暂存';
  String get tooManyChangedFilesWarning =>
      isEnglish ? 'Too many changed files, displaying the first 500 only.' : '变更文件过多，仅显示前 500 个。';
  String get unknownBranch => isEnglish ? 'Unknown branch' : '未知分支';
  String aheadBehind(int ahead, int behind) =>
      isEnglish ? 'ahead $ahead · behind $behind' : '领先 $ahead · 落后 $behind';
  String aheadBehindStatus(int ahead, int behind) =>
      isEnglish ? 'ahead $ahead · behind $behind' : '领先 $ahead · 落后 $behind';
  String get syncedWithRemote => isEnglish ? 'In sync with remote' : '与远程同步';
  String get inSyncWithRemote => isEnglish ? 'In sync with remote' : '与远程同步';
  String get switchBranch => isEnglish ? 'Switch Branch' : '切换分支';
  String get branchTreeSection => isEnglish ? 'Branch Tree' : '分支树';
  String get localBranches => isEnglish ? 'Local' : '本地';
  String get remoteBranches => isEnglish ? 'Remote' : '远程';
  String get currentBranchBadge => isEnglish ? 'CURRENT' : '当前';
  String get checkoutBranchAction => isEnglish ? 'Switch' : '切换';
  String get noBranches => isEnglish ? 'No branches found' : '未找到分支';
  String get changesLabel => isEnglish ? 'Changes' : '变更';
  String get changes => isEnglish ? 'Changes' : '变更';
  String changesSummary(int additions, int deletions, int changed) => isEnglish
      ? '+$additions −$deletions · $changed files in total'
      : '+$additions −$deletions · 共 $changed 个文件';
  String get commitSection => isEnglish ? 'Commit' : '提交';
  String get commitButton => isEnglish ? 'Commit' : '提交';
  String get commitMessagePlaceholder => isEnglish ? 'Commit message' : '提交信息';
  String get remoteOperations => isEnglish ? 'Remote Operations' : '远程操作';
  String get stageAction => isEnglish ? 'Stage' : '暂存';
  String get unstageAction => isEnglish ? 'Unstage' : '取消暂存';
  String get discardChanges => isEnglish ? 'Discard Changes' : '放弃更改';
  String get gitChangeAdded => isEnglish ? 'Added' : '新增';
  String get gitChangeDeleted => isEnglish ? 'Deleted' : '删除';
  String get gitChangeRenamed => isEnglish ? 'Renamed' : '重命名';
  String get gitChangeConflict => isEnglish ? 'Conflict' : '冲突';
  String get gitChangeUntracked => isEnglish ? 'Untracked' : '未跟踪';
  String get gitChangeIgnored => isEnglish ? 'Ignored' : '忽略';
  String get gitChangeModified => isEnglish ? 'Modified' : '修改';
  String get cannotLoadDiff => isEnglish ? 'Unable to load diff.' : '无法加载 diff。';
  String get binaryFileCannotShowDiff =>
      isEnglish ? 'Binary file, diff cannot be displayed.' : '二进制文件，无法显示 diff。';
  String get noDiffContent => isEnglish ? 'No diff content.' : '无 diff 内容。';
  String fileTooLargePartialContent(String partial) => isEnglish
      ? 'File is too large, showing partial content:\n$partial'
      : '文件过大，以下为部分内容：\n$partial';
  String get workspaceClean => isEnglish ? 'Workspace Clean' : '工作区干净';
  String get noPendingChanges => isEnglish ? 'No changes to commit.' : '没有待提交的变更。';

  // ---------------------------------------------------------------------------
  // 11. Settings & Profile
  // ---------------------------------------------------------------------------
  String get settingsTitle => isEnglish ? 'Settings' : '设置';
  String get settings => isEnglish ? 'Settings' : '设置';
  String get appearanceSection => isEnglish ? 'Appearance' : '外观';
  String get appearance => isEnglish ? 'Appearance' : '外观';
  String get sessionListEntriesSection => isEnglish ? 'Session List Entries' : '会话列表入口';
  String get sessionListEntries => isEnglish ? 'Session List Entries' : '会话列表入口';
  String get sessionRowSubtitleSection => isEnglish ? 'Session Row Details' : '会话行信息';
  String get sessionRowShowMessageCount => isEnglish ? 'Message count' : '消息数';
  String get sessionRowShowProjectName => isEnglish ? 'Project name' : '项目名';
  String get sessionRowShowWorkspace => isEnglish ? 'Workspace' : '工作区';
  String get sessionRowShowChannel => isEnglish ? 'Channel' : '渠道';
  String get sessionRowShowEstimatedCost => isEnglish ? 'Estimated cost' : '预估价钱';
  String get themeLabel => isEnglish ? 'Theme' : '主题';
  String get theme => isEnglish ? 'Theme' : '主题';
  String get themeSystem => isEnglish ? 'System' : '跟随系统';
  String get themeLight => isEnglish ? 'Light' : '浅色';
  String get themeDark => isEnglish ? 'Dark' : '深色';
  String get desktopSection => isEnglish ? 'Desktop' : '桌面';
  String get desktop => isEnglish ? 'Desktop' : '桌面';
  String get minimizeToTray => isEnglish ? 'Minimize to Tray' : '最小化到托盘';
  String get minimizeToTraySubtitle =>
      isEnglish ? 'Hide to tray instead of quitting when closing window' : '关闭窗口时隐藏到托盘而非退出';
  String get globalShortcuts => isEnglish ? 'Global Shortcuts' : '全局快捷键';
  String get globalShortcutsSubtitle => isEnglish
      ? 'Ctrl+Shift+H show window, Ctrl+Shift+N new session'
      : 'Ctrl+Shift+H 唤起主窗口，Ctrl+Shift+N 新建会话';
  String get rememberWindowPosition => isEnglish ? 'Remember Window Position' : '记住窗口位置';
  String get rememberWindowPositionSubtitle =>
      isEnglish ? 'Restore window size and position on startup' : '启动时恢复上次窗口位置与尺寸';
  String get serverSection => isEnglish ? 'Servers' : '服务器';
  String get serverSectionDisconnected => isEnglish ? 'Servers (Not Connected)' : '服务器（未连接）';
  String get noServerConfigured => isEnglish ? 'No servers configured' : '尚未配置服务器';
  String get noServerConfiguredSubtitle =>
      isEnglish ? 'Click "Add Server" below or configure from onboarding' : '点击下方「添加服务器」或从引导页配置';
  String get addServer => isEnglish ? 'Add Server' : '添加服务器';
  String get editServer => isEnglish ? 'Edit Server' : '编辑服务器';
  String get deleteServer => isEnglish ? 'Delete Server' : '删除服务器';
  String confirmDeleteServer(String name) =>
      isEnglish ? 'Are you sure you want to delete "$name"?' : '确定删除「$name」吗？';
  String get serverNamePlaceholder =>
      isEnglish ? 'Name (optional, defaults to host)' : '名称（可选，默认使用主机名）';
  String get serverNameOptionalPlaceholder =>
      isEnglish ? 'Name (optional, defaults to host)' : '名称（可选，默认使用主机名）';
  String get advancedSettings => isEnglish ? 'Advanced Settings' : '高级设置';
  String get advancedSettingsSection => isEnglish ? 'Advanced Settings' : '高级设置';
  String get serverBasicInfoSection => isEnglish ? 'Basic Information' : '基本信息';
  String get serverNameLabel => isEnglish ? 'Name' : '名称';
  String get serverUrlLabel => isEnglish ? 'Address' : '地址';
  String get serverPasswordLabel => isEnglish ? 'Password' : '密码';
  String get serverUrlExampleHint =>
      isEnglish ? 'e.g. https://hermes.example.com:30002' : '例如 https://hermes.example.com:30002';
  String get serverPasswordPlaceholder =>
      isEnglish ? 'Password (optional; leave blank to keep existing)' : '密码（可选；编辑时留空保持原密码）';
  String get serverPasswordOptionalPlaceholder =>
      isEnglish ? 'Password (optional; leave blank to keep existing)' : '密码（可选；编辑时留空保持原密码）';
  String get loadingModels => isEnglish ? 'Loading models…' : '正在加载模型…';
  String get modelsLoadFailed => isEnglish ? 'Failed to load models' : '模型加载失败';
  String get defaultModel => isEnglish ? 'Default Model' : '默认模型';
  String get notSet => isEnglish ? 'Not set' : '未设置';
  String get reasoningEffort => isEnglish ? 'Reasoning Effort' : '推理强度';
  String get noAvailableModels => isEnglish ? 'No models available' : '暂无可用模型';
  String get noModelsAvailable => isEnglish ? 'No models available' : '暂无可用模型';
  String get aboutSection => isEnglish ? 'About' : '关于';
  String get about => isEnglish ? 'About' : '关于';
  String get hermesWebUIClient => isEnglish ? 'Hermes WebUI Client' : 'Hermes WebUI 客户端';
  String get hermesWebUiClient => isEnglish ? 'Hermes WebUI Client' : 'Hermes WebUI 客户端';
  String get version => isEnglish ? 'Version' : '版本';
  String get profile => isEnglish ? 'Profile' : 'Profile';
  String get notRead => isEnglish ? 'Not loaded' : '未读取';
  String get notLoaded => isEnglish ? 'Not loaded' : '未读取';
  String get readFailed => isEnglish ? 'Read Failed' : '读取失败';
  String get clickToRetry => isEnglish ? 'Click to retry' : '点击重试';
  String get selectProfile => isEnglish ? 'Select Profile' : '选择 Profile';
  String get profileSwitchFailed => isEnglish ? 'Profile Switch Failed' : 'Profile 切换失败';

  // ---------------------------------------------------------------------------
  // 12. Projects
  // ---------------------------------------------------------------------------
  String get noProject => isEnglish ? 'No Project' : '无项目';
  String get unnamedProject => isEnglish ? 'Untitled project' : '未命名项目';
  String get newProject => isEnglish ? 'New Project' : '新建项目';
  String get newProjectEllipsis => isEnglish ? 'New Project…' : '新建项目…';
  String get projectNamePlaceholder => isEnglish ? 'Project name' : '项目名称';
  String get projectManagement => isEnglish ? 'Project Management' : '项目管理';
  String get renameProject => isEnglish ? 'Rename Project' : '重命名项目';
  String get deleteProject => isEnglish ? 'Delete Project' : '删除项目';
  String get deleteProjectDescription => isEnglish
      ? 'Sessions in the project will not be deleted, only unassigned.'
      : '删除后项目内会话不会被删除，仅解除归类。';
  String get deleteProjectWarning => isEnglish
      ? 'Sessions in the project will not be deleted, only unassigned.'
      : '删除后项目内会话不会被删除，仅解除归类。';

  // ---------------------------------------------------------------------------
  // 13. Saved Prompts
  // ---------------------------------------------------------------------------
  String get savedPrompts => isEnglish ? 'Saved Prompts' : '收藏提示词';
  String get savedPromptsTitle => isEnglish ? 'Saved Prompts' : '收藏提示词';
  String get savedPromptsEmpty => isEnglish ? 'No saved prompts yet.' : '暂无收藏提示词';
  String get savedPromptsDelete => isEnglish ? 'Delete' : '删除';
  String get savedPromptsSaveCurrent => isEnglish ? 'Save current input' : '收藏当前输入';
  String get saveCurrentInput => isEnglish ? 'Save current input' : '收藏当前输入';
  String get savedPromptsEmptyInput => isEnglish ? 'Type a prompt first' : '请先输入提示词';
  String get bookmarkPrompt => isEnglish ? 'Saved prompts' : '收藏提示词';
  String get promptSaved => isEnglish ? 'Prompt saved' : '已收藏';
  String get promptDeleted => isEnglish ? 'Prompt deleted' : '已删除';
  String get savePromptFailed => isEnglish ? 'Failed to save prompt' : '收藏失败';
  String get deletePromptFailed => isEnglish ? 'Failed to delete prompt' : '删除失败';

  // ---------------------------------------------------------------------------
  // 14. Settings · Extensions/MCP/Auxiliary
  // ---------------------------------------------------------------------------
  String get extensionsSection => isEnglish ? 'Extensions' : '扩展 (Extensions)';
  String get extensionsTitle => isEnglish ? 'Extensions' : '扩展';
  String get installedExtensions => isEnglish ? 'Installed Extensions' : '已安装扩展';
  String get noExtensions => isEnglish ? 'No extensions installed' : '暂无已安装扩展';
  String get installExtension => isEnglish ? 'Install Extension' : '安装扩展';
  String get extensionId => isEnglish ? 'Extension ID' : '扩展 ID';
  String get extensionDownloadUrl => isEnglish ? 'Download URL' : '下载地址';
  String get extensionSha256 => isEnglish ? 'SHA256 Checksum' : 'SHA256 校验和';
  String get extensionSidecarConsent => isEnglish ? 'Sidecar Proxy Consent' : 'Sidecar 代理授权';
  String get extensionSidecarActive => isEnglish ? 'Sidecar Active' : 'Sidecar 运行中';
  String get extensionSidecarInactive => isEnglish ? 'Sidecar Inactive' : 'Sidecar 未运行';
  String get uninstall => isEnglish ? 'Uninstall' : '卸载';
  String get uninstallExtension => isEnglish ? 'Uninstall Extension' : '卸载扩展';
  String confirmUninstallExtension(String name) =>
      isEnglish ? 'Are you sure you want to uninstall "$name"?' : '确定卸载「$name」扩展吗？';
  String get extensionDetails => isEnglish ? 'Extension Details' : '扩展详情';
  String get extensionRegistry => isEnglish ? 'Extension Registry' : '扩展源';
  String get selectFromRegistry => isEnglish ? 'Select from Registry' : '从扩展源选择';
  String get loadingExtensions => isEnglish ? 'Loading extensions…' : '正在加载扩展…';
  String get extensionsLoadFailed => isEnglish ? 'Failed to load extensions' : '扩展加载失败';

  String get mcpSection => isEnglish ? 'MCP Servers' : 'MCP 服务器';
  String get mcpServersTitle => isEnglish ? 'MCP Servers' : 'MCP 服务器';
  String get noMcpServers => isEnglish ? 'No MCP servers configured' : '暂无已配置的 MCP 服务器';
  String get addMcpServer => isEnglish ? 'Add MCP Server' : '添加 MCP 服务器';
  String get editMcpServer => isEnglish ? 'Edit MCP Server' : '编辑 MCP 服务器';
  String get deleteMcpServer => isEnglish ? 'Delete MCP Server' : '删除 MCP 服务器';
  String confirmDeleteMcpServer(String name) =>
      isEnglish ? 'Are you sure you want to delete "$name"?' : '确定删除 MCP 服务器「$name」吗？';
  String get mcpServerName => isEnglish ? 'Server Name' : '服务器名称';
  String get mcpCommand => isEnglish ? 'Command' : '执行命令';
  String get mcpArgs => isEnglish ? 'Arguments' : '参数';
  String get mcpArgsPlaceholder =>
      isEnglish ? 'Arguments (one per line or space separated)' : '命令参数（每行一个）';
  String get mcpEnv => isEnglish ? 'Environment Variables (JSON)' : '环境变量（JSON）';
  String get mcpServerEnabled => isEnglish ? 'Enabled' : '启用';
  String get mcpTools => isEnglish ? 'MCP Tools' : 'MCP 工具';
  String mcpToolsCount(int count) => isEnglish ? '$count tools' : '$count 个工具';
  String get viewMcpTools => isEnglish ? 'View Tools' : '查看工具';
  String get noMcpTools => isEnglish ? 'No tools available' : '暂无可用的 MCP 工具';
  String get mcpStatusConnected => isEnglish ? 'Connected' : '已连接';
  String get mcpStatusDisconnected => isEnglish ? 'Disconnected' : '未连接';
  String get mcpServerDetails => isEnglish ? 'MCP Server Details' : 'MCP 服务器详情';
  String get loadingMcpServers => isEnglish ? 'Loading MCP servers…' : '正在加载 MCP 服务器…';
  String get mcpServersLoadFailed => isEnglish ? 'Failed to load MCP servers' : 'MCP 服务器加载失败';
  String get mcpServerNameRequired => isEnglish ? 'Server name is required' : '请输入服务器名称';
  String get mcpCommandRequired => isEnglish ? 'Command is required' : '请输入执行命令';
  String get mcpEnvInvalidJson => isEnglish ? 'Environment must be valid JSON' : '环境变量必须是合法的 JSON 对象';

  String get auxiliaryModelsSection => isEnglish ? 'Auxiliary Models' : '辅助模型';
  String get auxiliaryModelsTitle => isEnglish ? 'Auxiliary Models' : '辅助模型';
  String get resetAuxiliary => isEnglish ? 'Reset All to Auto' : '全部重置为自动';
  String get confirmResetAuxiliary =>
      isEnglish ? 'Reset all auxiliary model tasks to automatic?' : '确定将所有辅助模型任务重置为自动吗？';
  String get auto => isEnglish ? 'Auto' : '自动';
  String get apiKeyConfigured => isEnglish ? 'API Key Configured' : '已配置 API Key';
  String get apiKeyNotConfigured => isEnglish ? 'No API Key' : '未配置 API Key';
  String get auxTaskPickerTitle => isEnglish ? 'Select Auxiliary Model' : '选择辅助模型';
  String get auxMainModel => isEnglish ? 'Main Model' : '主模型';
  String get auxTasks => isEnglish ? 'Task Bindings' : '任务绑定';
  String get loadingAuxiliaryModels => isEnglish ? 'Loading auxiliary models…' : '正在加载辅助模型…';
  String get auxiliaryModelsLoadFailed => isEnglish ? 'Failed to load auxiliary models' : '辅助模型加载失败';

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('zh'));
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => const ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}