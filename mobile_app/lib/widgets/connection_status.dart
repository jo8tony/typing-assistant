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
    Widget? statusIndicator;

    switch (connectionModel.status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
              statusIndicator ?? Icon(
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
        ),
        // 显示错误信息
        if (connectionModel.status == ConnectionStatus.error &&
            connectionModel.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(Constants.paddingSmall),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              connectionModel.errorMessage,
              style: TextStyle(
                fontSize: Constants.fontSizeSmall,
                color: Colors.red[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}
