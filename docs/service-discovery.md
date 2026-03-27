# 服务发现机制技术说明与设计文档

## 概述

本项目采用类似 LocalSend 的服务发现机制，通过 UDP 多播和局域网扫描相结合的方式，实现局域网内设备的自动发现。该机制支持跨平台（macOS、Windows、Linux、Android、iOS），无需依赖中心服务器，设备之间可以直接通信。

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        应用层                                    │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │   手机端 App    │              │   电脑端服务    │          │
│  │  (Flutter/Dart) │              │   (Python)      │          │
│  └────────┬────────┘              └────────┬────────┘          │
│           │                                │                    │
│  ┌────────▼────────┐              ┌────────▼────────┐          │
│  │ DiscoveryService│              │ DiscoveryService│          │
│  │    (Dart)       │              │    (Python)     │          │
│  └────────┬────────┘              └────────┬────────┘          │
└───────────┼─────────────────────────────────┼──────────────────┘
            │                                 │
            │         UDP 多播                │
            │    ┌───────────────┐           │
            └────►  224.0.0.168  ◄───────────┘
                 │   :53318      │
                 └───────┬───────┘
                         │
            ┌────────────▼────────────┐
            │      局域网交换机        │
            └────────────┬────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │ 设备 A  │    │ 设备 B  │    │ 设备 C  │
    └─────────┘    └─────────┘    └─────────┘
```

### 核心组件

| 组件 | 平台 | 文件路径 | 说明 |
|------|------|----------|------|
| DiscoveryService | Python | `computer-server/discovery_service.py` | 电脑端发现服务 |
| Config | Python | `computer-server/config.py` | 配置管理 |
| DiscoveryService | Dart | `mobile_app/lib/services/local_send_discovery_service.dart` | 手机端发现服务 |

## 发现协议

### 协议参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 多播地址 | `224.0.0.168` | IPv4 D类多播地址 |
| 多播端口 | `53318` | 避免与 LocalSend (53317) 冲突 |
| WebSocket 端口 | `8765` | 数据传输端口 |
| 宣告间隔 | 2秒 | 设备宣告广播频率 |
| 设备超时 | 30秒 | 设备离线判定时间 |
| 清理间隔 | 10秒 | 过期设备清理频率 |

### 消息格式

设备宣告消息采用 JSON 格式：

```json
{
  "announce": true,
  "fingerprint": "a1b2c3d4e5f6...",
  "alias": "打字助手-MacBook",
  "version": "1.0.0",
  "deviceModel": "Mac",
  "deviceType": "macos",
  "port": 8765,
  "protocol": "ws",
  "download": true,
  "ip": "192.168.1.100"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| announce | boolean | 是 | 消息类型标识，true 表示设备宣告 |
| fingerprint | string | 是 | 设备唯一标识符（UUID） |
| alias | string | 是 | 设备显示名称 |
| version | string | 是 | 协议版本号 |
| deviceModel | string | 否 | 设备型号（Mac、Windows PC、Linux PC、Mobile） |
| deviceType | string | 是 | 设备类型（macos、windows、linux、mobile） |
| port | integer | 是 | WebSocket 服务端口 |
| protocol | string | 是 | 协议类型（ws/wss） |
| download | boolean | 否 | 是否支持接收文件 |
| ip | string | 是 | 设备 IP 地址 |

## 发现流程

### 1. 服务启动流程

```
┌─────────────────────────────────────────────────────────────┐
│                      服务启动流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 获取本机 IP 地址                                         │
│     ├── 连接外部地址获取                                     │
│     └── 解析 ifconfig/ipconfig 作为备选                     │
│                                                             │
│  2. 生成设备指纹                                             │
│     └── UUID v4 格式，持久化存储                             │
│                                                             │
│  3. 创建 UDP 多播 Socket                                     │
│     ├── 绑定端口 53318                                       │
│     ├── 加入多播组 224.0.0.168                               │
│     ├── 设置 TTL = 2                                         │
│     └── 设置多播回环                                         │
│                                                             │
│  4. 启动后台线程                                             │
│     ├── 宣告线程：每 2 秒广播一次                            │
│     ├── 监听线程：接收其他设备的宣告                         │
│     └── 清理线程：每 10 秒清理过期设备                       │
│                                                             │
│  5. 执行局域网扫描（手机端）                                  │
│     └── 并发扫描同子网 254 个 IP                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2. 设备发现流程

```
┌──────────────┐                    ┌──────────────┐
│   手机端     │                    │   电脑端     │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       │  ┌─────────────────────────────┐  │
       │  │ 方式一：UDP 多播发现        │  │
       │  └─────────────────────────────┘  │
       │                                   │
       │     UDP Multicast Announce        │
       │◄─────────────────────────────────│
       │     {announce: true, ...}         │
       │                                   │
       │     UDP Multicast Announce        │
       │─────────────────────────────────►│
       │     {announce: true, ...}         │
       │                                   │
       │  ┌─────────────────────────────┐  │
       │  │ 方式二：局域网扫描（手机端） │  │
       │  └─────────────────────────────┘  │
       │                                   │
       │     WebSocket Handshake           │
       │─────────────────────────────────►│
       │     GET / HTTP/1.1                │
       │     Upgrade: websocket            │
       │                                   │
       │     HTTP/1.1 101 Switching        │
       │◄─────────────────────────────────│
       │     发现 WebSocket 服务           │
       │                                   │
       ▼                                   ▼
```

### 3. 设备连接流程

```
┌──────────────┐                    ┌──────────────┐
│   手机端     │                    │   电脑端     │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       │  用户点击设备卡片                  │
       │                                   │
       │     WebSocket Connect             │
       │─────────────────────────────────►│
       │     ws://192.168.1.100:8765       │
       │                                   │
       │     Connection Established        │
       │◄─────────────────────────────────│
       │                                   │
       │     心跳保活 (30s interval)        │
       │◄───────────────────────────────►│
       │                                   │
       │     数据传输                       │
       │◄───────────────────────────────►│
       │                                   │
```

## 技术实现细节

### 电脑端 (Python)

#### 1. 多播 Socket 配置

```python
# 创建 UDP Socket
multicast_socket = socket.socket(
    socket.AF_INET,      # IPv4
    socket.SOCK_DGRAM,   # UDP
    socket.IPPROTO_UDP   # UDP 协议
)

# 设置端口复用
multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

# 非Windows系统支持 SO_REUSEPORT
if platform.system() != 'Windows':
    multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)

# 绑定端口
multicast_socket.bind(('', MULTICAST_PORT))

# 加入多播组
group = socket.inet_aton(MULTICAST_ADDRESS)
mreq = group + socket.inet_aton('0.0.0.0')
multicast_socket.setsockopt(
    socket.IPPROTO_IP,
    socket.IP_ADD_MEMBERSHIP,
    mreq
)

# 设置多播 TTL
multicast_socket.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

# 设置多播回环
multicast_socket.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)

# 指定多播出口接口
multicast_socket.setsockopt(
    socket.IPPROTO_IP,
    socket.IP_MULTICAST_IF,
    socket.inet_aton(local_ip)
)
```

#### 2. 设备宣告

```python
def _send_announce(self):
    message = json.dumps({
        "announce": True,
        "fingerprint": self.device_info["fingerprint"],
        "alias": self.device_info["alias"],
        "version": self.device_info["version"],
        "deviceModel": self.device_info["deviceModel"],
        "deviceType": self.device_info["deviceType"],
        "port": self.device_info["port"],
        "protocol": self.device_info["protocol"],
        "download": self.device_info["download"],
        "ip": self.local_ip,
    }, ensure_ascii=False).encode('utf-8')

    self.multicast_socket.sendto(
        message,
        (MULTICAST_ADDRESS, MULTICAST_PORT)
    )
```

#### 3. 设备清理

```python
def _cleanup_loop(self):
    while self.is_running:
        time.sleep(10)  # 每10秒清理一次
        current_time = time.time()
        expired = [
            fp for fp, device in self._discovered_devices.items()
            if current_time - device.get("lastSeen", 0) > 30  # 30秒超时
        ]
        for fp in expired:
            del self._discovered_devices[fp]
```

### 手机端 (Dart/Flutter)

#### 1. 多播监听

```dart
Future<void> _startMulticastListener() async {
  // 创建 UDP Socket
  _multicastSocket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    DiscoveryConstants.multicastPort,
    reuseAddress: true,
    reusePort: true,
  );

  _multicastSocket!.broadcastEnabled = true;

  // 加入多播组
  final multicastGroup = InternetAddress(DiscoveryConstants.multicastAddress);
  _multicastSocket!.joinMulticast(multicastGroup);

  // 监听消息
  _multicastSocket!.listen((event) {
    if (event == RawSocketEvent.read) {
      final datagram = _multicastSocket!.receive();
      if (datagram != null) {
        _handleMulticastMessage(datagram);
      }
    }
  });
}
```

#### 2. 局域网扫描

```dart
Future<void> _runNetworkScan() async {
  final ipParts = _localIp!.split('.');
  final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

  // 并发扫描子网
  final futures = <Future>[];
  for (int i = 1; i <= 254; i++) {
    final ip = '$subnet.$i';
    if (ip == _localIp) continue;

    futures.add(_checkDevice(ip));

    // 限制并发数量
    if (futures.length >= 64) {
      await Future.wait(futures);
      futures.clear();
      await Future.delayed(Duration(milliseconds: 5));
    }
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
  }
}
```

#### 3. WebSocket 探测

```dart
Future<void> _checkDevice(String ip) async {
  final socket = await Socket.connect(
    ip,
    DiscoveryConstants.websocketPort,
    timeout: Duration(milliseconds: 300),
  );

  // 发送 WebSocket 握手请求
  final request = 'GET / HTTP/1.1\r\n'
      'Host: $ip:${DiscoveryConstants.websocketPort}\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Key: $key\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      '\r\n';

  socket.write(request);

  // 检查响应
  final response = await socket.first.timeout(
    Duration(milliseconds: 300),
  );

  if (response.contains('101') || response.contains('Switching Protocols')) {
    // 发现 WebSocket 服务
    _addDevice(device);
  }

  await socket.close();
}
```

#### 4. Android MulticastLock

Android 系统默认禁用多播，需要获取 MulticastLock：

```dart
// 通过 MethodChannel 调用原生代码
static const MethodChannel _multicastChannel =
    MethodChannel('com.example.typing_assistant/multicast');

Future<bool> _acquireMulticastLock() async {
  if (!Platform.isAndroid) return true;

  final result = await _multicastChannel.invokeMethod('acquireMulticastLock');
  return result == true;
}
```

Android 原生代码 (Kotlin)：

```kotlin
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, 
            "com.example.typing_assistant/multicast").setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    val wifiManager = getSystemService(Context.WIFI_SERVICE) as WifiManager
                    multicastLock = wifiManager.createMulticastLock("typing_assistant")
                    multicastLock?.acquire()
                    result.success(true)
                }
                "releaseMulticastLock" -> {
                    multicastLock?.release()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
```

## 设备模型

### DiscoveredDevice

```dart
class DiscoveredDevice {
  final String fingerprint;  // 设备唯一标识
  final String alias;        // 设备名称
  final String ip;           // IP 地址
  final int port;            // WebSocket 端口
  final String deviceModel;  // 设备型号
  final String deviceType;   // 设备类型
  final String version;      // 协议版本
  final String protocol;     // 协议类型
  final DateTime lastSeen;   // 最后发现时间
}
```

### 设备类型映射

| deviceType | deviceModel | 平台 |
|------------|-------------|------|
| macos | Mac | macOS |
| windows | Windows PC | Windows |
| linux | Linux PC | Linux |
| mobile | Mobile | Android/iOS |

## 网络安全

### IP 地址过滤

只允许来自私有网络地址的连接：

```python
ALLOWED_NETWORKS = [
    "192.168.",      # C类私有网络
    "10.",           # A类私有网络
    "172.16.",       # B类私有网络 (172.16.0.0 - 172.31.255.255)
    "172.17.", "172.18.", "172.19.",
    "172.20.", "172.21.", "172.22.", "172.23.",
    "172.24.", "172.25.", "172.26.", "172.27.",
    "172.28.", "172.29.", "172.30.", "172.31.",
    "127.0.0.1",     # 本地回环
]
```

### 设备指纹验证

每个设备生成唯一的 UUID 作为指纹，用于：
- 区分不同设备
- 防止设备欺骗
- 支持设备重连识别

## 性能优化

### 1. 并发扫描

局域网扫描采用并发方式，限制最大并发数为 64，避免：
- 网络拥塞
- 系统资源耗尽
- 扫描时间过长

### 2. 超时控制

| 操作 | 超时时间 |
|------|----------|
| Socket 连接 | 300ms |
| 响应等待 | 300ms |
| 设备离线判定 | 30s |

### 3. 定期重扫

每 15 秒执行一次局域网扫描，确保：
- 发现新上线设备
- 更新设备状态
- 补充多播发现可能遗漏的设备

## 故障排除

### 常见问题

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 无法发现设备 | 防火墙阻止 | 开放 UDP 53318 和 TCP 8765 端口 |
| Android 多播不工作 | MulticastLock 未获取 | 检查 WiFi 权限和原生代码 |
| 设备频繁掉线 | 网络不稳定 | 增加心跳频率或超时时间 |
| 扫描速度慢 | 网络延迟高 | 减少并发数或增加超时时间 |

### 防火墙配置

**Windows:**
```powershell
netsh advfirewall firewall add rule name="Typing Assistant UDP" dir=in action=allow protocol=UDP localport=53318
netsh advfirewall firewall add rule name="Typing Assistant TCP" dir=in action=allow protocol=TCP localport=8765
```

**macOS:**
```bash
# 临时关闭防火墙测试
sudo pfctl -d
```

**Linux:**
```bash
sudo ufw allow 53318/udp
sudo ufw allow 8765/tcp
```

## 与 LocalSend 的差异

| 特性 | 本项目 | LocalSend |
|------|--------|-----------|
| 多播端口 | 53318 | 53317 |
| 多播地址 | 224.0.0.168 | 224.0.0.167 |
| 主要用途 | 文字传输 | 文件传输 |
| 安全传输 | 可选 | HTTPS |
| 设备认证 | 指纹识别 | 指纹 + PIN |

## 未来改进

1. **安全增强**
   - 添加 TLS/SSL 加密
   - 实现设备配对码验证
   - 支持设备黑名单

2. **性能优化**
   - 智能扫描策略
   - 设备缓存持久化
   - 增量扫描

3. **功能扩展**
   - 支持文件传输
   - 多设备同步
   - 云端中继（跨网络）

## 参考资料

- [LocalSend GitHub](https://github.com/localsend/localsend)
- [RFC 1112 - Host Extensions for IP Multicasting](https://tools.ietf.org/html/rfc1112)
- [WebSocket Protocol RFC 6455](https://tools.ietf.org/html/rfc6455)
