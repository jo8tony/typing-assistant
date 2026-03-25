import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import '../utils/constants.dart';

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
  final Map<int, GlobalKey> _chipKeys = {};
  final Set<int> _lastSelectedIndices = {};
  bool _initialToggleState = false;
  int? _dragStartIndex;

  @override
  void initState() {
    super.initState();
    _wordBlocks = _splitBlocksIntoCharacters(widget.textBlocks);
    for (int i = 0; i < _wordBlocks.length; i++) {
      _chipKeys[i] = GlobalKey();
    }
  }

  List<OcrWordBlock> _splitBlocksIntoCharacters(List<OcrTextBlock> blocks) {
    List<OcrWordBlock> characters = [];
    int charIndex = 0;

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final text = block.text;

      for (int j = 0; j < text.length; j++) {
        final char = text[j];

        if (char.trim().isEmpty) continue;

        characters.add(OcrWordBlock(
          text: char,
          originalIndex: i,
          charIndex: charIndex++,
        ));
      }
    }

    return characters;
  }

  String _getSelectedText() {
    final selectedChars = _wordBlocks.where((w) => w.isSelected).toList();
    if (selectedChars.isEmpty) return '';

    selectedChars.sort((a, b) => a.charIndex.compareTo(b.charIndex));

    final buffer = StringBuffer();
    for (final char in selectedChars) {
      buffer.write(char.text);
    }

    return buffer.toString();
  }

  void _handleWordTap(int index) {
    setState(() {
      _wordBlocks[index].isSelected = !_wordBlocks[index].isSelected;
    });
  }

  int? _findChipIndexAtPosition(Offset globalPosition) {
    int? closestIndex;
    double closestDistance = double.infinity;

    for (int i = 0; i < _wordBlocks.length; i++) {
      final key = _chipKeys[i];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox;
        final size = box.size;
        final position = box.localToGlobal(Offset.zero);

        final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
        // 扩展检测区域，增加灵敏度（上下左右各扩展 10 像素）
        final expandedRect = rect.inflate(10);

        if (expandedRect.contains(globalPosition)) {
          // 计算手指位置到字符中心的距离
          final center = Offset(
            position.dx + size.width / 2,
            position.dy + size.height / 2,
          );
          final distance = (center - globalPosition).distance;

          if (distance < closestDistance) {
            closestDistance = distance;
            closestIndex = i;
          }
        }
      }
    }
    return closestIndex;
  }

  void _onPanStart(DragStartDetails details) {
    _lastSelectedIndices.clear();
    final index = _findChipIndexAtPosition(details.globalPosition);
    if (index != null) {
      _dragStartIndex = index;
      _initialToggleState = !_wordBlocks[index].isSelected;
      setState(() {
        _wordBlocks[index].isSelected = _initialToggleState;
        _lastSelectedIndices.add(index);
      });
    } else {
      // 如果没有找到字符，记录当前位置，尝试在 update 时找到
      _dragStartIndex = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final currentIndex = _findChipIndexAtPosition(details.globalPosition);
    if (currentIndex == null) return;

    // 如果在 start 时没有找到起始字符，现在找到了，设置为起始
    if (_dragStartIndex == null) {
      _dragStartIndex = currentIndex;
      _initialToggleState = !_wordBlocks[currentIndex].isSelected;
    }

    // 计算起始和结束索引
    final startIndex = _dragStartIndex! < currentIndex ? _dragStartIndex! : currentIndex;
    final endIndex = _dragStartIndex! < currentIndex ? currentIndex : _dragStartIndex!;

    setState(() {
      // 选中起始行开始到结束行结束之间的所有字符
      for (int i = startIndex; i <= endIndex; i++) {
        if (!_lastSelectedIndices.contains(i)) {
          _wordBlocks[i].isSelected = _initialToggleState;
          _lastSelectedIndices.add(i);
        }
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _lastSelectedIndices.clear();
    _dragStartIndex = null;
  }

  void _fillSelectedText() {
    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      _showSnackBar('请先选择文字');
      return;
    }

    // 先关闭页面，再回调，避免页面切换时的视觉异常
    if (mounted) {
      Navigator.pop(context, selectedText);
    }
  }

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
          Container(
            height: 40,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selectedCount > 0 ? Icons.check_circle : Icons.info_outline,
                  color: selectedCount > 0 ? Colors.blue[700] : Colors.grey[400],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  selectedCount > 0 ? '已选择 $selectedCount 个字符' : '点击或滑动选择文字',
                  style: TextStyle(
                    fontSize: Constants.fontSizeNormal,
                    color: selectedCount > 0 ? Colors.blue[700] : Colors.grey[500],
                    fontWeight: selectedCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                color: Colors.grey[100],
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Constants.paddingNormal),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _wordBlocks.asMap().entries.map((entry) {
                      return _buildWordChip(entry.key, entry.value);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(Constants.paddingNormal),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
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

  Widget _buildWordChip(int index, OcrWordBlock word) {
    return GestureDetector(
      key: _chipKeys[index],
      onTap: () => _handleWordTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: word.isSelected ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: word.isSelected ? Colors.blue : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          word.text,
          style: TextStyle(
            fontSize: Constants.fontSizeNormal,
            color: word.isSelected ? Colors.white : Colors.black87,
            fontWeight: word.isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}