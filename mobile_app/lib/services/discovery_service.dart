import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';

class DiscoveredComputer {
  final String name;
  final String ip;
  final int port;
  final String platform;

  DiscoveredComputer({
    required this.name,
    required this.ip,
    required this.port,
    required this.platform,
  });

  @override
  String toString() => 'DiscoveredComputer(name: $name, ip: $ip, port: $port)';
}

class DiscoveryService {
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;
  Timer? _queryTimer;
  final _computersController = StreamController<List<DiscoveredComputer>>.broadcast();
  final List<DiscoveredComputer> _discoveredComputers = [];
  bool _isScanning = false;

  static const int broadcastPort = 8766;
  static const Duration broadcastInterval = Duration(seconds: 2);

  Stream<List<DiscoveredComputer>> get computersStream => _computersController.stream;
  List<DiscoveredComputer> get discoveredComputers => List.unmodifiable(_discoveredComputers);
  bool get isScanning => _isScanning;

  Future<void> startDiscovery() async {
    await stopDiscovery();
    _isScanning = true;
    _discoveredComputers.clear();
    _computersController.add([]);

    debugPrint('开始网络发现...');
    debugPrint('UDP 广播端口：$broadcastPort');

    await _startUdpDiscovery();
    await _startNetworkScan();

    _isScanning = false;
    debugPrint('网络发现完成，发现 ${_discoveredComputers.length} 个服务');
  }

  Future<void> _startUdpDiscovery() async {
    try {
      debugPrint('正在启动 UDP 广播...');
      
      // 绑定到一个随机端口用于接收
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      
      _udpSocket!.broadcastEnabled = true;
      
      // 监听 UDP 消息
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleUdpMessage(datagram);
          }
        }
      });
      
      debugPrint('UDP socket 已启动，端口：${_udpSocket!.port}');
      
      // 立即发送查询
      unawaited(_sendBroadcastQuery());
      
      // 定期发送查询
      _queryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isScanning) {
          unawaited(_sendBroadcastQuery());
        }
      });
      
    } catch (e, stackTrace) {
      debugPrint('UDP 启动失败：$e');
      debugPrint('堆栈：$stackTrace');
      rethrow;
    }
  }

  Future<void> _sendBroadcastQuery() async {
    if (_udpSocket == null) return;

    try {
      final query = jsonEncode({
        'type': 'query',
        'data': {
          'client': 'mobile',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      });

      debugPrint('发送广播查询到端口 $broadcastPort...');
      
      // 发送到广播地址
      _udpSocket!.send(
        utf8.encode(query),
        InternetAddress(
          '255.255.255.255',
          type: InternetAddressType.IPv4,
        ),
        broadcastPort,
      );
      
      debugPrint('广播查询已发送');
      
    } catch (e) {
      debugPrint('发送广播失败：$e');
    }
  }

  void _handleUdpMessage(Datagram datagram) {
    try {
      debugPrint('收到 UDP 消息：${datagram.data.length} bytes, 来自 ${datagram.address.address}:${datagram.port}');
      
      final message = utf8.decode(datagram.data);
      debugPrint('消息内容：$message');
      
      final data = jsonDecode(message);
      
      final type = data['type'];
      debugPrint('消息类型：$type');
      
      if (type == 'discovery' || type == 'response') {
        final serverData = data['data'];
        if (serverData != null) {
          final computer = DiscoveredComputer(
            name: serverData['name'] ?? '未知电脑',
            ip: serverData['ip'] ?? datagram.address.address,
            port: serverData['port'] ?? Constants.websocketPort,
            platform: serverData['platform'] ?? 'unknown',
          );
          
          debugPrint('收到${type == 'discovery' ? '广播' : '响应'}: ${computer.name} (${computer.ip}:${computer.port})');
          _addComputer(computer);
        } else {
          debugPrint('警告：消息中没有 data 字段');
        }
      } else {
        debugPrint('忽略未知类型的消息：$type');
      }
    } catch (e) {
      debugPrint('处理 UDP 消息失败：$e');
    }
  }

  Future<void> _startNetworkScan() async {
    final localIp = await _getLocalIp();
    if (localIp == null) {
      debugPrint('无法获取本机 IP，跳过局域网扫描');
      return;
    }

    debugPrint('本机 IP: $localIp，开始扫描局域网...');

    final ipParts = localIp.split('.');
    if (ipParts.length != 4) return;

    final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == localIp) continue;

      futures.add(_checkWebSocketService(ip));

      if (futures.length >= 30) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint('局域网扫描完成');
  }

  Future<void> _checkWebSocketService(String ip) async {
    try {
      final socket = await Socket.connect(ip, Constants.websocketPort,
          timeout: const Duration(milliseconds: 800));

      final request =
          'GET / HTTP/1.1\r\nHost: $ip:${Constants.websocketPort}\r\n'
          'Upgrade: websocket\r\nConnection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n\r\n';

      socket.write(request);

      await socket.listen((data) {
        final responseStr = utf8.decode(data);
        if (responseStr.contains('HTTP/1.1 101') ||
            responseStr.contains('Upgrade: websocket') ||
            responseStr.contains('Sec-WebSocket-Accept')) {
          final computer = DiscoveredComputer(
            name: '电脑 (${ip.split('.').last})',
            ip: ip,
            port: Constants.websocketPort,
            platform: 'unknown',
          );
          _addComputer(computer);
          debugPrint('IP 扫描发现服务：$ip');
        }
        socket.destroy();
      }).asFuture().timeout(const Duration(seconds: 2));

    } catch (e) {
    }
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('127.') &&
              !ip.startsWith('169.254.') &&
              !ip.startsWith('0.')) {
            debugPrint('找到本机 IP: $ip (接口：${interface.name})');
            return ip;
          }
        }
      }
    } catch (e) {
      debugPrint('获取本机 IP 失败：$e');
    }
    return null;
  }

  void _addComputer(DiscoveredComputer computer) {
    if (!_discoveredComputers.any((c) => c.ip == computer.ip)) {
      _discoveredComputers.add(computer);
      _computersController.add(List.unmodifiable(_discoveredComputers));
      debugPrint('发现新服务：${computer.name} (${computer.ip})');
    }
  }

  Future<void> stopDiscovery() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _queryTimer?.cancel();
    _queryTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _discoveredComputers.clear();
    _isScanning = false;
  }

  Future<void> restartDiscovery() async {
    _discoveredComputers.clear();
    _computersController.add([]);
    await startDiscovery();
  }

  void addComputerManually(String name, String ip, int port) {
    final computer = DiscoveredComputer(
      name: name,
      ip: ip,
      port: port,
      platform: 'manual',
    );

    _addComputer(computer);
  }

  void dispose() {
    stopDiscovery();
    _computersController.close();
  }
}
