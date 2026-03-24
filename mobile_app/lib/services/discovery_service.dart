import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
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
  MDnsClient? _client;
  Timer? _searchTimer;
  final _computersController = StreamController<List<DiscoveredComputer>>.broadcast();
  final List<DiscoveredComputer> _discoveredComputers = [];
  bool _isScanning = false;

  Stream<List<DiscoveredComputer>> get computersStream => _computersController.stream;
  List<DiscoveredComputer> get discoveredComputers => List.unmodifiable(_discoveredComputers);
  bool get isScanning => _isScanning;

  Future<void> startDiscovery() async {
    await stopDiscovery();
    _isScanning = true;
    _discoveredComputers.clear();
    _computersController.add([]);

    debugPrint('开始网络发现...');

    await Future.wait([
      _startMdnsDiscovery(),
      _startNetworkScan(),
    ]);

    _isScanning = false;
    debugPrint('网络发现完成，发现 ${_discoveredComputers.length} 个服务');
  }

  Future<void> _startMdnsDiscovery() async {
    try {
      _client = MDnsClient();
      await _client!.start();
      debugPrint('mDNS 客户端已启动');

      unawaited(_searchMdnsServices());

      _searchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isScanning) {
          unawaited(_searchMdnsServices());
        }
      });
    } catch (e) {
      debugPrint('mDNS 启动失败：$e');
      rethrow;
    }
  }

  Future<void> _searchMdnsServices() async {
    if (_client == null) return;

    try {
      debugPrint('开始 mDNS 搜索...');
      
      // 直接查询 _typing._tcp.local. 域下的所有服务实例
      final ptrRecords = await _client!
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(Constants.mdnsServiceType),
          )
          .timeout(
            const Duration(seconds: 3),
            onTimeout: (EventSink<PtrResourceRecord> sink) {
              sink.close();
            },
          )
          .toList();
      
      debugPrint('mDNS PTR 查询完成，发现 ${ptrRecords.length} 个服务');
      
      for (final ptr in ptrRecords) {
        try {
          final serviceName = ptr.domainName;
          debugPrint('发现服务：$serviceName');
          
          // 获取 SRV 记录
          final srvRecords = await _client!
              .lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(serviceName),
              )
              .timeout(
                const Duration(seconds: 2),
                onTimeout: (EventSink<SrvResourceRecord> sink) {
                  sink.close();
                },
              )
              .toList();
          
          for (final srv in srvRecords) {
            debugPrint('  SRV: ${srv.target}:${srv.port}');
            
            // 获取 IP 地址
            final ipRecords = await _client!
                .lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target),
                )
                .timeout(
                  const Duration(milliseconds: 800),
                  onTimeout: (EventSink<IPAddressResourceRecord> sink) {
                    sink.close();
                  },
                )
                .toList();
            
            for (final ip in ipRecords) {
              debugPrint('  IP: ${ip.address.address}');
              
              // 获取 TXT 记录
              String platform = 'unknown';
              try {
                final txtRecords = await _client!
                    .lookup<TxtResourceRecord>(
                      ResourceRecordQuery.text(serviceName),
                    )
                    .timeout(
                      const Duration(milliseconds: 500),
                      onTimeout: (EventSink<TxtResourceRecord> sink) {
                        sink.close();
                      },
                    )
                    .toList();
                
                for (final txt in txtRecords) {
                  final text = utf8.decode(txt.text as List<int>);
                  debugPrint('  TXT: $text');
                  if (text.contains('platform=')) {
                    platform = text.split('platform=')[1].split(',')[0];
                  }
                }
              } catch (e) {
                debugPrint('  TXT 记录获取失败：$e');
              }

              final computer = DiscoveredComputer(
                name: serviceName.split('.')[0],
                ip: ip.address.address,
                port: srv.port,
                platform: platform,
              );

              _addComputer(computer);
            }
          }
        } catch (e) {
          debugPrint('处理服务记录失败：$e');
        }
      }
    } catch (e) {
      debugPrint('mDNS 搜索失败：$e');
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
    _searchTimer?.cancel();
    _searchTimer = null;
    _client?.stop();
    _client = null;
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
