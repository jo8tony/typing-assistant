import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR 识别的文字块
class OcrTextBlock {
  final String text;
  final int index;
  bool isSelected;

  OcrTextBlock({
    required this.text,
    required this.index,
    this.isSelected = false,
  });
}

/// OCR 文字识别服务 - 支持中文
class OcrService {
  // 使用中文脚本配置 TextRecognizer
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  /// 识别图片中的文字
  Future<List<OcrTextBlock>> recognizeText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      List<OcrTextBlock> blocks = [];
      int index = 0;

      // 按文本块分割
      for (TextBlock block in recognizedText.blocks) {
        if (block.text.trim().isNotEmpty) {
          blocks.add(OcrTextBlock(
            text: block.text.trim(),
            index: index++,
          ));
        }
      }

      return blocks;
    } catch (e) {
      print('OCR 识别失败: $e');
      throw Exception('文字识别失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _textRecognizer.close();
  }
}
