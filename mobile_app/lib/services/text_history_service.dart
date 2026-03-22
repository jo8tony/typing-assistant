import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文本历史记录服务
/// 支持保存最近 30 条发送记录
class TextHistoryService extends ChangeNotifier {
  static const String _historyKey = 'text_history';
  static const int _maxHistoryCount = 30;
  
  final List<String> _history = [];
  bool _isLoading = true;

  List<String> get history => List.unmodifiable(_history);
  bool get isLoading => _isLoading;

  TextHistoryService() {
    _loadHistory();
  }

  /// 加载历史记录
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);
      
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _history.clear();
        _history.addAll(decoded.cast<String>());
      }
    } catch (e) {
      debugPrint('加载文本历史记录失败：$e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 保存历史记录
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(_history);
      await prefs.setString(_historyKey, historyJson);
    } catch (e) {
      debugPrint('保存文本历史记录失败：$e');
    }
  }

  /// 添加新的历史记录
  Future<void> addHistory(String text) async {
    if (text.trim().isEmpty) return;

    // 移除重复的记录（如果存在）
    _history.remove(text);

    // 添加到列表开头
    _history.insert(0, text);

    // 限制历史记录数量
    if (_history.length > _maxHistoryCount) {
      _history.removeLast();
    }

    await _saveHistory();
    notifyListeners();
  }

  /// 删除指定历史记录
  Future<void> removeHistory(String text) async {
    if (_history.remove(text)) {
      await _saveHistory();
      notifyListeners();
    }
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  /// 获取最近 N 条记录
  List<String> getRecentHistory(int count) {
    if (count >= _history.length) {
      return List.from(_history);
    }
    return _history.sublist(0, count);
  }

}
