import 'dart:io';

import 'package:adb_tool/app/modules/tools/services/tool_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('真实 latest 下载、校验、解压、运行检查与离线恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('mlink-tools-smoke-');
    final tools = ToolEnvironment(rootProvider: () async => root);
    final messages = <String>{};
    tools.addListener(() {
      if (messages.add(tools.message)) {
        // ignore: avoid_print
        print(tools.message);
      }
    });
    try {
      expect(await tools.ensure(), isTrue, reason: tools.message);
      expect(tools.directory, isNotNull);
      final restored = ToolEnvironment(
          rootProvider: () async => root,
          releaseLoader: (_) => throw StateError('离线恢复不应请求网络'));
      expect(await restored.ensure(), isTrue, reason: restored.message);
      expect(restored.directory, tools.directory);
      restored.dispose();
    } finally {
      tools.dispose();
      await root.delete(recursive: true);
    }
  },
      skip: !Platform.isWindows ||
          Platform.environment['MLINK_TOOLS_SMOKE'] != '1',
      timeout: const Timeout(Duration(minutes: 12)));
}
