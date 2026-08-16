# 发布指南（RELEASE）

> 适用版本：v0.1.0（Phase 1-6 全功能 + Android 通知里程碑）
> 编写日期：2026-08-17 ｜ 发布前请逐项核对下方检查清单。

## 1. 发布流程总览

1. 确认质量门禁：`flutter test`（722 用例全绿）+ `flutter analyze`（零告警）——实测通过；
2. 完成本指南 §2 的 Android 签名配置（当前 release 仍用 debug keystore 占位）；
3. 对齐版本号（§4），更新 CHANGELOG.md；
4. 构建产物（§2 Android / §3 Windows）；
5. 真机验证（§5，含 Phase 6 通知 8 项验证）；
6. 补齐 LICENSE 文件与 README 截图后打 tag 发布。

## 2. Android APK 签名发布

> 现状：`android/app/build.gradle.kts` 中 release buildType 仍为
> `signingConfig = signingConfigs.getByName("debug")`（脚手架 TODO 未处理），
> **发布前必须完成以下签名配置**，否则产物是 debug 签名的不可发布包。

### 2.1 生成 keystore（一次性）

```bash
# 在项目外安全位置生成（如 %USERPROFILE%\.android\），勿提交到仓库
keytool -genkeypair -v \
  -keystore ~/.android/hermex-release.jks \
  -alias hermex \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <你的密码> -keypass <你的密码>
```

### 2.2 配置 build.gradle.kts

在 `android/app/build.gradle.kts` 的 `android {}` 块内增加：

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

android {
    // ... 现有配置保持不变 ...

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // 可选：启用混淆/压缩（发布建议开启）
            // isMinifyEnabled = true
            // isShrinkResources = true
        }
    }
}
```

`android/key.properties`（**加入 .gitignore，严禁提交**）：

```properties
storeFile=C:/Users/<你>/.android/hermex-release.jks
storePassword=<你的密码>
keyAlias=hermex
keyPassword=<你的密码>
```

### 2.3 构建与验证

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk

# 验证签名（应为 v1+v2，别名 hermex）
# Windows 下用 Android SDK build-tools 的 apksigner：
"$ANDROID_HOME/build-tools/<版本>/apksigner.bat" verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

可选：上架 Google Play 时改出 AAB：

```bash
flutter build appbundle --release   # build/app/outputs/bundle/release/app-release.aab
```

> 已知参数：`applicationId` = `com.silentreader.hermex_flutter`，minSdk 24（Android 7.0+），
> targetSdk 36，compileSdk 37。

## 3. Windows 打包

### 3.1 基础构建

```bash
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
#   （hermex_flutter.exe + 依赖 DLL + data/ 目录，整体拷贝即可分发）
```

前置条件：Visual Studio Build Tools 2022（含「使用 C++ 的桌面开发」工作负载）。
> 注：本仓库 Windows release 构建链路尚未实际跑通验证，首次发布前需在本机完整执行一次并记录产物清单。

### 3.2 可选：MSIX 打包

- 方式一：`flutter build windows --msix`（需安装 `msix` 包：`flutter pub add --dev msix`，
  并在 `pubspec.yaml` 配置 `msix_config`：`display_name`、`publisher_display_name`、`identity_name` 等）。
- 方式二：Visual Studio → 项目属性 → Packaging → 创建 App 包（需要代码签名证书，企业内部分发可跳过）。

### 3.3 可选：Inno Setup 安装器

1. 安装 [Inno Setup](https://jrsoftware.org/isinfo.php)；
2. 编写脚本将 `build/windows/x64/runner/Release/` 整体打包为 `Setup.exe`；
3. 配置：应用名 `Hermex`、版本号与 §4 对齐、安装目录 `{autopf}\Hermex`、桌面快捷方式。

## 4. 版本号管理

- 唯一事实来源：`pubspec.yaml` 的 `version: <major>.<minor>.<patch>+<build>`；
  Android 的 `versionName`/`versionCode`、Windows 的文件版本均取自它（build.gradle 用 `flutter.versionName/versionCode`）。
- **当前状态**：pubspec 为 `1.0.0+1`，与 CHANGELOG 的 v0.1.0 里程碑**不一致**。
  发布 v0.1.0 前二选一：
  - 改为 `0.1.0+1`（推荐，与 SemVer + CHANGELOG 对齐）；或
  - 保留 `1.0.0` 并把 CHANGELOG 首版里程碑改名为 v1.0.0。
- 发布节奏建议：每发一版递增 `patch`（如 0.1.1），破坏性变更递增 `minor`；`+build` 每次构建递增。
- 每次发版：改 pubspec → 更新 CHANGELOG.md → 跑测试/analyze → 构建 → 打 git tag（`git tag v0.1.0`）。

## 5. 真机验证清单

### 5.1 Phase 6 通知功能（Android，8 项）

依据 `lib/features/notifications/` 的行为契约逐项验证：

1. **前台不打扰**：app 在前台完成一个回合 → 不弹通知，且清掉历史残留通知；
2. **后台必达**：app 退后台（Home 键/锁屏/切走）后回合完成 → 弹出系统通知（标题 + 单行预览）；
3. **点击回跳**：点击通知 → app 冷启动（被杀进程）与热启动两种场景均回到对应会话页 `/chat/:sessionId`；
4. **回前台清理**：手动回到 app 前台 → 通知栏自动清除该通知；
5. **权限适配**：Android 13+ 首次启动按需弹 POST_NOTIFICATIONS 授权；拒绝授权不影响聊天主流程；
6. **防堆积**：连续多回合完成 → 通知栏只有一条（固定 ID 1001 替换，不堆积）；
7. **预览截断**：长内容通知预览为单行且 ≤120 字符，无换行符/乱码；
8. **失败隔离**：通知服务初始化/发送失败（如被系统禁用）→ 聊天流式主流程不受影响，仅日志记录。

### 5.2 常规冒烟（Android 真机 + Windows 桌面）

- [ ] 首次启动进入 Onboarding，配置服务器（含自定义 Header / 用户名密码）后进入会话列表；
- [ ] 新建会话 → 完整流式对话（含工具调用卡片）→ 中途 steer / 停止；
- [ ] 会话列表：搜索 / 置顶 / 归档 / 分支 / 删除；
- [ ] 任务：创建 → 启停 → 触发 → 查看输出；
- [ ] 技能浏览、记忆分区展示；
- [ ] 工作区：浏览目录 → 下载文件（删除/重命名预期提示 501，见 QA.md）；
- [ ] Git：status / diff / commit / pull；
- [ ] 看板：切换看板、查看卡片；
- [ ] 统计：切换时间范围、柱状图渲染；
- [ ] 设置：主题三态切换、多服务器增删改切换；
- [ ] 深/浅色主题下各页面无对比度问题。

## 6. 发布前检查清单

- [ ] `flutter test` 全绿（722 用例）
- [ ] `flutter analyze` 零告警
- [ ] Android release 签名已配置（§2），APK 签名验证通过
- [ ] pubspec 版本号与 CHANGELOG 对齐（§4）
- [ ] LICENSE 文件已补充（MIT 全文 + 版权人，README 已声明基于 Hermex 蓝本）
- [ ] README 截图已补齐（移除 `[截图待补]` 标记）
- [ ] 通知 8 项真机验证通过（§5.1）
- [ ] 常规冒烟通过（§5.2）
- [ ] git tag 已打，release 产物（APK / Windows 包）已归档
