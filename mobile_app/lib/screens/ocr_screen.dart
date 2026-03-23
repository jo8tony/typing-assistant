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

  @override
  void initState() {
    super.initState();
    _wordBlocks = _splitBlocksIntoCharacters(widget.textBlocks);
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

  void _fillSelectedText() {
    final selectedText = _getSelectedText();
    if (selectedText.isEmpty) {
      _showSnackBar('请先选择文字');
      return;
    }

    widget.onSend(selectedText);

    if (mounted) {
      Navigator.pop(context);
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: selectedCount > 0 ? 40 : 0,
            child: selectedCount > 0
                ? Container(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '已选择 $selectedCount 个字符',
                          style: TextStyle(
                            fontSize: Constants.fontSizeNormal,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _handleWordTap(index);
      },
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
              color: Colors.black.withOpacity(0.05),
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