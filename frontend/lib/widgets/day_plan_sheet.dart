import 'package:flutter/material.dart';

import '../services/day_plan_engine.dart';

class DayPlanSheet extends StatefulWidget {
  const DayPlanSheet({super.key, required this.tasks, required this.profile});

  final List<Map<String, dynamic>> tasks;
  final Map<String, dynamic> profile;

  @override
  State<DayPlanSheet> createState() => _DayPlanSheetState();
}

class _DayPlanSheetState extends State<DayPlanSheet> {
  late int _capacity;

  @override
  void initState() {
    super.initState();
    final saved =
        (widget.profile['dailyCapacityMinutes'] as num?)?.toInt() ?? 60;
    _capacity = [30, 60, 90, 120].reduce(
      (closest, value) =>
          (value - saved).abs() < (closest - saved).abs() ? value : closest,
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = DayPlanEngine.create(
      tasks: widget.tasks,
      profile: widget.profile,
      capacityMinutes: _capacity,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plan a realistic day',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the energy you actually have. NeuroNudge keeps breathing room instead of filling every minute.',
            ),
            const SizedBox(height: 20),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30m')),
                ButtonSegment(value: 60, label: Text('1h')),
                ButtonSegment(value: 90, label: Text('1.5h')),
                ButtonSegment(value: 120, label: Text('2h')),
              ],
              selected: {_capacity},
              onSelectionChanged: (value) =>
                  setState(() => _capacity = value.first),
            ),
            const SizedBox(height: 18),
            if (plan.tasks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No task fits this capacity yet. Try a larger window or shorten a task.',
                  ),
                ),
              )
            else
              ...plan.tasks.map(
                (task) => ListTile(
                  leading: CircleAvatar(child: Text('${task.minutes}')),
                  title: Text(task.title),
                  subtitle: const Text('Focused minutes'),
                ),
              ),
            const Divider(),
            Text(
              '${plan.plannedMinutes}m focused • ${plan.bufferMinutes}m protected buffer • ${plan.deferredCount} deferred',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: plan.tasks.isEmpty
                  ? null
                  : () => Navigator.pop(context, plan),
              icon: const Icon(Icons.today),
              label: const Text('Use this plan'),
            ),
          ],
        ),
      ),
    );
  }
}
