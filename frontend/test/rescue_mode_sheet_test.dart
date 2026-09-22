import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/rescue_mode_sheet.dart';

void main() {
  testWidgets('guides overwhelm into a two-minute rescue mission', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RescueModeSheet(
            tasks: [
              {
                'id': 'task-1',
                'title': 'Prepare presentation',
                'steps': ['Open the slide deck'],
              },
            ],
            profile: {'preferredNudgeStyle': 'Gentle'},
          ),
        ),
      ),
    );

    expect(find.text('Rescue mode'), findsOneWidget);
    await tester.tap(find.text('I am ready for one small step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shrink it for me'));
    await tester.pumpAndSettle();

    expect(find.text('Only this—not the whole task'), findsOneWidget);
    expect(find.text('Stay with me for 2 minutes'), findsOneWidget);
  });
}
