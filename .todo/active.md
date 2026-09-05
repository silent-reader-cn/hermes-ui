# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。
> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
> 3. 本文件只保留未收口任务，收口即清出。

---

（空——#56-#63 已全部收口誊写至 `.todo/20260905.md`，待新任务）

---

### #65 [P1→已修复待真机复验] 下载中心「打开」Android 必炸：裸 file:// URI 被 StrictMode 拦截
- 位置：`lib/features/downloads/download_page.dart` `openDownloadedFile` Android 分支（原 :79 `data: file://$path`）
- 复现：下载任一文件（png/apk）→ 下载页点「打开」→ 弹「无法打开文件 PlatformException(error, file:///storage/emulated/0/Download/... exposed beyond app through Intent.getData())」
- 现状 vs 预期：Android 7+ 禁止 file:// URI 跨应用共享（FileUriExposedException 包装成 PlatformException）；预期走 FileProvider content:// URI 正常打开
- 修复：MainActivity.kt 注册 MethodChannel `com.silentreader.hermes_ui/file_share`（getShareUri → FileProvider.getUriForFile，authority `<appId>.provider` 复用既有 provider_paths.xml external-path）；Dart 侧 `_androidContentUriFor` 换取 content:// 后再发 ACTION_VIEW，通道失败兜底回 file://；build.gradle.kts 补 `androidx.core:core-ktx:1.13.1`
- 验收：真机下载 png/apk 点「打开」→ 系统应用正常接管；Windows 行为不变（explorer /select）

---

### #66 [P1→已修复待真机复验] 图片预览双指缩放被困小图区域，无法铺满全屏
- 位置：`lib/features/chat/widgets/chat_media_view.dart` AttachmentLightbox 图片分支（原 `Center > InteractiveViewer > Image(contain)`）+ `lib/features/workspace_manager/file_preview_page.dart` 图片 sliver 同款结构
- 复现：打开一张小于屏幕的图片（如 100×100 于 1000×1000 屏）→ 双指放大 → 内容放大了但仍被限制在初始小框内，四周黑边不利用全屏
- 根因（探针实锤）：InteractiveViewer 的 ClipRect 采用自身盒子尺寸；Center 给松约束时其盒子收缩为子图自然尺寸（探针测得 viewerSize=0×476 于 1x1 图），放大内容被裁回小框
- 修复：两处改 `SizedBox.expand` 紧约束钉满视口（Lightbox=Expanded+SizedBox.expand；工作区=SliverFillRemaining(hasScrollBody:false)+SizedBox.expand），子 Image 均 BoxFit.contain 初始仍 contain 铺满
- 验收：小图打开后双指放大可铺满全屏并可平移；大图行为不变；回归断言 viewerSize.width==800 已入 chat_media_bubble_test + file_preview_page_test（stash RED 校验通过）

---


---

---


---

