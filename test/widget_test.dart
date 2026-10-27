
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhom6/widgets/avatar.dart';

void main() {
  testWidgets(
    'Avatar renders user initials',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Avatar(
              name: 'Nguyen Van A',
            ),
          ),
        ),
      );

      expect(
        find.byType(Avatar),
        findsOneWidget,
      );
    },
  );
}
