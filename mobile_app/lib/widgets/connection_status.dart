import 'package:flutter/material.dart';
import '../models/connection_model.dart';

/// 连接状态指示器（小型化设计）
class ConnectionStatusWidget extends StatelessWidget {
  final ConnectionModel connectionModel;

  const ConnectionStatusWidget({
    super.key,
    required this.connectionModel,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    Widget? statusIndicator;
    String tooltip;

    switch (connectionModel.status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        tooltip = '已连接：${connectionModel.computerIp}';
        break;
      case ConnectionStatus.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusIndicator = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        );
        tooltip = '连接中...';
        break;
      case ConnectionStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        tooltip = connectionModel.errorMessage.isNotEmpty 
            ? connectionModel.errorMessage 
            : '连接错误';
        break;
      case ConnectionStatus.disconnected:
        statusColor = Colors.grey;
        statusIcon = Icons.cloud_off;
        tooltip = '未连接';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: statusIndicator ?? Icon(
          statusIcon,
          color: statusColor,
          size: 24,
        ),
      ),
    );
  }
}
