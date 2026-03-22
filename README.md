# 跨设备打字助手

专为不熟悉电脑打字的中年人设计的跨设备输入解决方案。在手机上手写或拍照识别文字，自动在电脑光标位置输入。

## 功能特点

- **手写输入**: 手机端手写文字，一键发送到电脑
- **拍照 OCR**: 拍照识别文字，选择后发送到电脑
- **自动发现**: 局域网内自动发现电脑，无需手动配置
- **大字体界面**: 适合中年人视力，操作简单直观
- **实时同步**: 文字即时同步到电脑光标位置

---

## 项目结构

```
.
├── computer-server/          # 电脑端服务 (Python)
│   ├── main.py              # 入口程序
│   ├── config.py            # 配置管理
│   ├── websocket_server.py  # WebSocket 服务器
│   ├── input_simulator.py   # 键盘模拟输入
│   ├── discovery_service.py # mDNS 局域网发现
│   └── requirements.txt     # Python 依赖
│
├── mobile_app/              # 手机端 App (Flutter)
│   ├── lib/
│   │   ├── main.dart        # 入口
│   │   ├── models/          # 数据模型
│   │   ├── services/        # 服务层
│   │   ├── screens/         # 界面
│   │   ├── widgets/         # 组件
│   │   └── utils/           # 工具类
│   ├── android/             # Android 配置
│   └── pubspec.yaml         # Flutter 依赖
│
└── design.md                # 设计文档
```

---

## 电脑端部署

### 环境要求

- Python 3.8 或更高版本
- Windows / macOS / Linux

### 安装步骤

1. **安装依赖**

```bash
cd computer-server
pip install -r requirements.txt
```

2. **运行服务**

```bash
python main.py
```

3. **(可选) 带系统托盘运行**

```bash
python main.py --tray
```

### 打包为可执行文件

使用 PyInstaller 打包为独立的可执行文件：

```bash
pip install pyinstaller
pyinstaller --onefile --windowed main.py
```

打包后的文件在 `dist/` 目录下。

### 开机自启

#### Windows
1. 将打包好的 `main.exe` 放入启动文件夹:
   - 按 `Win + R`，输入 `shell:startup`
   - 将 `main.exe` 复制到打开的文件夹

#### macOS
1. 创建 plist 文件:
```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.typingassistant.server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.typingassistant.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/path/to/computer-server/main.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.typingassistant.server.plist
```

#### Linux (systemd)
```bash
sudo tee /etc/systemd/system/typing-assistant.service > /dev/null << EOF
[Unit]
Description=Typing Assistant Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/path/to/computer-server
ExecStart=/usr/bin/python3 main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable typing-assistant
sudo systemctl start typing-assistant
```

---

## 手机端部署

### 环境要求

- Flutter SDK 3.0 或更高版本
- Android Studio / Xcode
- Android 5.0 (API 21) 或更高版本

### 安装步骤

1. **安装 Flutter 依赖**

```bash
cd mobile_app
flutter pub get
```

2. **构建 APK**

```bash
flutter build apk --release
```

APK 文件路径: `build/app/outputs/flutter-apk/app-release.apk`

3. **安装到手机**

```bash
flutter install
```

或者通过 ADB:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 开发调试

```bash
# 连接手机，开启 USB 调试
flutter devices  # 查看已连接设备
flutter run      # 运行调试
```

---

## 使用说明

### 首次使用

1. **电脑端**
   - 运行电脑端服务程序
   - 确保电脑和手机在同一 WiFi 网络下

2. **手机端**
   - 安装并打开 App
   - 授予相机权限（用于拍照识字）
   - App 会自动搜索并连接电脑

### 日常使用

#### 方式 1: 手写输入
1. 打开手机 App
2. 在输入框中手写或输入文字
3. 点击"发送文字"按钮
4. 文字自动出现在电脑光标位置

#### 方式 2: 拍照识字
1. 点击"拍照识字"按钮
2. 对准要识别的文字拍照
3. 在识别结果中选择需要的文字
4. 点击"发送"按钮
5. 选中的文字自动出现在电脑光标位置

### 手动连接

如果自动发现失败，可以手动输入电脑 IP:
1. 点击右上角设置图标
2. 输入电脑的 IP 地址（如 `192.168.1.100`）
3. 点击"连接"

---

## 故障排除

### 无法连接

1. **检查网络**
   - 确保手机和电脑在同一 WiFi 下
   - 检查电脑防火墙是否允许端口 8765

2. **查看电脑 IP**
   - Windows: 运行 `ipconfig`，查看 IPv4 地址
   - macOS/Linux: 运行 `ifconfig` 或 `ip addr`

3. **手动连接**
   - 在 App 中手动输入电脑 IP 地址

### 文字未输入

1. 确保电脑端服务正在运行
2. 确保电脑上的输入框已获得焦点（有光标闪烁）
3. 检查是否有其他程序拦截了键盘输入

### OCR 识别失败

1. 确保照片清晰，光线充足
2. 文字与背景对比度要高
3. 避免拍摄反光或模糊的照片

---

## 技术架构

### 通信协议

- **WebSocket**: 手机与电脑之间的实时通信
- **mDNS**: 局域网内自动发现服务
- **心跳机制**: 保持连接状态，自动重连

### 安全机制

- 仅允许局域网内连接（192.168.x.x, 10.x.x.x 等）
- 拒绝外网连接请求

---

## 开发计划

### 已实现 ✅
- [x] 电脑端 WebSocket 服务器
- [x] 电脑端键盘模拟输入
- [x] mDNS 局域网自动发现
- [x] 手机端基础界面
- [x] 手写文字发送
- [x] 拍照 OCR 识别
- [x] OCR 结果选择
- [x] 连接状态显示

### 待实现 📋
- [ ] 历史记录功能
- [ ] 常用语快捷发送
- [ ] 语音输入功能
- [ ] iOS 版本支持
- [ ] 剪贴板同步
- [ ] 文件传输功能

---

## 贡献指南

欢迎提交 Issue 和 Pull Request！

---

## 许可证

MIT License

---

## 联系方式

如有问题或建议，欢迎反馈！
