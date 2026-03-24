import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_send_discovery_service.dart';
import '../utils/constants.dart';

class NetworkDiscoveryWidget extends StatefulWidget {
  final LocalSendDiscoveryService discoveryService;
  final Function(DiscoveredDevice) onDeviceSelected;

  const NetworkDiscoveryWidget({
    super.key,
    required this.discoveryService,
    required this.onDeviceSelected,
  });

  @override
  State<NetworkDiscoveryWidget> createState() => _NetworkDiscoveryWidgetState();
}

class _NetworkDiscoveryWidgetState extends State<NetworkDiscoveryWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<List<DiscoveredDevice>>? _subscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _subscription = widget.discoveryService.devicesStream.listen((_) {
      if (mounted) setState(() {});
    });

    widget.discoveryService.startDiscovery();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _restartDiscovery() {
    widget.discoveryService.restartDiscovery();
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.discoveryService.discoveredDevices;
    final isScanning = widget.discoveryService.isScanning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(isScanning),
        const SizedBox(height: 16),
        if (devices.isEmpty && isScanning)
          _buildScanningState()
        else if (devices.isEmpty && !isScanning)
          _buildEmptyState()
        else
          _buildDeviceList(devices),
        const SizedBox(height: 16),
        _buildManualInputButton(),
      ],
    );
  }

  Widget _buildHeader(bool isScanning) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isScanning ? _pulseAnimation.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isScanning
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isScanning ? Icons.radar : Icons.check_circle,
                  color: isScanning ? Colors.blue : Colors.green,
                  size: 24,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isScanning ? '正在搜索设备' : '设备发现',
                style: const TextStyle(
                  fontSize: Constants.fontSizeNormal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isScanning ? 'UDP多播 + HTTP扫描中...' : '已找到所有可用设备',
                style: TextStyle(
                  fontSize: Constants.fontSizeSmall,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        if (isScanning)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _restartDiscovery,
            tooltip: '重新扫描',
          ),
      ],
    );
  }

  Widget _buildScanningState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          const Text(
            '正在搜索局域网中的设备',
            style: TextStyle(
              fontSize: Constants.fontSizeNormal,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请确保电脑端服务已启动',
            style: TextStyle(
              fontSize: Constants.fontSizeSmall,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildScanMethodChip(Icons.hub, 'UDP多播'),
              const SizedBox(width: 8),
              _buildScanMethodChip(Icons.wifi, 'HTTP扫描'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanMethodChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: Colors.orange[300],
          ),
          const SizedBox(height: 12),
          const Text(
            '未发现设备',
            style: TextStyle(
              fontSize: Constants.fontSizeNormal,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '请检查：\n1. 电脑端服务是否已启动\n2. 手机和电脑是否在同一网络',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Constants.fontSizeSmall,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _restartDiscovery,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新扫描'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(List<DiscoveredDevice> devices) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  '发现 ${devices.length} 台设备',
                  style: TextStyle(
                    fontSize: Constants.fontSizeSmall,
                    fontWeight: FontWeight.w500,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final device = devices[index];
              return _buildDeviceTile(device);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(DiscoveredDevice device) {
    final IconData deviceIcon;
    final Color iconColor;

    if (device.deviceType == 'mobile') {
      deviceIcon = Icons.smartphone;
      iconColor = Colors.blue;
    } else if (device.platform == 'macos' || device.platform == 'darwin') {
      deviceIcon = Icons.apple;
      iconColor = Colors.grey[700]!;
    } else {
      deviceIcon = Icons.computer;
      iconColor = Colors.grey[700]!;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(deviceIcon, color: iconColor, size: 24),
      ),
      title: Text(
        device.name,
        style: const TextStyle(
          fontSize: Constants.fontSizeSmall,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${device.ip}:${device.port}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      trailing: ElevatedButton(
        onPressed: () => widget.onDeviceSelected(device),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: const Text('连接'),
      ),
      onTap: () => widget.onDeviceSelected(device),
    );
  }

  Widget _buildManualInputButton() {
    return OutlinedButton.icon(
      onPressed: () => _showManualInputDialog(),
      icon: const Icon(Icons.add, size: 20),
      label: const Text('手动输入IP地址'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: Colors.grey[400]!),
      ),
    );
  }

  void _showManualInputDialog() {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '${Constants.websocketPort}');
    final nameController = TextEditingController(text: '手动输入');
    bool isTesting = false;
    bool? testSuccess;
    String? testMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('手动输入设备信息'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '设备名称',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: '例如：我的电脑',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'IP地址',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ipController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '例如：192.168.1.100',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.computer),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '端口',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '默认：8765',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isTesting
                            ? null
                            : () async {
                                final ip = ipController.text.trim();

                                if (ip.isEmpty) {
                                  setDialogState(() {
                                    testSuccess = false;
                                    testMessage = '请输入IP地址';
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isTesting = true;
                                  testSuccess = null;
                                  testMessage = null;
                                });

                                await Future.delayed(const Duration(seconds: 1));

                                setDialogState(() {
                                  isTesting = false;
                                  testSuccess = true;
                                  testMessage = '设备信息已保存';
                                });
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isTesting
                            ? null
                            : () {
                                final ip = ipController.text.trim();
                                final port = int.tryParse(portController.text.trim()) ?? Constants.websocketPort;
                                final name = nameController.text.trim().isEmpty ? '手动输入' : nameController.text.trim();

                                if (ip.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('请输入IP地址')),
                                  );
                                  return;
                                }

                                widget.discoveryService.addDeviceManually(
                                  ip,
                                  port,
                                  name: name,
                                );

                                Navigator.pop(context);

                                final device = DiscoveredDevice(
                                  id: 'manual-${ip.hashCode}',
                                  name: name,
                                  ip: ip,
                                  port: port,
                                  platform: 'manual',
                                  deviceType: 'manual',
                                );

                                widget.onDeviceSelected(device);
                              },
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('连接'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (testMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: testSuccess == true
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          testSuccess == true ? Icons.check_circle : Icons.error,
                          color: testSuccess == true ? Colors.green : Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testMessage!,
                            style: TextStyle(
                              color: testSuccess == true ? Colors.green[700] : Colors.red[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}