import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/day_plan_engine.dart';

void main() {
  final tasks = <Map<String, dynamic>>[
    {
      'id': 'low',
      'title': 'Low priority',
      'priorityScore': 1,
      'timeboxMinutes': 20,
      'createdAt': 1,
    },
    {
      'id': 'high',
      'title': 'High priority',
      'priorityScore': 3,
      'timeboxMinutes': 25,
      'createdAt': 2,
    },
    {
      'id': 'medium',
      'title': 'Medium priority',
      'priorityScore': 2,
      'timeboxMinutes': 25,
      'createdAt': 3,
    },
  ];

  test('protects twenty percent capacity and prioritizes important work', () {
    final plan = DayPlanEngine.create(
      tasks: tasks,
      profile: const {'dailyTaskTarget': 3},
      capacityMinutes: 60,
    );

    expect(plan.focusBudgetMinutes, 48);
    expect(plan.tasks.map((task) => task.id), ['high', 'low']);
    expect(plan.plannedMinutes, 45);
    expect(plan.bufferMinutes, 15);
    expect(plan.deferredCount, 1);
  });

  test('does not include completed tasks or exceed the daily task target', () {
    final plan = DayPlanEngine.create(
      tasks: [
        {...tasks.first, 'completed': true},
        ...tasks.skip(1),
      ],
      profile: const {'dailyTaskTarget': 1},
      capacityMinutes: 120,
    );

    expect(plan.tasks, hasLength(1));
    expect(plan.tasks.single.id, 'high');
  });
}
