# Hermes UI TODO — Active（进行中队列 · 完整规格）

> **规则**：
> 1. 新增任务直接在【本文件】写完整规格（位置/范围/复现/现状vs预期/验收），不写日期文件。

> 2. 条目完成收口 → 将完整条目【誊写】到完成当天日期文件 `.todo/YYYYMMDD.md`（不存在则新建)，标题标 `[已收口]` 作归档备份；随后从本文件移除该条。
>
> 3. 本文件只保留未收口任务，收口即清出。

---

## #41 [方向类·手势状态机] 聊天底部跟随取消时机重构——触摸即解锁，松手按方向/按压前状态定夺

  - 类型：方向类（行为状态机重构）+ 问题类（现状「一碰就丢跟随」）。
  - 位置：
    - 消息列表状态：`lib/features/chat/widgets/chat_message_list.dart`（`ChatMessageListState`：跟随态 `_userHasScrolled` :159、`_nearBottom` :153、`_isUserInteracting` :160；贴底阈值 `_nearBottomThreshold=80` :150-151）
    - 手势/滚动通知链：`NotificationListener<ScrollNotification>` :1390-1463（ScrollStart+dragDetails→interacting :1392-1395；UserScroll **forward=取消** :1404-1416；ScrollUpdate 拖拽 `delta.dy>0`/`scrollDelta<0` **=取消** :1425-1438；非拖拽 `scrollDelta<-1.0`**=取消** :1441-1456；ScrollEnd→interacting=false :1459-1461）
    -位置离底取消：`_onScroll` :375-388；恢复：:363-374
    -相位跟随复位：`_phaseSub` :213-236（sending/streaming 启用相位强制复位跟随 :217-233、:293-309）
    -steered 相位：`chat_state.dart:20-21`；steer accepted → 置 steered：`chat_controller.dart:1070-1072`
  - **术语约定（主人 2026-09-01 拍死，防再搞反）**：一律以**内容方向**命名——**「向上滑」** = 手指从**上往下**滑，内容相对视口**向上**移动（滚动**朝底部/新内容**方向，pixels 增大）；**「向下滑」** = 手指从**下往上**滑，内容相对视口**向下**移动（滚动**朝顶部/历史**方向（pixels 减小）。下方「现状/预期/验收」所有方向词均指此约定。
- 现状（取消跟随全清单——主人所问「现在都在什么时机被取消」）：（注：下述「向底部方向」= 主人术语「向上滑」；「向顶部/历史方向」=「向下滑」）
    1. `_onScroll` 位置离底 >80px 且（交互中或已离底）→ 置 `_userHasScrolled=true`（:378-383），**无方向判断**（任何方式离开底 80px 都算「用户上滚」）
    2. `UserScrollNotification.direction==forward`（= 滚动**向底部**方向 = 术语「向上滑」）→ 直接取消（:1404-1416）——**向底部方向滑反而取消跟随**
    3. `ScrollUpdateNotification` 拖拽 `dragDetails.delta.dy>0`（= 内容向上= 向底部）或 `scrollDelta<0` → 取消（:1425-1438）
    4. 非拖拽惯性滚动 `scrollDelta<-1.0` → 取消（:1441-1456）
    5. 恢复跟随仅三条路：滚回离底 <80px 且非交互中（:363-374）；sending/streaming 相位复位（:217-233）；换 session（:263）
    6. `_isUserInteracting` 有接线（ScrollStart+dragDetails→true :1394；UserScroll idle→false :1398、非 idle→true :1400；ScrollUpdate dragDetails→true :1421；ScrollEnd→false :1460）但**无「按压前跟随态」记录、无「松手方向恢复」**
  - 根因：现有逻辑「位置+方向」混合且**方向判断自相矛盾**（**向底部方向滑也触发取消**，:1404、:1425：即主人术语「向上滑」也会被砍），无「按压前跟随态」、无「松手恢复」——任何一滑（哪怕朝底部方向）都砍跟随，砍了不回头（除非滚回 80px 内）。
  - 预期（主人已拍板全口径）：
    **新状态机（两段式：拖动开始解锁 → 松手按方向/按压前状态定夺）**：
    1. **触摸判定**：**按下并拖动才算**（ScrollStart+dragDetails 系），拖动阈值**调敏感**（排除轻点）；拖动开始即置取消（解锁自由滚动，不滚到离底不算用户离开）
    2. **方向判定**：= 整个手势**累计位移**（起止方向，非松手瞬时速度）：
       - 累计**向上滑**（= 内容向上 = 滚动朝底部/新内容：手指从上往下滑）——按压前**跟随中** → **恢复跟随**（继续跟）；按压前**不跟随** → 若松手位置接近底部超 **80px 阈值** → **进入跟随**；否则保持不跟随
       - 累计**向下滑**（= 内容向下 = 滚动朝顶部/历史：手指从下往上滑）→ **一定取消跟随**
       - **无位移**（轻点已排除）→ 状态**回到按压前**（不改变）
    3. **其他任何操作都不得取消跟随**：除触摸手势外的任何来源（新消息到达、键盘/输入栏高度挤压、窗口 resize、程序滚动等）一律不得置 `_userHasScrolled=true`（需防 `_onScroll` :375-388 把布局挤压/程序滚动误判为用户离底——现注释 :376-377 仅防键盘/新气泡，需扩到全「其他操作」）
    4. **例外**：大纲跳转 `outlineJumpTo` / 高亮搜索定位 `scrollToHighlight` = 用户**主动导航**，算「用户主动取消」（离底即不跟随）
    5. **发送/Steer**（OOB）：
       - 普通发送新消息后 → **自动跟随**（维持现状相位复位 :217-233）
       - **Steer 发送**（时机 = **steer 请求发出时**，非 steered 相位）→ **不打开自动跟随**（不进跟随）
       - **若先前已跟随 → 不故意取消**（steer 保持当前跟随态原样）
  - 待实施时定：拖动起始阈值具体值（建议 ~4-8px 或 touchSlop 基准）；「按压前跟随态」记录字段（建议新增 `_pressFollowed` 等，勿覆盖 `_userHasScrolled`）。
  - 验收口径：
    1. 跟随中：**向上拖动**（= 内容向上 = 朝底部，松手仍近底）→ 保持跟随；**向下拖动**（= 内容向下 = 朝顶部）→ 取消
    2. 不跟随中：**向上拖动**接近底部（= 内容向上，松手 <80px）→ 恢复跟随；否则保持不跟随；轻点/无位移 → 状态不变
    3. 新消息/键盘/布局挤压/窗口 resize/程序滚动 → 不取消跟随
    4. 大纲跳转/高亮定位 → 离底不跟随（主动导航例外）
    5. 发送新消息 → 进跟随；steer 请求发出 → 不进跟随、先前已跟随则保持
    6. `flutter analyze` 零告警；`flutter test` 全绿（跟随状态机单测同步更新（现测 nearBottom/userHasScrolled 系）

  ---

## #42 [问题类·配色一致性] Fork 会话「分支」图标颜色同步——聊天标题 badge vs 会话列表副标题

  - 类型：问题类（配色/主题一致性）。
  - 位置：
    - 聊天标题「分支」badge：`lib/features/chat/chat_page.dart:233-258`（`parentSessionId != null` 时显示；图标 `CupertinoIcons.arrow_2_squarepath` :243-247，**固定 `CupertinoColors.secondaryLabel`**（未 resolveFrom），size 12）
    - 会话列表副标题「分支」图标：`lib/features/session_list/session_list_page.dart:1316-1324`（`isBranched = parentSessionId != null` :1313；图标同 `arrow_2_squarepath`，**`color: secondaryColor`**（:1311 = `secondaryText.resolveFrom(context)` 项目动态主题色），size 10）
  - 复现：（主人实测）Fork 会话进入聊天页后，标题下方「分支」badge 图标颜色与会话列表项副标题「分支」图标颜色不同。
  - 现状 vs 预期：
    -现状：两处**同一图标**（`arrow_2_squarepath`）但**着色源不同**：聊天标题 = `CupertinoColors.secondaryLabel`（Cupertino 内置动态色，未走项目主题 resolve）；列表副标题 = `secondaryText.resolveFrom(context)`（项目自定义 secondary 色）→ 渲染结果（尤其暗色/自定义主题下）色相/透明度不一致；另 **size 不一致**（12 vs 10）。
    -预期：两处「分支」图标**颜色同步**（统一走 `secondaryText.resolveFrom(context)` 或同一主题解析路径）；顺带统一 size（建议 10 或 12 二选一，实施时定）。
  - 验收口径：
    1. Fork 会话：聊天标题 badge 图标与会话列表副标题图标颜色一致（浅色/暗色均齐）
    2. （可选）size 统一（10 或 12）
    3. `flutter analyze` 零告警；`flutter test` 全绿
