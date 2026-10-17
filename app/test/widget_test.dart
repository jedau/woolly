import 'package:flutter_test/flutter_test.dart';
import 'package:woolly/main.dart';

void main() {
  testWidgets('Sign-in lists the client and a worker', (tester) async {
    await tester.pumpWidget(const WoollyApp());
    expect(find.text('WOOLLY'), findsOneWidget);
    expect(find.text('Cool Client'), findsOneWidget);
    expect(find.text('Worker One'), findsOneWidget);
  });
}
