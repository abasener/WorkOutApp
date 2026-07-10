import 'package:flutter_test/flutter_test.dart';

import 'package:terpinlift/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const TerpinLiftApp());
    await tester.pump();
  });
}
