import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/websocket_service.dart';
import '../services/discovery_service.dart';
import '../services/ocr_service.dart';
import '../services/text_history_service.dart';
import '../widgets/connection_status.dart';
import '../utils/constants.dart';
import 'ocr_screen.dart';

/// 主界面
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
  bool _hasAutoConnected = false; // 标记是否已经尝试过自动连接
  bool _isShowingServerList = false; // 标记是否正在显示服务器列表
  Timer? _discoveryTimer; // 延迟检测定时器
  List<DiscoveredComputer> _lastDiscoveredComputers = []; // 上次检测到的服务列表

  @override
  void initState() {
    super.initState();
    _initDiscovery();
  }

  @override
  void dispose() {
    _textController.dispose();
    _discoveryService.dispose();
    super.dispose();
  }

  /// 显示历史记录对话框
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
          height: 320, // 固定高度，约可显示8行
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
                      // 将选中的历史记录追加到输入框（直接追加，不换行）
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

  /// 初始化发现服务
  Future<void> _initDiscovery() async {
    await _discoveryService.startDiscovery();

    // 监听发现的电脑
    _discoveryService.computersStream.listen((computers) {
      if (!mounted) return;

      final wsService = context.read<WebSocketService>();

      // 如果已经连接或正在连接，不处理
      if (wsService.connectionModel.isConnected ||
          wsService.connectionModel.isConnecting) {
        return;
      }

      // 如果已经自动连接过，不再处理
      if (_hasAutoConnected) return;

      // 更新检测到的服务列表
      _lastDiscoveredComputers = computers;

      // 取消之前的定时器（如果有）
      _discoveryTimer?.cancel();

      if (computers.isEmpty) {
        // 没有发现服务，不处理
        return;
      }

      // 延迟 2 秒后再决定是否连接，确保检测到所有服务
      _discoveryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;

        // 如果已经连接或正在连接，不处理
        if (wsService.connectionModel.isConnected ||
            wsService.connectionModel.isConnecting) {
          return;
        }

        // 如果已经自动连接过，不再处理
        if (_hasAutoConnected) return;

        // 标记已经尝试过自动连接
        _hasAutoConnected = true;

        // 使用最新的检测结果
        final currentComputers = _lastDiscoveredComputers;

        if (currentComputers.isEmpty) {
          return;
        }

        if (currentComputers.length == 1) {
          // 只有一个服务，自动连接
          debugPrint('发现唯一服务，自动连接: ${currentComputers.first.ip}');
          wsService.connect(currentComputers.first, autoReconnect: true);
          _showSnackBar('已自动连接到 ${currentComputers.first.name}', isError: false);
        } else {
          // 多个服务，显示选择对话框
          debugPrint('发现多个服务，显示选择对话框: ${currentComputers.length} 个');
          _showServerSelectionDialog(currentComputers);
        }
      });
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
      
      // 保存到历史记录
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

  /// 检查并请求存储权限
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

  /// 显示权限设置对话框
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

  /// 拍照识别
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

  /// 从相册选择
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

  /// 处理图片进行 OCR
  Future<void> _processImage(String imagePath) async {
    if (!mounted) return;

    final ocrService = context.read<OcrService>();

    BuildContext? dialogContext;
    
    try {
      debugPrint('开始 OCR 识别: $imagePath');
      
      if (!mounted) return;
      
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

      // ignore: use_build_context_synchronously
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }

      if (!mounted) return;

      if (blocks.isEmpty) {
        _showSnackBar('未识别到文字，请确保图片中有清晰的文字');
        return;
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OcrScreen(
            textBlocks: blocks,
            onSend: (selectedText) {
              // 将选中的文字追加到输入框（直接追加，不换行）
              final currentText = _textController.text;
              _textController.text = currentText + selectedText;
            },
          ),
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('OCR 平台异常: ${e.code} - ${e.message}');
      debugPrint('详细信息: ${e.details}');
      // ignore: use_build_context_synchronously
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      if (mounted) {
        _showSnackBar('识别失败: ${e.message ?? e.code}');
      }
    } catch (e, stackTrace) {
      debugPrint('OCR 处理异常: $e');
      debugPrint('堆栈: $stackTrace');
      // ignore: use_build_context_synchronously
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      if (mounted) {
        _showSnackBar('识别失败: $e');
      }
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

  /// 显示服务器选择对话框
  void _showServerSelectionDialog(List<DiscoveredComputer> computers) {
    if (_isShowingServerList) return; // 避免重复显示
    _isShowingServerList = true;

    showDialog(
      context: context,
      barrierDismissible: false, // 必须选择或关闭
      builder:
          (context) => AlertDialog(
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
                              computer.platform == 'macos'
                                  ? Icons.apple
                                  : Icons.computer,
                            ),
                            title: Text(computer.name),
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
                                    '已连接到 ${computer.name}',
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
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('手动输入 IP 地址'),
                    onTap: () {
                      _isShowingServerList = false;
                      Navigator.pop(context);
                      _showConnectionDialog();
                    },
                  ),
                ],
              ),
            ),
          ),
    ).then((_) {
      _isShowingServerList = false;
    });
  }

  /// 显示服务端列表弹窗（点击状态按钮后弹出）
  void _showServerListPopup() {
    // 重置自动连接标记，允许重新扫描
    _hasAutoConnected = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('局域网服务端')),
                // 扫描按钮
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新扫描',
                  onPressed: () {
                    // 重新启动发现服务
                    _discoveryService.restartDiscovery();
                    setDialogState(() {});
                    _showSnackBar('正在扫描局域网...', isError: false);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: StreamBuilder<List<DiscoveredComputer>>(
                stream: _discoveryService.computersStream,
                initialData: _discoveryService.discoveredComputers,
                builder: (context, snapshot) {
                  final computers = snapshot.data ?? [];
                  final wsService = context.read<WebSocketService>();
                  final currentIp = wsService.connectionModel.computerIp;

                  if (computers.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在扫描局域网中的服务端...'),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('发现 ${computers.length} 台电脑：'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: computers.length,
                          itemBuilder: (context, index) {
                            final computer = computers[index];
                            final isCurrent = computer.ip == currentIp &&
                                wsService.connectionModel.isConnected;

                            return Card(
                              color: isCurrent
                                  ? Colors.green.withOpacity(0.1)
                                  : null,
                              child: ListTile(
                                leading: Icon(
                                  computer.platform == 'macos'
                                      ? Icons.apple
                                      : Icons.computer,
                                  color: isCurrent ? Colors.green : null,
                                ),
                                title: Text(computer.name),
                                subtitle: Text(computer.ip),
                                trailing: isCurrent
                                    ? const Chip(
                                        label: Text('当前'),
                                        backgroundColor: Colors.green,
                                        labelStyle:
                                            TextStyle(color: Colors.white),
                                      )
                                    : ElevatedButton(
                                        onPressed: () async {
                                          // 先断开当前连接
                                          if (wsService
                                              .connectionModel.isConnected) {
                                            await wsService.disconnect();
                                          }

                                          // 连接到新服务端
                                          final success = await wsService.connect(
                                            computer,
                                            autoReconnect: true,
                                          );

                                          if (success && mounted) {
                                            Navigator.pop(context);
                                            _showSnackBar(
                                              '已切换到 ${computer.name}',
                                              isError: false,
                                            );
                                          } else if (mounted) {
                                            final errorMsg = wsService
                                                .connectionModel.errorMessage;
                                            _showSnackBar(errorMsg.isNotEmpty
                                                ? errorMsg
                                                : '连接失败');
                                          }
                                        },
                                        child: const Text('切换'),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  _discoveryService.restartDiscovery();
                  setDialogState(() {});
                  _showSnackBar('正在扫描局域网...', isError: false);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重新扫描'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示连接对话框
  void _showConnectionDialog() {
    final ipController = TextEditingController();
    bool isConnecting = false;
    bool isTesting = false;
    String? testResult;
    bool? testSuccess;
    String? savedIp;

    // 加载保存的 IP
    final wsService = context.read<WebSocketService>();
    savedIp = wsService.connectionModel.computerIp;
    if (savedIp.isNotEmpty) {
      ipController.text = savedIp;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  '连接设置',
                  style: TextStyle(fontSize: Constants.fontSizeLarge),
                ),
              ),
              // 关闭按钮
              IconButton(
                icon: const Icon(Icons.close, size: 24),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // 当前连接状态显示
                Consumer<WebSocketService>(
                  builder: (context, service, child) {
                    final isConnected = service.connectionModel.isConnected;
                    final currentIp = service.connectionModel.computerIp;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isConnected ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isConnected ? Icons.check_circle : Icons.cloud_off,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isConnected ? '已连接' : '未连接',
                                  style: TextStyle(
                                    fontSize: Constants.fontSizeNormal,
                                    fontWeight: FontWeight.bold,
                                    color: isConnected ? Colors.green : Colors.grey,
                                  ),
                                ),
                                if (isConnected && currentIp.isNotEmpty)
                                  Text(
                                    currentIp,
                                    style: TextStyle(
                                      fontSize: Constants.fontSizeSmall,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 显示已发现的服务列表
                StreamBuilder<List<DiscoveredComputer>>(
                  stream: _discoveryService.computersStream,
                  initialData: _discoveryService.discoveredComputers,
                  builder: (context, snapshot) {
                    final computers = snapshot.data ?? [];
                    if (computers.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '发现的电脑',
                          style: TextStyle(
                            fontSize: Constants.fontSizeNormal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...computers.map((computer) => ListTile(
                          dense: true,
                          leading: Icon(
                            computer.platform == 'macos'
                                ? Icons.apple
                                : Icons.computer,
                          ),
                          title: Text(
                            computer.name,
                            style: const TextStyle(fontSize: Constants.fontSizeSmall),
                          ),
                          subtitle: Text(
                            computer.ip,
                            style: const TextStyle(fontSize: Constants.fontSizeSmall),
                          ),
                          trailing: TextButton(
                            onPressed: isConnecting || isTesting
                                ? null
                                : () {
                                    ipController.text = computer.ip;
                                    setDialogState(() {});
                                  },
                            child: const Text('使用'),
                          ),
                        )),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
                const Text(
                  '电脑 IP 地址',
                  style: TextStyle(
                    fontSize: Constants.fontSizeNormal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ipController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  enabled: !isConnecting && !isTesting,
                  decoration: InputDecoration(
                    hintText: '例如: 192.168.1.100',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.computer),
                    suffixIcon: ipController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: isConnecting || isTesting
                                ? null
                                : () {
                                    ipController.clear();
                                    setDialogState(() {});
                                  },
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: Constants.fontSizeNormal),
                  onChanged: (_) => setDialogState(() {
                    testResult = null;
                    testSuccess = null;
                  }),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '端口: ${Constants.websocketPort}',
                      style: const TextStyle(
                        fontSize: Constants.fontSizeSmall,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    // 测试连接按钮
                    if (ipController.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: isConnecting || isTesting
                            ? null
                            : () async {
                                final ip = ipController.text.trim();
                                // 简单的 IP 格式验证
                                final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                                if (!ipRegex.hasMatch(ip)) {
                                  setDialogState(() {
                                    testResult = 'IP 地址格式不正确';
                                    testSuccess = false;
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isTesting = true;
                                  testResult = null;
                                  testSuccess = null;
                                });

                                // 测试连接
                                final success = await wsService.testConnection(
                                  ip,
                                  Constants.websocketPort,
                                );

                                if (mounted) {
                                  setDialogState(() {
                                    isTesting = false;
                                    testSuccess = success;
                                    testResult = success
                                        ? '连接测试成功！'
                                        : (wsService.connectionModel.errorMessage.isNotEmpty
                                            ? wsService.connectionModel.errorMessage
                                            : '连接测试失败');
                                  });
                                }
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check, size: 18),
                        label: const Text('测试连接'),
                      ),
                  ],
                ),
                // 测试结果提示
                if (testResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: testSuccess == true
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: testSuccess == true
                            ? Colors.green.withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          testSuccess == true ? Icons.check_circle : Icons.error,
                          color: testSuccess == true ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: TextStyle(
                              fontSize: Constants.fontSizeSmall,
                              color: testSuccess == true ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (savedIp != null && savedIp.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.history, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '上次：$savedIp',
                          style: TextStyle(
                            fontSize: Constants.fontSizeSmall,
                            color: Colors.blue[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                ],
              ),
            ),
          ),
          actions: [
            // 断开连接按钮（只在已连接时显示）
            Consumer<WebSocketService>(
              builder: (context, service, child) {
                final isConnected = service.connectionModel.isConnected;
                if (!isConnected) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: isConnecting || isTesting
                      ? null
                      : () async {
                          await wsService.disconnect();
                          _showSnackBar('已断开连接', isError: false);
                          setDialogState(() {});
                        },
                  icon: const Icon(Icons.link_off, color: Colors.red, size: 20),
                  label: const Text(
                    '断开',
                    style: TextStyle(color: Colors.red, fontSize: Constants.fontSizeNormal),
                  ),
                );
              },
            ),
            // 连接按钮
            ElevatedButton.icon(
              onPressed: isConnecting || isTesting
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

                      // 先重置状态，再判断是否关闭对话框
                      if (mounted) {
                        setDialogState(() => isConnecting = false);
                      }

                      if (success && mounted) {
                        Navigator.pop(context);
                        _showSnackBar('连接成功！', isError: false);
                      } else if (mounted) {
                        final errorMsg = wsService.connectionModel.errorMessage;
                        _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
                      }
                    },
              icon: isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link, size: 20),
              label: Text(
                isConnecting ? '连接中' : '连接',
                style: const TextStyle(fontSize: Constants.fontSizeNormal),
              ),
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
            icon: const Icon(Icons.settings),
            onPressed: _showConnectionDialog,
            tooltip: '连接设置',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Constants.paddingNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 在未连接状态下显示发现状态
              Consumer<WebSocketService>(
                builder: (context, wsService, child) {
                  if (wsService.connectionModel.isConnected) {
                    return const SizedBox.shrink();
                  }

                  return StreamBuilder<List<DiscoveredComputer>>(
                    stream: _discoveryService.computersStream,
                    initialData: _discoveryService.discoveredComputers,
                    builder: (context, snapshot) {
                      final computers = snapshot.data ?? [];

                      if (computers.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '正在搜索局域网中的电脑...',
                                  style: TextStyle(color: Colors.blue),
                                ),
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
                            if (computers.length > 1)
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
              // 文字输入区域 - 使用 Flexible 而不是 Expanded，避免键盘弹出时被压缩
              Flexible(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      // 文本输入框
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
                          // 为右上角按钮留出空间，右侧增加padding
                          contentPadding: const EdgeInsets.fromLTRB(
                            Constants.paddingNormal, 
                            Constants.paddingNormal, 
                            48, // 右侧留出空间给清空按钮
                            Constants.paddingNormal,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                      // 右上角清空按钮
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
