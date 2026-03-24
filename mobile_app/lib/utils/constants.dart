// 常量定义

class Constants {
  // WebSocket 配置
  static const String websocketHost = '0.0.0.0';
  static const int websocketPort = 8765;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration reconnectInterval = Duration(seconds: 5);

  // LocalSend 风格网络发现配置
  static const String multicastAddress = '224.0.0.167';
  static const int multicastPort = 41317;
  static const int discoveryHttpPort = 41317;
  static const String apiVersion = 'v2';

  // mDNS 配置 (保留用于兼容)
  static const String mdnsServiceType = '_typing._tcp.local.';

  // 消息类型
  static const String msgTypeText = 'text';
  static const String msgTypeOcrText = 'ocr_text';
  static const String msgTypePing = 'ping';
  static const String msgTypePong = 'pong';
  static const String msgTypeInputResult = 'input_result';

  // 连接状态
  static const String statusConnected = '已连接';
  static const String statusDisconnected = '未连接';
  static const String statusConnecting = '连接中...';

  // 字体大小 (适合中年人)
  static const double fontSizeSmall = 16.0;
  static const double fontSizeNormal = 20.0;
  static const double fontSizeLarge = 24.0;
  static const double fontSizeXLarge = 32.0;

  // 间距
  static const double paddingSmall = 8.0;
  static const double paddingNormal = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // 按钮高度
  static const double buttonHeight = 60.0;
  static const double buttonHeightLarge = 80.0;
}
