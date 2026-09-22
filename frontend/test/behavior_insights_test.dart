import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/behavior_insights.dart';

void main() {
  test('summarizes starts, completions, and activation conversion', () {
    final now = DateTime(2026, 9, 22, 12);
    final today = DateTime(2026, 9, 22, 9).millisecondsSinceEpoch;
    final insights = BehaviorInsights.fromSessions([
      {
        'event': 'activation_started',
        'barrier': 'It feels too big',
        'createdAt': today,
      },
      {
        'completed': true,
        'source': 'activation',
        'barrier': 'It feels too big',
        'durationMin': 3,
        'createdAt': today,
      },
    ], now: now);

    expect(insights.startsToday, 1);
    expect(insights.completedToday, 1);
    expect(insights.focusMinutesToday, 3);
    expect(insights.activationSuccessPercent, 100);
    expect(insights.mostHelpfulBarrier, 'It feels too big');
  });

  test('empty history is safe', () {
    final insights = BehaviorInsights.fromSessions(const []);
    expect(insights.activationSuccessPercent, 0);
    expect(insights.mostHelpfulBarrier, isNull);
  });
}
