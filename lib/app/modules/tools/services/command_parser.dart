/// 将命令行拆为独立参数；保留 Windows 路径的反斜杠，不调用本地 shell。
List<String> parseToolCommand(String text) {
  final result = <String>[];
  var token = StringBuffer();
  String? quote;
  var started = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == r'\' &&
        quote != "'" &&
        i + 1 < text.length &&
        (text[i + 1] == '"' ||
            quote == null && RegExp(r'\s').hasMatch(text[i + 1]))) {
      token.write(text[++i]);
      started = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        token.write(char);
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      started = true;
    } else if (RegExp(r'\s').hasMatch(char)) {
      if (started) {
        result.add(token.toString());
        token = StringBuffer();
        started = false;
      }
    } else {
      token.write(char);
      started = true;
    }
  }
  if (quote != null) throw const FormatException('命令中的引号未闭合');
  if (started) result.add(token.toString());
  if (result.isEmpty || !['adb', 'scrcpy'].contains(result.first)) {
    throw const FormatException('命令需以 adb 或 scrcpy 开头');
  }
  return result;
}
