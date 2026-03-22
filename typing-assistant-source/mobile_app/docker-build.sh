#!/bin/bash

# 使用 Docker 构建 APK

echo "=========================================="
echo "  使用 Docker 构建 APK"
echo "=========================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "错误: 未找到 Docker"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "构建 Docker 镜像..."
docker build -t typing-assistant-builder .

echo ""
echo "创建输出目录..."
mkdir -p output

echo ""
echo "运行构建容器..."
docker run --rm \
    -v "$(pwd)/output:/output" \
    typing-assistant-builder

echo ""
echo "=========================================="
echo "  构建完成!"
echo "=========================================="
echo ""
echo "APK 文件路径:"
echo "  $(pwd)/output/typing-assistant.apk"
echo ""
