import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  TextRecognizer? _textRecognizer;
  bool _isDisposed = false;

  TextRecognizer get textRecognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.chinese);
    return _textRecognizer!;
  }

  Future<List<OcrTextBlock>> recognizeText(File imageFile) async {
    if (_isDisposed) {
      throw Exception('OcrService has been disposed');
    }

    try {
      final exists = await imageFile.exists();
      if (!exists) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }

      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        throw Exception('图片文件为空');
      }

      if (fileSize > 50 * 1024 * 1024) {
        throw Exception('图片文件过大，请选择较小的图片');
      }

      final inputImage = InputImage.fromFile(imageFile);
      
      final recognizedText = await textRecognizer.processImage(inputImage);

      if (_isDisposed) {
        return [];
      }

      List<OcrTextBlock> blocks = [];
      int index = 0;

      for (TextBlock block in recognizedText.blocks) {
        final text = block.text.trim();
        if (text.isNotEmpty) {
          blocks.add(OcrTextBlock(
            text: text,
            index: index++,
          ));
        }
      }

      return blocks;
    } on PlatformException catch (e) {
      debugPrint('OCR 平台异常: ${e.code} - ${e.message}');
      debugPrint('详细信息: ${e.details}');
      throw Exception('OCR识别失败: ${e.message ?? e.code}');
    } catch (e) {
      debugPrint('OCR 识别失败: $e');
      rethrow;
    }
  }

  void dispose() {
    _isDisposed = true;
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
