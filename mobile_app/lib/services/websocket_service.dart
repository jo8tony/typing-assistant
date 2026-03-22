import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/connection_model.dart';
import '../utils/constants.dart';
import 'discovery_service.dart';

/// 超时异常
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

/// WebSocket 通信服务
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final ConnectionModel _connectionModel = ConnectionModel();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false; // 默认不重连，手动连接时才重连
  bool _isConnecting = false; // 防止重复连接

  ConnectionModel get connectionModel => _connectionModel;

  WebSocketService() {
    // 监听连接模型的变化，并通知 UI 更新
    _connectionModel.addListener(() {
      notifyListeners();
    });
    // 加载保存的 IP 并尝试连接
    _loadSavedConnection();
  }

  /// 加载保存的连接信息
  Future<void> _loadSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('last_connected_ip');
      final savedPort = prefs.getInt('last_connected_port') ?? Constants.websocketPort;

      if (savedIp != null && savedIp.isNotEmpty) {
        print('发现保存的 IP: $savedIp:$savedPort');
        // 自动尝试连接（但不强制重连）
        final computer = DiscoveredComputer(
          name: '历史连接',
          ip: savedIp,
          port: savedPort,
          platform: 'manual',
        );
        // 延迟一点再连接，确保 UI 已经加载
        Future.delayed(const Duration(seconds: 1), () {
          connect(computer, autoReconnect: false);
        });
      }
    } catch (e) {
      print('加载保存的连接信息失败: $e');
    }
  }

  /// 保存连接信息
  Future<void> _saveConnection(String ip, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_ip', ip);
      await prefs.setInt('last_connected_port', port);
      print('已保存连接信息: $ip:$port');
    } catch (e) {
      print('保存连接信息失败: $e');
    }
  }

  /// 清除保存的连接信息
  Future<void> clearSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_connected_ip');
      await prefs.remove('last_connected_port');
    } catch (e) {
      print('清除连接信息失败: $e');
    }
  }

  /// 连接到指定的电脑
  Future<bool> connect(DiscoveredComputer computer, {bool autoReconnect = true}) async {
    // 防止重复连接
    if (_isConnecting) {
      print('正在连接中，忽略重复请求');
      return false;
    }

    // 如果已经连接到同一个地址，直接返回成功
    if (_connectionModel.isConnected &&
        _connectionModel.computerIp == computer.ip &&
        _connectionModel.computerName == computer.name) {
      print('已经连接到 $computer.ip，无需重复连接');
      return true;
    }

    _isConnecting = true;
    await disconnect();

    _connectionModel.setConnecting();
    _shouldReconnect = autoReconnect;

    final wsUrl = 'ws://${computer.ip}:${computer.port}';
    print('正在连接到: $wsUrl');

    try {
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        connectTimeout: const Duration(seconds: 5),
      );

      // 等待连接建立或超时
      await _channel!.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('连接超时，请检查 IP 地址和端口是否正确');
        },
      );

      // 监听连接状态 - 使用 cancelOnError: false 确保 onDone 能被调用
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // 保存连接信息
      await _saveConnection(computer.ip, computer.port);

      _connectionModel.setConnected(computer.ip, computer.name);

      // 启动心跳
      _startHeartbeat();

      // 取消重连定时器
      _reconnectTimer?.cancel();

      print('连接成功: $wsUrl');
      _isConnecting = false;
      return true;
    } on TimeoutException catch (e) {
      print('连接超时: $e');
      _connectionModel.setError('连接超时，请检查:\n1. IP 地址是否正确\n2. 电脑端服务是否已启动\n3. 手机和电脑是否在同一网络');
      _isConnecting = false;
      if (autoReconnect) {
        _scheduleReconnect(computer);
      }
      return false;
    } catch (e) {
      print('连接失败: $e');
      _connectionModel.setError('连接失败: $e');
      _isConnecting = false;
      if (autoReconnect) {
        _scheduleReconnect(computer);
      }
      return false;
    }
  }

  /// 手动连接到指定 IP
  Future<bool> connectManually(String ip, int port) async {
    final computer = DiscoveredComputer(
      name: '手动输入',
      ip: ip,
      port: port,
      platform: 'manual',
    );
    return await connect(computer, autoReconnect: true);
  }

  /// 断开连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        print('关闭连接时出错: $e');
      }
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
          print('收到心跳响应');
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
    // 只有在已连接状态下才设置为错误，避免覆盖正在连接的状态
    if (_connectionModel.isConnected) {
      _connectionModel.setError('连接错误: $error');
    }
  }

  /// 连接关闭
  void _onDone() {
    print('WebSocket 连接已关闭');
    // 只有在已连接或错误状态下才设置为断开
    if (_connectionModel.isConnected || _connectionModel.status == ConnectionStatus.error) {
      _connectionModel.setDisconnected();
    }

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
        try {
          final message = {
            'type': Constants.msgTypePing,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          _channel!.sink.add(jsonEncode(message));
        } catch (e) {
          print('发送心跳失败: $e');
        }
      }
    });
  }

  /// 安排重连
  void _scheduleReconnect(DiscoveredComputer computer) {
    _reconnectTimer?.cancel();
    print('${_shouldReconnect ? "将" : "不"}在 ${Constants.reconnectInterval.inSeconds} 秒后重连');

    if (!_shouldReconnect) return;

    _reconnectTimer = Timer(Constants.reconnectInterval, () {
      if (_shouldReconnect) {
        print('尝试重新连接...');
        connect(computer, autoReconnect: true);
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
