import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saizhijian/theme.dart';
import 'package:saizhijian/widgets/common.dart';

void main() {
  testWidgets('brand renders in Chinese', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: BrandMark())));
    expect(find.text('赛智荐'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });
}

