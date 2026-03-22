# 跨设备打字系统设计方案

## 项目概述

专为不熟悉电脑的中年人设计的打字软件，让用户可以在手机上手写或拍照识别文字，然后自动在电脑光标位置输入文字。

**核心价值**: 解决中年人在电脑上打字困难的问题，利用手机触屏手写和拍照 OCR 的便利性，实现无缝文字输入。

---

## 系统架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        局域网环境                                │
│                                                                  │
│   ┌─────────────────┐                    ┌─────────────────┐    │
│   │   手机端 (Android) │  ←──────────→   │   电脑端 (Windows/Mac/Linux) │    │
│   │                 │    WebSocket     │                 │    │
│   │  ┌───────────┐  │    实时通信      │  ┌───────────┐  │    │
│   │  │ 手写输入   │  │                 │  │ 输入服务   │  │    │
│   │  │ 聊天界面   │  │                 │  │ (后台运行) │  │    │
│   │  └───────────┘  │                 │  └───────────┘  │    │
│   │  ┌───────────┐  │                 │  ┌───────────┐  │    │
│   │  │ 拍照 OCR  │  │                 │  │ 模拟键盘   │  │    │
│   │  │ 文字选择   │  │                 │  │ 输入文字   │  │    │
│   │  └───────────┘  │                 │  └───────────┘  │    │
│   └─────────────────┘                    └─────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 一、电脑端设计

### 1.1 功能定位
- **后台服务**: 无界面或极简托盘图标，静默运行
- **核心功能**: 接收手机端文字，模拟键盘输入到当前光标位置
- **启动方式**: 开机自启或手动启动

### 1.2 技术方案

#### 技术栈
- **语言**: Python 3.8+
- **WebSocket 服务器**: `websockets` 库
- **模拟键盘输入**: 
  - Windows: `pyautogui` 或 `pynput`
  - macOS: `pynput` 或 `applescript`
  - Linux: `pynput` 或 `xdotool`
- **自动发现**: mDNS (Bonjour/Avahi) 实现局域网内手机自动发现电脑

#### 核心模块

```
computer-server/
├── main.py                 # 入口程序
├── config.py               # 配置管理
├── websocket_server.py     # WebSocket 服务端
├── input_simulator.py      # 键盘模拟输入
├── discovery_service.py    # 局域网发现服务
├── tray_icon.py           # 系统托盘图标 (可选)
└── requirements.txt
```

#### 关键代码结构

```python
# websocket_server.py
class TypingServer:
    """WebSocket 服务器，接收手机端文字"""
    
    async def handle_client(self, websocket, path):
        """处理客户端连接"""
        async for message in websocket:
            data = json.loads(message)
            if data['type'] == 'text':
                self.input_text(data['content'])
            elif data['type'] == 'ocr_result':
                # OCR 结果需要用户确认，这里直接输入选中的文字
                self.input_text(data['selected_text'])
    
    def input_text(self, text: str):
        """将文字输入到当前光标位置"""
        # 使用 pynput 模拟键盘输入
        controller = keyboard.Controller()
        controller.type(text)
```

### 1.3 运行流程

```
1. 启动电脑端服务
   ↓
2. 启动 WebSocket 服务器 (端口 8765)
   ↓
3. 启动 mDNS 服务广播 (服务名: _typing._tcp)
   ↓
4. 等待手机端连接
   ↓
5. 接收文字 → 模拟键盘输入到当前光标位置
```

### 1.4 安装部署

#### Windows
```bash
# 打包为 exe，方便用户直接使用
pyinstaller --onefile --windowed main.py
```

#### 启动方式
- **手动启动**: 双击运行
- **开机自启**: 添加到系统启动项

---

## 二、手机端设计 (Android)

### 2.1 功能定位
- **目标用户**: 不熟悉电脑打字的中年人
- **核心体验**: 简单、直观、大字体、易操作
- **两种输入模式**:
  1. **手写输入模式**: 直接在输入框手写，发送后电脑自动输入
  2. **拍照 OCR 模式**: 拍照识别文字，选择后发送

### 2.2 界面设计

#### 设计理念
- **极简主义**: 界面元素少，操作步骤少
- **大字体**: 适合中年人视力
- **高对比度**: 按钮清晰可辨
- **明确反馈**: 操作后有明确提示

#### 界面原型

```
┌─────────────────────────┐
│  跨设备打字助手           │ ← 标题栏
├─────────────────────────┤
│                         │
│  [连接状态: 已连接 ✓]     │ ← 状态提示
│                         │
│  ┌─────────────────┐    │
│  │                 │    │
│  │   点击此处手写   │    │ ← 手写输入区域
│  │   或输入文字     │    │    (大输入框)
│  │                 │    │
│  └─────────────────┘    │
│                         │
│  ┌─────────────────┐    │
│  │    📷 拍照识字   │    │ ← 拍照 OCR 按钮
│  └─────────────────┘    │    (大按钮，醒目)
│                         │
│  ┌─────────────────┐    │
│  │    ✉️ 发送文字   │    │ ← 发送按钮
│  └─────────────────┘    │    (大按钮，绿色)
│                         │
└─────────────────────────┘
```

#### OCR 结果选择界面

```
┌─────────────────────────┐
│  选择要发送的文字         │
├─────────────────────────┤
│                         │
│  识别结果:               │
│                         │
│  ┌─────────────────┐    │
│  │ 今天天气真好，   │    │ ← 可选择的文字块
│  │ 适合出去散步。   │    │    (点击选中/取消)
│  └─────────────────┘    │
│                         │
│  ┌─────────────────┐    │
│  │ 明天可能会下雨   │    │
│  └─────────────────┘    │
│                         │
│  ┌─────────────────┐    │
│  │ 记得带伞出门。   │    │
│  └─────────────────┘    │
│                         │
│  ┌────────┐ ┌────────┐ │
│  │  重拍  │ │  发送  │ │ ← 重拍 / 发送按钮
│  └────────┘ └────────┘ │
│                         │
└─────────────────────────┘
```

### 2.3 技术方案

#### 技术栈
- **开发框架**: Flutter (跨平台，未来可扩展 iOS)
- **状态管理**: Provider 或 Riverpod
- **网络通信**: `web_socket_channel`
- **OCR 识别**: 
  - 方案 A: 百度/腾讯/阿里 OCR API (需联网)
  - 方案 B: ML Kit (Google，离线，推荐)
  - 方案 C: Tesseract OCR (完全离线)
- **局域网发现**: `multicast_dns` (mDNS)

#### 项目结构

```
mobile_app/
├── lib/
│   ├── main.dart                    # 入口
│   ├── app.dart                     # App 根组件
│   ├── models/
│   │   ├── connection_model.dart    # 连接状态
│   │   └── message_model.dart       # 消息模型
│   ├── services/
│   │   ├── websocket_service.dart   # WebSocket 通信
│   │   ├── discovery_service.dart   # 局域网发现
│   │   └── ocr_service.dart         # OCR 识别服务
│   ├── screens/
│   │   ├── home_screen.dart         # 主界面
│   │   ├── ocr_screen.dart          # OCR 结果界面
│   │   └── settings_screen.dart     # 设置界面
│   ├── widgets/
│   │   ├── connection_status.dart   # 连接状态组件
│   │   ├── handwriting_input.dart   # 手写输入组件
│   │   ├── photo_button.dart        # 拍照按钮
│   │   └── send_button.dart         # 发送按钮
│   └── utils/
│       ├── constants.dart           # 常量
│       └── helpers.dart             # 工具函数
├── android/                         # Android 配置
├── assets/                          # 资源文件
├── pubspec.yaml
└── README.md
```

### 2.4 核心功能实现

#### WebSocket 通信服务

```dart
// websocket_service.dart
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  
  // 自动发现电脑并连接
  Future<void> connectToComputer() async {
    // 1. 通过 mDNS 发现局域网内的电脑服务
    final computer = await _discoverComputer();
    if (computer != null) {
      // 2. 连接 WebSocket
      _channel = IOWebSocketChannel.connect('ws://${computer.ip}:8765');
      _status = ConnectionStatus.connected;
      notifyListeners();
    }
  }
  
  // 发送文字到电脑
  void sendText(String text) {
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.add(jsonEncode({
        'type': 'text',
        'content': text,
      }));
    }
  }
}
```

#### OCR 服务

```dart
// ocr_service.dart
class OCRService {
  // 使用 Google ML Kit 进行 OCR
  final textRecognizer = TextRecognizer();
  
  Future<List<String>> recognizeText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await textRecognizer.processImage(inputImage);
    
    // 将识别的文字按段落分割
    List<String> paragraphs = [];
    for (TextBlock block in recognizedText.blocks) {
      paragraphs.add(block.text);
    }
    return paragraphs;
  }
}
```

### 2.5 用户操作流程

#### 流程 1: 手写输入
```
1. 打开手机 App
   ↓
2. 自动连接电脑 (显示"已连接")
   ↓
3. 在手写区域输入文字
   ↓
4. 点击"发送文字"按钮
   ↓
5. 文字自动出现在电脑光标位置
```

#### 流程 2: 拍照 OCR
```
1. 打开手机 App
   ↓
2. 点击"拍照识字"按钮
   ↓
3. 拍摄包含文字的照片
   ↓
4. 显示识别结果，用户点击选择需要的文字
   ↓
5. 点击"发送"按钮
   ↓
6. 选中的文字自动出现在电脑光标位置
```

---

## 三、通信协议

### 3.1 WebSocket 消息格式

```json
// 手机 → 电脑: 发送文字
{
  "type": "text",
  "content": "用户输入的文字内容",
  "timestamp": 1699123456789
}

// 手机 → 电脑: 心跳包
{
  "type": "ping",
  "timestamp": 1699123456789
}

// 电脑 → 手机: 心跳响应
{
  "type": "pong",
  "timestamp": 1699123456789
}

// 电脑 → 手机: 输入结果
{
  "type": "input_result",
  "success": true,
  "message": "输入成功"
}
```

### 3.2 局域网发现协议 (mDNS)

```
服务类型: _typing._tcp
服务名称: 打字助手-电脑名
端口: 8765
TXT 记录:
  - version=1.0
  - platform=windows|macos|linux
```

---

## 四、安全考虑

### 4.1 局域网隔离
- 仅监听局域网地址 (192.168.x.x, 10.x.x.x)
- 拒绝外网连接

### 4.2 连接验证 (可选)
- 首次连接需要电脑端确认
- 使用简单的配对码验证

---

## 五、开发计划

### 阶段 1: 基础功能 (MVP)
- [ ] 电脑端 WebSocket 服务器
- [ ] 电脑端键盘模拟输入
- [ ] 手机端基础界面
- [ ] 手机端文字发送功能
- [ ] 局域网手动连接 (IP 输入)

### 阶段 2: 体验优化
- [ ] 局域网自动发现 (mDNS)
- [ ] 手机端 OCR 功能
- [ ] 电脑端系统托盘图标
- [ ] 连接状态显示
- [ ] 错误提示和重连机制

### 阶段 3: 完善功能
- [ ] 历史记录功能
- [ ] 常用语快捷发送
- [ ] 多设备支持
- [ ] 界面主题定制

---

## 六、技术难点与解决方案

### 6.1 难点 1: 电脑端模拟键盘输入
**问题**: 不同操作系统模拟键盘的方式不同
**解决**: 
- 使用 `pynput` 库，支持跨平台
- 针对特殊字符做兼容性处理

### 6.2 难点 2: 手机端 OCR 准确性
**问题**: 手写文字、复杂背景识别率低
**解决**:
- 使用 Google ML Kit，识别率高
- 提供识别结果选择和编辑功能
- 引导用户在光线充足、背景简洁的环境下拍照

### 6.3 难点 3: 局域网连接稳定性
**问题**: 网络波动导致连接断开
**解决**:
- WebSocket 自动重连机制
- 心跳包检测连接状态
- 断线后自动重新发现电脑

---

## 七、部署方案

### 7.1 电脑端部署
```bash
# 1. 安装 Python 依赖
pip install -r requirements.txt

# 2. 运行服务
python main.py

# 3. (可选) 打包为可执行文件
pyinstaller --onefile --windowed main.py
```

### 7.2 手机端部署
```bash
# 1. 安装 Flutter
# 2. 构建 APK
flutter build apk --release

# 3. 安装到手机
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## 八、使用说明

### 首次使用
1. 在电脑上运行服务端程序
2. 在手机上安装 App
3. 确保手机和电脑在同一 WiFi 下
4. 打开 App，自动连接电脑
5. 开始打字!

### 日常使用
1. 打开电脑端服务 (或设置为开机自启)
2. 打开手机 App
3. 手写或拍照输入文字
4. 点击发送，文字自动出现在电脑上

---

## 九、扩展思路

### 未来可扩展功能
1. **语音输入**: 手机端语音转文字，发送到电脑
2. **剪贴板同步**: 手机复制，电脑粘贴
3. **文件传输**: 手机发送图片、文档到电脑
4. **远程控制**: 手机控制电脑鼠标、PPT 翻页
5. **iOS 支持**: 使用 Flutter 开发，可打包 iOS 版本

---

## 十、总结

本系统通过 WebSocket 实现局域网内手机与电脑的实时通信，利用手机触屏手写和拍照 OCR 的便利性，帮助不熟悉电脑打字的中年人轻松完成文字输入。

**核心优势**:
- 零学习成本: 手机端界面极简，操作直观
- 无需注册: 局域网内直接使用，无需账号
- 实时响应: 文字即时同步到电脑
- 双模输入: 支持手写和拍照 OCR

**技术选型**:
- 电脑端: Python + WebSocket + pynput
- 手机端: Flutter + ML Kit OCR
- 通信: WebSocket + mDNS
