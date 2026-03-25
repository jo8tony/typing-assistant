import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DiscoveredDevice {
  final String fingerprint;
  final String alias;
  final String ip;
  final int port;
  final String deviceModel;
  final String deviceType;
  final String version;
  final String protocol;
  final DateTime lastSeen;

  DiscoveredDevice({
    required this.fingerprint,
    required this.alias,
    required this.ip,
    required this.port,
    required this.deviceModel,
    required this.deviceType,
    this.version = '1.0',
    this.protocol = 'ws',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory DiscoveredDevice.fromAnnounce(Map<String, dynamic> json, String ip) {
    return DiscoveredDevice(
      fingerprint: json['fingerprint'] ?? '',
      alias: json['alias'] ?? '未知设备',
      ip: ip,
      port: json['port'] ?? 8765,
      deviceModel: json['deviceModel'] ?? '',
      deviceType: json['deviceType'] ?? 'desktop',
      version: json['version'] ?? '1.0',
      protocol: json['protocol'] ?? 'ws',
      lastSeen: DateTime.now(),
    );
  }

  String get id => fingerprint;

  String get name => alias;

  String get platform => deviceType;

  @override
  String toString() => 'DiscoveredDevice($alias @ $ip:$port)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}

class DiscoveryConstants {
  static const String multicastAddress = '224.0.0.167';
  static const int multicastPort = 53317;
  static const int websocketPort = 8765;
  static const Duration announceInterval = Duration(seconds: 2);
  static const Duration cleanupInterval = Duration(seconds: 10);
  static const Duration deviceTimeout = Duration(seconds: 30);
}

class DiscoveryService extends ChangeNotifier {
  static const MethodChannel _multicastChannel =
      MethodChannel('com.example.typing_assistant/multicast');

  RawDatagramSocket? _multicastSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _rescanTimer;

  final Map<String, DiscoveredDevice> _discoveredDevices = {};
  final StreamController<List<DiscoveredDevice>> _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  bool _isRunning = false;
  bool _isScanning = false;
  bool _multicastLockAcquired = false;
  String? _localIp;
  late String _fingerprint;
  int _announceCount = 0;

  String get fingerprint => _fingerprint;
  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;
  Stream<List<DiscoveredDevice>> get computersStream => _devicesController.stream;
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices.values.toList());
  List<DiscoveredDevice> get discoveredComputers => discoveredDevices;
  bool get isRunning => _isRunning;
  bool get isScanning => _isScanning;

  DiscoveryService() {
    _fingerprint = _generateFingerprint();
  }

  String _generateFingerprint() {
    final random = Random();
    const hexDigits = '0123456789abcdef';
    return List.generate(32, (_) => hexDigits[random.nextInt(16)]).join();
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

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('启动 LocalSend 风格网络发现');
    debugPrint('════════════════════════════════════════════════════');

    final multicastAcquired = await _acquireMulticastLock();
    if (!multicastAcquired && Platform.isAndroid) {
      debugPrint('警告: MulticastLock 获取失败，多播发现可能无法工作');
    }

    _localIp = await _getLocalIp();
    debugPrint('  本机 IP: $_localIp');
    debugPrint('  设备指纹: ${_fingerprint.substring(0, 8)}...');
    debugPrint('  多播地址: ${DiscoveryConstants.multicastAddress}:${DiscoveryConstants.multicastPort}');
    debugPrint('');

    await _startMulticastListener();

    _announceTimer = Timer.periodic(DiscoveryConstants.announceInterval, (_) {
      if (_isRunning) {
        _sendAnnounce();
      }
    });

    _cleanupTimer = Timer.periodic(DiscoveryConstants.cleanupInterval, (_) {
      _cleanupStaleDevices();
    });

    _sendAnnounce();

    debugPrint('开始局域网扫描...');
    await _runNetworkScan();
    debugPrint('局域网扫描完成');

    _isScanning = false;
    debugPrint('');
    debugPrint('发现服务初始化完成，发现 ${_discoveredDevices.length} 台设备');
    debugPrint('');

    _rescanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isRunning && !_isScanning) {
        debugPrint('定期重新扫描...');
        _runNetworkScan();
      }
    });
  }

  Future<void> _startMulticastListener() async {
    try {
      _multicastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        DiscoveryConstants.multicastPort,
        reuseAddress: true,
        reusePort: true,
      );

      _multicastSocket!.broadcastEnabled = true;

      debugPrint('多播 Socket 已绑定，端口: ${_multicastSocket!.port}');

      try {
        final multicastGroup =
            InternetAddress(DiscoveryConstants.multicastAddress);
        _multicastSocket!.joinMulticast(multicastGroup);
        debugPrint('✓ 已加入多播组: ${DiscoveryConstants.multicastAddress}');
      } catch (e) {
        debugPrint('✗ 加入多播组失败: $e');
        debugPrint('  多播发现可能无法工作，将依赖网络扫描');
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
      debugPrint('收到多播消息: ${message.length} bytes from ${datagram.address.address}');

      final json = jsonDecode(message);

      if (json is Map<String, dynamic> && json['announce'] == true) {
        final fingerprint = json['fingerprint'] as String?;
        if (fingerprint != null && fingerprint != _fingerprint) {
          final deviceIp = json['ip'] ?? datagram.address.address;
          final device = DiscoveredDevice.fromAnnounce(json, deviceIp);
          _addDevice(device);
          debugPrint('✓ 多播发现设备: ${device.alias} @ ${device.ip}');
        }
      }
    } catch (e) {
      // 忽略解析错误
    }
  }

  void _sendAnnounce() {
    if (_multicastSocket == null) return;

    try {
      final message = jsonEncode({
        'announce': true,
        'fingerprint': _fingerprint,
        'alias': '手机客户端',
        'version': '1.0.0',
        'deviceModel': 'Mobile',
        'deviceType': 'mobile',
        'port': 0,
        'protocol': 'ws',
        'download': false,
        'ip': _localIp ?? '0.0.0.0',
      });

      _multicastSocket!.send(
        utf8.encode(message),
        InternetAddress(DiscoveryConstants.multicastAddress),
        DiscoveryConstants.multicastPort,
      );

      _announceCount++;
      if (_announceCount % 5 == 0) {
        debugPrint('  [广播] #$_announceCount 已发送');
      }
    } catch (e) {
      debugPrint('发送宣告失败: $e');
    }
  }

  Future<void> _runNetworkScan() async {
    if (_localIp == null) {
      debugPrint('无法获取本机 IP，跳过网络扫描');
      return;
    }

    final ipParts = _localIp!.split('.');
    if (ipParts.length != 4) return;

    final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
    final futures = <Future>[];

    debugPrint('扫描子网: $subnet.*');

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == _localIp) continue;

      futures.add(_checkDevice(ip));

      if (futures.length >= 64) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> _checkDevice(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        DiscoveryConstants.websocketPort,
        timeout: const Duration(milliseconds: 300),
      );

      final key = base64Encode(
          utf8.encode('typing_${DateTime.now().millisecondsSinceEpoch}'));
      final request = 'GET / HTTP/1.1\r\n'
          'Host: $ip:${DiscoveryConstants.websocketPort}\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          '\r\n';

      socket.write(request);

      List<int> response = [];
      try {
        response = await socket.first.timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => Uint8List(0),
        );
      } catch (_) {}

      await socket.close();

      if (response.isNotEmpty) {
        final responseStr = utf8.decode(response, allowMalformed: true);
        if (responseStr.contains('101') ||
            responseStr.contains('Switching Protocols')) {
          final device = DiscoveredDevice(
            fingerprint: 'ws-${ip.hashCode}',
            alias: '打字助手-$ip',
            ip: ip,
            port: DiscoveryConstants.websocketPort,
            deviceModel: 'Desktop',
            deviceType: 'desktop',
          );
          _addDevice(device);
          debugPrint('✓ 扫描发现设备: ${device.alias}');
        }
      }
    } catch (e) {
      // 连接失败是正常的
    }
  }

  void _addDevice(DiscoveredDevice device) {
    final existing = _discoveredDevices[device.fingerprint];
    if (existing == null || existing.ip != device.ip) {
      _discoveredDevices[device.fingerprint] = device;
      _devicesController.add(List.unmodifiable(_discoveredDevices.values.toList()));
      notifyListeners();
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleKeys = <String>[];

    for (final entry in _discoveredDevices.entries) {
      if (now.difference(entry.value.lastSeen) >
          DiscoveryConstants.deviceTimeout) {
        staleKeys.add(entry.key);
      }
    }

    for (final key in staleKeys) {
      _discoveredDevices.remove(key);
    }

    if (staleKeys.isNotEmpty) {
      _devicesController.add(List.unmodifiable(_discoveredDevices.values.toList()));
      notifyListeners();
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
      } catch (e) {}
      _multicastSocket = null;
    }

    await _releaseMulticastLock();

    _isRunning = false;
    _isScanning = false;
  }

  Future<void> restartDiscovery() async {
    debugPrint('重新开始网络发现...');

    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _rescanTimer?.cancel();

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
      fingerprint: 'manual-${ip.hashCode}',
      alias: name,
      ip: ip,
      port: port,
      deviceModel: 'Manual',
      deviceType: 'manual',
    );
    _addDevice(device);
  }

  @override
  void dispose() {
    stopDiscovery();
    _devicesController.close();
    super.dispose();
  }
}

typedef DiscoveredComputer = DiscoveredDevice;

typedef LocalSendDiscoveryService = DiscoveryService;
