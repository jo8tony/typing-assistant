# 手机端 App 构建说明

## 环境要求

- Flutter SDK 3.0 或更高版本
- Android Studio (用于 Android SDK)
- JDK 8 或更高版本

## 安装 Flutter

### macOS

```bash
# 使用 Homebrew 安装
brew install flutter

# 或者手动下载
# 访问 https://flutter.dev/docs/get-started/install/macos
```

### Windows

```powershell
# 下载 Flutter SDK
# 访问 https://flutter.dev/docs/get-started/install/windows
```

### 配置环境变量

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
export PATH="$PATH:/path/to/flutter/bin"
```

## 构建步骤

### 1. 检查 Flutter 环境

```bash
flutter doctor
```

确保所有检查项都通过（特别是 Android toolchain）。

### 2. 获取依赖

```bash
cd mobile_app
flutter pub get
```

### 3. 构建 APK

```bash
# 构建发布版 APK
flutter build apk --release

# 或者使用构建脚本
chmod +x build.sh
./build.sh
```

### 4. 获取 APK 文件

构建完成后，APK 文件位于：
```
build/app/outputs/flutter-apk/app-release.apk
```

### 5. 安装到手机

#### 方式 1: 使用 Flutter 命令
```bash
flutter install
```

#### 方式 2: 使用 ADB
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

#### 方式 3: 手动安装
1. 将 APK 文件传输到手机
2. 在手机上点击安装
3. 允许安装未知来源应用

## 开发调试

### 连接手机

1. 开启手机的 USB 调试模式
2. 使用 USB 线连接电脑
3. 检查设备是否连接
```bash
adb devices
```

### 运行调试

```bash
flutter run
```

### 热重载

在调试模式下，按 `r` 键进行热重载。

## 常见问题

### 1. 构建失败

```bash
# 清理构建缓存
flutter clean
flutter pub get
flutter build apk --release
```

### 2. 依赖下载失败

检查网络连接，或者使用国内镜像：
```bash
# 配置国内镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
```

### 3. Android SDK 未找到

```bash
# 配置 Android SDK 路径
flutter config --android-sdk /path/to/android-sdk
```

### 4. Gradle 下载慢

编辑 `android/build.gradle`，修改仓库地址：
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

## 测试步骤

1. **启动电脑端服务**
   ```bash
   cd computer-server
   python3 main.py
   ```

2. **安装手机 App**
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. **确保手机和电脑在同一 WiFi 下**

4. **打开手机 App**
   - 授予相机权限
   - App 会自动搜索并连接电脑

5. **测试功能**
   - 手写输入文字，点击发送
   - 拍照识别文字，选择后发送

## 连接信息

- **电脑端端口**: 8765
- **服务类型**: `_typing._tcp`
- **WebSocket 地址**: `ws://<电脑IP>:8765`

如果自动发现失败，可以在 App 中手动输入电脑 IP 地址。
