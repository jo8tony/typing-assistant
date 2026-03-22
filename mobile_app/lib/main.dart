import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'services/ocr_service.dart';
import 'services/text_history_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置屏幕方向为竖屏
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // 预初始化 OCR 服务，提前触发模型加载
  _preloadOcrService();
  
  runApp(const TypingAssistantApp());
}

/// 预加载 OCR 服务
Future<void> _preloadOcrService() async {
  try {
    debugPrint('正在预初始化 OCR 服务...');
    final ocrService = OcrService();
    // 访问 textRecognizer getter 来触发初始化
    ocrService.textRecognizer;
    debugPrint('OCR 服务预初始化完成');
  } catch (e) {
    debugPrint('OCR 服务预初始化失败: $e');
  }
}

class TypingAssistantApp extends StatelessWidget {
  const TypingAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => TextHistoryService()),
        Provider<OcrService>(
          create: (_) => OcrService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: '跨设备打字助手',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          // 设置全局字体大小，适合中年人
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 20),
            bodyMedium: TextStyle(fontSize: 18),
            bodySmall: TextStyle(fontSize: 16),
            titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            titleSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          // 按钮主题
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // 输入框主题
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
