import 'dart:io';

class ScreenshotState {
  final File? latestScreenshot;
  final List<File> history;
  final bool isCapturing;

  ScreenshotState({this.latestScreenshot, List<File>? history, this.isCapturing = false}) : history = history ?? [];

  ScreenshotState copyWith({File? latestScreenshot, List<File>? history, bool? isCapturing}) {
    return ScreenshotState(
      latestScreenshot: latestScreenshot ?? this.latestScreenshot,
      history: history ?? this.history,
      isCapturing: isCapturing ?? this.isCapturing,
    );
  }
}
