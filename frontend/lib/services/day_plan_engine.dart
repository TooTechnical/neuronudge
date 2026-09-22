class PlannedTask {
  const PlannedTask({
    required this.id,
    required this.title,
    required this.minutes,
  });

  final String id;
  final String title;
  final int minutes;
}

class DayPlan {
  const DayPlan({
    required this.capacityMinutes,
    required this.focusBudgetMinutes,
    required this.bufferMinutes,
    required this.tasks,
    required this.deferredCount,
  });

  final int capacityMinutes;
  final int focusBudgetMinutes;
  final int bufferMinutes;
  final List<PlannedTask> tasks;
  final int deferredCount;

  int get plannedMinutes =>
      tasks.fold(0, (total, task) => total + task.minutes);
}

class DayPlanEngine {
  static DayPlan create({
    required List<Map<String, dynamic>> tasks,
    required Map<String, dynamic> profile,
    int? capacityMinutes,
  }) {
    final capacity =
        (capacityMinutes ??
                (profile['dailyCapacityMinutes'] as num?)?.toInt() ??
                60)
            .clamp(15, 240);
    final taskLimit = ((profile['dailyTaskTarget'] as num?)?.toInt() ?? 3)
        .clamp(1, 10);
    final focusBudget = (capacity * .8).floor();
    final buffer = capacity - focusBudget;

    final candidates =
        tasks
            .where((task) => task['completed'] != true)
            .map(Map<String, dynamic>.from)
            .toList()
          ..sort((a, b) {
            final priority = ((b['priorityScore'] as num?)?.toInt() ?? 2)
                .compareTo((a['priorityScore'] as num?)?.toInt() ?? 2);
            if (priority != 0) return priority;
            return ((a['createdAt'] as num?)?.toInt() ?? 0).compareTo(
              (b['createdAt'] as num?)?.toInt() ?? 0,
            );
          });

    final selected = <PlannedTask>[];
    var remaining = focusBudget;
    for (final task in candidates) {
      if (selected.length >= taskLimit) break;
      final estimate = ((task['timeboxMinutes'] as num?)?.toInt() ?? 25).clamp(
        5,
        60,
      );
      if (estimate > remaining) continue;
      selected.add(
        PlannedTask(
          id: task['id'] as String,
          title: task['title'] as String? ?? 'Untitled task',
          minutes: estimate,
        ),
      );
      remaining -= estimate;
    }

    return DayPlan(
      capacityMinutes: capacity,
      focusBudgetMinutes: focusBudget,
      bufferMinutes: buffer + remaining,
      tasks: selected,
      deferredCount: candidates.length - selected.length,
    );
  }
}
