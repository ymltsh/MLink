import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/screenshot_service.dart';
import 'screenshot_state.dart';

class ScreenshotCubit extends Cubit<ScreenshotState> {
  final ScreenshotService _service;
  Timer? _continuousCaptureTimer;

  ScreenshotCubit(this._service) : super(ScreenshotState()) {
    refreshHistory();
  }

  @override
  Future<void> close() {
    _continuousCaptureTimer?.cancel();
    return super.close();
  }

  Future<void> capture(String serial) async {
    if (state.isCapturing) return;
    emit(state.copyWith(isCapturing: true));
    try {
      final file = await _service.captureScreen(serial);
      final history = await _service.loadHistory();
      emit(state.copyWith(
        latestScreenshot: file, 
        history: history, 
        isCapturing: false,
        continuousCaptureCount: state.isContinuousCapturing ? state.continuousCaptureCount + 1 : 0,
      ));
    } catch (e) {
      emit(state.copyWith(isCapturing: false));
      rethrow;
    }
  }

  /// 开始连续截屏
  void startContinuousCapture(String serial) {
    if (state.isContinuousCapturing) return;
    
    emit(state.copyWith(
      isContinuousCapturing: true,
      continuousCaptureCount: 0,
    ));
    
    // 立即执行第一次截屏
    capture(serial);
    
    // 设置定时器，每隔指定时间执行截屏
    _continuousCaptureTimer = Timer.periodic(
      Duration(seconds: state.continuousCaptureInterval), 
      (timer) {
        if (state.isContinuousCapturing) {
          capture(serial);
        } else {
          timer.cancel();
        }
      }
    );
  }

  /// 停止连续截屏
  void stopContinuousCapture() {
    if (!state.isContinuousCapturing) return;
    
    _continuousCaptureTimer?.cancel();
    _continuousCaptureTimer = null;
    
    emit(state.copyWith(
      isContinuousCapturing: false,
    ));
  }

  /// 设置连续截屏间隔时间
  void setContinuousCaptureInterval(int interval, {String? serial}) {
    if (interval < 1) interval = 1; // 最小间隔1秒
    if (interval > 60) interval = 60; // 最大间隔60秒
    
    emit(state.copyWith(continuousCaptureInterval: interval));
    
    // 如果正在连续截屏，需要重启定时器
    if (state.isContinuousCapturing && serial != null) {
      stopContinuousCapture();
      startContinuousCapture(serial);
    }
  }

  Future<void> refreshHistory() async {
    final history = await _service.loadHistory();
    emit(state.copyWith(history: history));
  }

  Future<void> open(File file) async {
    try {
      await _service.openImage(file.path);
    } catch (e) {
      // ignore
    }
  }

  /// Set the preview image without changing history.
  void setPreview(File file) {
    emit(state.copyWith(latestScreenshot: file));
  }
}
