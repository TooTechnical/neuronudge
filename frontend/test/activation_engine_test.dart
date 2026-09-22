import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/activation_engine.dart';

void main() {
  const task = {
    'id': 'task-1',
    'title': 'Tax return',
    'steps': ['Find the documents folder', 'Open the tax portal'],
  };

  test('uses the first existing step as the activation mission', () {
    final plan = ActivationEngine.create(
      task: task,
      profile: const {'activationMinutes': 3, 'preferredNudgeStyle': 'Coach'},
      barrier: 'I do not know where to start',
      energy: 2,
    );

    expect(plan.firstAction, 'Find the documents folder');
    expect(plan.minutes, 3);
  });

  test('low energy always produces a two-minute mission', () {
    final plan = ActivationEngine.create(
      task: task,
      profile: const {'activationMinutes': 10},
      barrier: 'I am low on energy',
      energy: 1,
    );

    expect(plan.minutes, 2);
    expect(plan.firstAction, startsWith('Put the task in front of you'));
  });

  test('perfectionism reframes the first step as a rough start', () {
    final plan = ActivationEngine.create(
      task: task,
      profile: const {'preferredNudgeStyle': 'Gentle'},
      barrier: 'I want to do it perfectly',
      energy: 3,
    );

    expect(plan.firstAction, contains('deliberately rough'));
    expect(plan.supportLine, contains('only beginning'));
  });
}
