import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_send_discovery_service.dart';

class DeviceDiscoverySheet extends StatefulWidget {
  final DiscoveryService discoveryService;
  final Function(DiscoveredDevice) onDeviceSelected;
  final String? currentConnectedIp;

  const DeviceDiscoverySheet({
    super.key,
    required this.discoveryService,
    required this.onDeviceSelected,
    this.currentConnectedIp,
  });

  static Future<void> show({
    required BuildContext context,
    required DiscoveryService discoveryService,
    required Function(DiscoveredDevice) onDeviceSelected,
    String? currentConnectedIp,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DeviceDiscoverySheet(
          discoveryService: discoveryService,
          onDeviceSelected: onDeviceSelected,
          currentConnectedIp: currentConnectedIp,
        ),
      ),
    );
  }

  @override
  State<DeviceDiscoverySheet> createState() => _DeviceDiscoverySheetState();
}

class _DeviceDiscoverySheetState extends State<DeviceDiscoverySheet> {
  StreamSubscription<List<DiscoveredDevice>>? _subscription;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '${DiscoveryConstants.websocketPort}');
  final FocusNode _ipFocusNode = FocusNode();
  final FocusNode _portFocusNode = FocusNode();

  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.discoveryService.devicesStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ipController.dispose();
    _portController.dispose();
    _ipFocusNode.dispose();
    _portFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      await widget.discoveryService.restartDiscovery();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已重新扫描'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.discoveryService.discoveredDevices;
    final isScanning = widget.discoveryService.isScanning;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(isScanning),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(isScanning, devices.length),
                  const SizedBox(height: 20),
                  if (devices.isNotEmpty) ...[
                    _buildSectionTitle('发现的设备', devices.length),
                    const SizedBox(height: 12),
                    ...devices.map((device) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildDeviceCard(device),
                        )),
                    const SizedBox(height: 20),
                  ],
                  _buildSectionTitle('手动连接', null),
                  const SizedBox(height: 12),
                  _buildManualInput(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isScanning) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade600,
            Colors.blue.shade700,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.devices,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '发现设备',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'LocalSend 风格 · 多播发现',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              if (isScanning)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '扫描中',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isScanning, int deviceCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: deviceCount > 0
            ? Colors.green.shade50
            : isScanning
                ? Colors.blue.shade50
                : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deviceCount > 0
              ? Colors.green.shade200
              : isScanning
                  ? Colors.blue.shade200
                  : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: deviceCount > 0
                  ? Colors.green.shade100
                  : isScanning
                      ? Colors.blue.shade100
                      : Colors.orange.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              deviceCount > 0
                  ? Icons.check_circle
                  : isScanning
                      ? Icons.search
                      : Icons.info_outline,
              size: 24,
              color: deviceCount > 0
                  ? Colors.green.shade600
                  : isScanning
                      ? Colors.blue.shade600
                      : Colors.orange.shade600,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceCount > 0
                      ? '已发现 $deviceCount 台设备'
                      : isScanning
                          ? '正在扫描局域网...'
                          : '未发现设备',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: deviceCount > 0
                        ? Colors.green.shade700
                        : isScanning
                            ? Colors.blue.shade700
                            : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  deviceCount > 0
                      ? '点击设备卡片进行连接'
                      : isScanning
                          ? '请稍候，正在搜索附近的设备'
                          : '请检查网络或手动输入 IP 地址',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (!isScanning)
            IconButton(
              onPressed: _isRefreshing ? null : _handleRefresh,
              icon: _isRefreshing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue.shade600,
                      ),
                    )
                  : Icon(
                      Icons.refresh,
                      color: Colors.blue.shade600,
                    ),
              tooltip: '重新扫描',
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int? count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeviceCard(DiscoveredDevice device) {
    final isConnected = device.ip == widget.currentConnectedIp;

    IconData deviceIcon;
    Color iconColor;
    Color bgColor;

    if (device.deviceType == 'mobile') {
      deviceIcon = Icons.smartphone;
      iconColor = Colors.blue.shade600;
      bgColor = Colors.blue.shade50;
    } else if (device.deviceType == 'macos' || device.deviceType == 'darwin') {
      deviceIcon = Icons.apple;
      iconColor = Colors.grey.shade800;
      bgColor = Colors.grey.shade100;
    } else if (device.deviceType == 'windows') {
      deviceIcon = Icons.desktop_windows;
      iconColor = Colors.blue.shade700;
      bgColor = Colors.blue.shade50;
    } else if (device.deviceType == 'linux') {
      deviceIcon = Icons.computer;
      iconColor = Colors.orange.shade600;
      bgColor = Colors.orange.shade50;
    } else {
      deviceIcon = Icons.computer;
      iconColor = Colors.grey.shade600;
      bgColor = Colors.grey.shade100;
    }

    return Container(
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected ? Colors.green.shade300 : Colors.grey.shade200,
          width: isConnected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            widget.onDeviceSelected(device);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green.shade100 : bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(deviceIcon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              device.alias,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isConnected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade500,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                '已连接',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.wifi,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${device.ip}:${device.port}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (device.deviceModel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                device.deviceModel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isConnected)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Colors.blue.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ipController,
                  focusNode: _ipFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'IP 地址',
                    hintText: '192.168.1.100',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon: Icon(Icons.computer, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _portController,
                  focusNode: _portFocusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '端口',
                    hintText: '8765',
                    labelStyle: const TextStyle(fontSize: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final ip = _ipController.text.trim();
                final port = int.tryParse(_portController.text.trim()) ??
                    DiscoveryConstants.websocketPort;

                if (ip.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入 IP 地址')),
                  );
                  return;
                }

                final device = DiscoveredDevice(
                  fingerprint: 'manual-${ip.hashCode}',
                  alias: '手动连接 ($ip)',
                  ip: ip,
                  port: port,
                  deviceModel: '',
                  deviceType: 'manual',
                );

                Navigator.pop(context);
                widget.onDeviceSelected(device);
              },
              icon: const Icon(Icons.link, size: 18),
              label: const Text('连接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
