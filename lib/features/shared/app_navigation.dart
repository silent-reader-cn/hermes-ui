import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/adaptive_shell.dart';

/// 全平台（窄屏/宽屏）顶层功能页入口统一 push 积累栈（#77）。
///
/// 会话列表 ⇄ 顶层功能页（技能/定时任务/设置/记忆/看板/统计/下载等）的入口：
/// 全平台均通过 `push` 积累栈深度（#77：宽屏右侧面板 push 累积，返回按钮
/// `AppBackButton` 可逐级 `pop()` 回退，唯点击具体聊天会话时通过 `go` 清栈）；
/// 窄屏下返回时同样走 `pop()` 反向动画露出底层列表。
void openAdaptiveRoute(BuildContext context, String path) {
  final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  if (isWide) {
    unawaited(context.push(path));
  } else {
    unawaited(context.push(path));
  }
}

/// 窄屏 pop / 宽屏 go 回主页（todo：#51 返回动画对齐——归档等「离开当前页」
/// 场景）。窄屏若当前页是真入栈（`canPop`）则 `pop` 反向滑出露出列表；深链
/// 直进（无栈）或宽屏双栏则 `go('/')` 替换。
void leaveToRoot(BuildContext context) {
  final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  if (!isWide && context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}
