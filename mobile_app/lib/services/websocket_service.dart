import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/connection_model.dart';
import '../utils/constants.dart';
import 'local_send_discovery_service.dart';

typedef DiscoveredComputer = DiscoveredDevice;

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final ConnectionModel _connectionModel = ConnectionModel();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  bool _isConnecting = false;

  ConnectionModel get connectionModel => _connectionModel;

  WebSocketService() {
    _connectionModel.addListener(() {
      notifyListeners();
    });
    _loadSavedConnection();
  }

  Future<void> _loadSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('last_connected_ip');
      final savedPort = prefs.getInt('last_connected_port') ?? Constants.websocketPort;

      if (savedIp != null && savedIp.isNotEmpty) {
        debugPrint('发现保存的 IP: $savedIp:$savedPort');
        final computer = DiscoveredComputer(
          fingerprint: 'saved-${savedIp.hashCode}',
          alias: '历史连接',
          ip: savedIp,
          port: savedPort,
          deviceModel: '',
          deviceType: 'manual',
        );
        Future.delayed(const Duration(seconds: 1), () {
          connect(computer, autoReconnect: false);
        });
      }
    } catch (e) {
      debugPrint('加载保存的连接信息失败：$e');
    }
  }

  Future<void> _saveConnection(String ip, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_ip', ip);
      await prefs.setInt('last_connected_port', port);
      debugPrint('已保存连接信息：$ip:$port');
    } catch (e) {
      debugPrint('保存连接信息失败：$e');
    }
  }

  Future<void> clearSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_connected_ip');
      await prefs.remove('last_connected_port');
    } catch (e) {
      debugPrint('清除连接信息失败：$e');
    }
  }

  Future<bool> connect(DiscoveredComputer computer, {bool autoReconnect = true}) async {
    if (_connectionModel.isConnected &&
        _connectionModel.computerIp == computer.ip) {
      debugPrint('已经连接到 $computer.ip，无需重复连接');
      return true;
    }

    if (_isConnecting) {
      debugPrint('正在连接中，但请求连接新 IP ${computer.ip}，取消当前连接');
      _reconnectTimer?.cancel();
      _shouldReconnect = false;
      _isConnecting = false;
      await disconnect();
    }

    _isConnecting = true;
    await disconnect();

    _connectionModel.setConnecting();
    _shouldReconnect = autoReconnect;

    final wsUrl = 'ws://${computer.ip}:${computer.port}';
    debugPrint('正在连接到：$wsUrl');

    try {
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        connectTimeout: const Duration(seconds: 5),
      );

      await _channel!.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('连接超时，请检查 IP 地址和端口是否正确');
        },
      );

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      try {
        await _saveConnection(computer.ip, computer.port).timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('保存连接信息超时，继续执行');
          },
        );
      } catch (e) {
        debugPrint('保存连接信息失败，继续执行: $e');
      }

      _connectionModel.setConnected(computer.ip, computer.alias);

      _startHeartbeat();

      _reconnectTimer?.cancel();

      debugPrint('连接成功：$wsUrl');
      _isConnecting = false;
      return true;
    } on TimeoutException catch (e) {
      debugPrint('连接超时：$e');
      _connectionModel.setError('连接超时，请检查:\n1. IP 地址是否正确\n2. 电脑端服务是否已启动\n3. 手机和电脑是否在同一网络');
      _isConnecting = false;
      if (autoReconnect) {
        _scheduleReconnect(computer);
      }
      return false;
    } catch (e) {
      debugPrint('连接失败: $e');
      _connectionModel.setError('连接失败: $e');
      _isConnecting = false;
      if (autoReconnect) {
        _scheduleReconnect(computer);
      }
      return false;
    }
  }

  Future<bool> connectManually(String ip, int port) async {
    final computer = DiscoveredComputer(
      fingerprint: 'manual-${ip.hashCode}',
      alias: '手动输入',
      ip: ip,
      port: port,
      deviceModel: '',
      deviceType: 'manual',
    );
    return await connect(computer, autoReconnect: true);
  }

  Future<bool> testConnection(String ip, int port) async {
    if (_connectionModel.isConnected && _connectionModel.computerIp == ip) {
      debugPrint('已经连接到 $ip，测试通过');
      return true;
    }

    final wsUrl = 'ws://$ip:$port';
    debugPrint('测试连接到：$wsUrl');

    WebSocketChannel? testChannel;
    try {
      testChannel = IOWebSocketChannel.connect(
        wsUrl,
        connectTimeout: const Duration(seconds: 5),
      );

      await testChannel.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('连接超时');
        },
      );

      final testMessage = {
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      testChannel.sink.add(jsonEncode(testMessage));

      final response = await testChannel.stream
          .firstWhere(
            (msg) {
              try {
                final data = jsonDecode(msg);
                return data['type'] == 'pong';
              } catch (_) {
                return false;
              }
            },
            orElse: () => null,
          )
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      await testChannel.sink.close();

      if (response != null) {
        debugPrint('连接测试成功');
        return true;
      } else {
        debugPrint('连接测试失败：未收到响应');
        _connectionModel.setError('连接测试失败：服务器无响应');
        return false;
      }
    } on TimeoutException catch (e) {
      debugPrint('连接测试超时: $e');
      _connectionModel.setError('连接超时，请检查:\n1. IP 地址是否正确\n2. 电脑端服务是否已启动');
      testChannel?.sink.close();
      return false;
    } catch (e) {
      debugPrint('连接测试失败: $e');
      _connectionModel.setError('连接失败: $e');
      testChannel?.sink.close();
      return false;
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      try {
        await _channel!.sink.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('关闭连接超时');
          },
        );
      } catch (e) {
        debugPrint('关闭连接时出错: $e');
      }
      _channel = null;
    }

    _connectionModel.setDisconnected();
  }

  Future<void> sendText(String text) async {
    if (_channel == null || !_connectionModel.isConnected) {
      throw Exception('未连接到电脑');
    }

    final message = {
      'type': 'text',
      'content': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
    debugPrint('发送文字: $text');
  }

  Future<void> sendOcrText(String text) async {
    if (_channel == null || !_connectionModel.isConnected) {
      throw Exception('未连接到电脑');
    }

    final message = {
      'type': 'ocr_text',
      'selected_text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
    debugPrint('发送 OCR 文字: $text');
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      switch (type) {
        case 'pong':
          debugPrint('收到心跳响应');
          break;
        case 'input_result':
          final success = data['success'] ?? false;
          final msg = data['message'] ?? '';
          debugPrint('输入结果: $success, $msg');
          break;
        default:
          debugPrint('收到未知类型消息: $type');
      }
    } catch (e) {
      debugPrint('解析消息失败: $e');
    }
  }

  void _onError(error) {
    debugPrint('WebSocket 错误：$error');
    _isConnecting = false;

    if (_connectionModel.isConnected || _connectionModel.isConnecting) {
      _connectionModel.setError('连接错误：$error');
    }
  }

  void _onDone() {
    debugPrint('WebSocket 连接已关闭');
    _isConnecting = false;

    if (!_connectionModel.isDisconnected) {
      _connectionModel.setDisconnected();
    }

    if (_shouldReconnect && _connectionModel.computerIp.isNotEmpty) {
      final computer = DiscoveredComputer(
        fingerprint: 'reconnect-${_connectionModel.computerIp.hashCode}',
        alias: _connectionModel.computerName,
        ip: _connectionModel.computerIp,
        port: Constants.websocketPort,
        deviceModel: '',
        deviceType: 'unknown',
      );
      _scheduleReconnect(computer);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_channel != null && _connectionModel.isConnected) {
        try {
          final message = {
            'type': 'ping',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          _channel!.sink.add(jsonEncode(message));
        } catch (e) {
          debugPrint('发送心跳失败: $e');
        }
      }
    });
  }

  void _scheduleReconnect(DiscoveredComputer computer) {
    _reconnectTimer?.cancel();
    debugPrint('${_shouldReconnect ? "将" : "不"}在 5 秒后重连');

    if (!_shouldReconnect) return;

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_shouldReconnect) {
        debugPrint('尝试重新连接...');
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
