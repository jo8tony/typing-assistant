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
    if (_textRecognizer == null) {
      try {
        debugPrint('初始化 OCR 识别器（默认模式，支持多语言）');
        _textRecognizer = TextRecognizer();
        debugPrint('OCR 识别器初始化成功');
      } catch (e) {
        debugPrint('创建默认 TextRecognizer 失败: $e');
        try {
          debugPrint('尝试使用 Latin 脚本作为备用');
          _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        } catch (e2) {
          debugPrint('创建 Latin TextRecognizer 也失败: $e2');
          rethrow;
        }
      }
    }
    return _textRecognizer!;
  }

  Future<List<OcrTextBlock>> recognizeText(File imageFile) async {
    if (_isDisposed) {
      debugPrint('OcrService has been disposed');
      return [];
    }

    try {
      debugPrint('开始 OCR 识别，图片路径: ${imageFile.path}');
      
      final exists = await imageFile.exists();
      debugPrint('图片文件存在: $exists');
      if (!exists) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }

      final fileSize = await imageFile.length();
      debugPrint('图片文件大小: $fileSize bytes');
      if (fileSize == 0) {
        throw Exception('图片文件为空');
      }

      if (fileSize > 50 * 1024 * 1024) {
        throw Exception('图片文件过大，请选择较小的图片');
      }

      debugPrint('准备 InputImage');
      final inputImage = InputImage.fromFile(imageFile);
      
      debugPrint('开始 processImage');
      final recognizedText = await textRecognizer.processImage(inputImage);
      debugPrint('processImage 完成');

      if (_isDisposed) {
        debugPrint('OcrService 已被释放');
        return [];
      }

      debugPrint('原始识别结果 - 完整文本: ${recognizedText.text}');
      debugPrint('原始识别结果 - 文字块数量: ${recognizedText.blocks.length}');

      List<OcrTextBlock> blocks = [];
      int index = 0;

      if (recognizedText.blocks.isEmpty) {
        debugPrint('未识别到文字块');
        return blocks;
      }

      for (TextBlock block in recognizedText.blocks) {
        final text = block.text.trim();
        debugPrint('文字块 $index: $text');
        if (text.isNotEmpty) {
          blocks.add(OcrTextBlock(
            text: text,
            index: index++,
          ));
        }
      }

      debugPrint('最终识别到 ${blocks.length} 个有效文字块');
      return blocks;
    } on PlatformException catch (e) {
      debugPrint('OCR 平台异常: ${e.code} - ${e.message}');
      debugPrint('详细信息: ${e.details}');
      if (e.code == 'modelNotFound') {
        throw Exception('OCR模型未找到，请确保网络连接正常以首次下载模型');
      }
      throw Exception('OCR识别失败: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      debugPrint('OCR 识别失败: $e');
      debugPrint('堆栈: $stackTrace');
      rethrow;
    }
  }

  void dispose() {
    _isDisposed = true;
    if (_textRecognizer != null) {
      try {
        _textRecognizer!.close();
      } catch (e) {
        debugPrint('关闭 TextRecognizer 失败: $e');
      }
      _textRecognizer = null;
    }
  }
}
