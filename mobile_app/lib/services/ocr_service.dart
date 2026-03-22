import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  Future<List<OcrTextBlock>> recognizeText(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }

      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      List<OcrTextBlock> blocks = [];
      int index = 0;

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
      rethrow;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
