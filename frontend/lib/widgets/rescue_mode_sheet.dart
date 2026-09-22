import 'package:flutter/material.dart';

import '../services/activation_engine.dart';

class RescueModeSheet extends StatefulWidget {
  const RescueModeSheet({
    super.key,
    required this.tasks,
    required this.profile,
  });

  final List<Map<String, dynamic>> tasks;
  final Map<String, dynamic> profile;

  @override
  State<RescueModeSheet> createState() => _RescueModeSheetState();
}

class _RescueModeSheetState extends State<RescueModeSheet> {
  int _stage = 0;
  String? _taskId;
  String _barrier = 'It feels too big';

  @override
  void initState() {
    super.initState();
    if (widget.tasks.isNotEmpty) _taskId = widget.tasks.first['id'] as String;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: switch (_stage) {
          0 => _reset(context),
          1 => _choose(context),
          _ => _mission(context),
        },
      ),
    ),
  );

  Widget _reset(BuildContext context) => Column(
    key: const ValueKey('reset'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.spa_outlined, size: 44),
      const SizedBox(height: 12),
      Text(
        'Rescue mode',
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      const Text(
        'Nothing has gone wrong. Put both feet on the floor, drop your shoulders, and take one slow breath out.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.tasks.isEmpty
            ? null
            : () => setState(() => _stage = 1),
        child: Text(
          widget.tasks.isEmpty
              ? 'Add a task first'
              : 'I am ready for one small step',
        ),
      ),
    ],
  );

  Widget _choose(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('choose'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What needs rescuing?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _taskId,
          decoration: const InputDecoration(labelText: 'Task'),
          items: widget.tasks
              .map(
                (task) => DropdownMenuItem(
                  value: task['id'] as String,
                  child: Text(task['title'] as String? ?? 'Untitled task'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _taskId = value),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'It feels too big', label: Text('Too big')),
            ButtonSegment(
              value: 'I am low on energy',
              label: Text('Low energy'),
            ),
            ButtonSegment(
              value: 'I want to do it perfectly',
              label: Text('Perfectionism'),
            ),
          ],
          selected: {_barrier},
          onSelectionChanged: (value) => setState(() => _barrier = value.first),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => setState(() => _stage = 2),
          child: const Text('Shrink it for me'),
        ),
      ],
    ),
  );

  Widget _mission(BuildContext context) {
    final task = widget.tasks.firstWhere((item) => item['id'] == _taskId);
    final plan = ActivationEngine.create(
      task: task,
      profile: {...widget.profile, 'activationMinutes': 2},
      barrier: _barrier,
      energy: 1,
    );
    return Column(
      key: const ValueKey('mission'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Only this—not the whole task',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              plan.firstAction,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, plan),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Stay with me for 2 minutes'),
        ),
      ],
    );
  }
}
