import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saizhijian/theme.dart';
import 'package:saizhijian/widgets/common.dart';

void main() {
  testWidgets('brand renders in Chinese', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: BrandMark()),
      ),
    );
    expect(find.text('赛智荐'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });

  testWidgets('section title stacks its action on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(22),
            child: SectionTitle(
              '我的项目',
              subtitle: '手机窄屏下操作按钮应换到下一行。',
              trailing: ElevatedButton(
                onPressed: () {},
                child: const Text('新建项目'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final title = tester.getTopLeft(find.text('我的项目'));
    final action = tester.getTopLeft(find.text('新建项目'));
    expect(action.dy, greaterThan(title.dy));
  });
}
