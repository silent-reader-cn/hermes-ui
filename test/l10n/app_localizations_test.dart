import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations (zh locale)', () {
    const l10n = AppLocalizations(Locale('zh'));

    test('isEnglish is false', () {
      expect(l10n.isEnglish, isFalse);
    });

    test('Common strings return Chinese values', () {
      expect(l10n.ok, '好');
      expect(l10n.cancel, '取消');
      expect(l10n.save, '保存');
      expect(l10n.create, '创建');
      expect(l10n.delete, '删除');
      expect(l10n.edit, '编辑');
      expect(l10n.close, '关闭');
      expect(l10n.retry, '重试');
      expect(l10n.loading, '加载中…');
      expect(l10n.loadingEllipsis, '加载中…');
      expect(l10n.export, '导出');
      expect(l10n.rename, '重命名');
      expect(l10n.notice, '提示');
      expect(l10n.unknown, '未知');
      expect(l10n.unnamed, '未命名');
      expect(l10n.unknownError, '未知错误');
      expect(l10n.loadFailed, '加载失败');
      expect(l10n.loadFailedRetry, '加载失败，请重试');
      expect(l10n.actionFailed, '操作失败');
      expect(l10n.dismissNotice, '关闭提示');
      expect(l10n.closeNotice, '关闭提示');
      expect(l10n.dismissError, '关闭错误提示');
      expect(l10n.offlineCache, '离线缓存');
      expect(l10n.all, '全部');
      expect(l10n.name, '名称');
      expect(l10n.value, '值');
      expect(l10n.info, '信息');
      expect(l10n.description, '描述');
      expect(l10n.noDescription, '暂无描述');
      expect(l10n.copiedToClipboard, '已复制到剪贴板');
    });

    test('Onboarding strings return Chinese values', () {
      expect(l10n.connectServer, '连接服务器');
      expect(l10n.connectYourHermexServer, '连接你的 Hermex 服务器');
      expect(l10n.testConnection, '连接测试');
      expect(l10n.haveApiKeySkipWizard, '已有 API Key？跳过向导');
      expect(l10n.checking, '正在检查…');
      expect(l10n.connectionSuccessful, '连接成功');
      expect(l10n.connectionSuccessfulWithCheck, '✅ 连接成功');
      expect(l10n.serverReturnedAbnormalStatus, '服务器返回异常状态');
      expect(l10n.cannotConnectToServer, '无法连接到服务器');
      expect(l10n.authentication, '认证');
      expect(l10n.detectingServerAuth, '正在检测服务器认证…');
      expect(
        l10n.serverNoPasswordRequired,
        '该服务器未启用密码认证，可直接继续',
      );
      expect(l10n.serverPasswordRequired, '该服务器需要密码认证，请登录');
      expect(l10n.usernameOptional, '用户名（可选）');
      expect(l10n.password, '密码');
      expect(l10n.skipAuthNoPasswordMode, '跳过认证（无密码模式）');
      expect(l10n.loginFailed, '登录失败');
      expect(l10n.loginFailedWithReason('timeout'), '登录失败：timeout');
      expect(l10n.loginFailedWithMessage('network'), '登录失败：network');
      expect(l10n.cannotConnectRetryLater, '无法连接到服务器，请稍后重试');
      expect(l10n.customHeadersOptional, '自定义 Headers（可选）');
      expect(
        l10n.customHeadersDescription,
        '反向代理场景可添加自定义请求头，如 Authorization: Bearer xxx',
      );
      expect(l10n.addHeader, '添加 Header');
      expect(l10n.headerName, 'Header 名');
      expect(l10n.deleteHeader, '删除 Header');
      expect(l10n.nextStep, '下一步');
      expect(l10n.continueAction, '继续');
      expect(l10n.loginAndContinue, '登录并继续');
      expect(l10n.finish, '完成');
      expect(l10n.pleaseEnterServerUrl, '请输入服务器地址');
      expect(l10n.serverUrlRequired, '请输入服务器地址');
      expect(
        l10n.pleaseEnterValidServerUrl,
        '请输入有效的服务器地址，例如 https://hermes.example.com:30002',
      );
      expect(
        l10n.serverUrlInvalid,
        '请输入有效的服务器地址，例如 https://hermes.example.com:30002',
      );
      expect(
        l10n.headerValidationFailed,
        'Header 名必须是合法 token，值不能包含换行',
      );
    });

    test('Session List strings return Chinese values', () {
      expect(l10n.sessions, '会话');
      expect(l10n.doneSelecting, '完成选择');
      expect(l10n.newSession, '新建会话');
      expect(l10n.searchSessions, '搜索会话');
      expect(l10n.archived, '已归档');
      expect(l10n.clearFilter, '清除筛选');
      expect(l10n.untitledProject, '未命名项目');
      expect(l10n.selectedCount(3), '已选 3 个');
      expect(l10n.selectAll, '全选');
      expect(l10n.archive, '归档');
      expect(l10n.batchMoveProject, '移动项目');
      expect(l10n.moveToProject, '移动到项目');
      expect(l10n.pin, '置顶');
      expect(l10n.unpin, '取消置顶');
      expect(l10n.unarchive, '恢复归档');
      expect(l10n.branch, '分支');
      expect(l10n.exportSession, '导出会话');
      expect(l10n.markdownFormat, 'Markdown');
      expect(l10n.jsonFormat, 'JSON');
      expect(l10n.exportSuccess('JSON'), 'JSON 导出成功');
      expect(l10n.exportContentEmpty, '导出内容为空');
      expect(l10n.copyContent, '复制内容');
      expect(l10n.exportFailed, '导出失败');
      expect(l10n.deleteSession, '删除会话');
      expect(
        l10n.confirmDeleteSession('Test Session'),
        '确定删除「Test Session」？此操作不可撤销。',
      );
      expect(l10n.batchArchiveTitle, '批量归档');
      expect(l10n.confirmBatchArchivePrompt, '归档选中的会话？');
      expect(l10n.batchDeleteTitle, '批量删除');
      expect(
        l10n.confirmBatchDeletePrompt(5),
        '删除选中的 5 个会话？此操作不可撤销。',
      );
      expect(l10n.noMore, '没有更多了');
      expect(l10n.noMatchingSessionsFound, '未找到相关会话');
      expect(l10n.noSessions, '暂无会话');
      expect(l10n.tryAnotherKeyword, '换个关键词试试');
      expect(l10n.tapButtonToStartNewChat, '点击下方按钮开始新对话');
      expect(l10n.pendingInput, '待输入');
      expect(l10n.sessionActions, '会话操作');
      expect(l10n.untitledSession, '未命名会话');
      expect(l10n.messageCountLabel(10), '10 条消息');
      expect(l10n.pinnedSection, '置顶');
      expect(l10n.todaySection, '今天');
      expect(l10n.yesterdaySection, '昨天');
      expect(l10n.earlierSection, '更早');
      expect(l10n.searchResultsSection, '搜索结果');
    });

    test('Chat strings return Chinese values', () {
      expect(l10n.branchBadge, '分支');
      expect(l10n.branchSession, '分支会话');
      expect(
        l10n.branchSessionDescription('sess-123'),
        '该会话是另一个会话的分支。\n父会话 sess-123',
      );
      expect(l10n.jumpToParentSession, '跳转父会话');
      expect(l10n.renameSession, '重命名会话');
      expect(l10n.compressSession, '压缩会话');
      expect(l10n.focusTopicPlaceholder, '聚焦主题（可留空）');
      expect(l10n.compress, '压缩');
      expect(l10n.undoLastTurn, '撤销上一轮');
      expect(l10n.confirmUndoLastTurnPrompt, '删除最后一轮对话？此操作不可撤销');
      expect(l10n.retryLastTurn, '重试上一轮');
      expect(l10n.sessionSettings, '会话设置');
      expect(l10n.workspaceOptionalPlaceholder, 'Workspace（可留空）');
      expect(l10n.modelNameOptionalPlaceholder, '模型名（可留空）');
      expect(l10n.enableYolo, '开启 YOLO');
      expect(l10n.disableYolo, '关闭 YOLO');
      expect(l10n.createBranch, '创建分支');
      expect(l10n.exportSuccessDialogTitle, '导出成功');
      expect(l10n.markdownCopiedToClipboard, 'Markdown 已复制到剪贴板。');
      expect(l10n.approvalNeeded, '需要审批');
      expect(l10n.clarificationNeeded, '需要澄清');
      expect(
        l10n.queuedBannerMessage(2),
        '已排队 2 条消息，将在当前回复结束后自动发送',
      );
      expect(l10n.pendingUserMessageBanner, '（该会话有一条待处理消息…）');
      expect(l10n.pickFileFailed, '选择文件失败');
      expect(l10n.selectFileFailed, '选择文件失败');
      expect(l10n.uploadSucceeded, '上传成功');
      expect(l10n.uploadSuccess, '上传成功');
      expect(l10n.attachmentUploadedNotice('doc.pdf'), '附件「doc.pdf」已上传。');
      expect(l10n.attachmentUploaded('doc.pdf'), '附件「doc.pdf」已上传。');
      expect(l10n.uploadFailed, '上传失败');
      expect(l10n.selectModel, '选择模型');
      expect(l10n.followServerDefault, '跟随服务器默认');
      expect(l10n.addAttachment, '添加附件');
      expect(l10n.sessionIsReadOnly, '此会话为只读');
      expect(l10n.readOnlySessionPlaceholder, '此会话为只读');
      expect(l10n.steerCurrentReplyPlaceholder, '提示当前回复（steer）…');
      expect(l10n.steerPromptPlaceholder, '提示当前回复（steer）…');
      expect(l10n.sendMessagePlaceholder, '发送消息…');
      expect(l10n.steerCurrentReply, '提示当前回复');
      expect(l10n.steerPrompt, '提示当前回复');
      expect(l10n.stopGenerating, '停止生成');
      expect(l10n.sendMessage, '发送消息');
      expect(l10n.copiedToClipboardNotice, '已复制到剪贴板');
      expect(l10n.thinking, '思考中…');
      expect(l10n.thinkingIndicator, '思考中…');
      expect(l10n.sending, '发送中…');
      expect(l10n.sendingIndicator, '发送中…');
      expect(l10n.messageActions, '消息操作');
      expect(l10n.copyText, '复制文本');
      expect(l10n.copyMarkdown, '复制 Markdown');
      expect(l10n.editAndResend, '编辑并重新发送');
      expect(l10n.branchFromHere, '从此处创建分支');
      expect(l10n.truncateFromHere, '从此处截断');
      expect(
        l10n.confirmTruncatePrompt,
        '删除此消息之后的所有消息？此操作不可撤销。',
      );
      expect(l10n.truncate, '截断');
      expect(l10n.attachmentFallback, '附件');
      expect(l10n.thinkingBlock, 'Thinking');
      expect(l10n.thinkingLabel, 'Thinking');
      expect(l10n.runningDots, '运行中…');
      expect(l10n.runningIndicator, '运行中…');
      expect(l10n.failedStatus, '失败');
      expect(l10n.runningStatus, '运行中');
      expect(l10n.toolFailedStatus, '失败');
      expect(l10n.toolRunningStatus, '运行中');
    });

    test('Tasks strings return Chinese values', () {
      expect(l10n.cronTasks, '定时任务');
      expect(l10n.tasksTitle, '定时任务');
      expect(l10n.newScheduledTask, '新建定时任务');
      expect(l10n.totalTasksHeader(4), '共 4 个任务');
      expect(l10n.noTasks, '暂无任务');
      expect(l10n.noTasksDescription, '创建定时任务，让助手按调度自动执行');
      expect(l10n.createTaskPrompt, '创建定时任务，让助手按调度自动执行');
      expect(l10n.newTask, '新建任务');
      expect(l10n.editTask, '编辑任务');
      expect(l10n.run, '运行');
      expect(l10n.runTask, '运行');
      expect(l10n.resume, '恢复');
      expect(l10n.resumeTask, '恢复');
      expect(l10n.pause, '暂停');
      expect(l10n.pauseTask, '暂停');
      expect(l10n.viewOutput, '查看输出');
      expect(l10n.deleteTask, '删除任务');
      expect(
        l10n.confirmDeleteTaskPrompt('Daily Sync'),
        '确定删除「Daily Sync」？此操作不可撤销。',
      );
      expect(
        l10n.confirmDeleteTask('Daily Sync'),
        '确定删除「Daily Sync」？此操作不可撤销。',
      );
      expect(l10n.taskActions, '任务操作');
      expect(l10n.lastRunTime('10:00'), '上次运行 10:00');
      expect(l10n.taskOutput, '任务输出');
      expect(l10n.closeOutputPanel, '关闭输出面板');
      expect(l10n.noOutput, '暂无输出');
      expect(l10n.outputNumber(1), '输出 1');
      expect(l10n.outputItemTitle(2), '输出 2');
      expect(l10n.taskName, '名称');
      expect(l10n.taskNamePlaceholder, '任务名称（可选）');
      expect(l10n.scheduleExpression, '调度表达式');
      expect(l10n.schedulePlaceholder, '例如 0 9 * * * 或 every 2 hours');
      expect(l10n.promptLabel, '提示词');
      expect(l10n.promptPlaceholder, '定时执行时发送给助手的提示词');
      expect(l10n.pushNotifications, '推送通知');
      expect(l10n.taskStatusRunning, '运行中');
      expect(l10n.taskStatusActive, '正常');
      expect(l10n.taskStatusPaused, '已暂停');
      expect(l10n.taskStatusOff, '已停用');
      expect(l10n.taskStatusError, '出错');
      expect(l10n.taskStatusNeedsAttention, '需关注');
    });

    test('Skills strings return Chinese values', () {
      expect(l10n.skills, '技能');
      expect(l10n.skillsTitle, '技能');
      expect(l10n.refreshSkills, '刷新技能');
      expect(l10n.searchSkills, '搜索技能');
      expect(l10n.noMatchingSkillsFound, '未找到相关技能');
      expect(l10n.noSkills, '暂无技能');
      expect(l10n.serverSkillsWillShowHere, '服务器的技能将显示在这里');
      expect(l10n.disabledBadge, '已禁用');
      expect(l10n.skillDisabledBadge, '已禁用');
      expect(l10n.noMoreSkillDetails, '该技能没有更多详情');
      expect(l10n.noMoreDetailsForSkill, '该技能没有更多详情');
      expect(l10n.pathLabel, '路径');
      expect(l10n.skillPathLabel, '路径');
      expect(l10n.relatedSkillsLabel, '相关技能');
      expect(l10n.skillsGroupBuiltin, '内置技能');
      expect(l10n.skillsGroupProject, '项目技能');
      expect(l10n.skillsGroupGlobal, '全局技能');
      expect(l10n.skillsGroupOther, '其他技能');
    });

    test('Memory strings return Chinese values', () {
      expect(l10n.memory, '记忆');
      expect(l10n.memoryTitle, '记忆');
      expect(l10n.refreshMemory, '刷新记忆');
      expect(l10n.noMemory, '暂无记忆');
      expect(l10n.noMemoryContentYet, '还没有任何记忆内容');
      expect(l10n.projectContext, '项目上下文');
      expect(l10n.projectContextTitle, '项目上下文');
      expect(l10n.memoryNotesTitle, '我的笔记');
      expect(l10n.memoryUserTitle, '用户画像');
      expect(l10n.memorySoulTitle, '智能体灵魂');
      expect(l10n.memoryNotesEmpty, '暂无笔记');
      expect(l10n.memoryUserEmpty, '暂无画像');
      expect(l10n.memorySoulEmpty, '暂无灵魂设定');
      expect(
        l10n.projectContextShadowedWarning,
        '工作区本地文件正在覆盖全局项目上下文。',
      );
    });

    test('Workspace strings return Chinese values', () {
      expect(l10n.files, '文件');
      expect(l10n.workspaceFilesTitle, '工作区文件');
      expect(l10n.refreshFileList, '刷新文件列表');
      expect(l10n.uploadFile, '上传文件');
      expect(l10n.location, '位置');
      expect(l10n.locationLabel, '位置');
      expect(l10n.rootDir, '根目录');
      expect(l10n.rootDirectory, '根目录');
      expect(l10n.parentDir, '上一级');
      expect(l10n.parentDirectory, '上一级');
      expect(l10n.noFiles, '暂无文件');
      expect(l10n.unnamedFile, '未命名');
      expect(l10n.loadingIndicator, '加载中…');
      expect(l10n.download, '下载');
      expect(l10n.deleteFile, '删除文件');
      expect(
        l10n.confirmDeleteFilePrompt('main.dart'),
        '确定要删除「main.dart」吗？此操作不可撤销。',
      );
      expect(
        l10n.confirmDeleteFile('main.dart'),
        '确定要删除「main.dart」吗？此操作不可撤销。',
      );
      expect(l10n.filePickerNotAvailable, '文件选择功能待接入');
      expect(
        l10n.filePickerPendingPlatformSupport,
        '选择本地文件需要平台通道支持（file picker），将在后续版本提供。',
      );
      expect(l10n.fileActions, '文件操作');
    });

    test('Kanban strings return Chinese values', () {
      expect(l10n.kanban, '看板');
      expect(l10n.kanbanTitle, '看板');
      expect(l10n.newCard, '新建卡片');
      expect(l10n.unnamedBoard, '未命名看板');
      expect(l10n.kanbanEmptyContent, '看板暂无内容');
      expect(l10n.clickPlusToCreateFirstCard, '点击右上角 + 创建第一张卡片');
      expect(l10n.noKanbanBoards, '暂无看板');
      expect(l10n.createBoardOnServerPrompt, '在服务器端创建看板后下拉刷新');
      expect(l10n.noCards, '暂无卡片');
      expect(l10n.unnamedCard, '未命名卡片');
      expect(l10n.unassigned, '未指派');
      expect(l10n.parentsDependency(2), '前驱 2');
      expect(l10n.childrenDependency(3), '后继 3');
      expect(l10n.cardDetail, '卡片详情');
      expect(l10n.cardDoesNotExist, '卡片不存在');
      expect(l10n.statusLabel, '状态');
      expect(l10n.assigneeLabel, '负责人');
      expect(l10n.priorityLabel, '优先级');
      expect(l10n.createdAtLabel, '创建时间');
      expect(l10n.updatedAtLabel, '更新时间');
      expect(l10n.changeStatus, '变更状态');
      expect(l10n.commentsHeader(5), '评论（5）');
      expect(l10n.noComments, '暂无评论');
      expect(l10n.addCommentPlaceholder, '添加评论…');
      expect(l10n.sendComment, '发送评论');
      expect(l10n.boardPrefix('Hermex Board'), '看板：Hermex Board');
      expect(l10n.titleLabel, '标题');
      expect(l10n.cardTitlePlaceholder, '卡片标题');
      expect(l10n.cardDescriptionPlaceholder, '卡片描述（可选）');
      expect(l10n.assignProfilePlaceholder, '指派 profile（可选）');
      expect(l10n.initialStatus, '初始状态');
      expect(l10n.kanbanStatusTriage, '待分类');
      expect(l10n.kanbanStatusTodo, '待办');
      expect(l10n.kanbanStatusReady, '就绪');
      expect(l10n.kanbanStatusRunning, '运行中');
      expect(l10n.kanbanStatusBlocked, '受阻');
      expect(l10n.kanbanStatusDone, '完成');
      expect(l10n.kanbanStatusArchived, '已归档');
      expect(l10n.kanbanStatusUnknown, '未知状态');
      expect(l10n.kanbanStatusUnsupported('custom'), '不支持: custom');
    });

    test('Insights strings return Chinese values', () {
      expect(l10n.insightsTitle, '用量统计');
      expect(l10n.refreshInsights, '刷新用量统计');
      expect(l10n.timeframeToday, '今天');
      expect(l10n.timeframeLast7Days, '近 7 天');
      expect(l10n.timeframeLast30Days, '近 30 天');
      expect(l10n.timeframeAll, '全部');
      expect(l10n.recentDaysHeader(7), '最近 7 天');
      expect(l10n.metricSessions, '会话');
      expect(l10n.metricMessages, '消息');
      expect(l10n.metricInputTokens, '输入令牌');
      expect(l10n.metricOutputTokens, '输出令牌');
      expect(l10n.metricTotalTokens, '总令牌');
      expect(l10n.metricEstimatedCost, '估算费用');
      expect(l10n.metricCacheHitRate, '缓存命中率');
      expect(l10n.metricCacheReadTokens, '缓存读取令牌');
      expect(l10n.models, '模型');
      expect(l10n.tokensLast14Days, '近 14 天令牌');
      expect(l10n.activity, '活动');
      expect(l10n.mostActiveDay, '最活跃的一天');
      expect(l10n.peakDaySessions('Monday', 12), 'Monday · 12 个会话');
      expect(l10n.mostActiveHour, '最活跃时段');
      expect(l10n.peakHourSessions('14:00', 8), '14:00 · 8 个会话');
      expect(l10n.insightsSourceFooter(30), '来源：服务器按最近 30 天统计。');
      expect(l10n.noInsights, '暂无统计');
      expect(l10n.insightsWillShowHere, '有对话后这里会显示用量数据。');
      expect(l10n.unknownModel, '未知模型');
      expect(l10n.modelTokensSubtitle('100K'), '100K 令牌');
    });

    test('Git strings return Chinese values', () {
      expect(l10n.gitPanel, 'Git 面板');
      expect(l10n.gitPanelTitle, 'Git 面板');
      expect(l10n.refreshGitStatus, '刷新 Git 状态');
      expect(l10n.notAGitRepo, '不是 Git 仓库');
      expect(
        l10n.notAGitRepoDetail,
        '该工作区不是 git 仓库，无法使用 Git 功能。',
      );
      expect(l10n.stagedSection, '已暂存');
      expect(l10n.unstagedSection, '未暂存');
      expect(l10n.tooManyChangedFilesWarning, '变更文件过多，仅显示前 500 个。');
      expect(l10n.unknownBranch, '未知分支');
      expect(l10n.aheadBehind(2, 1), '领先 2 · 落后 1');
      expect(l10n.syncedWithRemote, '与远程同步');
      expect(l10n.switchBranch, '切换分支');
      expect(l10n.changesLabel, '变更');
      expect(l10n.changesSummary(10, 5, 2), '+10 −5 · 共 2 个文件');
      expect(l10n.commitSection, '提交');
      expect(l10n.commitButton, '提交');
      expect(l10n.commitMessagePlaceholder, '提交信息');
      expect(l10n.remoteOperations, '远程操作');
      expect(l10n.stageAction, '暂存');
      expect(l10n.unstageAction, '取消暂存');
      expect(l10n.discardChanges, '放弃更改');
      expect(l10n.gitChangeAdded, '新增');
      expect(l10n.gitChangeDeleted, '删除');
      expect(l10n.gitChangeRenamed, '重命名');
      expect(l10n.gitChangeConflict, '冲突');
      expect(l10n.gitChangeUntracked, '未跟踪');
      expect(l10n.gitChangeIgnored, '忽略');
      expect(l10n.gitChangeModified, '修改');
      expect(l10n.cannotLoadDiff, '无法加载 diff。');
      expect(l10n.binaryFileCannotShowDiff, '二进制文件，无法显示 diff。');
      expect(l10n.noDiffContent, '无 diff 内容。');
      expect(
        l10n.fileTooLargePartialContent('code snippet'),
        '文件过大，以下为部分内容：\ncode snippet',
      );
      expect(l10n.workspaceClean, '工作区干净');
      expect(l10n.noPendingChanges, '没有待提交的变更。');
    });

    test('Settings & Profile & Project strings return Chinese values', () {
      expect(l10n.settingsTitle, '设置');
      expect(l10n.settings, '设置');
      expect(l10n.appearanceSection, '外观');
      expect(l10n.appearance, '外观');
      expect(l10n.themeLabel, '主题');
      expect(l10n.theme, '主题');
      expect(l10n.themeSystem, '跟随系统');
      expect(l10n.themeLight, '浅色');
      expect(l10n.themeDark, '深色');
      expect(l10n.desktopSection, '桌面');
      expect(l10n.desktop, '桌面');
      expect(l10n.minimizeToTray, '最小化到托盘');
      expect(l10n.minimizeToTraySubtitle, '关闭窗口时隐藏到托盘而非退出');
      expect(l10n.globalShortcuts, '全局快捷键');
      expect(
        l10n.globalShortcutsSubtitle,
        'Ctrl+Shift+H 唤起主窗口，Ctrl+Shift+N 新建会话',
      );
      expect(l10n.rememberWindowPosition, '记住窗口位置');
      expect(l10n.rememberWindowPositionSubtitle, '启动时恢复上次窗口位置与尺寸');
      expect(l10n.serverSection, '服务器');
      expect(l10n.serverSectionDisconnected, '服务器（未连接）');
      expect(l10n.noServerConfigured, '尚未配置服务器');
      expect(
        l10n.noServerConfiguredSubtitle,
        '点击下方「添加服务器」或从引导页配置',
      );
      expect(l10n.addServer, '添加服务器');
      expect(l10n.editServer, '编辑服务器');
      expect(l10n.deleteServer, '删除服务器');
      expect(
        l10n.confirmDeleteServer('Main Server'),
        '确定删除「Main Server」吗？',
      );
      expect(l10n.serverNamePlaceholder, '名称（可选，默认使用主机名）');
      expect(
        l10n.serverPasswordPlaceholder,
        '密码（可选；编辑时留空保持原密码）',
      );
      expect(l10n.loadingModels, '正在加载模型…');
      expect(l10n.modelsLoadFailed, '模型加载失败');
      expect(l10n.defaultModel, '默认模型');
      expect(l10n.notSet, '未设置');
      expect(l10n.reasoningEffort, '推理强度');
      expect(l10n.noAvailableModels, '暂无可用模型');
      expect(l10n.aboutSection, '关于');
      expect(l10n.hermesWebUIClient, 'Hermes WebUI 客户端');
      expect(l10n.version, '版本');
      expect(l10n.profile, 'Profile');
      expect(l10n.notRead, '未读取');
      expect(l10n.readFailed, '读取失败');
      expect(l10n.clickToRetry, '点击重试');
      expect(l10n.selectProfile, '选择 Profile');
      expect(l10n.profileSwitchFailed, 'Profile 切换失败');
      expect(l10n.noProject, '无项目');
      expect(l10n.unnamedProject, '未命名项目');
      expect(l10n.newProject, '新建项目');
      expect(l10n.newProjectEllipsis, '新建项目…');
      expect(l10n.projectNamePlaceholder, '项目名称');
      expect(l10n.projectManagement, '项目管理');
      expect(l10n.renameProject, '重命名项目');
      expect(l10n.deleteProject, '删除项目');
      expect(
        l10n.deleteProjectWarning,
        '删除后项目内会话不会被删除，仅解除归类。',
      );
    });
  });

  group('AppLocalizations (en locale)', () {
    const l10n = AppLocalizations(Locale('en'));

    test('isEnglish is true', () {
      expect(l10n.isEnglish, isTrue);
    });

    test('Common strings return English values', () {
      expect(l10n.ok, 'OK');
      expect(l10n.cancel, 'Cancel');
      expect(l10n.save, 'Save');
      expect(l10n.create, 'Create');
      expect(l10n.delete, 'Delete');
      expect(l10n.edit, 'Edit');
      expect(l10n.close, 'Close');
      expect(l10n.retry, 'Retry');
      expect(l10n.loading, 'Loading…');
      expect(l10n.export, 'Export');
      expect(l10n.rename, 'Rename');
      expect(l10n.notice, 'Notice');
      expect(l10n.unknown, 'Unknown');
      expect(l10n.unnamed, 'Unnamed');
      expect(l10n.unknownError, 'Unknown error');
      expect(l10n.loadFailed, 'Failed to load');
      expect(l10n.loadFailedRetry, 'Loading failed, please retry');
      expect(l10n.actionFailed, 'Action Failed');
      expect(l10n.dismissNotice, 'Dismiss notice');
      expect(l10n.dismissError, 'Dismiss error');
      expect(l10n.offlineCache, 'Offline cache');
      expect(l10n.all, 'All');
      expect(l10n.name, 'Name');
      expect(l10n.value, 'Value');
      expect(l10n.info, 'Info');
      expect(l10n.description, 'Description');
      expect(l10n.noDescription, 'No description');
      expect(l10n.copiedToClipboard, 'Copied to clipboard');
    });

    test('Parameterized methods work in English', () {
      expect(l10n.selectedCount(4), 'Selected 4');
      expect(l10n.exportSuccess('Markdown'), 'Markdown exported successfully');
      expect(
        l10n.confirmDeleteSession('My Chat'),
        'Are you sure you want to delete "My Chat"? This action cannot be undone.',
      );
      expect(
        l10n.confirmBatchDeletePrompt(3),
        'Delete selected 3 sessions? This action cannot be undone.',
      );
      expect(l10n.totalTasksHeader(5), '5 tasks in total');
      expect(
        l10n.confirmDeleteTask('Sync Job'),
        'Are you sure you want to delete "Sync Job"? This action cannot be undone.',
      );
      expect(l10n.parentsDependency(2), 'Parents 2');
      expect(l10n.childrenDependency(3), 'Children 3');
      expect(l10n.commentsHeader(7), 'Comments (7)');
      expect(l10n.recentDaysHeader(14), 'Last 14 Days');
      expect(l10n.peakDaySessions('Monday', 8), 'Monday · 8 sessions');
      expect(l10n.peakHourSessions('15:00', 4), '15:00 · 4 sessions');
      expect(
        l10n.insightsSourceFooter(7),
        'Source: Server statistics over the last 7 days.',
      );
      expect(l10n.aheadBehind(3, 2), 'ahead 3 · behind 2');
      expect(
        l10n.changesSummary(20, 10, 3),
        '+20 −10 · 3 files in total',
      );
      expect(
        l10n.confirmDeleteServer('Alpha Server'),
        'Are you sure you want to delete "Alpha Server"?',
      );
    });
  });

  group('AppLocalizationsDelegate', () {
    const delegate = AppLocalizationsDelegate();

    test('isSupported checks supported locales', () {
      expect(delegate.isSupported(const Locale('zh')), isTrue);
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('fr')), isFalse);
    });

    test('load returns AppLocalizations instance', () async {
      final l10nZh = await delegate.load(const Locale('zh'));
      expect(l10nZh.isEnglish, isFalse);

      final l10nEn = await delegate.load(const Locale('en'));
      expect(l10nEn.isEnglish, isTrue);
    });

    test('shouldReload is false', () {
      expect(delegate.shouldReload(delegate), isFalse);
    });
  });

  group('AppLocalizations.of widget test', () {
    testWidgets('reads correct locale from BuildContext', (tester) async {
      AppLocalizations? foundL10n;

      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: const [
            AppLocalizationsDelegate(),
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                foundL10n = AppLocalizations.of(context);
                return Text(foundL10n!.ok);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(foundL10n, isNotNull);
      expect(foundL10n!.isEnglish, isTrue);
      expect(foundL10n!.ok, 'OK');
      expect(find.text('OK'), findsOneWidget);
    });
  });
}
