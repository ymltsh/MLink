import 'package:flutter/foundation.dart';

/// A small global notifier used to show logs in the main output panel.
final ValueNotifier<String> appOutputNotifier = ValueNotifier<String>('');

/// Append a line to the app output (keeps existing content and adds a newline).
void appendAppOutput(String line) {
  final prev = appOutputNotifier.value;
  if (prev.isEmpty) {
    appOutputNotifier.value = line;
  } else {
    appOutputNotifier.value = '$prev\n$line';
  }
}
