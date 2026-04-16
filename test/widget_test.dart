import 'package:flutter_test/flutter_test.dart';
import 'package:campus_buddy/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CampusBuddyApp());
    expect(find.byType(CampusBuddyApp), findsOneWidget);
  });
}
