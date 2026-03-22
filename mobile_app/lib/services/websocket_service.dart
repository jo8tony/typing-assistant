import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/connection_model.dart';
import '../utils/constants.dart';
import 'discovery_service.dart';

/// WebSocket 通信服务
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final ConnectionModel _connectionModel = ConnectionModel();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;

  ConnectionModel get connectionModel => _connectionModel;

  /// 连接到指定的电脑
  Future<void> connect(DiscoveredComputer computer) async {
    await disconnect();

    _connectionModel.setConnecting();
    _shouldReconnect = true;

    try {
      final wsUrl = 'ws://${computer.ip}:${computer.port}';
      print('正在连接到: $wsUrl');

      _channel = IOWebSocketChannel.connect(
        wsUrl,
        connectTimeout: const Duration(seconds: 10),
      );

      // 监听连接状态
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _connectionModel.setConnected(computer.ip, computer.name);

      // 启动心跳
      _startHeartbeat();

      // 取消重连定时器
      _reconnectTimer?.cancel();

    } catch (e) {
      print('连接失败: $e');
      _connectionModel.setError('连接失败: $e');
      _scheduleReconnect(computer);
    }
  }

  /// 手动连接到指定 IP
  Future<void> connectManually(String ip, int port) async {
    final computer = DiscoveredComputer(
      name: '手动输入',
      ip: ip,
      port: port,
      platform: 'manual',
    );
    await connect(computer);
  }

  /// 断开连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    _connectionModel.setDisconnected();
  }

  /// 发送文字到电脑
  Future<void> sendText(String text) async {
    if (_channel == null || !_connectionModel.isConnected) {
      throw Exception('未连接到电脑');
    }

    final message = {
      'type': Constants.msgTypeText,
      'content': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
    print('发送文字: $text');
  }

  /// 发送 OCR 文字到电脑
  Future<void> sendOcrText(String text) async {
    if (_channel == null || !_connectionModel.isConnected) {
      throw Exception('未连接到电脑');
    }

    final message = {
      'type': Constants.msgTypeOcrText,
      'selected_text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
    print('发送 OCR 文字: $text');
  }

  /// 处理收到的消息
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      switch (type) {
        case 'pong':
          // 心跳响应
          break;
        case 'input_result':
          final success = data['success'] ?? false;
          final msg = data['message'] ?? '';
          print('输入结果: $success, $msg');
          break;
        default:
          print('收到未知类型消息: $type');
      }
    } catch (e) {
      print('解析消息失败: $e');
    }
  }

  /// 处理错误
  void _onError(error) {
    print('WebSocket 错误: $error');
    _connectionModel.setError('连接错误: $error');
  }

  /// 连接关闭
  void _onDone() {
    print('WebSocket 连接已关闭');
    _connectionModel.setDisconnected();

    // 如果需要重连
    if (_shouldReconnect && _connectionModel.computerIp.isNotEmpty) {
      final computer = DiscoveredComputer(
        name: _connectionModel.computerName,
        ip: _connectionModel.computerIp,
        port: Constants.websocketPort,
        platform: 'unknown',
      );
      _scheduleReconnect(computer);
    }
  }

  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Constants.heartbeatInterval, (_) {
      if (_channel != null && _connectionModel.isConnected) {
        final message = {
          'type': Constants.msgTypePing,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        _channel!.sink.add(jsonEncode(message));
      }
    });
  }

  /// 安排重连
  void _scheduleReconnect(DiscoveredComputer computer) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Constants.reconnectInterval, () {
      if (_shouldReconnect) {
        print('尝试重新连接...');
        connect(computer);
      }
    });
  }

  @override
  void dispose() {
    disconnect();
    _connectionModel.dispose();
    super.dispose();
  }
}
