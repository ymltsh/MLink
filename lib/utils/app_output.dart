import 'dart:collection';
import 'package:flutter/foundation.dart';

class AppLogEntry {
  final String task;
  final String message;
  AppLogEntry(this.task, this.message);
  @override
  String toString() => '[$task] $message';
}

/// 按消息保存有界日志；界面读取时才合并文本。
class AppLogBuffer extends ChangeNotifier implements ValueListenable<String> {
  final int maxEntries;
  final int maxCharacters;
  final Queue<AppLogEntry> _entries = Queue();
  int _characters = 0;
  String? _cached;
  AppLogBuffer({this.maxEntries = 500, this.maxCharacters = 65536}) {
    if (maxEntries < 1 || maxCharacters < 32) throw ArgumentError('日志容量过小');
  }
  List<AppLogEntry> get entries => List.unmodifiable(_entries);
  @override
  String get value => _cached ??= _entries.join('\n');

  void append(String message, {String task = '应用'}) {
    if (message.isEmpty) return;
    if (task.length > maxCharacters ~/ 4) {
      task = task.substring(0, maxCharacters ~/ 4);
    }
    var entry = AppLogEntry(task, message);
    final available = maxCharacters - task.length - 4;
    if (message.length > available) {
      entry = AppLogEntry(
          task, '…${message.substring(message.length - available + 1)}');
    }
    _entries.add(entry);
    _characters += entry.toString().length + 1;
    while (_entries.length > maxEntries || _characters > maxCharacters) {
      _characters -= _entries.removeFirst().toString().length + 1;
    }
    _cached = null;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _characters = 0;
    _cached = null;
    notifyListeners();
  }
}

final appOutputNotifier = AppLogBuffer();
void appendAppOutput(String line, {String task = '文件'}) =>
    appOutputNotifier.append(line, task: task);
void clearAppOutput() => appOutputNotifier.clear();
