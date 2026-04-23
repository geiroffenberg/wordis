import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wordis/main.dart';

void main() {
  testWidgets('renders wordis shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const WordisApp());
    await tester.pump();

    expect(find.text('Wordis'), findsWidgets);
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });
}
