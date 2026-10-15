import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/screenshot_service.dart';
import 'screenshot_state.dart';

class ScreenshotCubit extends Cubit<ScreenshotState> {
  final ScreenshotService _service;
  Timer? _timer;
  bool _closing = false;
  int _historyGeneration = 0;
  bool get _alive => !_closing && !isClosed;
  ScreenshotCubit(this._service) : super(ScreenshotState()) {
    unawaited(refreshHistory());
  }
  @override
  Future<void> close() {
    _closing = true;
    _historyGeneration++;
    _timer?.cancel();
    _service.dispose();
    return super.close();
  }

  Future<void> capture(String serial) async {
    if (!_alive || state.isCapturing) return;
    emit(state.copyWith(isCapturing: true, errorMessage: null));
    try {
      final file = await _service.captureScreen(serial);
      if (!_alive) return;
      _historyGeneration++;
      final history = await _service.loadHistory();
      if (!_alive) return;
      emit(state.copyWith(
          latestScreenshot: file,
          history: history,
          isCapturing: false,
          continuousCaptureCount: state.isContinuousCapturing
              ? state.continuousCaptureCount + 1
              : 0));
    } catch (error) {
      if (!_alive) return;
      _timer?.cancel();
      emit(state.copyWith(
          isCapturing: false,
          isContinuousCapturing: false,
          errorMessage: '截图失败：$error'));
    }
  }

  void startContinuousCapture(String serial) {
    if (!_alive || state.isContinuousCapturing) return;
    emit(state.copyWith(
        isContinuousCapturing: true,
        continuousCaptureCount: 0,
        errorMessage: null));
    _timer =
        Timer.periodic(Duration(seconds: state.continuousCaptureInterval), (_) {
      if (_alive && state.isContinuousCapturing) unawaited(capture(serial));
    });
    unawaited(capture(serial));
  }

  void stopContinuousCapture() {
    _timer?.cancel();
    _timer = null;
    if (_alive) emit(state.copyWith(isContinuousCapturing: false));
  }

  void setContinuousCaptureInterval(int interval, {String? serial}) {
    if (!_alive) return;
    emit(state.copyWith(continuousCaptureInterval: interval.clamp(1, 60)));
    if (state.isContinuousCapturing && serial != null) {
      stopContinuousCapture();
      startContinuousCapture(serial);
    }
  }

  Future<void> refreshHistory() async {
    if (!_alive) return;
    final generation = ++_historyGeneration;
    try {
      final history = await _service.loadHistory();
      if (_alive && generation == _historyGeneration) {
        emit(state.copyWith(history: history));
      }
    } catch (error) {
      if (_alive && generation == _historyGeneration) {
        emit(state.copyWith(errorMessage: '读取截图记录失败：$error'));
      }
    }
  }

  Future<void> open(File file) async {
    if (!_alive) return;
    try {
      await _service.openImage(file.path);
    } catch (error) {
      if (_alive) emit(state.copyWith(errorMessage: '打开截图失败：$error'));
    }
  }

  void setPreview(File file) {
    if (_alive) emit(state.copyWith(latestScreenshot: file));
  }
}
