import 'package:flutter/foundation.dart';

/// 连接状态枚举
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// 连接状态模型
class ConnectionModel extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _computerIp = '';
  String _computerName = '';
  String _errorMessage = '';
  DateTime? _connectedAt;

  // Getters
  ConnectionStatus get status => _status;
  String get computerIp => _computerIp;
  String get computerName => _computerName;
  String get errorMessage => _errorMessage;
  DateTime? get connectedAt => _connectedAt;

  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isDisconnected => _status == ConnectionStatus.disconnected;

  String get statusText {
    switch (_status) {
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.connecting:
        return '连接中...';
      case ConnectionStatus.disconnected:
        return '未连接';
      case ConnectionStatus.error:
        return '连接错误';
    }
  }

  // Setters
  void setConnecting() {
    _status = ConnectionStatus.connecting;
    _errorMessage = '';
    notifyListeners();
  }

  void setConnected(String ip, String name) {
    _status = ConnectionStatus.connected;
    _computerIp = ip;
    _computerName = name;
    _connectedAt = DateTime.now();
    _errorMessage = '';
    notifyListeners();
  }

  void setDisconnected() {
    _status = ConnectionStatus.disconnected;
    _connectedAt = null;
    notifyListeners();
  }

  void setError(String message) {
    _status = ConnectionStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = '';
    if (_status == ConnectionStatus.error) {
      _status = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }
}
