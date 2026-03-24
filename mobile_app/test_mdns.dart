import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

void main() async {
  debugPrint('开始 mDNS 测试...');
  
  final client = MDnsClient();
  await client.start();
  debugPrint('mDNS 客户端已启动');
  
  // 等待一下
  await Future.delayed(const Duration(seconds: 1));
  
  // 查询所有服务类型
  debugPrint('查询 _services._dns-sd._udp.local....');
  try {
    final services = await client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local.'),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: (EventSink<PtrResourceRecord> sink) {
            debugPrint('PTR 查询超时');
            sink.close();
          },
        )
        .toList();
    
    debugPrint('发现 ${services.length} 个服务类型');
    for (final service in services) {
      debugPrint('  服务类型：${service.domainName}');
    }
  } catch (e) {
    debugPrint('查询失败：$e');
  }
  
  // 查询 _typing._tcp.local.
  debugPrint('\n查询 _typing._tcp.local....');
  try {
    final ptrRecords = await client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_typing._tcp.local.'),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: (EventSink<PtrResourceRecord> sink) {
            debugPrint('PTR 查询超时');
            sink.close();
          },
        )
        .toList();
    
    debugPrint('发现 ${ptrRecords.length} 个服务实例');
    for (final ptr in ptrRecords) {
      debugPrint('  PTR: ${ptr.domainName}');
      
      // 查询 SRV
      try {
        final srvRecords = await client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(
              const Duration(seconds: 2),
              onTimeout: (EventSink<SrvResourceRecord> sink) {
                sink.close();
              },
            )
            .toList();
        
        for (final srv in srvRecords) {
          debugPrint('    SRV: ${srv.target}:${srv.port}');
        }
      } catch (e) {
        debugPrint('    SRV 查询失败：$e');
      }
    }
  } catch (e) {
    debugPrint('查询失败：$e');
  }
  
  client.stop();
  debugPrint('测试完成');
}
