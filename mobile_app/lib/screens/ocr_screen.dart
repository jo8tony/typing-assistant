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

  /// 处理触摸事件（点击）
  void _handleTouch(int index) {
    setState(() {
      _wordBlocks[index].isSelected = !_wordBlocks[index].isSelected;
    });
  }

  /// 填充选中的文字到输入框
  void _fillSelectedText() {
    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      _showSnackBar('请先选择文字');
      return;
    }

    // 将选中的文字填充到输入框
    widget.onSend(selectedText);
    
    // 关闭 OCR 界面
    if (mounted) {
      Navigator.pop(context);
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
          // 已选择数量
          if (selectedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Constants.paddingNormal,
                vertical: Constants.paddingSmall,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    '已选择 $selectedCount 个词',
                    style: TextStyle(
                      fontSize: Constants.fontSizeNormal,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // 词块网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(Constants.paddingNormal),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 2.0,
              ),
              itemCount: _wordBlocks.length,
              itemBuilder: (context, index) {
                final word = _wordBlocks[index];
                return GestureDetector(
                  onTap: () => _handleTouch(index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: word.isSelected ? Colors.blue : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: word.isSelected ? Colors.blue : Colors.grey[300]!,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          word.text,
                          style: TextStyle(
                            fontSize: word.text.length > 6 
                                ? Constants.fontSizeSmall 
                                : Constants.fontSizeNormal,
                            color: word.isSelected ? Colors.white : Colors.black87,
                            fontWeight: word.isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
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
                    child: SizedBox(
                      height: Constants.buttonHeight,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.camera_alt, size: 20),
                        label: const Text(
                          '重拍',
                          style: TextStyle(fontSize: Constants.fontSizeNormal),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: Constants.paddingNormal),

                  // 确认按钮
                  Expanded(
                    child: SizedBox(
                      height: Constants.buttonHeight,
                      child: ElevatedButton.icon(
                        onPressed: selectedCount == 0 ? null : _fillSelectedText,
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text(
                          '确认',
                          style: TextStyle(fontSize: Constants.fontSizeNormal),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[300],
                          disabledForegroundColor: Colors.grey[500],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
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
