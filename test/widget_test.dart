import 'package:flutter_test/flutter_test.dart';
import 'package:gravitysmash/main.dart';

void main() {
  testWidgets('Gravity Smash loading screen starts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GravitySmashApp());

    expect(find.text('GRAVITY\nSMASH'), findsWidgets);
    expect(find.text('LOADING'), findsOneWidget);
  });
}
