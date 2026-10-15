import 'dart:io';

class ScreenshotState {
  static const _unchanged = Object();
  final String? errorMessage;
  final File? latestScreenshot;
  final List<File> history;
  final bool isCapturing;
  final bool isContinuousCapturing;
  final int continuousCaptureInterval;
  final int continuousCaptureCount;

  ScreenshotState({
    this.errorMessage,
    this.latestScreenshot,
    List<File>? history,
    this.isCapturing = false,
    this.isContinuousCapturing = false,
    this.continuousCaptureInterval = 5, // 默认5秒
    this.continuousCaptureCount = 0,
  }) : history = history ?? [];

  ScreenshotState copyWith({
    Object? errorMessage = _unchanged,
    File? latestScreenshot,
    List<File>? history,
    bool? isCapturing,
    bool? isContinuousCapturing,
    int? continuousCaptureInterval,
    int? continuousCaptureCount,
  }) {
    return ScreenshotState(
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      latestScreenshot: latestScreenshot ?? this.latestScreenshot,
      history: history ?? this.history,
      isCapturing: isCapturing ?? this.isCapturing,
      isContinuousCapturing:
          isContinuousCapturing ?? this.isContinuousCapturing,
      continuousCaptureInterval:
          continuousCaptureInterval ?? this.continuousCaptureInterval,
      continuousCaptureCount:
          continuousCaptureCount ?? this.continuousCaptureCount,
    );
  }
}
