import 'dart:async';
import 'package:adb_tool/app/modules/tools/services/tool_environment.dart';
import 'package:adb_tool/app/modules/tools/widgets/tool_environment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeEnvironment extends ToolEnvironment {
  final attempts = <Completer<bool>>[];
  @override
  Future<bool> ensure({bool force = false}) {
    phase = ToolPhase.downloading;
    message = '正在下载测试环境';
    notifyListeners();
    final done = Completer<bool>();
    attempts.add(done);
    return done.future;
  }

  void complete(bool ok) {
    phase = ok ? ToolPhase.ready : ToolPhase.failed;
    message = ok ? '环境已就绪' : '网络错误';
    notifyListeners();
    attempts.last.complete(ok);
  }
}

void main() {
  testWidgets('第一次运行自动补全，完成前不创建业务页面', (tester) async {
    final tools = FakeEnvironment();
    await tester.pumpWidget(MaterialApp(
        home: ToolBootstrap(
      environment: tools,
      child: const Text('业务页面'),
    )));
    expect(tools.attempts.length, 1);
    expect(find.text('业务页面'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    tools.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('业务页面'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tools.dispose();
  });

  testWidgets('首次失败可重试，完成后进入业务页面', (tester) async {
    final tools = FakeEnvironment();
    await tester.pumpWidget(MaterialApp(
        home: ToolBootstrap(
      environment: tools,
      child: const Text('业务页面'),
    )));
    tools.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('重试补全'), findsOneWidget);
    await tester.tap(find.text('重试补全'));
    await tester.pump();
    expect(tools.attempts.length, 2);
    tools.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('业务页面'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tools.dispose();
  });
}
