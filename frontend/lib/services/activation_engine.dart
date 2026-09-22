class ActivationPlan {
  const ActivationPlan({
    required this.taskId,
    required this.taskTitle,
    required this.firstAction,
    required this.minutes,
    required this.barrier,
    required this.supportLine,
  });

  final String taskId;
  final String taskTitle;
  final String firstAction;
  final int minutes;
  final String barrier;
  final String supportLine;
}

class ActivationEngine {
  static const barriers = <String>[
    'I do not know where to start',
    'It feels too big',
    'I am low on energy',
    'I am distracted',
    'I want to do it perfectly',
  ];

  static ActivationPlan create({
    required Map<String, dynamic> task,
    required Map<String, dynamic> profile,
    required String barrier,
    required int energy,
  }) {
    final title = (task['title'] as String?)?.trim();
    final safeTitle = title == null || title.isEmpty ? 'this task' : title;
    final steps =
        (task['steps'] as List?)
            ?.whereType<String>()
            .map((step) => step.trim())
            .where((step) => step.isNotEmpty)
            .toList() ??
        const <String>[];
    final firstStep = steps.isEmpty
        ? 'open what you need for $safeTitle'
        : steps.first;

    var minutes = (profile['activationMinutes'] as num?)?.toInt() ?? 3;
    minutes = minutes.clamp(2, 10);
    if (energy <= 1 || barrier == 'I am low on energy') minutes = 2;
    if (barrier == 'It feels too big' && minutes > 3) minutes = 3;

    final firstAction = switch (barrier) {
      'It feels too big' => 'Ignore the rest. Do only this: $firstStep',
      'I am low on energy' => 'Put the task in front of you, then $firstStep',
      'I am distracted' => 'Silence one distraction, then $firstStep',
      'I want to do it perfectly' =>
        'Make a deliberately rough start: $firstStep',
      _ =>
        steps.isEmpty
            ? 'Open what you need and identify one visible next action'
            : firstStep,
    };

    return ActivationPlan(
      taskId: task['id'] as String,
      taskTitle: safeTitle,
      firstAction: firstAction,
      minutes: minutes,
      barrier: barrier,
      supportLine: _supportLine(profile['preferredNudgeStyle'] as String?),
    );
  }

  static String _supportLine(String? style) => switch (style) {
    'Gentle' => 'You are not finishing the task. You are only beginning.',
    'DrillSergeant' => 'No planning spiral. One mission. Start now.',
    'Comedian' =>
      'We are just poking the task. It does not need to be elegant.',
    _ => 'Make contact with the task. Momentum can come later.',
  };
}
