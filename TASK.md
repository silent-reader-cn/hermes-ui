# TASK: 聊天输入栏两段式 composer（自适应增高 + 工具行）

## 背景

聊天输入框目前只有一行（`CupertinoTextField` 默认 maxLines:1），输入长文本体验差。
直接加高会暴露问题：左右按钮（附件/收藏/发送/圆环）与单行文本同行，多行后按钮上方空旷。

方案已与主人定稿：**ChatGPT 式两段式 composer**——文本区在上、工具按钮行在下，
文本区自适应增高（有上限、超限内部滚动），工具行永远一行高，彻底消除空旷感。

## 硬性约束（必读）

- 项目根的 `AGENTS.md` 是执行契约，先读再动手。
- Cupertino-only UI（禁 Material 组件）；Riverpod；手写容错 fromJson。
- 验收硬门槛：`flutter analyze` 零告警 + `flutter test` 全绿。
  **Windows 下 flutter 必须走 `C:/tmp/f.bat`**（HOME/PATH 特殊 + pub.flutter-io.cn 镜像）：
  - `C:/tmp/f.bat analyze`
  - `C:/tmp/f.bat test`
- 金照若因本改动失败：`C:/tmp/f.bat test test/golden/golden_screens_test.dart --update-goldens` 更新基准。
- **禁止 git commit / push**——只改工作区，提交由 Leader 统一处理。
- 只动下述「允许触碰」的文件；不要顺手重构无关代码。
- 暗黑模式铁律：业务层自绘背景盒里的裸 `CupertinoDynamicColor` 必须 `.resolveFrom(context)`；
  内联 `TextStyle(color: 动态色)` 同样必须 resolveFrom（否则暗黑模式画浅色变体）。

## 允许触碰的文件

- `lib/features/chat/widgets/chat_input_bar.dart`（主要改造对象）
- 新增：`lib/features/chat/widgets/chat_input_bar_test.dart` 或
  `test/features/chat/chat_input_bar_composer_test.dart`（widget 测试）
- 金照基准 PNG（仅当 analyze+test 全绿后确需更新）
- 其余文件一律不动。

## 规格细节

### 布局（chat_input_bar.dart build 方法，约 L423-L587）

现状：单个 `Row(crossAxisAlignment: end)` = [加号, 收藏, Expanded(TextField), steer, 停止/发送, 圆环]。

改为：

```
Container(同现有 border-top 装饰)
 └ SafeArea(top:false)
    └ Column(mainAxisSize.min)
       ├ CupertinoTextField(minLines:2, maxLines:8)   ← 文本区，撑满宽度
       ├ SizedBox(height:6)
       └ Row(工具行，crossAxisAlignment:center)
          ├ 加号按钮（原样搬入）
          ├ 收藏按钮（_bookmarkKey 容器原样搬入）
          ├ Spacer()
          ├ steer 按钮（流式时）
          ├ 停止按钮（流式时）
          ├ 发送按钮（原逻辑：!isSending 时显示）
          └ 圆环 ContextWindowIndicator（_contextIndicatorKey 容器原样搬入）
```

要点：
- TextField 参数：`minLines: 2, maxLines: 8`（自动增高到 8 行封顶后内部滚动）；
  `keyboardType: TextInputType.multiline`；保留 controller/placeholder/enabled/
  contextMenuBuilder/onChanged 全部现有逻辑不动。
- **回车语义**：桌面（非移动端）Enter=发送、Shift+Enter=换行。实现方式自选其一并写注释说明：
  a) `Shortcuts` 里映射 `SingleActivator(LogicalKeyboardKey.enter)` → 自定义 SendIntent
     （注意 Shift 变体不拦截，让其默认插入换行）；
  b) 或 `onSubmitted` 配合 `textInputAction: TextInputAction.newline` + 硬件键监听。
  手机端保持 Enter=换行、按钮发送（用 `kIsWeb`/平台判断或 `defaultTargetPlatform` 分流均可）。
  注意现有 Ctrl+V / Cmd+V 粘贴 Shortcuts 必须继续生效（新 Shortcuts map 要合并旧条目）。
- 工具行内按钮尺寸/颜色/key 全部保持现状（`chat-attach-button` 等 ValueKey 不许改，
  测试和金照依赖它们）。图标 22px 不变。
- `SelectionChipPanel` 与 `AttachmentPendingBar` 在 Container 之外的位置保持不变。
- 删除原 `Row(crossAxisAlignment: end)` 外壳，避免残留死代码。

### 测试要求（新增 widget 测试文件）

至少覆盖：
1. 输入多行长文本（含 `\n`）时 TextField 可见高度增长且 ≤ 上限（ pump 后断言 size.height 变化合理区间）。
2. Enter 键在桌面平台触发发送（注入 fake chat controller 或验证 `_submit` 效果：
   输入文字 → sendRaw/调用计数），Shift+Enter 不发送而是换行（controller.text 含 '\n'）。
3. 现有按钮 key 全部仍可找到（chat-attach-button / chat-saved-prompts-button /
   chat-send-button / chat-input-field）。
4. 流式状态（phase=streaming）时工具行出现 steer+停止按钮。

参考现有测试写法：`test/features/chat/` 下已有 widget 测试（fake api 注入模式见
`test/helpers/fake_chat_api.dart`；媒体相关测试需要 InMemorySecureStorage +
connectionStoreProvider.overrideWithValue，本任务不涉及媒体可不注入）。

## 验收清单

- [ ] `C:/tmp/f.bat analyze` 零告警
- [ ] `C:/tmp/f.bat test` 全绿（~1082+）
- [ ] 新增 composer widget 测试全过
- [ ] 金照如失败已按上述命令更新并在汇报中注明
- [ ] 无 commit、无越界文件改动
- [ ] `git status --short` 干净列出改动文件清单写入汇报

## 汇报格式

完成后输出：改动文件列表 + analyze/test 结果摘要 + 回车语义实现方式一句话说明 + 遗留风险。
