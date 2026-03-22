import 'package:flutter/material.dart';
import '../models/connection_model.dart';
import '../utils/constants.dart';

/// 连接状态显示组件
class ConnectionStatusWidget extends StatelessWidget {
  final ConnectionModel connectionModel;

  const ConnectionStatusWidget({
    Key? key,
    required this.connectionModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    switch (connectionModel.status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case ConnectionStatus.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        break;
      case ConnectionStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case ConnectionStatus.disconnected:
        statusColor = Colors.grey;
        statusIcon = Icons.cloud_off;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Constants.paddingNormal,
        vertical: Constants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            '连接状态: ${connectionModel.statusText}',
            style: TextStyle(
              fontSize: Constants.fontSizeNormal,
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (connectionModel.isConnected) ...[
            const SizedBox(width: 8),
            Text(
              '(${connectionModel.computerIp})',
              style: TextStyle(
                fontSize: Constants.fontSizeSmall,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
