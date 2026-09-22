import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/get_started_sheet.dart';

void main() {
  testWidgets('turns an avoided task into one visible mission', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GetStartedSheet(
            tasks: [
              {
                'id': 'task-1',
                'title': 'Tax return',
                'steps': ['Find the documents folder'],
              },
            ],
            profile: {'activationMinutes': 3, 'preferredNudgeStyle': 'Coach'},
          ),
        ),
      ),
    );

    expect(find.text('Get me started'), findsOneWidget);
    await tester.tap(find.text('Give me one mission'));
    await tester.pump();

    expect(find.text('Your first mission'), findsOneWidget);
    expect(find.text('Find the documents folder'), findsOneWidget);
    expect(find.text('Start 3-minute mission'), findsOneWidget);
  });
}
