#!/bin/bash

# 跨设备打字助手 - 构建脚本

echo "=========================================="
echo "  跨设备打字助手 - 构建脚本"
echo "=========================================="
echo ""

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "错误: 未找到 Flutter"
    echo "请先安装 Flutter SDK: https://flutter.dev/docs/get-started/install"
    exit 1
fi

# 检查 Flutter 环境
echo "检查 Flutter 环境..."
flutter doctor -v

echo ""
echo "获取依赖..."
flutter pub get

echo ""
echo "构建发布版 APK..."
flutter build apk --release

echo ""
echo "=========================================="
echo "  构建完成!"
echo "=========================================="
echo ""
echo "APK 文件路径:"
echo "  build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "安装到手机:"
echo "  adb install build/app/outputs/flutter-apk/app-release.apk"
echo ""
