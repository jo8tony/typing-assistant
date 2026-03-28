import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/websocket_service.dart';
import '../utils/constants.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
      _initScanner();
    } else if (status.isDenied) {
      final result = await Permission.camera.request();
      setState(() {
        _hasPermission = result.isGranted;
        _isCheckingPermission = false;
      });
      if (result.isGranted) {
        _initScanner();
      }
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _hasPermission = false;
        _isCheckingPermission = false;
      });
      if (mounted) {
        _showPermissionDialog();
      }
    } else {
      setState(() {
        _hasPermission = false;
        _isCheckingPermission = false;
      });
    }
  }

  void _initScanner() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('相机权限被拒绝'),
        content: const Text('请在设置中开启相机权限，以便使用扫码功能'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    
    if (rawValue == null || rawValue.isEmpty) return;

    if (!rawValue.startsWith('ws://') && !rawValue.startsWith('wss://')) {
      _showError('无效的二维码格式');
      return;
    }

    _isProcessing = true;
    _controller?.stop();

    _connectFromUrl(rawValue);
  }

  Future<void> _connectFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      _showError('无效的连接地址');
      Navigator.pop(context);
      return;
    }

    final ip = uri.host;
    final port = uri.port > 0 ? uri.port : Constants.websocketPort;

    final wsService = context.read<WebSocketService>();

    if (wsService.connectionModel.isConnected) {
      await wsService.disconnect();
    }

    final success = await wsService.connectManually(ip, port);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已连接到 $ip:$port'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      _showError('连接失败，请检查网络');
      _isProcessing = false;
      _controller?.start();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '扫码连接',
          style: TextStyle(fontSize: Constants.fontSizeLarge),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_off),
            onPressed: () {
              _controller?.toggleTorch();
            },
            tooltip: '切换闪光灯',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isCheckingPermission) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              '需要相机权限才能扫码',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkCameraPermission,
              child: const Text('请求权限'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '将二维码放入框内自动扫描',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        if (_isProcessing)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
