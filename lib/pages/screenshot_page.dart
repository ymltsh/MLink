import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../app/modules/screenshot/bloc/screenshot_cubit.dart';
import '../app/modules/screenshot/bloc/screenshot_state.dart';
import '../app/modules/screenshot/services/screenshot_service.dart';

class _CaptureIntent extends Intent {
  const _CaptureIntent();
}

class ScreenshotPage extends StatelessWidget {
  final String serial;
  const ScreenshotPage({Key? key, required this.serial}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ScreenshotCubit(ScreenshotService()),
      child: _ScreenshotView(serial: serial),
    );
  }
}

class _ScreenshotView extends StatefulWidget {
  final String serial;
  const _ScreenshotView({Key? key, required this.serial}) : super(key: key);

  @override
  State<_ScreenshotView> createState() => _ScreenshotViewState();
}

class _ScreenshotViewState extends State<_ScreenshotView> {
  late ScreenshotCubit cubit;

  @override
  void initState() {
    super.initState();
    cubit = context.read<ScreenshotCubit>();
    cubit.refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    // keyboard shortcuts: Enter / Space to capture
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.enter): const _CaptureIntent(),
        LogicalKeySet(LogicalKeyboardKey.space): const _CaptureIntent(),
      },
      child: Actions(
        actions: {
          _CaptureIntent: CallbackAction<_CaptureIntent>(onInvoke: (intent) {
            cubit.capture(widget.serial);
            return null;
          }),
        },
        child: BlocBuilder<ScreenshotCubit, ScreenshotState>(
          builder: (context, state) {
            final latest = state.latestScreenshot;
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.black12,
                            child: Stack(
                              children: [
                                if (latest != null && latest.existsSync())
                                  Center(
                                    child: GestureDetector(
                                      onTap: () => cubit.open(latest),
                                      child: Image.file(
                                        latest,
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                    ),
                                  )
                                else
                                  const Center(child: Text('暂无截图')),
                                if (state.isCapturing)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black26,
                                      child: const Center(child: CircularProgressIndicator()),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              icon: state.isCapturing ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.camera_alt),
                              label: const Text('立即截屏'),
                              onPressed: state.isCapturing ? null : () => cubit.capture(widget.serial),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('历史截图', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: state.history.isEmpty
                              ? const Center(child: Text('无历史记录'))
                              : GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1),
                                  itemCount: state.history.length,
                                  itemBuilder: (context, index) {
                                    final file = state.history[index];
                                    return GestureDetector(
                                      onTap: () {
                                        cubit.setPreview(file);
                                      },
                                      onDoubleTap: () => cubit.open(file),
                                      child: Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Image.file(file, fit: BoxFit.cover),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
