import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/screenshot_service.dart';
import 'screenshot_state.dart';

class ScreenshotCubit extends Cubit<ScreenshotState> {
  final ScreenshotService _service;

  ScreenshotCubit(this._service) : super(ScreenshotState()) {
    refreshHistory();
  }

  Future<void> capture(String serial) async {
    if (state.isCapturing) return;
    emit(state.copyWith(isCapturing: true));
    try {
      final file = await _service.captureScreen(serial);
      final history = await _service.loadHistory();
      emit(state.copyWith(latestScreenshot: file, history: history, isCapturing: false));
    } catch (e) {
      emit(state.copyWith(isCapturing: false));
      rethrow;
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
