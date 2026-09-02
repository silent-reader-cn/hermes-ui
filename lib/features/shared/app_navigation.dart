import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/adaptive_shell.dart';

/// 窄屏 push / 宽屏 go 的统一导航（todo：#51 全项目返回动画对齐）。
///
/// 会话列表 ⇄ 顶层功能页（技能/定时任务/设置/记忆/看板/统计/下载等）的入口，
/// 窄屏（< kAdaptiveBreakpoint，手机单栈）必须 `push` 真入栈——返回时
/// `AppBackButton` 走 `pop()` 反向（当前页向右滑出、底层列表原地），
/// 而不是 `go()` 兜底把列表当新路由正向盖上来。
///
/// 宽屏（>= kAdaptiveBreakpoint，桌面双栏）保持 `go` 替换：右侧切页不破坏
/// 左侧侧栏选中态，返回也无 push/pop 栈深度累积。
void openAdaptiveRoute(BuildContext context, String path) {
  final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  if (isWide) {
    context.go(path);
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
