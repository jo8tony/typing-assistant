import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import '../utils/constants.dart';

/// OCR 结果选择界面（支持词块拆分和滑动选择）
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
  late List<OcrWordBlock> _wordBlocks;
  bool _isSending = false;
  bool _isSelectionMode = false;
  int? _lastTouchedIndex;

  @override
  void initState() {
    super.initState();
    _wordBlocks = _splitBlocksIntoWords(widget.textBlocks);
  }

  /// 将大块文本拆分成词块
  List<OcrWordBlock> _splitBlocksIntoWords(List<OcrTextBlock> blocks) {
    List<OcrWordBlock> words = [];
    int wordIndex = 0;

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      // 按空格、标点符号等拆分，但保留中文词语
      final text = block.text.trim();
      
      // 简单的拆分逻辑：按空格和标点拆分
      final RegExp splitPattern = RegExp(r'[\s,，.。！？!？;；:：、]+');
      final parts = text.split(splitPattern).where((s) => s.isNotEmpty).toList();
      
      for (final part in parts) {
        words.add(OcrWordBlock(
          text: part,
          originalIndex: i,
          wordIndex: wordIndex++,
        ));
      }
      
      // 如果没有拆分出任何部分，至少保留原文本
      if (parts.isEmpty && text.isNotEmpty) {
        words.add(OcrWordBlock(
          text: text,
          originalIndex: i,
          wordIndex: wordIndex++,
        ));
      }
    }

    return words;
  }

  /// 获取选中的文字
  String _getSelectedText() {
    final selectedWords = _wordBlocks.where((w) => w.isSelected).toList();
    if (selectedWords.isEmpty) return '';
    
    // 按顺序组合选中的词块
    selectedWords.sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    
    // 智能组合：中文不加空格，英文加空格
    final buffer = StringBuffer();
    String? lastText;
    
    for (final word in selectedWords) {
      if (buffer.isEmpty) {
        buffer.write(word.text);
      } else {
        // 判断是否需要添加空格
        final needSpace = _needSpaceBetween(lastText!, word.text);
        if (needSpace) {
          buffer.write(' ');
        }
        buffer.write(word.text);
      }
      lastText = word.text;
    }
    
    return buffer.toString();
  }

  /// 判断两个文本之间是否需要空格
  bool _needSpaceBetween(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return false;
    
    final lastChar = text1.codeUnitAt(text1.length - 1);
    final firstChar = text2.codeUnitAt(0);
    
    // 中文字符范围
    final isLastCharChinese = lastChar >= 0x4E00 && lastChar <= 0x9FFF;
    final isFirstCharChinese = firstChar >= 0x4E00 && firstChar <= 0x9FFF;
    
    // 如果最后字符和首字符都是中文，不需要空格
    if (isLastCharChinese && isFirstCharChinese) {
      return false;
    }
    
    // 其他情况添加空格
    return true;
  }

  /// 处理触摸事件（点击或滑动）
  void _handleTouch(int index) {
    if (_lastTouchedIndex != null) {
      // 滑动选择：选中两个索引之间的所有词块
      final start = _lastTouchedIndex! < index ? _lastTouchedIndex! : index;
      final end = _lastTouchedIndex! < index ? index : _lastTouchedIndex!;
      
      for (int i = start; i <= end; i++) {
        _wordBlocks[i].isSelected = true;
      }
    } else {
      // 点击选择：切换单个词块的状态
      setState(() {
        _wordBlocks[index].isSelected = !_wordBlocks[index].isSelected;
      });
    }
    
    _lastTouchedIndex = index;
    setState(() {});
  }

  /// 结束滑动选择
  void _endDrag() {
    _lastTouchedIndex = null;
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
    final selectedCount = _wordBlocks.where((w) => w.isSelected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '选择文字',
          style: TextStyle(fontSize: Constants.fontSizeLarge),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (selectedCount > 0)
            TextButton(
              onPressed: () {
                setState(() {
                  for (var word in _wordBlocks) {
                    word.isSelected = false;
                  }
                });
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 提示信息
          Container(
            padding: const EdgeInsets.all(Constants.paddingNormal),
            color: Colors.blue.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.touch_app, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点击或滑动选择词块，再次点击取消',
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
                    '已选择 $selectedCount 个词块',
                    style: TextStyle(
                      fontSize: Constants.fontSizeNormal,
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // 词块网格
          Expanded(
            child: GestureDetector(
              onPanEnd: (_) => _endDrag(),
              child: GridView.builder(
                padding: const EdgeInsets.all(Constants.paddingNormal),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.5,
                ),
                itemCount: _wordBlocks.length,
                itemBuilder: (context, index) {
                  final word = _wordBlocks[index];
                  return GestureDetector(
                    onTap: () => _handleTouch(index),
                    onTapDown: (_) => _handleTouch(index),
                    onPanUpdate: (details) {
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localPosition = renderBox.globalToLocal(details.globalPosition);
                      final size = renderBox.size;
                      
                      // 检查是否在网格内
                      if (localPosition.dx >= 0 && 
                          localPosition.dx <= size.width &&
                          localPosition.dy >= 0 && 
                          localPosition.dy <= size.height) {
                        _handleTouch(index);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: word.isSelected
                            ? Colors.green.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: word.isSelected
                              ? Colors.green
                              : Colors.grey.withOpacity(0.3),
                          width: word.isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            word.text,
                            style: TextStyle(
                              fontSize: word.text.length > 10 
                                  ? Constants.fontSizeSmall 
                                  : Constants.fontSizeNormal,
                              color: word.isSelected
                                  ? Colors.green[800]
                                  : Colors.black87,
                              fontWeight: word.isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
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
                              : '发送选中的',
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
