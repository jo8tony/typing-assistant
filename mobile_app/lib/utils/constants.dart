class Constants {
  static const String websocketHost = '0.0.0.0';
  static const int websocketPort = 8765;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration reconnectInterval = Duration(seconds: 5);

  static const String multicastAddress = '224.0.0.168';
  static const int multicastPort = 53318;
  static const String apiVersion = 'v1';
  static const Duration announceInterval = Duration(seconds: 2);
  static const Duration deviceTimeout = Duration(seconds: 30);

  static const String mdnsServiceType = '_typing._tcp.local.';

  static const String msgTypeText = 'text';
  static const String msgTypeOcrText = 'ocr_text';
  static const String msgTypePing = 'ping';
  static const String msgTypePong = 'pong';
  static const String msgTypeInputResult = 'input_result';

  static const String statusConnected = '已连接';
  static const String statusDisconnected = '未连接';
  static const String statusConnecting = '连接中...';

  static const double fontSizeSmall = 16.0;
  static const double fontSizeNormal = 20.0;
  static const double fontSizeLarge = 24.0;
  static const double fontSizeXLarge = 32.0;

  static const double paddingSmall = 8.0;
  static const double paddingNormal = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  static const double buttonHeight = 60.0;
  static const double buttonHeightLarge = 80.0;
}
