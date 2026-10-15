class MirrorConfig {
  final String bitrate;
  final String maxSize;
  final String dpi;
  final bool turnScreenOff;
  final bool h265;
  final bool physicalKeyboard;
  final bool disableAudio;
  final bool record;
  const MirrorConfig(
      {this.bitrate = '8',
      this.maxSize = '1080',
      this.dpi = '420',
      this.turnScreenOff = false,
      this.h265 = false,
      this.physicalKeyboard = false,
      this.disableAudio = false,
      this.record = false});

  static String _integer(String value, String label) {
    final number = int.tryParse(value.trim());
    if (number == null || number < 1 || number > 32768) {
      throw FormatException('$label 必须是 1–32768 的整数');
    }
    return number.toString();
  }

  List<String> command(
      {String bitrateOverride = '',
      String sizeOverride = '',
      bool audioOnly = false,
      bool camera = false,
      String? package,
      String displaySize = '',
      String dpiOverride = ''}) {
    final args = ['scrcpy'];
    if (audioOnly) {
      args.add('--no-video');
    } else {
      final rate = bitrateOverride.trim().isEmpty
          ? bitrate.trim()
          : bitrateOverride.trim();
      final parsed = int.tryParse(rate);
      if (parsed == null || parsed < 1 || parsed > 1000) {
        throw const FormatException('码率必须是 1–1000 的整数（M）');
      }
      args.add('--video-bit-rate=${parsed}M');
      args.add(
          '--max-size=${_integer(sizeOverride.trim().isEmpty ? maxSize : sizeOverride, '分辨率最大值')}');
      if (h265) args.add('--video-codec=h265');
      if (camera) args.add('--video-source=camera');
    }
    if (turnScreenOff) args.add('--turn-screen-off');
    if (physicalKeyboard) args.add('--keyboard=uhid');
    if (disableAudio && !audioOnly) args.add('--no-audio');
    if (record) {
      args.add('--record=scrcpy_${DateTime.now().microsecondsSinceEpoch}.mp4');
    }
    if (package != null) {
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$')
          .hasMatch(package)) {
        throw const FormatException('请输入有效的应用包名');
      }
      var display = displaySize.trim();
      if (display.isNotEmpty) {
        final parts = display.split('x');
        if (parts.length != 2) throw const FormatException('虚拟显示分辨率格式应为 宽x高');
        display = '${_integer(parts[0], '显示宽度')}x${_integer(parts[1], '显示高度')}';
      }
      final density =
          _integer(dpiOverride.trim().isEmpty ? dpi : dpiOverride, 'DPI');
      args.addAll([
        '--start-app=$package',
        '--new-display=$display/$density',
        '--no-vd-system-decorations'
      ]);
    }
    return args;
  }
}
