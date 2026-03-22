import 'dart:async';
import 'dart:convert';
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

  Stream<List<DiscoveredComputer>> get computersStream => _computersController.stream;
  List<DiscoveredComputer> get discoveredComputers => List.unmodifiable(_discoveredComputers);

  /// 开始搜索局域网内的电脑
  Future<void> startDiscovery() async {
    await stopDiscovery();

    _client = MDnsClient();
    await _client!.start();

    // 立即搜索一次
    await _searchServices();

    // 每 5 秒搜索一次
    _searchTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _searchServices();
    });
  }

  /// 停止发现服务
  Future<void> stopDiscovery() async {
    _searchTimer?.cancel();
    _searchTimer = null;
    _client?.stop();
    _client = null;
    _discoveredComputers.clear();
  }

  /// 搜索服务
  Future<void> _searchServices() async {
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

            // 添加到列表（避免重复）
            if (!_discoveredComputers.any((c) => c.ip == computer.ip)) {
              _discoveredComputers.add(computer);
              _computersController.add(List.unmodifiable(_discoveredComputers));
            }
          }
        }
      }
    } catch (e) {
      print('mDNS 搜索出错: $e');
    }
  }

  /// 手动添加电脑（如果 mDNS 不可用）
  void addComputerManually(String name, String ip, int port) {
    final computer = DiscoveredComputer(
      name: name,
      ip: ip,
      port: port,
      platform: 'manual',
    );

    if (!_discoveredComputers.any((c) => c.ip == ip)) {
      _discoveredComputers.add(computer);
      _computersController.add(List.unmodifiable(_discoveredComputers));
    }
  }

  void dispose() {
    stopDiscovery();
    _computersController.close();
  }
}
