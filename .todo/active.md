# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

### #53 [P1] 聊天附件 + 工作区文件下载：统一接入下载中心（补齐断链，非新建）

**一句话**：下载中心（队列/落盘/`/downloads` 页/入口/完成通知）早在 9-01 已合入 main（`f0990b7` UI 层 + `60e3427` 核心层），但三个入口没接上它——聊天图片预览无下载按钮、非图片附件 URL 无效时按钮禁用「点了没反应」、工作区下载是「拉字节直接丢」的假下载。本条把这些入口统一接入下载中心。

**交互拍板（主人 2026-09-04）**：
- 图片附件：点击 → 预览（Lightbox）→ **图片下方一个下载按钮**。
- 非图片附件：点击 → 预览弹层 → 下载按钮；**下载前必须弹确认框**（展示 文件名/类型/大小/来源会话）。
- 工作区文件/文件夹：下载前 **同样弹确认框**（理由：「用户的流量是宝贵的」）。
- 即：**确认弹窗全部保留**（推翻柚子此前「去掉弹窗」推荐）。

**范围（分区）**：
- 区 A 聊天附件预览 `lib/features/chat/widgets/chat_media_view.dart`
- 区 B 下载中心核心 `lib/features/downloads/download_controller.dart` + `download_models.dart`（enqueue 双模式扩展）
- 区 C 工作区下载 `lib/features/workspace/workspace_providers.dart` + `lib/features/workspace_manager/file_preview_page.dart`
- 区 D Android 落盘兜底 `lib/features/downloads/download_save_service.dart`

---

#### 区 A：聊天附件

**A-1 图片附件（现状：预览完全无下载按钮）**
- 位置：`AttachmentLightbox.build` 图片分支 `chat_media_view.dart:418-455`（当前 = `Center→InteractiveViewer→viewerContent`，整页唯一可点是 navigationBar 的 ✕ :421）。
- 复现：聊天里发/收一张图片 → 点缩略图 → 进入全屏预览 → **上下左右没有任何「下载」入口**。
- 现状 vs 预期：现状图片只能缩放；预期在图片**下方**加下载按钮，复用文档分支已有的 `_AttachmentDownloadButton`（:542）状态机（未下载→确认框→入队→下载中 spinner→已完成「打开文件」→失败「重试」）。确认框走既有 `showDownloadConfirmationDialog`（:280），点击入队 `downloadControllerProvider.enqueue`（:710）。
- 关键坑：`_AttachmentDownloadButton.isLocalAvailable`（:571）当前把 `bytes != null`（含 data URI 解码出的内存字节）直接判成「已下载」→ 按钮变「已下载」但**从未真正落盘**。需改为：内存字节 / data URI 走区 B 的 bytes 入队模式落盘后才算已下载；仅 `File(url).existsSync()`（本地路径型）才直接「打开文件」。

**A-2 非图片附件（现状：有按钮但常禁用「点了没反应」）**
- 位置：文档分支 `_AttachmentDownloadButton`（:497 挂载），禁用源 `:683 onPressed: url != null ? ... : null`。
- 复现：聊天里的 .zip/.pdf/文档芯片 → 点击 → 弹层 → 下载按钮灰着（`resolvedUrl` 经 `ChatMediaResolver.resolveMediaUrl` 拼不出 http 地址时 url 为空）。
- 预期：url 无法解析时按钮**不得静默禁用**——给出可见反馈（置灰 + 「无法从此来源下载」提示，或用附件原始引用兜底解析）。数据字段已够用：`MessageAttachment`（`lib/core/models/message_attachment.dart`）含 name/path/mime/size，确认框与入队都能填全。

---

#### 区 B：下载中心 enqueue 扩展（支撑区 A/C 的两类来源）

现状：`DownloadController.enqueue`（`download_controller.dart:146`）只接受 `sourceUrl`，`_processQueue`（:328-340）硬编码 `bytes = await _downloader(uri)`（走 `apiClient.downloadData`，同域自动带 cookie/autoReauth）。缺两类能力：
- **B-1 bytes 模式**：内存字节（data URI、已解码图）直接落盘，`_downloader` 跳过网络。`DownloadTask`（`download_models.dart`）需新增来源类型（url/bytes）；bytes 不入 Drift（体积大），重启后按「记录仍在、文件已删→可重下」的现有降级处理即可，具体在实现时对齐现有 completed 判定（:771 `savedPath` + `File.existsSync`）。
- **B-2 进度回调**：`DownloadTask.receivedBytes` 字段存在但 worker 整段拉完才置 completed，进度恒 0→full。工作区/大图下载需要真实进度（`CupertinoProgressBar` 已在 `download_page.dart:157`）。`downloadData` 目前一次性返回 `Uint8List`，接入流式写入或分块回调（列 P2 可分期，不阻塞主链接线）。

> 去重契约不变：同 `sourceUrl` 已完成且文件仍在 → 返回旧 ID；活跃同 URL → 合并（:146-230）。bytes 模式无 URL，按 fileName 去重或直接新建（实现时定）。

---

#### 区 C：工作区下载（现状：假下载，字节直接丢弃）

**C-1 文件列表下载**
- 位置：`WorkspaceController.download`（`workspace_providers.dart:292`）：`downloadFile()` 拉回 `bytes` 后 **只弹 notice「已下载 N 字节，保存到本地待平台通道接入」**，bytes 随即丢弃，从不落盘、从不进下载中心。文件夹 `downloadFolder`（:324）同病（`/api/folder/download` 打包 zip 字节丢弃）。
- 预期：`download`/`downloadFolder` 改为——先弹 `showDownloadConfirmationDialog`（文件名/类型/大小/来源=会话工作区+path）→ 确认后 `enqueue`（用 `/api/file/raw?session_id=&path=` 或 `/api/folder/download` 构造同域 GET URL 让下载中心拉，**不再在 controller 内先 `_api.downloadFile` 拉一遍**——原代码拉了又丢是纯浪费流量，改成入队后只拉一次）。
- 触发点保持：`workspace_page.dart:360 _onDownload` → provider；文件夹 `:173 onDownloadFolder`。

**C-2 预览页下载**
- 位置：`FilePreviewPage._onDownload`（`file_preview_page.dart:678`）：同样是 `_api.downloadFile` → 丢弃 → `_showInfoDialog「待平台通道接入」`。入口 = AppBar `_DownloadButton`（:351）+ 兜底视图按钮（:612/:667）。
- 预期：同 C-1，改确认框 + 入队下载中心，删掉「待平台通道接入」文案。音视频预览页本身为播放已下载字节到临时文件，与「下载保存」是两条路，下载按钮统一走队列即可。

---

#### 区 D：Android 落盘风险（接线后必查，否则=第二个假成功）

- 位置：`download_save_service.dart:88-115` Android 分支：写公共 `/storage/emulated/0/Download` 前先探活写删，失败即**显式抛 `DownloadSaveException`（诚实但会失败）**。
- 风险：Android 11+（本项目 targetSdk 37）Scoped Storage 下，普通 App 直接往公共 Download 目录写文件**大概率被拒** → 接线到区 A/C 后，Windows 桌面能落盘、**Android 可能全部报错**。
- 预期：实机验证；若被拒 → 改走 SAF（`file_picker`/`share_plus` 存到用户选定位置）或 MediaStore Downloads 接口（`device_info`/原生通道）。具体方案实现时先实机探活再定，验收必须含 Android 真机「点下载→文件真的出现在系统 Download 目录且能打开」，不接受仅弹窗提示。

---

**验收口径**：
1. `C:/tmp/f.bat analyze` 零告警 + `C:/tmp/f.bat test` 全绿（现有 downloads 相关测试：`test/features/downloads/*` 4 文件 + `chat_media_bubble_test.dart`，需为新增按钮/入队断言补测；工作区 `workspace`/`file_preview` 相关测试改「假下载文案」断言）。
2. 金照 `--update-goldens`（预览页/工作区新增下载按钮可能改变既有金照）。
3. 手动/实机：①聊天图片预览→下方下载→确认框→`/downloads` 见进度→完成→文件在系统 Downloads 目录可打开；②聊天非图片附件同上；③工作区文件 + 文件夹 zip + 预览页下载三处均入同一下载中心；④Windows 与 **Android 真机各验一次落盘**（区 D 关键）。
4. 「点了没反应」两类（图片无按钮 / url 无效禁用）均消除。

**提交拆分建议**：区 B（核心扩展）先行 → 区 A（聊天 UI）→ 区 C（工作区接线）→ 区 D（Android 落盘，可能独立一轮）；每层自洽过测后分开 commit（`feat(downloads)` / `fix(chat)` / `feat(workspace)` scope 对齐本条）。

**备注**：同根因并一条（下载中心已存在但入口未接 + 工作区假下载），勿拆成多个 issue 重复描述。区 B-2 流式进度可 P2 分期，不阻塞 A/C 主链接线。

---
