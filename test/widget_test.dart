import 'package:adb_tool/app/modules/settings/services/update_service.dart';
import 'package:adb_tool/app/modules/settings/widgets/update_check_tile.dart';
import 'package:adb_tool/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateRelease release(String version, int build) => UpdateRelease.fromJson({
      'version': version,
      'build': build,
      'name': '妙联 v$version',
      'notes': '修复设备连接',
    });

void main() {
  testWidgets('仅点击时检查，同版本提示最新', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UpdateCheckTile(check: () async {
      calls++;
      return release(AppConfig.appVersion, AppConfig.appBuild);
    }))));
    expect(calls, 0);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('已是最新版本'), findsOneWidget);
  });
  testWidgets('失败可重试，新版无下载地址时仍显示发布页', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UpdateCheckTile(check: () async {
      if (++calls == 1) throw Exception('offline');
      return release('99.0.0', 2);
    }))));
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('检查失败，点击重试'), findsOneWidget);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('妙联 v99.0.0'), findsOneWidget);
    expect(find.text('发布页'), findsOneWidget);
    expect(find.text('下载安装程序'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
