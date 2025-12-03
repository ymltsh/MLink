import 'dart:io';

class ScreenshotState {
  final File? latestScreenshot;
  final List<File> history;
  final bool isCapturing;
  final bool isContinuousCapturing;
  final int continuousCaptureInterval;
  final int continuousCaptureCount;

  ScreenshotState({
    this.latestScreenshot, 
    List<File>? history, 
    this.isCapturing = false,
    this.isContinuousCapturing = false,
    this.continuousCaptureInterval = 5, // 默认5秒
    this.continuousCaptureCount = 0,
  }) : history = history ?? [];

  ScreenshotState copyWith({
    File? latestScreenshot, 
    List<File>? history, 
    bool? isCapturing,
    bool? isContinuousCapturing,
    int? continuousCaptureInterval,
    int? continuousCaptureCount,
  }) {
    return ScreenshotState(
      latestScreenshot: latestScreenshot ?? this.latestScreenshot,
      history: history ?? this.history,
      isCapturing: isCapturing ?? this.isCapturing,
      isContinuousCapturing: isContinuousCapturing ?? this.isContinuousCapturing,
      continuousCaptureInterval: continuousCaptureInterval ?? this.continuousCaptureInterval,
      continuousCaptureCount: continuousCaptureCount ?? this.continuousCaptureCount,
    );
  }
}
