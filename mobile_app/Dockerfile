# Flutter 构建环境
FROM cirrusci/flutter:stable

# 设置工作目录
WORKDIR /app

# 复制项目文件
COPY . .

# 获取依赖
RUN flutter pub get

# 构建 APK
RUN flutter build apk --release

# 输出目录
VOLUME ["/app/build/app/outputs/flutter-apk"]

CMD ["cp", "build/app/outputs/flutter-apk/app-release.apk", "/output/typing-assistant.apk"]
