# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建），标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### #1 [P0] 聊天媒体预览、附件下载队列与完成通知
- 类型：问题 + 功能
- 位置：
  - 图片渲染与附件 Lightbox：`lib/features/chat/widgets/chat_media_view.dart:21-558`；聊天附件芯片：`chat_media_view.dart:695-825`
  - 媒体缓存：`lib/core/cache/media_cache_service.dart:36-325`
  - 附件模型：`lib/core/models/message_attachment.dart:8-333`
  - 通知服务：`lib/features/notifications/turn_notification_service.dart:8-408`
  - 顶层路由与侧栏入口：`lib/app/router.dart`、`lib/app/shell/sidebar_utility_toolbar.dart`
- 范围：Android + Windows 优先；聊天中用户发送的图片、Agent 返回的图片/任意附件均纳入。已有会话工作区下载逻辑不改语义。
- 复现/背景：
  1. 用户聊天框中的图片点击后只显示图片图标，无法加载或查看原图。
  2. Agent 发送的附件（例如 APK）当前仅落应用媒体缓存，用户看不到保存位置；没有文件信息确认、下载记录、队列进度或下载完成通知。
- 现状：
  - `ChatInlineMediaWidget` 通过 `mediaFileProvider` 拉取图片，失败时统一回退 `_ImageErrorPlaceholder`，没有可见失败原因、重试或原图下载动作。
  - `AttachmentLightbox` 的非图片 `_AttachmentDownloadButton` 仅调用 `mediaFileProvider` 写入应用私有缓存，状态只存 widget 内存，未保存至公共 Downloads，重启后没有记录。
  - 当前通知基础设施仅支持回合/澄清/异常三类，没有下载完成通道；也没有下载任务模型、持久化列表或页面。
- 已确认产品决策：
  1. 保存位置：Android 写公共 Downloads；Windows 写用户 Downloads。文件名冲突自动生成不覆盖的新名称。
  2. 入口：新增独立“下载”页面；宽屏加入侧栏工具区，窄屏加入导航下拉。
  3. 图片失败：显示“图片加载失败”卡片，提供“重新加载”和“下载原图”；下载仍失败必须展示可读错误。
  4. 确认规则：聊天图片和 Agent 附件首次下载均弹 Cupertino 确认框；已完成同一文件直接打开，不重复确认。
  5. 任务能力：第一版支持单任务与 FIFO 队列、实时进度、取消、失败重试、完成记录；不承诺后台持续下载/暂停恢复。
  6. 完成反馈：下载完成发送系统通知；前台同时显示应用内提示。点击通知进入下载页面；已完成记录可打开文件、重新下载、删除记录。
- 实现方向：
  - 新建 `features/downloads/`：任务模型、持久化仓库、Riverpod controller、DownloadPage、保存平台服务；以 authenticated `ApiClient.downloadData` 为唯一远程字节入口，不能复用仅用于缓存的 media 文件作为“已下载”。
  - 引入跨平台保存实现，Android 使用公共 Downloads 目录，Windows 使用用户 Downloads；下载确认弹窗先展示文件名、推断类型、已知字节数或“未知大小”、来源会话。
  - 扩展通知抽象，以独立 downloads 通道与稳定任务 ID 通知完成/失败；点击 payload 路由 `/downloads`。
  - 图片 URL 解析/加载失败必须保留失败原因供诊断；重试必须失效当前 provider/缓存条目后重新请求，不将“本地文件不存在”误判为成功。
  - 下载列表状态：queued/downloading/completed/failed/cancelled；持久化完成、失败与取消条目；下载中任务仅内存，应用终止后标为失败并可重试。
- 验收：
  1. 用户/Agent 图片成功显示且点击全屏缩放；无法显示时出现失败卡片，重试与下载原图均可触发真实下载路径。
  2. APK/PDF/压缩包等附件点击显示确认框，含文件名、类型、文件大小（服务端未知时明确写未知），确认后进入下载队列。
  3. Android/Windows 成功文件出现在各自用户 Downloads 目录，名称冲突不会覆盖；下载列表可见正确状态、大小、时间与进度。
  4. 成功、失败、取消、重试均有 widget/单测；下载完成触发应用内提示与系统通知，点击通知进入 `/downloads`。
  5. 深浅色、窄屏/宽屏无溢出；`flutter analyze` 零告警、`flutter test` 全绿、Android debug APK 构建成功。
- 状态：已确认，待实现。
