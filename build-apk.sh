#!/bin/bash

# 跨设备打字助手 - APK 构建脚本
# 这个脚本提供了多种构建 APK 的方法

set -e

echo "=========================================="
echo "  跨设备打字助手 - APK 构建"
echo "=========================================="
echo ""

PROJECT_DIR="/Users/liaopeng/Desktop/projs/print"
MOBILE_DIR="$PROJECT_DIR/mobile_app"

# 检查方法 1: 本地 Flutter
if command -v flutter &> /dev/null; then
    echo "✓ 检测到本地 Flutter 环境"
    echo "正在使用本地 Flutter 构建..."
    
    cd "$MOBILE_DIR"
    
    echo "获取依赖..."
    flutter pub get
    
    echo "构建 APK..."
    flutter build apk --release
    
    echo ""
    echo "=========================================="
    echo "  构建成功!"
    echo "=========================================="
    echo ""
    echo "APK 文件位置:"
    echo "  $MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    
    # 复制到项目根目录方便找到
    cp "$MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk" "$PROJECT_DIR/typing-assistant.apk"
    echo "已复制到: $PROJECT_DIR/typing-assistant.apk"
    
    exit 0
fi

# 检查方法 2: Docker
if command -v docker &> /dev/null; then
    echo "✓ 检测到 Docker"
    
    # 检查 Docker 是否运行
    if docker info &> /dev/null; then
        echo "正在使用 Docker 构建..."
        
        cd "$MOBILE_DIR"
        
        # 创建输出目录
        mkdir -p output
        
        # 使用 Docker 构建
        docker run --rm \
            -v "$MOBILE_DIR:/app" \
            -w /app \
            cirrusci/flutter:stable \
            bash -c "flutter pub get && flutter build apk --release"
        
        # 复制 APK
        if [ -f "$MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk" ]; then
            cp "$MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk" "$PROJECT_DIR/typing-assistant.apk"
            
            echo ""
            echo "=========================================="
            echo "  构建成功!"
            echo "=========================================="
            echo ""
            echo "APK 文件位置:"
            echo "  $PROJECT_DIR/typing-assistant.apk"
            echo ""
        fi
        
        exit 0
    else
        echo "✗ Docker 守护进程未运行"
    fi
fi

# 如果没有找到构建工具
echo ""
echo "=========================================="
echo "  未找到构建工具"
echo "=========================================="
echo ""
echo "请使用以下方法之一构建 APK:"
echo ""
echo "方法 1: 安装 Flutter"
echo "  macOS: brew install flutter"
echo "  其他: https://flutter.dev/docs/get-started/install"
echo ""
echo "方法 2: 启动 Docker"
echo "  macOS: open -a Docker"
echo "  然后重新运行此脚本"
echo ""
echo "方法 3: 使用 GitHub Actions"
echo "  查看 BUILD_APK.md 了解详情"
echo ""
echo "方法 4: 手动构建"
echo "  1. 在已安装 Flutter 的机器上"
echo "  2. 复制 mobile_app 目录"
echo "  3. 运行: flutter build apk --release"
echo ""

exit 1
