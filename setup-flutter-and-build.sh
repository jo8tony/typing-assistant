#!/bin/bash

# Flutter 安装和 APK 构建脚本
# 在目标机器上运行此脚本

set -e

echo "=========================================="
echo "  Flutter 安装和 APK 构建"
echo "=========================================="
echo ""

# 配置
FLUTTER_VERSION="3.24.5"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER_DIR="$HOME/flutter"

# 检查是否已安装 Flutter
if command -v flutter &> /dev/null; then
    echo "✓ Flutter 已安装"
    flutter --version
else
    echo "正在安装 Flutter..."
    
    # 检测系统架构
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        FLUTTER_ARCH="arm64"
    else
        FLUTTER_ARCH="x64"
    fi
    
    echo "系统架构: $ARCH"
    echo "下载 Flutter $FLUTTER_VERSION ($FLUTTER_ARCH)..."
    
    # 下载 Flutter
    cd /tmp
    FLUTTER_ZIP="flutter_macos_${FLUTTER_ARCH}_${FLUTTER_VERSION}-stable.zip"
    
    if [ ! -f "$FLUTTER_ZIP" ]; then
        echo "正在下载 Flutter..."
        curl -L -o "$FLUTTER_ZIP" \
            "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/$FLUTTER_ZIP"
    fi
    
    echo "解压 Flutter..."
    unzip -q "$FLUTTER_ZIP" -d "$HOME"
    
    # 添加到 PATH
    export PATH="$FLUTTER_DIR/bin:$PATH"
    
    echo "✓ Flutter 安装完成"
    flutter --version
fi

echo ""
echo "=========================================="
echo "  构建 APK"
echo "=========================================="
echo ""

# 进入项目目录
cd "$PROJECT_DIR/mobile_app"

# 获取依赖
echo "获取 Flutter 依赖..."
flutter pub get

# 构建 APK
echo "构建 APK..."
flutter build apk --release

# 复制 APK 到项目根目录
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp "build/app/outputs/flutter-apk/app-release.apk" "$PROJECT_DIR/typing-assistant.apk"
    
    echo ""
    echo "=========================================="
    echo "  构建成功!"
    echo "=========================================="
    echo ""
    echo "APK 文件位置:"
    echo "  $PROJECT_DIR/typing-assistant.apk"
    echo ""
    echo "文件大小:"
    ls -lh "$PROJECT_DIR/typing-assistant.apk"
    echo ""
    echo "安装到手机:"
    echo "  adb install typing-assistant.apk"
    echo ""
else
    echo "✗ 构建失败，未找到 APK 文件"
    exit 1
fi
