/// Android 系统返回「页面级拦截器」注册表（LIFO）。
///
/// 背景：AdaptiveShell 的 PopScope 在 Android 上接管全部系统返回
/// （root navigator 单页 + `canPop: !isAndroid`），页面内部再包 PopScope
/// 收不到事件，且 shell 第 2 步 `Navigator.pop` 直接 pop 绕过 PopScope。
/// 因此 shell 在「弹层关闭」与「Navigator pop」之间插入本注册表询问点，
/// 让具备子级导航状态的页面（如工作区文件浏览非根目录 → 上一级目录）
/// 优先消费返回事件。
///
/// 用法：页面在 `initState` 注册处理器、`dispose` 注销；处理器返回 true
/// 表示已消费本次返回（shell 终止后续分流），false 表示放行。
/// 处理器内部应自行校验「本页面是否为当前顶层路由」
/// （`ModalRoute.of(context)?.isCurrent`），避免文件预览页/弹窗覆盖在
/// 上层时误消费返回。
abstract final class AndroidBackInterceptorRegistry {
  static final List<bool Function()> _handlers = <bool Function()>[];

  /// 注册处理器（页面 initState 时调用）。
  static void register(bool Function() handler) => _handlers.add(handler);

  /// 注销处理器（页面 dispose 时调用；未注册时静默忽略）。
  static void unregister(bool Function() handler) {
    _handlers.remove(handler);
  }

  /// 依次询问处理器（后注册者优先）；任一返回 true 即消费本次返回。
  static bool handle() {
    for (final handler in List.of(_handlers).reversed) {
      if (handler()) return true;
    }
    return false;
  }

  /// 测试辅助：清空全部处理器。
  static void debugReset() => _handlers.clear();
}
