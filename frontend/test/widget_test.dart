import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('App initialization and splash screen smoke test', (WidgetTester tester) async {
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const EnclineApp());

    // Verify that the splash screen shows ENCLINE text
    expect(find.text('ENCLINE'), findsOneWidget);

    // Drain the splash navigation timer (3000ms delay + 800ms transition)
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
