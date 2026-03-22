# APK 构建指南

由于当前环境没有 Flutter SDK，以下是几种构建 APK 的方法：

---

## 方法 1: 使用 Docker（推荐）

如果你已安装 Docker，可以使用以下命令快速构建：

```bash
cd /Users/liaopeng/Desktop/projs/print/mobile_app
chmod +x docker-build.sh
./docker-build.sh
```

构建完成后，APK 文件会在 `output/typing-assistant.apk`

---

## 方法 2: 本地安装 Flutter 构建

### 步骤 1: 安装 Flutter

**macOS:**
```bash
# 使用 Homebrew
brew install flutter

# 或者手动安装
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"
```

**Windows:**
1. 下载 Flutter SDK: https://flutter.dev/docs/get-started/install/windows
2. 解压并添加到环境变量 PATH

**Linux:**
```bash
sudo snap install flutter --classic
```

### 步骤 2: 安装 Android SDK

下载 Android Studio: https://developer.android.com/studio

### 步骤 3: 构建 APK

```bash
# 进入项目目录
cd /Users/liaopeng/Desktop/projs/print/mobile_app

# 获取依赖
flutter pub get

# 构建 APK
flutter build apk --release

# APK 位置
# build/app/outputs/flutter-apk/app-release.apk
```

---

## 方法 3: 使用 GitHub Actions（自动构建）

我已经为你配置了 GitHub Actions 工作流。

### 步骤:

1. **创建 GitHub 仓库**
   ```bash
   cd /Users/liaopeng/Desktop/projs/print
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/你的用户名/typing-assistant.git
   git push -u origin main
   ```

2. **触发构建**
   - 推送代码到 main 分支会自动触发构建
   - 或者进入 GitHub 仓库 → Actions → Build APK → Run workflow

3. **下载 APK**
   - 构建完成后，在 Actions 页面下载 Artifact
   - 或者在 Releases 页面下载自动发布的 APK

---

## 方法 4: 使用在线 Flutter 构建服务

### Codemagic (推荐)
1. 访问 https://codemagic.io/
2. 使用 GitHub 账号登录
3. 导入你的仓库
4. 点击 "Start build"
5. 下载生成的 APK

### Flutter Build
访问在线构建服务，上传项目代码即可构建。

---

## 方法 5: 使用朋友的电脑

如果你有朋友已经安装了 Flutter 环境，可以把项目代码发给他帮忙构建：

```bash
# 压缩项目
cd /Users/liaopeng/Desktop/projs/print
zip -r typing-assistant.zip mobile_app/

# 发送给朋友构建
# 朋友构建完成后，把 APK 发回来
```

---

## 快速测试方案

如果你只是想快速测试，可以使用我提供的预编译版本（如果有的话），或者：

1. **使用 Flutter Web 版本**
   ```bash
   cd mobile_app
   flutter run -d chrome
   ```
   然后在手机上用浏览器访问电脑的 IP 地址。

2. **使用热重载调试**
   ```bash
   cd mobile_app
   flutter run
   ```
   连接手机后可以直接在手机上调试运行。

---

## 安装 APK

构建完成后，将 APK 安装到手机：

```bash
# 使用 ADB
adb install build/app/outputs/flutter-apk/app-release.apk

# 或者手动安装
# 1. 将 APK 传输到手机
# 2. 在文件管理器中点击安装
# 3. 允许安装未知来源应用
```

---

## 常见问题

### 1. Gradle 下载失败

修改 `android/build.gradle`:
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

### 2. 依赖下载慢

配置国内镜像:
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
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

对于快速测试，我建议：

1. **如果你有 Docker**: 使用方法 1，最简单
2. **如果你会 GitHub**: 使用方法 3，全自动
3. **如果你经常开发**: 使用方法 2，本地安装 Flutter

需要我帮你配置其中任何一种方法吗？
