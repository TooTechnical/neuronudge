import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/day_plan_sheet.dart';

void main() {
  testWidgets('shows capacity, buffer, and deferred work', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DayPlanSheet(
            tasks: [
              {
                'id': 'one',
                'title': 'Draft report',
                'priorityScore': 3,
                'timeboxMinutes': 25,
              },
              {
                'id': 'two',
                'title': 'Clear inbox',
                'priorityScore': 1,
                'timeboxMinutes': 25,
              },
            ],
            profile: {'dailyCapacityMinutes': 60, 'dailyTaskTarget': 3},
          ),
        ),
      ),
    );

    expect(find.text('Plan a realistic day'), findsOneWidget);
    expect(find.textContaining('protected buffer'), findsOneWidget);
    expect(find.text('Use this plan'), findsOneWidget);
  });
}
