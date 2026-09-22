class BehaviorInsights {
  const BehaviorInsights({
    required this.startsToday,
    required this.completedToday,
    required this.focusMinutesToday,
    required this.activationStarts,
    required this.activationCompletions,
    required this.mostHelpfulBarrier,
  });

  final int startsToday;
  final int completedToday;
  final int focusMinutesToday;
  final int activationStarts;
  final int activationCompletions;
  final String? mostHelpfulBarrier;

  int get activationSuccessPercent => activationStarts == 0
      ? 0
      : ((activationCompletions / activationStarts) * 100).round().clamp(
          0,
          100,
        );

  static BehaviorInsights fromSessions(
    List<Map<String, dynamic>> sessions, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    var startsToday = 0;
    var completedToday = 0;
    var focusMinutesToday = 0;
    var activationStarts = 0;
    var activationCompletions = 0;
    final completedBarriers = <String, int>{};

    for (final session in sessions) {
      final timestamp = (session['createdAt'] as num?)?.toInt();
      final created = timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp);
      final isToday =
          created != null &&
          created.year == current.year &&
          created.month == current.month &&
          created.day == current.day;
      final event = session['event'] as String?;
      final completed = session['completed'] == true;
      final source = session['source'] as String?;

      if (event == 'activation_started') {
        activationStarts += 1;
        if (isToday) startsToday += 1;
      }
      if (completed) {
        if (isToday) {
          completedToday += 1;
          focusMinutesToday += (session['durationMin'] as num?)?.toInt() ?? 0;
        }
        if (source == 'activation' || source == 'rescue') {
          activationCompletions += 1;
          final barrier = session['barrier'] as String?;
          if (barrier != null && barrier.isNotEmpty) {
            completedBarriers[barrier] = (completedBarriers[barrier] ?? 0) + 1;
          }
        }
      }
    }

    String? mostHelpfulBarrier;
    for (final entry in completedBarriers.entries) {
      if (mostHelpfulBarrier == null ||
          entry.value > completedBarriers[mostHelpfulBarrier]!) {
        mostHelpfulBarrier = entry.key;
      }
    }

    return BehaviorInsights(
      startsToday: startsToday,
      completedToday: completedToday,
      focusMinutesToday: focusMinutesToday,
      activationStarts: activationStarts,
      activationCompletions: activationCompletions,
      mostHelpfulBarrier: mostHelpfulBarrier,
    );
  }
}
