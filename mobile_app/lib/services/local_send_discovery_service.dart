import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

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
  static const String apiVersion = 'v2';

  RawDatagramSocket? _multicastSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _httpScanTimer;
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final Map<String, DiscoveredDevice> _discoveredDevices = {};
  bool _isRunning = false;
  bool _isScanning = false;
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

  Future<void> startDiscovery() async {
    if (_isRunning) return;

    await stopDiscovery();
    _isRunning = true;
    _isScanning = true;
    _discoveredDevices.clear();
    _devicesController.add([]);

    debugPrint('=== 开始 LocalSend 风格网络发现 ===');

    _localIp = await _getLocalIp();
    debugPrint('本机 IP: $_localIp');

    _startMulticastListener();

    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isRunning) {
        _sendMulticastAnnounce();
      }
    });

    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });

    _httpScanTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isRunning) {
        _runHttpScan();
      }
    });

    await Future.delayed(const Duration(seconds: 1));
    _sendProbeRequest();

    _isScanning = false;
    debugPrint('=== 网络发现初始化完成 ===');
  }

  void _startMulticastListener() {
    RawDatagramSocket.bind(InternetAddress.anyIPv4, multicastPort, reuseAddress: true, reusePort: true)
        .then((socket) {
      _multicastSocket = socket;
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            _handleMulticastMessage(datagram);
          }
        }
      });

      debugPrint('多播监听器已启动，端口: ${socket.port}');
    }).catchError((e) {
      debugPrint('启动多播监听器失败: $e');
    });
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
      debugPrint('无法获取本机 IP，跳过 HTTP 扫描');
      return;
    }

    debugPrint('开始 HTTP 局域网扫描...');

    final ipParts = _localIp!.split('.');
    if (ipParts.length != 4) return;

    final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
    final futures = <Future>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == _localIp) continue;

      futures.add(_checkHttpDevice(ip));

      if (futures.length >= 20) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint('HTTP 扫描完成');
  }

  Future<void> _checkHttpDevice(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        httpPort,
        timeout: const Duration(milliseconds: 500),
      );

      final request = 'GET /api/$apiVersion/info HTTP/1.1\r\nHost: $ip:$httpPort\r\nConnection: close\r\n\r\n';

      socket.write(request);

      final response = await socket.fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );

      await socket.close();

      final responseStr = utf8.decode(response, allowMalformed: true);

      if (responseStr.contains('HTTP/1.1 200') || responseStr.contains('HTTP/1.0 200')) {
        final jsonStart = responseStr.indexOf('{');
        final jsonEnd = responseStr.lastIndexOf('}');

        if (jsonStart != -1 && jsonEnd != -1) {
          final jsonStr = responseStr.substring(jsonStart, jsonEnd + 1);
          final data = jsonDecode(jsonStr);

          if (data['type'] == 'info') {
            final device = data['device'];
            if (device != null) {
              final deviceId = device['id'];
              if (deviceId != _deviceId && !_discoveredDevices.containsKey(deviceId)) {
                final discoveredDevice = DiscoveredDevice.fromJson(device, ip);
                _addDevice(discoveredDevice);
                debugPrint('HTTP 发现设备: ${discoveredDevice.name} @ $ip');
              }
            }
          }
        }
      }
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
    _httpScanTimer?.cancel();
    _httpScanTimer = null;

    if (_multicastSocket != null) {
      try {
        _multicastSocket!.close();
      } catch (e) {
      }
      _multicastSocket = null;
    }

    _isRunning = false;
    _isScanning = false;
  }

  Future<void> restartDiscovery() async {
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