import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String platform;
  final String deviceType;
  final DateTime lastSeen;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.platform,
    this.deviceType = 'desktop',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json, String ip) {
    return DiscoveredDevice(
      id: json['id'] ?? '',
      name: json['name'] ?? '未知设备',
      ip: ip,
      port: json['port'] ?? 8765,
      platform: json['platform'] ?? 'unknown',
      deviceType: json['deviceType'] ?? 'desktop',
      lastSeen: DateTime.now(),
    );
  }

  @override
  String toString() => 'DiscoveredDevice(id: $id, name: $name, ip: $ip, port: $port)';
}

enum DiscoveryMethod {
  multicast,
  httpScan,
  manual,
}

class LocalSendDiscoveryService {
  static const String multicastAddress = '224.0.0.167';
  static const int multicastPort = 41317;
  static const int httpPort = 41317;
  static const int websocketPort = 8765;  // WebSocket 端口
  static const String apiVersion = 'v2';

  static const MethodChannel _multicastChannel = MethodChannel('com.example.typing_assistant/multicast');

  RawDatagramSocket? _multicastSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _rescanTimer;
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final Map<String, DiscoveredDevice> _discoveredDevices = {};
  bool _isRunning = false;
  bool _isScanning = false;
  bool _multicastLockAcquired = false;
  String? _localIp;
  String? _deviceId;

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;
  Stream<List<DiscoveredDevice>> get computersStream => _devicesController.stream;
  List<DiscoveredDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices.values.toList());
  List<DiscoveredDevice> get discoveredComputers => List.unmodifiable(_discoveredDevices.values.toList());
  bool get isRunning => _isRunning;
  bool get isScanning => _isScanning;

  LocalSendDiscoveryService() {
    _deviceId = _generateDeviceId();
  }

  String _generateDeviceId() {
    final random = Random();
    const hexDigits = '0123456789abcdef';
    return List.generate(8, (_) => hexDigits[random.nextInt(16)]).join();
  }

  Future<bool> _acquireMulticastLock() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final result = await _multicastChannel.invokeMethod('acquireMulticastLock');
      _multicastLockAcquired = result == true;
      debugPrint('MulticastLock 获取结果: $_multicastLockAcquired');
      return _multicastLockAcquired;
    } catch (e) {
      debugPrint('获取 MulticastLock 失败: $e');
      return false;
    }
  }

  Future<void> _releaseMulticastLock() async {
    if (!Platform.isAndroid || !_multicastLockAcquired) {
      return;
    }

    try {
      await _multicastChannel.invokeMethod('releaseMulticastLock');
      _multicastLockAcquired = false;
      debugPrint('MulticastLock 已释放');
    } catch (e) {
      debugPrint('释放 MulticastLock 失败: $e');
    }
  }

  Future<void> startDiscovery() async {
    if (_isRunning) {
      debugPrint('发现服务已在运行中，跳过');
      return;
    }

    await stopDiscovery();
    _isRunning = true;
    _isScanning = true;
    _discoveredDevices.clear();
    _devicesController.add([]);

    debugPrint('=== 开始 LocalSend 风格网络发现 ===');

    final multicastAcquired = await _acquireMulticastLock();
    if (!multicastAcquired && Platform.isAndroid) {
      debugPrint('警告: MulticastLock 获取失败，多播发现可能无法工作');
    }

    _localIp = await _getLocalIp();
    debugPrint('本机 IP: $_localIp');

    if (_localIp == null) {
      debugPrint('无法获取本机 IP，网络发现可能无法正常工作');
    }

    await _startMulticastListener();

    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isRunning) {
        _sendMulticastAnnounce();
      }
    });

    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });

    _sendProbeRequest();

    debugPrint('=== 开始 HTTP 扫描 ===');
    await _runHttpScan();
    debugPrint('=== HTTP 扫描完成 ===');

    _isScanning = false;
    debugPrint('=== 网络发现初始化完成，发现 ${_discoveredDevices.length} 台设备 ===');

    _rescanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isRunning && !_isScanning) {
        debugPrint('=== 定期重新扫描 ===');
        _runHttpScan();
        _sendProbeRequest();
      }
    });
  }

  Future<void> _startMulticastListener() async {
    try {
      _multicastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        multicastPort,
        reuseAddress: true,
        reusePort: true,
      );

      _multicastSocket!.broadcastEnabled = true;

      debugPrint('多播Socket已绑定，端口: ${_multicastSocket!.port}');

      try {
        final multicastGroup = InternetAddress(multicastAddress);
        _multicastSocket!.joinMulticast(multicastGroup);
        debugPrint('✓ 已加入多播组: $multicastAddress');
      } catch (e) {
        debugPrint('✗ 加入多播组失败: $e');
        debugPrint('  多播发现可能无法工作，将依赖 HTTP 扫描');
      }

      _multicastSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _multicastSocket!.receive();
          if (datagram != null) {
            _handleMulticastMessage(datagram);
          }
        }
      });

      debugPrint('✓ 多播监听器已启动');
    } catch (e) {
      debugPrint('启动多播监听器失败: $e');
    }
  }

  void _handleMulticastMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message);

      final type = data['type'];

      if (type == 'announce') {
        final device = data['device'];
        if (device != null) {
          final deviceIp = device['ip'] ?? datagram.address.address;
          final deviceId = device['id'];

          if (deviceId != _deviceId) {
            final discoveredDevice = DiscoveredDevice.fromJson(device, deviceIp);
            _addDevice(discoveredDevice);
            debugPrint('多播发现设备: ${discoveredDevice.name} @ $deviceIp');
          }
        }
      }
    } catch (e) {
    }
  }

  void _sendMulticastAnnounce() {
    if (_multicastSocket == null) return;

    try {
      final message = jsonEncode({
        'type': 'announce',
        'device': {
          'id': _deviceId,
          'name': '手机客户端',
          'ip': _localIp ?? '0.0.0.0',
          'port': 0,
          'platform': Platform.operatingSystem.toLowerCase(),
          'deviceType': 'mobile',
          'version': '1.0',
          'apiVersion': apiVersion,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _multicastSocket!.send(
        utf8.encode(message),
        InternetAddress(multicastAddress),
        multicastPort,
      );
    } catch (e) {
      debugPrint('发送多播宣告失败: $e');
    }
  }

  void _sendProbeRequest() {
    if (_multicastSocket == null) return;

    try {
      final message = jsonEncode({
        'type': 'probe',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _multicastSocket!.send(
        utf8.encode(message),
        InternetAddress(multicastAddress),
        multicastPort,
      );

      debugPrint('已发送探测请求');
    } catch (e) {
      debugPrint('发送探测请求失败: $e');
    }
  }

  Future<void> _runHttpScan() async {
    if (_localIp == null) {
      debugPrint('无法获取本机 IP，跳过网络扫描');
      return;
    }

    debugPrint('开始局域网扫描（WebSocket 端口 $websocketPort）...');

    final ipParts = _localIp!.split('.');
    if (ipParts.length != 4) return;

    final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
    final futures = <Future>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == _localIp) continue;

      futures.add(_checkWebSocketDevice(ip));

      if (futures.length >= 64) {  // 增加并发数加快扫描
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint('局域网扫描完成');
  }

  /// 检查 WebSocket 端口是否有服务运行
  Future<void> _checkWebSocketDevice(String ip) async {
    try {
      // 快速尝试连接 WebSocket 端口
      final socket = await Socket.connect(
        ip,
        websocketPort,
        timeout: const Duration(milliseconds: 300),  // 局域网内应该很快响应
      );

      debugPrint('✓ 发现服务: $ip:$websocketPort');

      // 发送 WebSocket 握手请求来验证
      final key = base64Encode(utf8.encode('typing_${DateTime.now().millisecondsSinceEpoch}'));
      final request = 'GET / HTTP/1.1\r\n'
          'Host: $ip:$websocketPort\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          '\r\n';

      socket.write(request);

      // 读取响应（使用简单的方式）
      List<int> response = [];
      try {
        response = await socket.first.timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => Uint8List(0),
        );
      } catch (_) {
        // 读取超时或失败
      }

      await socket.close();

      if (response.isNotEmpty) {
        final responseStr = utf8.decode(response, allowMalformed: true);
        // 检查是否是 WebSocket 握手成功响应
        if (responseStr.contains('101') || responseStr.contains('Switching Protocols')) {
          final deviceId = 'ws-${ip.hashCode}';
          if (!_discoveredDevices.containsKey(deviceId)) {
            final discoveredDevice = DiscoveredDevice(
              id: deviceId,
              name: '打字助手-$ip',
              ip: ip,
              port: websocketPort,
              platform: 'unknown',
              deviceType: 'desktop',
            );
            _addDevice(discoveredDevice);
            debugPrint('✓ 发现设备: ${discoveredDevice.name}');
          }
        }
      }
    } catch (e) {
      // 连接失败是正常的，大部分 IP 没有服务
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
            return ip;
          }
        }
      }
    } catch (e) {
      debugPrint('获取本机 IP 失败: $e');
    }
    return null;
  }

  void _addDevice(DiscoveredDevice device) {
    _discoveredDevices[device.id] = device;
    _devicesController.add(List.unmodifiable(_discoveredDevices.values.toList()));
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleIds = <String>[];

    for (final entry in _discoveredDevices.entries) {
      if (now.difference(entry.value.lastSeen).inSeconds > 30) {
        staleIds.add(entry.key);
      }
    }

    for (final id in staleIds) {
      _discoveredDevices.remove(id);
    }

    if (staleIds.isNotEmpty) {
      _devicesController.add(List.unmodifiable(_discoveredDevices.values.toList()));
    }
  }

  Future<void> stopDiscovery() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _rescanTimer?.cancel();
    _rescanTimer = null;

    if (_multicastSocket != null) {
      try {
        _multicastSocket!.close();
      } catch (e) {
      }
      _multicastSocket = null;
    }

    await _releaseMulticastLock();

    _isRunning = false;
    _isScanning = false;
  }

  Future<void> restartDiscovery() async {
    debugPrint('=== 重新开始网络发现 ===');
    
    _announceTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _rescanTimer?.cancel();
    _rescanTimer = null;

    if (_multicastSocket != null) {
      try {
        _multicastSocket!.close();
      } catch (e) {}
      _multicastSocket = null;
    }

    _isRunning = false;
    _isScanning = false;
    
    _discoveredDevices.clear();
    _devicesController.add([]);
    
    await startDiscovery();
  }

  void addDeviceManually(String ip, int port, {String name = '手动输入'}) {
    final device = DiscoveredDevice(
      id: 'manual-${ip.hashCode}',
      name: name,
      ip: ip,
      port: port,
      platform: 'manual',
      deviceType: 'manual',
    );
    _addDevice(device);
  }

  void dispose() {
    stopDiscovery();
    _devicesController.close();
  }
}

class DiscoveryServiceWrapper {
  final LocalSendDiscoveryService _discoveryService = LocalSendDiscoveryService();

  Stream<List<DiscoveredDevice>> get devicesStream => _discoveryService.devicesStream;
  List<DiscoveredDevice> get discoveredDevices => _discoveryService.discoveredDevices;
  bool get isScanning => _discoveryService.isScanning;

  Future<void> startDiscovery() => _discoveryService.startDiscovery();
  Future<void> stopDiscovery() => _discoveryService.stopDiscovery();
  Future<void> restartDiscovery() => _discoveryService.restartDiscovery();
  void addDeviceManually(String ip, int port, {String name = '手动输入'}) =>
      _discoveryService.addDeviceManually(ip, port, name: name);
  void dispose() => _discoveryService.dispose();
}

typedef DiscoveredComputer = DiscoveredDevice;

extension DiscoveredComputerExtension on List<DiscoveredComputer> {
  List<DiscoveredComputer> whereByIp(String ip) {
    return where((d) => d.ip == ip).toList();
  }
}
