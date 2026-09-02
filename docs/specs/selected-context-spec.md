# 选中上下文渲染与交互 + 复制提示优化 规格

> 版本：v1.0 — 2026-08-22
> 模型：`gemini-3.8-flash-high`（固定，不可换）
> 蓝本：`D:\hermes-webui\static\messages.js` / `D:\hermes-webui\static\ui.js` / `D:\hermes-webui\static\style.css` / `lib/features/chat/widgets/injected_notice_card.dart` / `lib/features/chat/widgets/message_bubble.dart` / `lib/features/chat/widgets/chat_media_parser.dart` / `lib/features/chat/widgets/markdown_styles.dart` / `lib/features/chat/widgets/chat_message_list.dart` / `lib/features/chat/widgets/chat_input_bar.dart` / `lib/features/chat/chat_page.dart` / `lib/features/chat/chat_controller.dart`
> 用途：后续编码子代理按本文直接实现 `SelectedContext*` 解析/渲染与 composer 待发区及复制提示优化，不再重读 WebUI 源码。关键结论均带源码行号。

---

## 1. 背景与目标

WebUI 的「选中回复（Reply with selection）」允许用户在聊天区域选中任意文本，点击浮动按钮后把选中内容作为「具名上下文块」暂存到 composer 待发区，支持多选、重命名，发送时按固定格式串入 `POST /api/chat/start` 的 `message` 字段；历史消息中该格式被再次解析，渲染为「引用卡片」而非裸 Markdown。

Flutter 端现状：
- `ChatMessageBubble._UserContent` 仅处理 `MEDIA:`/`file://` 媒体标记与附件条，未处理选中上下文块（`message_bubble.dart:166-218`）。
- `chat_media_parser.dart` 已有「围栏保护→标记替换→还原」三段式解析范式，可复用。
- `InjectedNoticeCard` 已对齐 WebUI `style.css:2330` 的 `process-notice-*` 视觉（圆角 8、边框 `separator`、次要背景、头行图标+标题+Toggle），为本次 `SelectedContextCard` 提供参照（`injected_notice_card.dart:8-14`）。
- `chat_page.dart:_NoticeBanner`（`chat_page.dart:781-824`）与 `chat_controller.dart:setNotice`（`chat_controller.dart:2023-2024`）为常驻横幅，需优化为自动消失。

本规格一次性定义四件事：
1. WebUI 选中上下文的完整传输形态与解析正则（含边界）。
2. Flutter 端 `SelectedContext*` 解析与渲染规格。
3. Composer 待发区 `PendingSelection` + `SelectionChips` 规格。
4. 复制提示（`copiedToClipboardNotice`）的轻量自动消失横幅规格。

---

## 2. WebUI 选中上下文：传输形态与源码取证

### 2.1 待发区数据结构 `_pendingSelections`

```js
// messages.js:170
let _pendingSelections = []; // [{id, name, text}] — named context blocks
let _selectionIdCounter = 0; // messages.js:171
```

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `string` | `ctx-<递增整数>`，`_selectionIdCounter` 自增，清空时归零（`messages.js:904,913,918`） | 芯片 `data-selection-id` 与重命名/移除的键 |
| `name` | `string` | 默认 `Context <counter>`（`messages.js:905`，经 `_selectedTextReplyT('context_block_name_default','Context')` 本地化），重命名后 `trim` 并 `slice(0,120)`（`messages.js:1017`），空输入回退到原名 | 显示为 `**name:**` 的 label，1-200 字符校验在解析侧（见 2.4），输入侧上限 120 |
| `text` | `string` | 选中原文，未截断；预览时才 360 截断（`messages.js:930`） | 预览 `title` 保留全量，`textContent` 为截断版（`messages.js:978-979`） |

- 新增：`_addNamedContextBlock(text)` → `push({id, name, text})` → `_renderSelectionChips()`（`messages.js:903-908`）。
- 移除：`_removeNamedContextBlock(id)` → `filter` → 归零计数器 → `_renderSelectionChips()`（`messages.js:911-914`）。
- 清空：`_clearPendingSelections()` → 归零 → 清空数组 → `_renderSelectionChips()`（`messages.js:917-923`），同时暴露 `window._clearPendingSelections`。
- 存在性谓词：`window._hasPendingSelections = () => _pendingSelections.length>0`（`messages.js:176`），供 `ui.js` 的 `_composerHasContent` 判断「仅含选中块也算可发送」。

### 2.2 引用格式化 `_formatSelectedTextReplyQuote`

```js
// messages.js:791-794
function _formatSelectedTextReplyQuote(text){
  const normalized = String(text||'').replace(/\r\n?/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
  if(!normalized) return '';
  return `<!-- hermes-selected-context -->\n${normalized.split('\n').map(line=>`> ${line}`).join('\n')}`;
}
```

要点（Flutter 必须 1:1 对齐）：
- 归一化：`\r\n`/`\r` → `\n`，连续 3+ 空行压缩为 `\n\n`，首尾 `trim`。
- 空归一化返回 `''`（上层应跳过该块，避免产生空引用卡片）。
- 每行前缀 `> `（含空行也会变成 `> `），这是后续解析的锚点。
- 该函数**不含** label 行，label 由 `_composerTextWithPendingSelections` 另起一行拼接。

### 2.3 发送时组装 `_composerTextWithPendingSelections`

```js
// messages.js:1023-1028
function _composerTextWithPendingSelections(){
  const composer = $('msg');
  const current = String(composer && composer.value || '');
  if(!_pendingSelections.length) return current;
  const blocks = _pendingSelections.map(s=>`**${s.name}:**\n${_formatSelectedTextReplyQuote(s.text)}`).join('\n\n');
  return current.trim() ? `${current.replace(/\s+$/,'')}\n\n${blocks}\n\n` : `${blocks}\n\n`;
}
```

单块形态（`blocks` 中每一块）：

```
**<LABEL>:**\n<!-- hermes-selected-context -->\n> <quote line 1>\n> <quote line 2>\n...
```

多块以 `\n\n` 拼接（`join('\n\n')`）。若用户另有正文 `current`，则为 `current + \n\n + blocks + \n\n`（尾部固定双换行，便于后续解析以空行/下一 label 为边界）。

实际发送路径（`messages.js:1307,1327,1570`）在 `send()` 决策中取 `_composerTextWithPendingSelections().trim()` 作为 `messageForAPI`，并校验 `_pendingSelections.length` 作为可发送条件之一。

> **字段映射总表**

| WebUI 符号 | 位置 | Flutter 对应 | 说明 |
|---|---|---|---|
| `_pendingSelections[i].id` | `messages.js:170` | `PendingSelection.id` | `ctx-N` |
| `_pendingSelections[i].name` | `messages.js:905,1017` | `PendingSelection.name` | label，输入上限 120，解析上限 200 |
| `_pendingSelections[i].text` | `messages.js:906` | `PendingSelection.text` | 选中原文，全量 |
| `<!-- hermes-selected-context -->` | `messages.js:794, ui.js:322` | 同字符串常量 `kSelectedContextMarker` | 块的唯一合法性锚点，无此行不算选中块 |
| `**LABEL:**` | `messages.js:1027, ui.js:325` | `**<label>:**` | label 行，1-200 字符，首尾允许空白 |
| `> ...` | `messages.js:794, ui.js:331-332` | 引用行 | `> ` 或 `>` 前缀，剥离后为 quote |

### 2.4 行级解析规格 `stashSelectedContextBlocks`

源码：`ui.js:320-339`（`_renderUserFencedBlocks` 内部）

```js
// ui.js:320-339
const stashSelectedContextBlocks = (value)=>{
  const lines = String(value||'').split('\n');
  const marker = '<!-- hermes-selected-context -->';
  const out = [];
  for(let i=0;i<lines.length;i++){
    const labelMatch = lines[i].match(/^\*\*([^\n]{1,200}):\*\*\s*$/);
    if(!labelMatch){ out.push(lines[i]); continue; }
    const quoteLines = [];
    let j = i+1;
    if(lines[j] !== marker){ out.push(lines[i]); continue; }
    j++;
    while(j < lines.length && /^>/.test(lines[j])){
      quoteLines.push(lines[j].replace(/^>[ \t]?/,''));
      j++;
    }
    if(!quoteLines.length){ out.push(lines[i]); continue; }
    out.push(stashContext(labelMatch[1], quoteLines.join('\n')));
    i = j-1;
  }
  return out.join('\n');
};
```

#### 2.4.1 正则与行级状态机

解析是**行级扫描**，非全局正则替换（Flutter 也必须逐行扫，避免跨行误匹配）。

- **label 行正则**：`^\*\*([^\n]{1,200}):\*\*\s*$`（`ui.js:325`）
  - 以 `**` 开头，以 `:**` 结尾（冒号在闭合 `**` 之前），中间捕获 1-200 字符（`[^\n]{1,200}`），不含换行。
  - 行尾允许空白 `\s*`，但不允许尾随其他内容。
  - 捕获组即 `label`，后续 `trim` 已在捕获前保证非空；若需与 WebUI 完全一致，Flutter 侧也应对捕获做 `trim` 并回退为 `"Context"` 当空。
  - **超 200 字符的 label 行不匹配**，整行按普通文本保留（边界，见 2.7）。

- **marker 行**：严格 `<!-- hermes-selected-context -->` 全等（`ui.js:329`），无前后空白容忍（`lines[j] !== marker`）。Flutter 必须同样严格相等（不 `trim`），否则用户手写 `**foo:**` 不带 marker 会误判为卡片。

- **引用行**：`^>`（`ui.js:331`），剥离前缀 `^>[ \t]?`（`ui.js:332`），即 `>` 后可选一个空格或 tab。连续多行直到遇到非 `>` 行、空行或下一 label 行。**至少 1 行**才算有效块（`ui.js:335`），否则回退为普通文本。

- **块边界**：引用行序列结束后，`i = j-1`（`ui.js:337`），外层 `for` 自增后即指向引用区后的下一行。若下一行是新的 `**LABEL:**`，下一次迭代会尝试匹配下一块。

- **多块拼接**：发送侧以 `\n\n` 拼接（`messages.js:1027`），解析侧以行为单位自然处理，`trim` 后的内容中块间空行会被保留为空行，但不影响下一块的 label 识别（空行后 label 行仍能匹配）。

#### 2.4.2 围栏保护

`_renderUserFencedBlocks` 的整体流程（`ui.js:309-392`）：

1. 先提围栏代码块（`/(^|\n)[ ]{0,3}(`{3,})[^...]*\n...`）→ `\x00UF<n>\x00`（`ui.js:354`）。
2. 再提数学公式（`$$..$$`, `\[..\]`, `$..$`, `\(..\)`）→ `\x00UM<n>\x00`（`ui.js:379-382`）。
3. 再执行 `stashSelectedContextBlocks`（`ui.js:386`）。
4. 再 `esc(s).replace(/\n/g,'<br>')` 转义剩余文本（`ui.js:388`）。
5. 再还原 `\x00UF` / `\x00UC` / 数学占位（`ui.js:390-392`）。

因此，**围栏内出现的 `**LABEL:**` / `<!-- hermes-selected-context -->` / `> ` 不会被解析为选中块**。Flutter 的 `SelectedContextParser` 必须同样先提围栏与行内代码，再做选中块扫描（复用 `ChatMediaParser` 的围栏提存范式，见 3.2）。

#### 2.4.3 已发送气泡的 HTML

```js
// ui.js:314-317
const sentContextHtml = (label,quoteText)=>{
  const safeLabel = String(label||'').trim() || 'Context';
  const safeQuote = String(quoteText||'').replace(/\s+$/,'');
  return `<figure class="sent-selection-context" data-selected-context="1"><figcaption class="sent-selection-context-label">${esc(safeLabel)}</figcaption><blockquote class="sent-selection-context-quote">${esc(safeQuote)}</blockquote></figure>`;
};
```

`stashContext` 把 HTML 存入 `contextStash` 并返回 `\x00UC<n>\x00` 占位，最终还原进 `esc` 后的用户文本流（`ui.js:391`）。这意味着选中块在 WebUI 用户气泡中是**独立的 `<figure>` 卡片**，与普通文本的 `<br>` 流分离。

### 2.5 字段映射（端到端）

```
用户选中 text
  → PendingSelection{id, name, text}
    → _formatSelectedTextReplyQuote(text)  // marker + > 引用
      → `**name:**\n` + marker-quote  // 单块
        → 多块 `join('\n\n')` + 用户正文前后 `\n\n`
          → POST /api/chat/start {message: messageForAPI}
            → 服务端存 transcript: ChatMessage{role:"user", content: messageForAPI}
              → 客户端重载后 _renderUserFencedBlocks 解析
                → stashSelectedContextBlocks 行级扫描
                  → sentContextHtml 卡片
```

Dart 侧等价：

```
SelectionController: List<PendingSelection>
  → buildMessageForAPI(userText) // 同 _composerTextWithPendingSelections
    → ChatMessage{role:"user", content: messageForAPI}
      → SelectedContextParser.parse(message.content)
        → {blocks: List<SelectedContextBlock>, cleanText: string}
          → ChatMessageBubble: Column[ for(block in blocks) SelectedContextCard, if(cleanText非空) Markdown/Text ]
```

### 2.6 端到端示例

#### 示例 1：单块 + 正文

待发区：

```
PendingSelection{id:"ctx-1", name:"Context 1", text:"hello\nworld"}
current = "请解释一下"
```

`messageForAPI`：

```
请解释一下

**Context 1:**
<!-- hermes-selected-context -->
> hello
> world

```

解析后：`blocks=[{label:"Context 1", quote:"hello\nworld"}]`，`cleanText="请解释一下"`。

#### 示例 2：多块 + 无正文

待发区：

```
ctx-1 {name:"报错", text:"Null check operator used on a null value"}
ctx-2 {name:"Context 2", text:"lib/main.dart:42"}
current = ""
```

`messageForAPI`：

```
**报错:**
<!-- hermes-selected-context -->
> Null check operator used on a null value

**Context 2:**
<!-- hermes-selected-context -->
> lib/main.dart:42

```

解析后：两张卡片，垂直 `gap 8` 排列；`cleanText` 为空时仅渲染卡片区，不渲染空 Markdown。

#### 示例 3：围栏内不应解析

`message` 含：

````
请看代码：
```
**假的:**
<!-- hermes-selected-context -->
> 不应解析
```
````

提围栏后，围栏内三行被 `\x00FENCE` 占位，选中扫描器看不到它们，整段按围栏代码块渲染，无卡片。

### 2.7 边界与「不处理」情况（强制）

| 输入 | 期望行为 | 依据 |
|------|----------|------|
| `**短label:**\nhello`（无 marker 行） | **不处理**，整段按普通文本保留 | `ui.js:329` `lines[j] !== marker` → `out.push(lines[i])` |
| `**label:**\n<!-- hermes-selected-context -->\n`（marker 后无 `>` 行） | **不处理**，回退普通文本 | `ui.js:335` `!quoteLines.length` |
| `**<201字符label>:**`（201 字符） | **不处理**，正则 `{1,200}` 不匹配 | `ui.js:325` |
| `**label:**   `（尾随空白） | **处理**，`\s*` 允许 | `ui.js:325` |
| `> quote` 前有空格 ` > quote` | **不识别**为引用行（`^>` 严格行首） | `ui.js:331` |
| `>quote`（`>` 后无空格） | **识别**，剥离 `^>[ \t]?` 后为 `quote` | `ui.js:332` |
| `> ` 空引用行 | **识别**，剥离后为空字符串，仍计为一行（`join('\n')` 保留空行） | `ui.js:332` |
| marker 前后有空行 | 解析器按行扫，空行会中断引用区，但不影响下一块 | `ui.js:331` `while` 条件 |
| 纯 `**label:**` 无 marker，多次出现 | 全部按普通 Markdown `**加粗**` 渲染，不产生卡片 | WebUI 仅 marker 块算卡片 |

---

## 3. Flutter 解析与渲染规格

### 3.1 模型

```dart
/// 单个选中上下文块（对应 WebUI 的一次 _addNamedContextBlock）。
class SelectedContextBlock {
  const SelectedContextBlock({
    required this.label,
    required this.quote,
  });

  /// 卡片标题（已 trim，空回退 "Context"，1-200 字符；输入侧上限 120）。
  final String label;

  /// 引用原文（已剥离 `> ` 前缀、保留内部门换行、尾部 \s+ 已去）。
  final String quote;
}

/// 解析结果：卡片列表 + 剥离卡片后的剩余文本（供 Markdown 渲染）。
class SelectedContextParseResult {
  const SelectedContextParseResult({
    required this.blocks,
    required this.cleanText,
  });

  final List<SelectedContextBlock> blocks;

  /// 已移除所有选中块（及块间多余空行）后的剩余文本；可能为空。
  final String cleanText;
}
```

- `label` 与 `quote` 均为 `String` 非空；`quote` 为空的块不在 `blocks` 中（已被 2.7 规则过滤）。
- `cleanText` 保留用户正文与块间普通文本，去掉块本身；连续空行压缩与 WebUI 的 `\n\n` 拼接语义一致（见 3.2）。

### 3.2 `SelectedContextParser` 规格（对齐 `ChatMediaParser`）

> 文件：`lib/features/chat/widgets/selected_context_parser.dart`
> 参照：`lib/features/chat/widgets/chat_media_parser.dart:24-81` 的「提围栏→替换→还原」范式；`ui.js:309-392` 的围栏优先顺序。

#### 3.2.1 常量

```dart
const kSelectedContextMarker = '<!-- hermes-selected-context -->';
final kLabelLineRegex = RegExp(r'^\*\*([^\n]{1,200}):\*\*\s*$');
final kQuoteLineRegex = RegExp(r'^>');
final kQuoteStripRegex = RegExp(r'^>[ \t]?');
final kFencedBlockRegex = RegExp(r'(^|\n)[ ]{0,3}(`{3,})[^\n`]*\n[\s\S]*?\n[ ]{0,3}\2`*(?=\n|$)');
final kInlineCodeRegex = RegExp(r'`[^`\n]+`');
```

- `kLabelLineRegex` 必须逐行匹配（`split('\n')` 后逐行 `hasMatch`），不可用多行全局正则跨行吃掉。
- `kSelectedContextMarker` 严格相等，无 `trim`。

#### 3.2.2 算法（伪代码，逐行状态机）

```dart
SelectedContextParseResult parse(String raw) {
  if (raw.isEmpty) return empty;
  // 1. 提围栏与行内代码（复用 ChatMediaParser 的 codeStash 范式）
  final stash = <String>[];
  var s = raw.replaceAllMapped(kFencedBlockRegex, (m){ stash.add(m.group(0)!); return '\x00FENCE_${stash.length-1}\x00'; });
  s = s.replaceAllMapped(kInlineCodeRegex, (m){ stash.add(m.group(0)!); return '\x00CODE_${stash.length-1}\x00'; });

  // 2. 行级扫描
  final lines = s.split('\n');
  final blocks = <SelectedContextBlock>[];
  final outLines = <String>[];
  for (var i=0; i<lines.length; i++) {
    final lm = kLabelLineRegex.firstMatch(lines[i]);
    if (lm == null) { outLines.add(lines[i]); continue; }
    final label = lm.group(1)!.trim();
    if (label.isEmpty) { outLines.add(lines[i]); continue; }
    final j0 = i+1;
    if (j0 >= lines.length || lines[j0] != kSelectedContextMarker) { outLines.add(lines[i]); continue; }
    var j = j0+1;
    final q = <String>[];
    while (j < lines.length && kQuoteLineRegex.hasMatch(lines[j])) {
      q.add(lines[j].replaceFirst(kQuoteStripRegex, ''));
      j++;
    }
    if (q.isEmpty) { outLines.add(lines[i]); continue; }
    // 引用尾部 \s+ 去除（对齐 WebUI sentContextHtml 的 replace(/\s+$/,''))
    final quote = q.join('\n').replaceAll(RegExp(r'\s+$'), '');
    if (quote.isEmpty) { outLines.add(lines[i]); continue; } // 空引用不算块
    blocks.add(SelectedContextBlock(label: label, quote: quote));
    // 当前块行不入 outLines；块间空行由后续 outLines 自然保留，clean 时压缩
    i = j-1;
  }
  var clean = outLines.join('\n');
  // 还原围栏/行内代码
  clean = clean.replaceAllMapped(RegExp(r'\x00(?:FENCE|CODE)_(\d+)\x00'), (m){
    final idx = int.tryParse(m.group(1)??'')??-1;
    return (idx>=0 && idx<stash.length) ? stash[idx] : m.group(0)!;
  });
  // 块移除后可能留下连续空行，压缩为最多 \n\n（对齐 WebUI 的 \n{3,}→\n\n）
  clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  // 若 clean 仅剩空白，归为空字符串，避免渲染空 Markdown
  if (clean.trim().isEmpty) clean = '';
  return SelectedContextParseResult(blocks: blocks, cleanText: clean);
}
```

#### 3.2.3 容错与边界

- 围栏/行内代码内的 `**label:**` / marker / `>` 永远不识别（已提存）。
- label 超 200 字符、marker 缺失、引用区为空、quote 全空白 → 均回退为普通文本（见 2.7 表）。
- `quote` 内部保留原始换行与空行（`> ` 空行剥离后为空字符串，`join('\n')` 保留）。
- 解析是纯函数，无状态，可单测（见 §8）。

### 3.3 渲染位置：独立卡片区，不混入 Markdown

> 现状取证：`message_bubble.dart:119-126` 的 `_UserContent` 直接把 `message.content`（经 `contentWithoutAttachedFilesMarker` 与 `ChatMediaParser`）丢进 `Text`/`MarkdownBody`；`chat_media_parser.dart:33-81` 的围栏保护已保证代码块不被误转。

**新规格（强制）：**

- `ChatMessageBubble` 中 `role==user` 分支，先调用 `SelectedContextParser.parse(display)`（`display` 为已去附件标记、已 `trim` 的文本），得到 `blocks` 与 `cleanText`。
- 渲染结构（`Column`，`crossAxisAlignment: CrossAxisAlignment.stretch`）：

```
Column(children: [
  for (block in blocks) SelectedContextCard(block: block),  // 若多块，gap 8
  if (cleanText.isNotEmpty)
    // 原有 Markdown/Text 分支（hasMediaMarker ? MarkdownBody : Text）
    // cleanText 经 ChatMediaParser.parseMediaMarkers 再渲染
  if (attachments非空) ...附件条
])
```

- **禁止**把选中块塞进 Markdown 字符串再让 `flutter_markdown` 渲染（会受 `esc` / `replace(/\n/g,'<br>')` 影响，且无法实现左 accent 与可复制语义）。
- `blocks` 与 `cleanText` 的相对顺序：若 `cleanText` 中原本块在正文中间，剥离后块统一置顶是否符合 WebUI？WebUI 的 `stashSelectedContextBlocks` 是**原地替换**为 `<figure>` 占位，块保留在原文位置（`ui.js:336,386`）。但 Flutter 的气泡是蓝色整体背景，若块与文本混排会导致蓝泡内卡片与白字对比混乱。**折中**：块区置于 `cleanText` Markdown 之前（`blocks` 在上，`cleanText` 在下），并在两者间加 `SizedBox(height: 6)`（若两者均非空）。此为与 WebUI 的唯一有意偏离，需在代码注释中注明。

### 3.4 `SelectedContextCard` Widget 视觉规格（Cupertino）

> 对照：
> - WebUI 已发送卡片：`style.css:1399-1401` `.sent-selection-context` / `.sent-selection-context-label` / `.sent-selection-context-quote`
> - WebUI 待发区卡片：`style.css:1384-1395` `.selection-context-card` / `.selection-context-accent` / `.selection-context-body` / `.selection-context-header` / `.selection-context-name` / `.selection-context-quote`
> - Flutter 参照：`injected_notice_card.dart:44-117` 对齐 `style.css:2330` 的 `process-notice-*`（圆角 8、边框 `separator`、背景 `secondarySystemBackground`、头行 11px/700、code 块 12px/1.5、maxHeight 400）

#### 3.4.1 已发送卡片（`SelectedContextCard` / `SentSelectionContextCard`）

用于 `message_bubble.dart` 用户气泡内的历史渲染。单卡片规格：

| 属性 | 值 | 依据 |
|------|-----|------|
| 外容器 | `Container` + `BoxDecoration(border: Border.all(separator), borderRadius: 10-12, color: ...)`，左侧 `Border(left: 3px accent)` | `style.css:1399` `border-left:3px solid var(--accent)`，Flutter 用 `Container` 左侧 `BoxDecoration` 或 `Row[accent, body]` 实现；`injected_notice_card.dart:46-50` 同为 `Border.all(separator) + 8` |
| 背景 | `CupertinoColors.activeBlue` 气泡内：`white.withOpacity(0.14)` 叠加（对齐 `style.css:1399` `color-mix(user-bubble-bg 86%, accent-bg 14%)`）；若卡片置于气泡外（备选），用 `secondarySystemBackground` | `style.css:1399`；`injected_notice_card.dart:33` |
| 左 accent | `width 3px`，`color: CupertinoColors.activeBlue`（或 `CupertinoTheme.primaryColor`），`opacity 0.82`（WebUI）→ Flutter 用实色 `activeBlue` 即可 | `style.css:1385,1399` |
| label | `fontSize 11`, `fontWeight w700`, `letterSpacing 0.04*11`（对齐 injected 标题），`color: secondaryLabel` 或气泡内 `white.withOpacity(0.95)`，`maxLines 1, ellipsis` | `style.css:1400` `11px/750`；`injected_notice_card.dart:65-70` `11/700` |
| quote | `fontSize 12.5`, `height 1.45`, `color: secondaryLabel`（气泡外）或 `white.withOpacity(0.88)`（气泡内蓝底），`whiteSpace pre-wrap` → Flutter `SelectableText`，`maxLines` 不限（已发送卡片不截断，支持滚动） | `style.css:1401` `12.5/1.5`；`style.css:1394` 待发区 12.5/1.45 |
| 内边距 | `padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)`（外容器），label 与 quote 间 `SizedBox(height: 5)` | `style.css:1399` `10px 12px`；`style.css:1400` `margin-bottom:5px` |
| 圆角 | `12`（待发区）/ `10`（已发送）— Flutter 统一 `10` 以对齐 `injected_notice_card.dart:49` 的 `8` 与 WebUI 的 `10/12` | `style.css:1384:12`, `1399:10` |
| 多卡片间距 | `gap 8`（`Column` 子项间 `SizedBox(height: 8)`） | `style.css:1382` `.composer-selection-chips{gap:8px}` |
| 可复制 | `SelectableText`（`injected_notice_card.dart:99` 同款），长按选区；可选右上角「复制」按钮（`CupertinoButton` 小尺寸） | 规格要求「卡片内引用可复制」 |
| 无障碍 | `Semantics(header: true, label: label)` 包裹 | `injected_notice_card.dart:39-84` |

结构（建议 `Row` 实现左 accent）：

```dart
Container(
  decoration: BoxDecoration(
    color: bg,
    border: Border.all(color: separator),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(width: 3, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.horizontal(left: Radius.circular(10)))),
      Expanded(child: Padding(
        padding: EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: 5),
          SelectableText(quote, style: quoteStyle),
        ]),
      )),
    ],
  ),
)
```

#### 3.4.2 与 `InjectedNoticeCard` 的视觉对照

| 维度 | `InjectedNoticeCard`（`injected_notice_card.dart`） | `SelectedContextCard`（本规格） | 差异说明 |
|------|-----------------------------------------------------|--------------------------------|----------|
| 外容器圆角 | `8`（`injected_notice_card.dart:49`） | `10` | 选中卡片更强调引用，需稍大圆角 |
| 边框 | `Border.all(separator)` | 同 | 一致 |
| 左 accent | 无（仅头行图标） | `3px activeBlue` | 引用卡片的核心识别特征（`style.css:1399`） |
| 标题字号/字重 | `11 / 700`（`injected_notice_card.dart:66-68`） | 同 `11 / 700` | 一致 |
| 正文 | `12 / 1.5 monospace` code 块（`injected_notice_card.dart:101-106`） | `12.5 / 1.45` 非等宽 `SelectableText` | 引用非代码，用比例字体 |
| 展开能力 | 有（`expanded` + Toggle） | 无（始终展开；超长 quote 用 `ConstrainedBox(maxHeight: 220)` + 滚动） | 引用卡片无需折叠 |
| 背景 | `secondarySystemBackground` | 气泡内半透明白 / 气泡外 `secondarySystemBackground` | 依宿主气泡而变 |

#### 3.4.3 Markdown 渲染链集成点

- `message_bubble.dart:151-218` 的 `_UserContent.build` 中，`display` 计算后插入 `SelectedContextParser.parse(display)` 分支（见 3.3）。
- `cleanText` 再走现有 `hasMediaMarker ? MarkdownBody : Text` 分支（`message_bubble.dart:180-205`），保持媒体标记与附件条逻辑不变。
- `SelectedContextCard` **不**走 `MarkdownBody`，避免 `> ` 被二次转义为 `blockquote`。

---

## 4. Composer 待发区规格

### 4.1 模型 `PendingSelection`

```dart
class PendingSelection {
  const PendingSelection({
    required this.id,
    required this.name,
    required this.text,
  });

  final String id;   // ctx-N
  final String name; // 1-120 字符（输入侧），解析侧 1-200
  final String text; // 全量选中原文
}
```

- `id` 生成：`ctx-${++counter}`（`messages.js:904`），清空时 `counter=0`（`messages.js:913,918`）。
- `name` 默认：`Context <counter>`（`messages.js:905`，本地化键 `context_block_name_default`），Flutter 可固定 `Context` 或走 `AppLocalizations`。
- `name` 重命名：`trim` + `slice(0,120)`，空回退原名（`messages.js:1017`）。

### 4.2 状态持有

- 持有位置：`ChatController`（或 `ChatInputBar` 的 `Notifier`）内 `List<PendingSelection> pendingSelections`（`@protected` + `copyWith` 不可变更新），暴露 `pendingSelectionsProvider(sessionId)` 或直接 `chatControllerProvider(sessionId).select((s)=>s.pendingSelections)`。
- 操作：`addPendingSelection(text)`, `removePendingSelection(id)`, `renamePendingSelection(id, newName)`, `clearPendingSelections()`，全部同步 `notifyListeners` 并触发 `SelectionChips` 重建。
- 计数器：`int _selectionIdCounter` 与 WebUI 同步，`clear`/`remove` 至空时归零。

### 4.3 `SelectionChips` 条 UI

> 位置：`ChatInputBar` 上方（`chat_page.dart:134` 的 `ChatInputBar` 之前，`chat_page.dart:97-136` 的 `Column` 末段），或 `ChatInputBar` 内部 `Column[ chips, inputRow ]` 顶部。
> 参照：`style.css:1382-1398` `.composer-selection-chips` / `.selection-context-card` / `style.css:1384-1396`；`chat_input_bar.dart:324-435` 现有输入栏结构。

#### 4.3.1 容器

| 属性 | 值 | 依据 |
|------|-----|------|
| 布局 | `Column(gap: 8)`，垂直卡片列（`style.css:1382` `flex-direction:column;gap:8px`） | WebUI 为纵向列表，非横向流 |
| 宽度 | `maxWidth: clamp(780px,60vw,1100px)` 的 Flutter 等价：`ConstrainedBox(maxWidth: 600)` + 水平居中，或直接 `width: double.infinity` 占满输入栏宽度 | `style.css:1382` |
| 内边距 | `padding: EdgeInsets.only(top: 8)` | `style.css:1382` `padding:8px 0 0` |
| 最大高度 | `maxHeight: min(32vh,280px)` → `ConstrainedBox(maxHeight: 280)` + `SingleChildScrollView` | `style.css:1382` |
| 显隐 | `pending.isEmpty ? SizedBox.shrink() : chips`，等价 `wrap.hidden=!length`（`messages.js:937`） | `messages.js:937` |
| 滚动 | `scrollbar-gutter:stable` → Flutter `Scrollbar` 包裹 `SingleChildScrollView` | `style.css:1382` |

#### 4.3.2 单张待发卡片（与已发送卡片同构，交互增强）

结构对齐 `messages.js:939-987`：

```
article.selection-context-card
  div.selection-context-accent (3px)
  div.selection-context-body
    div.selection-context-header
      button.selection-context-name  // 可点击重命名
      button.selection-context-remove // ×
    blockquote.selection-context-quote // 预览
```

Flutter 等价：

- 外容器同 3.4.1（`12` 圆角、边框、`secondarySystemBackground` 渐变可简化为实色）。
- 头行：`Row(spaceBetween)`，左为 `CupertinoButton`（`name`，`11px/700`，`activeBlue`），点击/双击/`Enter`/`Space`/`F2` 触发重命名（`messages.js:960-967`）；右为 `×` 按钮（`12px`，`muted` → `hover:text`，`borderRadius 999`，`min 28x28`，触屏 `44x44`）（`style.css:1391-1393,1398`）。
- 预览：`Text`（非 `SelectableText`，卡片本身不可选中），`fontSize 12.5 / 1.45 / muted / pre-wrap / line-clamp 3 / ellipsis`（`style.css:1394` `display:-webkit-box;-webkit-line-clamp:3`），Flutter 用 `maxLines: 3, overflow: TextOverflow.ellipsis` 实现；`title` 全量（`messages.js:979`）→ Flutter 用 `Tooltip(message: text)`。

#### 4.3.3 引用预览截断

```js
// messages.js:926-931
function _selectedContextPreview(text){
  const normalized = String(text||'').replace(/\r\n?/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
  if(!normalized) return '';
  const max = 360;
  return normalized.length > max ? normalized.slice(0,max).trimEnd() + '…' : normalized;
}
```

Flutter 必须复用同一归一化与 `360` 截断（`slice(0,360).trimEnd() + '…'`），不可用字数/字节其他阈值。

#### 4.3.4 重命名交互

WebUI：`_editSelectionChipName`（`messages.js:996-1021`）

- 点击 `name` → 原地 `replaceWith(input.selection-chip-edit)`（`messages.js:1007`），`input.maxLength=120`（`messages.js:1004`），`focus+select`（`messages.js:1008`）。
- `blur` → `commit`（`messages.js:1019`），`Enter` → `commit`，`Escape` → `cancel`（`messages.js:1020`）。
- `commit`：`s.name = (inp.value.trim() || s.name).slice(0,120)`（`messages.js:1017`），`_renderSelectionChips()`，`restoreFocus` 回到 `name` 按钮（`messages.js:1010-1016`）。
- `cancel`：丢弃输入，`_renderSelectionChips()`。

Flutter 二选一：
- **方案 A（内联编辑）**：头行 `name` 区域在编辑态切换为 `CupertinoTextField(maxLength:120, autofocus:true)`，`onSubmitted` → commit，`onTapOutside`/`onEditingComplete` → commit，`Escape`（`RawKeyboardListener`）→ cancel。
- **方案 B（弹层）**：`showCupertinoDialog` 输入框，`Confirm` → commit。更符合 Cupertino 惯例，推荐 B。

#### 4.3.5 移除与清空

- 单张移除：`×` 按钮 `onPressed: () => removePendingSelection(id)`（`messages.js:974`）。
- 全部清空：`ChatInputBar` 头部或 `SelectionChips` 容器右上角「清空」文本按钮（WebUI 无全部清空按钮，Flutter 新增以提升可用性），`onPressed: clearPendingSelections`。
- 发送后清空：见 4.5。

#### 4.3.6 可访问性

- `name` 按钮：`aria-label: "Rename context block: <name>"`（`messages.js:959`）→ Flutter `Semantics(label: ...)` + `Tooltip("Click or press Enter to rename")`（`messages.js:958`）。
- `×` 按钮：`aria-label: "Remove context block: <name>"`（`messages.js:972`）。
- 卡片：`aria-label: name`（`messages.js:942`）。

### 4.4 发送时串入 `messageForAPI`

> 依据：`messages.js:1023-1028`；`chat_input_bar.dart:73-82` 的 `_submit` 直接 `send(text)`，需扩展为 `send(messageForAPI)`。

```dart
String buildMessageForAPI(String userText, List<PendingSelection> pending) {
  if (pending.isEmpty) return userText;
  String fmt(PendingSelection s) {
    final norm = s.text.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (norm.isEmpty) return ''; // 空归一化跳过
    final quoted = norm.split('\n').map((l)=> '> $l').join('\n');
    return '**${s.name}:**\n$kSelectedContextMarker\n$quoted';
  }
  final blocks = pending.map(fmt).where((b)=> b.isNotEmpty).join('\n\n');
  if (blocks.isEmpty) return userText;
  if (userText.trim().isEmpty) return '$blocks\n\n';
  return '${userText.replaceAll(RegExp(r'\s+$'), '')}\n\n$blocks\n\n';
}
```

- `blocks` 为空（全部空引用）时回退为纯 `userText`，不产生空卡片。
- 调用点：`ChatInputBar._submit` 中取 `_textController.text` 为 `current`，`ref.read(pendingSelectionsProvider)` 为 `pending`，`messageForAPI = buildMessageForAPI(current, pending)`，再 `controller.send(messageForAPI)`。
- `controller.send` 内部不需再拼块（块已在 `messageForAPI` 中），保持现有 `POST /api/chat/start {message: messageForAPI}` 契约（`chat_spec.md §4.1`）。

### 4.5 清空时机

| 时机 | 行为 | 依据 |
|------|------|------|
| 发送成功（`send` 乐观追加后） | `clearPendingSelections()` + `counter=0`（若空） | `messages.js:1031-1040` `_clearComposerAfterQueuedSelectionSend`（清空输入+附件+pending） |
| 用户手动清空 | 同上 | 新增 |
| 会话切换（`sessionId` 变化） | 清空旧会话的 pending（按 `sessionId` 隔离） | WebUI `_pendingSelections` 为全局，切换会话时未自动清空（潜在易错点）；Flutter 按 `sessionId` 维度持有，避免串会话 |

---

## 5. 复制提示优化规格

### 5.1 现状取证

- 状态：`ChatState.noticeMessage: String?`（`chat_state.dart:376,311`），`ChatController.setNotice(message)` → `copyWith(noticeMessage: message)`（`chat_controller.dart:2023-2024`），`dismissNotice()` → `clearNoticeMessage: true`（`chat_controller.dart:2028-2030`）。
- 视图：`chat_page.dart:128-133` `if (state.noticeMessage != null) _NoticeBanner(...)`，`_NoticeBanner` 为常驻绿色横幅（`chat_page.dart:781-824`：`systemGreen 0.12 + checkmark + secondaryLabel + ×`），需手动 `×` 关闭，无自动消失。
- 触发：`chat_message_list.dart:308-314` 复制动作 `copyMessageText(message)` 后 `controller.setNotice(copiedToClipboardNotice)`。
- 同列其他横幅：`_ErrorBanner`（`chat_page.dart:661-708` 红色）、`_OfflineCacheBanner`（`592-659` 蓝色）、`_QueuedBanner`（`710-732` 黄色）、`_PendingUserMessageBanner`（`734-778` 灰色）均为常驻。

### 5.2 新规格：轻量自动消失横幅

> 目标：`copiedToClipboardNotice` 等成功类轻提示改为 2.5-3s 自动消失，可手动 `×` 提前关闭，距输入栏 8-12px，不遮输入框，淡入淡出动画；错误横幅保持常驻以确保用户看到。

#### 5.2.1 分型

| 类型 | 触发 | 视觉 | 行为 | 依据 |
|------|------|------|------|------|
| **toast**（轻提示） | `setNotice` / `copiedToClipboardNotice` / `settingsSaved` 等成功类 | 绿色系（`systemGreen 0.12 + checkmark`，同现有 `_NoticeBanner`）或更轻的 `secondarySystemBackground + checkmark` | **自动消失 2.5-3s**（推荐 `2800ms`），可手动 `×`，淡入 `150ms` / 淡出 `200ms` | 本规格新增 |
| **error**（错误横幅） | `sendErrorMessage` / `setSendError` | 红色系（`systemRed 0.1 + exclamationmark`，同现有 `_ErrorBanner`） | **常驻**，仅手动 `×` | `chat_page.dart:661-708` 保持不变 |
| **info**（中性横幅） | `offlineCache` / `queued` / `pendingUserMessage` | 蓝/黄/灰 | 常驻（现有行为不变） | `chat_page.dart:592-778` |

#### 5.2.2 布局

```
Column(children: [
  _PendingPromptCard（若有）,
  _OfflineCacheBanner（若有）,
  ChatMessageList(Expanded),
  _ErrorBanner（若有，常驻，margin 12,6,12,0）,
  _QueuedBanner（若有）,
  _PendingUserMessageBanner（若有）,
  _NoticeBanner（toast，margin 12,6,12,8-12 ← 距输入栏 8-12px，见下）,
  ChatInputBar,
])
```

- 现有 `_NoticeBanner` 的 `margin: EdgeInsets.fromLTRB(12,6,12,0)`（`chat_page.dart:791`）距输入栏为 0，需改为 `EdgeInsets.fromLTRB(12,6,12,8)`（或 `12`），确保与 `ChatInputBar` 的 `border top 0.5` 有 8-12px 间隙，不遮输入框。
- `ChatInputBar` 本身有 `SafeArea(top:false)`（`chat_input_bar.dart:334`），横幅在 `SafeArea` 之外，不受底部 inset 影响。

#### 5.2.3 定时与手势

- `ChatPage` 或新 `NoticeBanner` StatefulWidget 内持 `Timer? _dismissTimer`。
- `didUpdateWidget` / `ref.listen(noticeMessage)` 触发：若 `noticeMessage` 非空且非 `error`，启动 `Timer(Duration(milliseconds: 2800), () => controller.dismissNotice())`。
- 手动 `×` → `controller.dismissNotice()` + `cancel timer`。
- 新 `setNotice` 到达时：`cancel` 旧 timer，重置新 timer（避免旧 timer 提前关闭新提示）。
- 动画：`AnimatedOpacity(duration: 150ms, opacity: visible?1:0)` + `AnimatedSlide` 或直接 `AnimatedSwitcher` 包裹 `_NoticeBanner`，`in: 150ms easeOut, out: 200ms easeIn`。

#### 5.2.4 与现有 API 的兼容

- `ChatController.setNotice` 保持签名不变，仅新增可选 `Duration? ttl` 参数（默认 `2800ms`），供特殊提示自定义时长；`dismissNotice` 不变。
- `chat_page.dart` 中 `ref.listen<String?>(chatControllerProvider(sessionId).select((s)=>s.noticeMessage), ...)` 负责启停 timer，避免在 Controller 内持 `Timer`（Controller 无 `BuildContext` 生命周期）。

---

## 6. 视觉对照表（汇总）

| 元素 | WebUI 选择 | Flutter 选择 | 备注 |
|------|------------|--------------|------|
| 待发区容器 | `flex column gap8 max-h 280`（`style.css:1382`） | `Column gap8 + ConstrainedBox 280 + ScrollView` | 一致 |
| 待发卡片 | `border 1 + radius12 + gradient`（`style.css:1384`） | `Border.all(separator) + 12 + secondarySystemBackground` | 渐变简化为实色 |
| 左 accent | `3px accent 0.82`（`style.css:1385`） | `3px activeBlue` | 一致 |
| 标题 | `11/700 accent-text`（`style.css:1388`） | `11/700 secondaryLabel / activeBlue` | 一致 |
| 引用预览 | `12.5/1.45 muted clamp3`（`style.css:1394`） | `12.5/1.45 secondaryLabel maxLines3` | 一致 |
| 已发送卡片 | `border-left 3px + 10px + label 11/750 + quote .94em/1.5 0.88`（`style.css:1399-1401`） | `Row[3px, body] + 10 + 11/700 + 12.5/1.45` | 字重 700 vs 750 差异可接受 |
| 折叠卡片参照 | `process-notice-*`（`style.css:2330`） | `InjectedNoticeCard`（`injected_notice_card.dart`） | 已对齐，本规格复用其令牌 |
| 复制横幅 | WebUI `showToast`（非本文件） | `chat_page.dart:781-824` `_NoticeBanner` | 本规格改为自动消失 2800ms |

---

## 7. 易错点（编码子代理必读）

1. **无 marker 的 `**label:**` 绝不算卡片**（`ui.js:329`）。手写 `**foo:**` 必须保持为 Markdown 加粗，不可误判。Flutter 解析器必须严格 `lines[j]==marker`，不可 `contains` 或 `trim` 后比较。

2. **label 正则 1-200 字符**（`ui.js:325`）。超长直接回退普通文本，不可截断后强行成卡。输入侧 120 上限（`messages.js:1004`）与解析侧 200 上限是两套约束，不可混用。

3. **围栏优先**。提围栏/行内代码必须在选中扫描之前（`ui.js:386` 在围栏提取之后），否则代码块内的示例文本会误触发卡片。`SelectedContextParser` 必须复用 `ChatMediaParser` 的提存顺序。

4. **引用行严格 `^>`**。行首空格后 `>` 不算引用；`> ` 与 `>` 均合法，剥离用 `^>[ \t]?`（`ui.js:332`）。

5. **空引用块不计入**。`!quoteLines.length` 与 `quote.trim().isEmpty` 均回退（`ui.js:335` + 本规格 3.2.2），避免空卡片。

6. **多块以 `\n\n` 拼接，尾部固定 `\n\n`**（`messages.js:1027-1028`）。解析器需容忍块间多余空行（`outLines` 自然保留），`cleanText` 阶段再压缩 `\n{3,}` → `\n\n`。

7. **预览 360 截断仅用于待发区显示**（`messages.js:930`），发送与解析均用全量 `text`，不可在 `PendingSelection.text` 阶段截断。

8. **重命名空输入回退原名**（`messages.js:1017` `trim()||s.name`），不可置空。

9. **待发区按 `sessionId` 隔离**。WebUI 全局单例在多会话切换时易串扰；Flutter 必须按 `sessionId` 维度持有 `pendingSelections`。

10. **渲染位置不混入 Markdown**。`SelectedContextCard` 必须在 `MarkdownBody` 之外独立渲染，否则 `esc` 与 `> ` 的 Markdown 语义会冲突（`ui.js:388` 的 `esc` 在卡片还原之后）。

11. **复制横幅与错误横幅分型**。`noticeMessage`（toast，自动消失）与 `sendErrorMessage`（error，常驻）不可共用同一 timer；`setNotice` 的 timer 仅针对 toast。

12. **`_hasPendingSelections` 语义**。`messages.js:176` 暴露给 `ui.js` 的 `_composerHasContent`，Flutter 的 `canSend` 需同样把 `pendingSelections.isNotEmpty` 计入可发送条件，否则「仅含选中块无正文」无法发送（`messages.js:1327` 的 `!text && !pendingFiles && !_pendingSelections.length` 守卫）。

---

## 8. 测试要点（DoD）

- **解析单测**：单块/多块/围栏内不解析/无 marker 不处理/超长 label 不处理/空引用不处理/`> ` 与 `>` 两种前缀/尾部空白剥离/块间空行压缩。
- **预览单测**：360 截断与 `…`、归一化 `\r\n`→`\n`、`\n{3,}`→`\n\n`。
- **组装单测**：`buildMessageForAPI` 的 `current` 空/非空 + 多块 `\n\n` 拼接 + 空引用跳过。
- **Widget 单测**：`SelectedContextCard` 渲染 label/quote、`SelectableText` 可复制、多卡片 `gap 8`、`cleanText` 为空时仅卡片。
- **Composer 单测**：`SelectionChips` 显隐、重命名 120 截断与空回退、移除/清空、发送后清空。
- **横幅单测**：toast 2.8s 自动消失、手动 `×` 取消 timer、新 toast 重置 timer、error 常驻不自动消失。
- `flutter analyze` 零告警；无 Material 混入。

---

## 9. 实施文件分区与接口契约

```
lib/features/chat/
  widgets/
    selected_context_parser.dart   // SelectedContextBlock, SelectedContextParseResult, SelectedContextParser
    selected_context_card.dart     // SelectedContextCard (已发送) + PendingSelectionCard (待发区，复用同视觉)
    selection_chips.dart           // SelectionChips (待发区列表，含重命名/移除/清空)
  chat_controller.dart             // 新增 pendingSelections + 四操作 + buildMessageForAPI
  chat_state.dart                  // 新增 List<PendingSelection> pendingSelections
  widgets/message_bubble.dart      // _UserContent 接入 SelectedContextParser + SelectedContextCard
  widgets/chat_input_bar.dart      // 顶部 SelectionChips + _submit 改走 messageForAPI
  chat_page.dart                   // _NoticeBanner 改造为自动消失 + 与 _ErrorBanner 分型
```

- 新增文件归 `lib/features/chat/`，禁止写 `lib/core/`。
- 命名：`SelectedContextBlock` / `SelectedContextParser` / `SelectedContextCard` / `PendingSelection` / `SelectionChips`，与 `ChatMediaParser` / `InjectedNoticeCard` 风格一致。
- Riverpod：`pendingSelections` 随 `ChatState` 持有，`chatControllerProvider(sessionId)` 为唯一写入口；`SelectionChips` 通过 `ref.watch(chatControllerProvider(sessionId).select((s)=>s.pendingSelections))` 订阅。

---

## 附录：关键源码行号索引

| 结论 | 源码 | 行号 |
|------|------|------|
| `_pendingSelections` 结构 | `D:\hermes-webui\static\messages.js` | 170-171 |
| `_hasPendingSelections` | `messages.js` | 176 |
| `_formatSelectedTextReplyQuote` | `messages.js` | 791-794 |
| `_addNamedContextBlock` / `_remove` / `_clear` | `messages.js` | 903-923 |
| `_selectedContextPreview` 360 | `messages.js` | 926-931 |
| `_renderSelectionChips` | `messages.js` | 933-994 |
| `_editSelectionChipName` 120 | `messages.js` | 996-1021 |
| `_composerTextWithPendingSelections` | `messages.js` | 1023-1028 |
| `stashSelectedContextBlocks` 行级扫描 | `D:\hermes-webui\static\ui.js` | 320-339 |
| `sentContextHtml` | `ui.js` | 314-317 |
| `_renderUserFencedBlocks` 围栏优先 | `ui.js` | 309-392 |
| `.composer-selection-chips` / `.selection-context-card` / `.sent-selection-context` | `D:\hermes-webui\static\style.css` | 1382-1401 |
| `process-notice-*` 参照 | `style.css` | 2330 |
| `InjectedNoticeCard` 对齐 process-notice | `lib/features/chat/widgets/injected_notice_card.dart` | 8-14,44-117 |
| `ChatMessageBubble._UserContent` 现状 | `lib/features/chat/widgets/message_bubble.dart` | 151-218 |
| `ChatMediaParser` 围栏范式 | `lib/features/chat/widgets/chat_media_parser.dart` | 24-81 |
| `ChatPage._NoticeBanner` 常驻 | `lib/features/chat/chat_page.dart` | 781-824 |
| `ChatController.setNotice` | `lib/features/chat/chat_controller.dart` | 2023-2030 |
| `ChatInputBar` 现状 | `lib/features/chat/widgets/chat_input_bar.dart` | 26-435 |
