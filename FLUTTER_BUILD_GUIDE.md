# Flutter 安装和 APK 构建完整指南

由于当前环境网络限制，请按照以下步骤在另一台机器上构建 APK。

---

## 方法一：使用自动脚本（推荐）

### 步骤 1: 准备环境

找一台可以访问外网的 macOS 机器，确保：
- 网络连接正常
- 有 curl 命令
- 有 unzip 命令

### 步骤 2: 复制项目

将项目复制到目标机器：

```bash
# 方式 1: 使用 U 盘或文件传输
# 将整个 print 目录复制到目标机器

# 方式 2: 使用 scp
scp -r /Users/liaopeng/Desktop/projs/print user@target-machine:~/

# 方式 3: 使用 zip 压缩后传输
cd /Users/liaopeng/Desktop/projs
zip -r print.zip print/
# 传输 print.zip 到目标机器
```

### 步骤 3: 运行构建脚本

在目标机器上执行：

```bash
cd ~/print  # 或你复制到的目录
chmod +x setup-flutter-and-build.sh
./setup-flutter-and-build.sh
```

脚本会自动：
1. 下载并安装 Flutter（如果未安装）
2. 获取项目依赖
3. 构建 APK
4. 输出到 `typing-assistant.apk`

---

## 方法二：手动安装 Flutter 并构建

### 步骤 1: 下载 Flutter

```bash
# 进入临时目录
cd /tmp

# 下载 Flutter（根据你的系统选择）
# macOS ARM64 (M1/M2/M3)
curl -L -o flutter_macos_arm64_3.24.5-stable.zip \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.24.5-stable.zip"

# macOS Intel (x64)
curl -L -o flutter_macos_x64_3.24.5-stable.zip \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_x64_3.24.5-stable.zip"
```

### 步骤 2: 安装 Flutter

```bash
# 解压到用户目录
cd /tmp
unzip flutter_macos_arm64_3.24.5-stable.zip -d ~/

# 添加到 PATH
export PATH="$HOME/flutter/bin:$PATH"

# 验证安装
flutter --version
```

### 步骤 3: 配置 Flutter

```bash
# 运行 Flutter 医生，检查环境
flutter doctor

# 根据提示安装缺失的组件
# 通常需要安装 Android Studio 和 Android SDK
```

### 步骤 4: 构建 APK

```bash
# 进入项目目录
cd /path/to/print/mobile_app

# 获取依赖
flutter pub get

# 构建 APK
flutter build apk --release
```

### 步骤 5: 获取 APK

构建完成后，APK 文件位于：
```
/path/to/print/mobile_app/build/app/outputs/flutter-apk/app-release.apk
```

复制到项目根目录：
```bash
cp build/app/outputs/flutter-apk/app-release.apk ../typing-assistant.apk
```

---

## 方法三：使用 Android Studio

### 步骤 1: 安装 Android Studio

1. 下载 Android Studio：https://developer.android.com/studio
2. 安装并启动
3. 完成初始配置

### 步骤 2: 安装 Flutter 插件

1. 打开 Android Studio
2. File → Settings → Plugins
3. 搜索 "Flutter" 并安装
4. 重启 Android Studio

### 步骤 3: 导入项目

1. File → Open
2. 选择 `print/mobile_app` 目录
3. 等待项目同步完成

### 步骤 4: 构建 APK

1. Build → Build Bundle(s) / APK(s) → Build APK(s)
2. 等待构建完成
3. 在右下角点击 "locate" 找到 APK 文件

---

## 方法四：使用朋友的电脑

如果你有朋友已经安装了 Flutter：

### 步骤 1: 准备项目

```bash
cd /Users/liaopeng/Desktop/projs/print
# 删除不需要的文件，减小体积
rm -rf mobile_app/build mobile_app/.dart_tool

# 压缩项目
zip -r typing-assistant-project.zip mobile_app/
```

### 步骤 2: 发送给朋友

通过邮件、微信、QQ 等方式发送 `typing-assistant-project.zip`

### 步骤 3: 朋友构建

朋友收到后执行：

```bash
unzip typing-assistant-project.zip
cd mobile_app
flutter pub get
flutter build apk --release
```

### 步骤 4: 获取 APK

朋友将生成的 APK 发送回来：
```
mobile_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## 安装 APK

构建完成后，将 APK 安装到手机：

### 方式 1: 使用 ADB
```bash
adb install typing-assistant.apk
```

### 方式 2: 手动安装
1. 将 APK 传输到手机
2. 在文件管理器中点击安装
3. 允许安装未知来源应用

---

## 常见问题

### 1. Flutter 下载慢

使用国内镜像：
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### 2. Gradle 下载慢

修改 `mobile_app/android/build.gradle`:
```gradle
buildscript {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/jcenter' }
        google()
        mavenCentral()
    }
}
```

### 3. 构建失败

```bash
# 清理缓存
flutter clean
flutter pub get
flutter build apk --release
```

---

## 推荐方案

| 方案 | 难度 | 时间 | 推荐度 |
|------|------|------|--------|
| 自动脚本 | 低 | 10-15 分钟 | ⭐⭐⭐⭐⭐ |
| 手动安装 | 中 | 20-30 分钟 | ⭐⭐⭐⭐ |
| Android Studio | 中 | 30-60 分钟 | ⭐⭐⭐ |
| 朋友帮忙 | 低 | 5 分钟 | ⭐⭐⭐⭐⭐ |

**最快的方式**：找有 Flutter 环境的朋友帮忙构建！

---

## 测试步骤

1. **电脑端**：确保服务正在运行
2. **手机端**：安装 APK，授予相机权限
3. **连接**：确保手机和电脑在同一 WiFi
4. **测试**：手写输入或拍照识字，发送到电脑

有问题随时问我！
