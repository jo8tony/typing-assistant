import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import '../utils/constants.dart';

/// OCR 结果选择界面
class OcrScreen extends StatefulWidget {
  final List<OcrTextBlock> textBlocks;
  final Function(String) onSend;

  const OcrScreen({
    super.key,
    required this.textBlocks,
    required this.onSend,
  });

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  late List<OcrTextBlock> _blocks;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.textBlocks);
  }

  /// 获取选中的文字
  String _getSelectedText() {
    final selectedBlocks = _blocks.where((b) => b.isSelected).toList();
    if (selectedBlocks.isEmpty) return '';
    return selectedBlocks.map((b) => b.text).join('\n');
  }

  /// 发送选中的文字
  Future<void> _sendSelectedText() async {
    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      _showSnackBar('请先选择要发送的文字');
      return;
    }

    setState(() => _isSending = true);

    try {
      await widget.onSend(selectedText);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar('发送失败: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  /// 显示提示
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: Constants.fontSizeNormal),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _blocks.where((b) => b.isSelected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '选择要发送的文字',
          style: TextStyle(fontSize: Constants.fontSizeLarge),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 提示信息
          Container(
            padding: const EdgeInsets.all(Constants.paddingNormal),
            color: Colors.blue.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点击文字块进行选择，再次点击取消选择',
                    style: TextStyle(
                      fontSize: Constants.fontSizeNormal,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 已选择数量
          if (selectedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Constants.paddingNormal,
                vertical: Constants.paddingSmall,
              ),
              color: Colors.green.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Text(
                    '已选择 $selectedCount 段文字',
                    style: TextStyle(
                      fontSize: Constants.fontSizeNormal,
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // 文字列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(Constants.paddingNormal),
              itemCount: _blocks.length,
              itemBuilder: (context, index) {
                final block = _blocks[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: Constants.paddingSmall),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        block.isSelected = !block.isSelected;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(Constants.paddingNormal),
                      decoration: BoxDecoration(
                        color: block.isSelected
                            ? Colors.green.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: block.isSelected
                              ? Colors.green
                              : Colors.grey.withOpacity(0.3),
                          width: block.isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            block.isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: block.isSelected ? Colors.green : Colors.grey,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              block.text,
                              style: TextStyle(
                                fontSize: Constants.fontSizeLarge,
                                color: block.isSelected
                                    ? Colors.green[800]
                                    : Colors.black87,
                                fontWeight: block.isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 底部按钮
          Container(
            padding: const EdgeInsets.all(Constants.paddingNormal),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 重拍按钮
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: Constants.buttonHeight,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.refresh, size: 24),
                        label: const Text(
                          '重拍',
                          style: TextStyle(fontSize: Constants.fontSizeNormal),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: Constants.paddingNormal),

                  // 发送按钮
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: Constants.buttonHeightLarge,
                      child: ElevatedButton.icon(
                        onPressed: _isSending || selectedCount == 0
                            ? null
                            : _sendSelectedText,
                        icon: _isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send, size: 28),
                        label: Text(
                          _isSending
                              ? '发送中...'
                              : '发送 ($selectedCount)',
                          style: const TextStyle(
                            fontSize: Constants.fontSizeLarge,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.green.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
