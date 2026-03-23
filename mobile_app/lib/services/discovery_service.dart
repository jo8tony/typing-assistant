import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../utils/constants.dart';

/// 发现的电脑设备
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

/// mDNS 局域网发现服务
class DiscoveryService {
  MDnsClient? _client;
  Timer? _searchTimer;
  final _computersController = StreamController<List<DiscoveredComputer>>.broadcast();
  final List<DiscoveredComputer> _discoveredComputers = [];
  bool _isScanning = false;

  Stream<List<DiscoveredComputer>> get computersStream => _computersController.stream;
  List<DiscoveredComputer> get discoveredComputers => List.unmodifiable(_discoveredComputers);
  bool get isScanning => _isScanning;

  /// 开始搜索局域网内的电脑
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _isScanning = true;

    // 启动 mDNS 发现
    _startMdnsDiscovery();

    // 同时启动局域网扫描作为备用
    _startNetworkScan();
  }

  /// 启动 mDNS 发现
  Future<void> _startMdnsDiscovery() async {
    try {
      _client = MDnsClient();
      await _client!.start();

      // 立即搜索一次
      await _searchMdnsServices();

      // 每 5 秒搜索一次
      _searchTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _searchMdnsServices();
      });
    } catch (e) {
      debugPrint('mDNS 启动失败：$e');
    }
  }

  /// 搜索 mDNS 服务
  Future<void> _searchMdnsServices() async {
    if (_client == null) return;

    try {
      await for (final PtrResourceRecord ptr in _client!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(Constants.mdnsServiceType),
      )) {
        final serviceName = ptr.domainName;

        // 获取 SRV 记录
        await for (final SrvResourceRecord srv in _client!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(serviceName),
        )) {
          // 获取 IP 地址
          await for (final IPAddressResourceRecord ip in _client!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            // 获取 TXT 记录
            String platform = 'unknown';
            await for (final TxtResourceRecord txt in _client!.lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(serviceName),
            )) {
              // txt.text 是 List<int> 类型，需要解码
              final text = utf8.decode(txt.text as List<int>);
              if (text.contains('platform=')) {
                platform = text.split('platform=')[1].split(',')[0];
              }
            }

            final computer = DiscoveredComputer(
              name: serviceName.replaceAll('.${Constants.mdnsServiceType}.local.', ''),
              ip: ip.address.address,
              port: srv.port,
              platform: platform,
            );

            _addComputer(computer);
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS 搜索出错：$e');
    }
  }

  /// 启动局域网扫描（作为 mDNS 的备用）
  Future<void> _startNetworkScan() async {
    // 获取本机 IP 地址
    final localIp = await _getLocalIp();
    if (localIp == null) {
      debugPrint('无法获取本机 IP，跳过局域网扫描');
      return;
    }

    debugPrint('本机 IP: $localIp，开始扫描局域网...');

    // 解析 IP 段
    final ipParts = localIp.split('.');
    if (ipParts.length != 4) return;

    final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

    // 扫描同网段的 IP（1-254）
    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      // 排除本机
      if (ip == localIp) continue;

      futures.add(_checkWebSocketService(ip));

      // 每 20 个 IP 一批，避免并发过多
      if (futures.length >= 20) {
        await Future.wait(futures);
        futures.clear();
        // 小延迟，避免网络拥塞
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    // 处理剩余的
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint('局域网扫描完成');
  }

  /// 检查指定 IP 是否有 WebSocket 服务
  Future<void> _checkWebSocketService(String ip) async {
    try {
      final socket = await Socket.connect(ip, Constants.websocketPort,
          timeout: const Duration(milliseconds: 500));

      // 发送 WebSocket 握手请求
      final request =
          'GET / HTTP/1.1\r\nHost: $ip:${Constants.websocketPort}\r\n'
          'Upgrade: websocket\r\nConnection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n\r\n';

      socket.write(request);

      // 等待响应
      await socket.listen((data) {
        final responseStr = utf8.decode(data);
        if (responseStr.contains('HTTP/1.1 101') ||
            responseStr.contains('Upgrade: websocket') ||
            responseStr.contains('Sec-WebSocket-Accept')) {
          // 这是一个 WebSocket 服务
          final computer = DiscoveredComputer(
            name: '电脑 (${ip.split('.').last})',
            ip: ip,
            port: Constants.websocketPort,
            platform: 'unknown',
          );
          _addComputer(computer);
        }
        socket.destroy();
      }).asFuture().timeout(const Duration(seconds: 1));

    } catch (e) {
      // 连接失败或不是 WebSocket 服务，忽略
    }
  }

  /// 获取本机 IP 地址
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          // 排除回环地址和本地链路地址
          if (!ip.startsWith('127.') &&
              !ip.startsWith('169.254.') &&
              !ip.startsWith('0.')) {
            debugPrint('找到本机 IP: $ip (接口: ${interface.name})');
            return ip;
          }
        }
      }
    } catch (e) {
      debugPrint('获取本机 IP 失败: $e');
    }
    return null;
  }

  /// 添加电脑到列表
  void _addComputer(DiscoveredComputer computer) {
    if (!_discoveredComputers.any((c) => c.ip == computer.ip)) {
      _discoveredComputers.add(computer);
      _computersController.add(List.unmodifiable(_discoveredComputers));
      debugPrint('发现新服务: ${computer.name} (${computer.ip})');
    }
  }

  /// 停止发现服务
  Future<void> stopDiscovery() async {
    _searchTimer?.cancel();
    _searchTimer = null;
    _client?.stop();
    _client = null;
    _discoveredComputers.clear();
    _isScanning = false;
  }

  /// 重新启动发现服务（用于刷新扫描）
  Future<void> restartDiscovery() async {
    _discoveredComputers.clear();
    _computersController.add([]);
    await startDiscovery();
  }

  /// 手动添加电脑（如果 mDNS 不可用）
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
