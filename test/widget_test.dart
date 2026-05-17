// Smoke test: the calming theme + glass widgets render without throwing.
// Full app tests would need Hive initialized, so we keep this lightweight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_buddy/core/theme/app_theme.dart';
import 'package:campus_buddy/core/widgets/glass.dart';

void main() {
  testWidgets('GlassContainer renders inside the app theme',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: GlassContainer(child: Text('CampusBuddy')),
        ),
      ),
    );

    expect(find.text('CampusBuddy'), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
  });
}
