import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/websocket_service.dart';
import '../services/local_send_discovery_service.dart';
import '../services/ocr_service.dart';
import '../services/text_history_service.dart';
import '../widgets/connection_status.dart';
import '../models/connection_model.dart';
import '../widgets/device_discovery_sheet.dart';
import '../utils/constants.dart';
import 'ocr_screen.dart';

typedef DiscoveredComputer = DiscoveredDevice;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final DiscoveryService _discoveryService = DiscoveryService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;
  bool _hasAutoConnected = false;
  bool _isShowingServerList = false;
  Timer? _discoveryTimer;
  List<DiscoveredComputer> _lastDiscoveredComputers = [];

  String? _tipMessage;
  bool _tipIsError = false;
  Timer? _tipTimer;

  @override
  void initState() {
    super.initState();
    _initDiscovery();
  }

  @override
  void dispose() {
    _textController.dispose();
    _discoveryService.dispose();
    _tipTimer?.cancel();
    super.dispose();
  }

  void _showTip(String message, {bool isError = false}) {
    _tipTimer?.cancel();
    setState(() {
      _tipMessage = message;
      _tipIsError = isError;
    });
    _tipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _tipMessage = null;
        });
      }
    });
  }

  void _showSnackBar(String message, {bool isError = true}) {
    _showTip(message, isError: isError);
  }

  void _showHistoryDialog() {
    final historyService = context.read<TextHistoryService>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Text('历史记录'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: Consumer<TextHistoryService>(
            builder: (context, service, child) {
              if (service.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (service.history.isEmpty) {
                return const Center(
                  child: Text('暂无历史记录'),
                );
              }

              return ListView.separated(
                itemCount: service.history.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final text = service.history[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: Constants.fontSizeNormal),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        historyService.removeHistory(text);
                      },
                    ),
                    onTap: () {
                      final currentText = _textController.text;
                      _textController.text = currentText + text;
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              historyService.clearHistory();
            },
            child: const Text('清空历史'),
          ),
        ],
      ),
    );
  }

  Future<void> _initDiscovery() async {
    await _discoveryService.startDiscovery();

    _discoveryService.computersStream.listen((computers) {
      if (!mounted) return;

      final wsService = context.read<WebSocketService>();

      if (wsService.connectionModel.isConnected ||
          wsService.connectionModel.isConnecting) {
        return;
      }

      if (_hasAutoConnected) return;

      _lastDiscoveredComputers = computers;

      _discoveryTimer?.cancel();

      if (computers.isEmpty) {
        return;
      }

      _discoveryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;

        if (wsService.connectionModel.isConnected ||
            wsService.connectionModel.isConnecting) {
          return;
        }

        if (_hasAutoConnected) return;

        _hasAutoConnected = true;

        final currentComputers = _lastDiscoveredComputers;

        if (currentComputers.isEmpty) {
          return;
        }

        if (currentComputers.length == 1) {
          debugPrint('发现唯一服务，自动连接: ${currentComputers.first.ip}');
          wsService.connect(currentComputers.first, autoReconnect: true);
          _showSnackBar('已自动连接到 ${currentComputers.first.alias}', isError: false);
        } else {
          debugPrint('发现多个服务，显示选择对话框: ${currentComputers.length} 个');
          _showServerSelectionDialog(currentComputers);
        }
      });
    });
  }

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

      if (mounted) {
        final historyService = context.read<TextHistoryService>();
        historyService.addHistory(text);
      }

      _textController.clear();
      _showSnackBar('发送成功！', isError: false);
    } catch (e) {
      _showSnackBar('发送失败：$e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<bool> _requestStoragePermission() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    if (androidInfo.version.sdkInt >= 33) {
      final status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        _showPermissionSettingsDialog('照片权限');
        return false;
      }
      return false;
    } else if (androidInfo.version.sdkInt >= 30) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        _showPermissionSettingsDialog('存储权限');
        return false;
      }
      return false;
    } else {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        _showPermissionSettingsDialog('存储权限');
        return false;
      }
      return false;
    }
  }

  void _showPermissionSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionName被拒绝'),
        content: Text('请在设置中开启$permissionName，以便应用正常工作'),
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

  Future<void> _takePhoto() async {
    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        if (cameraStatus.isPermanentlyDenied) {
          _showPermissionSettingsDialog('相机权限');
        } else {
          _showSnackBar('需要相机权限才能拍照');
        }
        return;
      }

      final storageGranted = await _requestStoragePermission();
      if (!storageGranted) {
        _showSnackBar('需要存储权限才能保存照片');
        return;
      }

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (photo != null) {
        await _processImage(photo.path);
      }
    } on PlatformException catch (e) {
      debugPrint('拍照平台异常: ${e.code} - ${e.message}');
      _showSnackBar('拍照失败: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      debugPrint('拍照异常: $e');
      debugPrint('堆栈: $stackTrace');
      _showSnackBar('拍照失败: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final storageGranted = await _requestStoragePermission();
      if (!storageGranted) {
        _showSnackBar('需要存储权限才能选择图片');
        return;
      }

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        await _processImage(image.path);
      }
    } on PlatformException catch (e) {
      debugPrint('选择图片平台异常: ${e.code} - ${e.message}');
      _showSnackBar('选择图片失败: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      debugPrint('选择图片异常: $e');
      debugPrint('堆栈: $stackTrace');
      _showSnackBar('选择图片失败: $e');
    }
  }

  Future<void> _processImage(String imagePath) async {
    if (!mounted) return;

    final ocrService = context.read<OcrService>();

    BuildContext? dialogContext;

    try {
      debugPrint('开始 OCR 识别: $imagePath');

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      final file = File(imagePath);

      final exists = await file.exists();
      debugPrint('文件存在: $exists');

      if (!exists) {
        throw Exception('图片文件不存在: $imagePath');
      }

      final fileSize = await file.length();
      debugPrint('文件大小: $fileSize bytes');

      if (fileSize == 0) {
        throw Exception('图片文件为空');
      }

      final blocks = await ocrService.recognizeText(file);
      debugPrint('OCR 识别完成，结果数量：${blocks.length}');

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }

      if (!mounted) return;

      if (blocks.isEmpty) {
        _showSnackBar('未识别到文字，请确保图片中有清晰的文字');
        return;
      }

      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OcrScreen(
            textBlocks: blocks,
            onSend: (_) {},
          ),
        ),
      );
      if (result != null && result is String && mounted) {
        final currentText = _textController.text;
        _textController.text = currentText + result;
      }
    } on PlatformException catch (e) {
      debugPrint('OCR 平台异常: ${e.code} - ${e.message}');
      debugPrint('详细信息: ${e.details}');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      if (mounted) {
        _showSnackBar('识别失败: ${e.message ?? e.code}');
      }
    } catch (e, stackTrace) {
      debugPrint('OCR 处理异常: $e');
      debugPrint('堆栈: $stackTrace');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      if (mounted) {
        _showSnackBar('识别失败: $e');
      }
    }
  }

  void _showServerSelectionDialog(List<DiscoveredComputer> computers) {
    if (_isShowingServerList) return;
    _isShowingServerList = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('选择电脑')),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _isShowingServerList = false;
                Navigator.pop(context);
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('发现了 ${computers.length} 台电脑：'),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: computers.length,
                  itemBuilder: (context, index) {
                    final computer = computers[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          computer.deviceType == 'macos'
                              ? Icons.apple
                              : Icons.computer,
                        ),
                        title: Text(computer.alias),
                        subtitle: Text(computer.ip),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            _isShowingServerList = false;
                            Navigator.pop(context);

                            final wsService = context.read<WebSocketService>();
                            final success = await wsService.connect(
                              computer,
                              autoReconnect: true,
                            );

                            if (success && mounted) {
                              _showSnackBar(
                                '已连接到 ${computer.alias}',
                                isError: false,
                              );
                            } else if (mounted) {
                              final errorMsg = wsService.connectionModel.errorMessage;
                              _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
                            }
                          },
                          child: const Text('连接'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      _isShowingServerList = false;
    });
  }

  void _showServerListPopup() {
    _hasAutoConnected = false;

    final wsService = context.read<WebSocketService>();

    DeviceDiscoverySheet.show(
      context: context,
      discoveryService: _discoveryService,
      currentConnectedIp: wsService.connectionModel.computerIp,
      onDeviceSelected: (device) async {
        if (wsService.connectionModel.isConnected) {
          await wsService.disconnect();
        }

        final success = await wsService.connect(device, autoReconnect: true);

        if (success && mounted) {
          _showSnackBar('已连接到 ${device.alias}', isError: false);
        } else if (mounted) {
          final errorMsg = wsService.connectionModel.errorMessage;
          _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<WebSocketService>(
              builder: (context, wsService, child) {
                return ConnectionStatusWidget(
                  connectionModel: wsService.connectionModel,
                  onTap: _showServerListPopup,
                );
              },
            ),
            const SizedBox(width: 8),
            const Text(
              '跨设备打字助手',
              style: TextStyle(fontSize: Constants.fontSizeLarge),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showHistoryDialog,
            tooltip: '历史记录',
          ),
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: _showServerListPopup,
            tooltip: '发现设备',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(Constants.paddingNormal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Consumer<WebSocketService>(
                    builder: (context, wsService, child) {
                      final connectionModel = wsService.connectionModel;

                      if (connectionModel.isConnected) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.computer, color: Colors.green, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          '已连接: ',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            connectionModel.computerName.isNotEmpty
                                                ? connectionModel.computerName
                                                : connectionModel.computerIp,
                                            style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      connectionModel.computerIp,
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showServerListPopup,
                                icon: const Icon(Icons.swap_horiz, size: 18),
                                label: const Text('切换'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (connectionModel.isConnecting) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '正在连接 ${connectionModel.computerIp}...',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (connectionModel.status == ConnectionStatus.error) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  connectionModel.errorMessage.isNotEmpty
                                      ? connectionModel.errorMessage
                                      : '连接失败',
                                  style: const TextStyle(color: Colors.red),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: _showServerListPopup,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }

                      return StreamBuilder<List<DiscoveredComputer>>(
                        stream: _discoveryService.computersStream,
                        initialData: _discoveryService.discoveredComputers,
                        builder: (context, snapshot) {
                          final computers = snapshot.data ?? [];
                          final isScanning = _discoveryService.isScanning;

                          if (computers.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  if (isScanning)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else
                                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      isScanning
                                          ? '正在搜索局域网中的电脑...'
                                          : '未发现设备，点击右侧手动输入',
                                      style: const TextStyle(color: Colors.blue),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _showServerListPopup,
                                    child: const Text('手动输入'),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '发现 ${computers.length} 台电脑',
                                    style: const TextStyle(color: Colors.green),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showServerSelectionDialog(computers),
                                  child: const Text('选择'),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Flexible(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _textController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontSize: Constants.fontSizeLarge,
                            ),
                            decoration: InputDecoration(
                              hintText: '点击此处手写或输入文字...',
                              hintStyle: const TextStyle(
                                fontSize: Constants.fontSizeLarge,
                                color: Colors.grey,
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                Constants.paddingNormal,
                                Constants.paddingNormal,
                                48,
                                Constants.paddingNormal,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _textController,
                              builder: (context, value, child) {
                                if (value.text.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return GestureDetector(
                                  onTap: () => _textController.clear(),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Constants.paddingNormal),
                  Row(
                    children: [
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
            if (_tipMessage != null)
              Positioned(
                top: 0,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: _tipIsError
                            ? Colors.red.withOpacity(0.85)
                            : Colors.green.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _tipMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
