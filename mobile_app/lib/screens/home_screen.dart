import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../services/discovery_service.dart';
import '../services/ocr_service.dart';
import '../widgets/connection_status.dart';
import '../utils/constants.dart';
import 'ocr_screen.dart';

/// 主界面
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final DiscoveryService _discoveryService = DiscoveryService();
  final OcrService _ocrService = OcrService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initDiscovery();
  }

  @override
  void dispose() {
    _textController.dispose();
    _discoveryService.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  /// 初始化发现服务
  Future<void> _initDiscovery() async {
    await _discoveryService.startDiscovery();

    // 监听发现的电脑
    _discoveryService.computersStream.listen((computers) {
      if (computers.isNotEmpty) {
        final wsService = context.read<WebSocketService>();
        if (!wsService.connectionModel.isConnected) {
          // 自动连接到第一个发现的电脑
          wsService.connect(computers.first);
        }
      }
    });
  }

  /// 发送文字
  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请输入文字');
      return;
    }

    final wsService = context.read<WebSocketService>();
    if (!wsService.connectionModel.isConnected) {
      _showSnackBar('未连接到电脑，请检查连接');
      return;
    }

    setState(() => _isSending = true);

    try {
      await wsService.sendText(text);
      _textController.clear();
      _showSnackBar('发送成功！', isError: false);
    } catch (e) {
      _showSnackBar('发送失败: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  /// 拍照识别
  Future<void> _takePhoto() async {
    // 请求相机权限
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showSnackBar('需要相机权限才能拍照');
      return;
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo != null) {
        await _processImage(photo.path);
      }
    } catch (e) {
      _showSnackBar('拍照失败: $e');
    }
  }

  /// 从相册选择
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        await _processImage(image.path);
      }
    } catch (e) {
      _showSnackBar('选择图片失败: $e');
    }
  }

  /// 处理图片进行 OCR
  Future<void> _processImage(String imagePath) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final file = File(imagePath);
      final blocks = await _ocrService.recognizeText(file);

      Navigator.pop(context); // 关闭加载对话框

      if (blocks.isEmpty) {
        _showSnackBar('未识别到文字');
        return;
      }

      // 跳转到 OCR 结果选择界面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OcrScreen(
            textBlocks: blocks,
            onSend: (selectedText) async {
              final wsService = context.read<WebSocketService>();
              if (!wsService.connectionModel.isConnected) {
                _showSnackBar('未连接到电脑');
                return;
              }

              try {
                await wsService.sendOcrText(selectedText);
                _showSnackBar('发送成功！', isError: false);
              } catch (e) {
                _showSnackBar('发送失败: $e');
              }
            },
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('识别失败: $e');
    }
  }

  /// 显示提示
  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: Constants.fontSizeNormal),
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 显示连接对话框
  void _showConnectionDialog() {
    final ipController = TextEditingController();
    bool isConnecting = false;
    String? savedIp;

    // 加载保存的 IP
    final wsService = context.read<WebSocketService>();
    savedIp = wsService.connectionModel.computerIp;
    if (savedIp.isNotEmpty) {
      ipController.text = savedIp;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            '手动连接',
            style: TextStyle(fontSize: Constants.fontSizeLarge),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '请输入电脑的 IP 地址',
                style: TextStyle(fontSize: Constants.fontSizeNormal),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                enabled: !isConnecting,
                decoration: InputDecoration(
                  hintText: '例如: 192.168.1.100',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.computer),
                  suffixIcon: ipController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: isConnecting
                              ? null
                              : () {
                                  ipController.clear();
                                  setDialogState(() {});
                                },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: Constants.fontSizeNormal),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                '端口: ${Constants.websocketPort}',
                style: const TextStyle(
                  fontSize: Constants.fontSizeSmall,
                  color: Colors.grey,
                ),
              ),
              if (savedIp != null && savedIp.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '上次连接: $savedIp',
                  style: TextStyle(
                    fontSize: Constants.fontSizeSmall,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isConnecting ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            if (savedIp != null && savedIp.isNotEmpty && !isConnecting)
              TextButton(
                onPressed: () async {
                  setDialogState(() => isConnecting = true);

                  final success = await wsService.connectManually(
                    savedIp!,
                    Constants.websocketPort,
                  );

                  if (mounted) {
                    setDialogState(() => isConnecting = false);

                    if (success) {
                      Navigator.pop(context);
                      _showSnackBar('连接成功！', isError: false);
                    } else {
                      final errorMsg = wsService.connectionModel.errorMessage;
                      _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
                    }
                  }
                },
                child: const Text('快速连接'),
              ),
            ElevatedButton(
              onPressed: isConnecting
                  ? null
                  : () async {
                      final ip = ipController.text.trim();
                      if (ip.isEmpty) {
                        _showSnackBar('请输入 IP 地址');
                        return;
                      }

                      // 简单的 IP 格式验证
                      final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                      if (!ipRegex.hasMatch(ip)) {
                        _showSnackBar('IP 地址格式不正确');
                        return;
                      }

                      setDialogState(() => isConnecting = true);

                      final success = await wsService.connectManually(
                        ip,
                        Constants.websocketPort,
                      );

                      if (mounted) {
                        setDialogState(() => isConnecting = false);

                        if (success) {
                          Navigator.pop(context);
                          _showSnackBar('连接成功！', isError: false);
                        } else {
                          // 显示错误信息，但不关闭对话框
                          final errorMsg = wsService.connectionModel.errorMessage;
                          _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
                        }
                      }
                    },
              child: isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('连接'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '跨设备打字助手',
          style: TextStyle(fontSize: Constants.fontSizeLarge),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showConnectionDialog,
            tooltip: '手动连接',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Constants.paddingNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 连接状态
              Consumer<WebSocketService>(
                builder: (context, wsService, child) {
                  return Center(
                    child: ConnectionStatusWidget(
                      connectionModel: wsService.connectionModel,
                    ),
                  );
                },
              ),

              const SizedBox(height: Constants.paddingNormal),

              // 文字输入区域 - 使用 Flexible 而不是 Expanded，避免键盘弹出时被压缩
              Flexible(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontSize: Constants.fontSizeLarge,
                    ),
                    decoration: const InputDecoration(
                      hintText: '点击此处手写或输入文字...',
                      hintStyle: TextStyle(
                        fontSize: Constants.fontSizeLarge,
                        color: Colors.grey,
                      ),
                      contentPadding: EdgeInsets.all(Constants.paddingNormal),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: Constants.paddingNormal),

              // 三个按钮水平排列在一行
              Row(
                children: [
                  // 拍照按钮
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt, size: 24),
                      label: const Text(
                        '拍照',
                        style: TextStyle(fontSize: Constants.fontSizeNormal),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 相册按钮
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library, size: 24),
                      label: const Text(
                        '相册',
                        style: TextStyle(fontSize: Constants.fontSizeNormal),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送按钮
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendText,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send, size: 24),
                      label: Text(
                        _isSending ? '发送中' : '发送',
                        style: const TextStyle(fontSize: Constants.fontSizeNormal),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green.withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: Constants.paddingSmall),
            ],
          ),
        ),
      ),
    );
  }
}
