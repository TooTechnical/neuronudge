import 'package:flutter/material.dart';

import '../services/activation_engine.dart';

class GetStartedSheet extends StatefulWidget {
  const GetStartedSheet({
    super.key,
    required this.tasks,
    required this.profile,
    this.initialTaskId,
  });

  final List<Map<String, dynamic>> tasks;
  final Map<String, dynamic> profile;
  final String? initialTaskId;

  @override
  State<GetStartedSheet> createState() => _GetStartedSheetState();
}

class _GetStartedSheetState extends State<GetStartedSheet> {
  late String _taskId;
  String _barrier = ActivationEngine.barriers.first;
  int _energy = 2;
  ActivationPlan? _plan;

  @override
  void initState() {
    super.initState();
    final requested = widget.initialTaskId;
    _taskId = widget.tasks.any((task) => task['id'] == requested)
        ? requested!
        : widget.tasks.first['id'] as String;
  }

  Map<String, dynamic> get _task =>
      widget.tasks.firstWhere((task) => task['id'] == _taskId);

  void _makePlan() {
    setState(() {
      _plan = ActivationEngine.create(
        task: _task,
        profile: widget.profile,
        barrier: _barrier,
        energy: _energy,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: plan == null
            ? _buildCheckIn(context)
            : _buildMission(context, plan),
      ),
    );
  }

  Widget _buildCheckIn(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Get me started',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose what is stuck. NeuroNudge will give you one tiny mission—not a whole plan.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _taskId,
          decoration: const InputDecoration(
            labelText: 'What are you avoiding?',
          ),
          items: widget.tasks
              .map(
                (task) => DropdownMenuItem(
                  value: task['id'] as String,
                  child: Text(task['title'] as String? ?? 'Untitled task'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _taskId = value ?? _taskId),
        ),
        const SizedBox(height: 20),
        const Text('What is getting in the way?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ActivationEngine.barriers
              .map(
                (barrier) => ChoiceChip(
                  label: Text(barrier),
                  selected: barrier == _barrier,
                  onSelected: (_) => setState(() => _barrier = barrier),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        Text('Energy right now: $_energy / 3'),
        Slider(
          value: _energy.toDouble(),
          min: 1,
          max: 3,
          divisions: 2,
          label: '$_energy',
          onChanged: (value) => setState(() => _energy = value.round()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _makePlan,
          icon: const Icon(Icons.bolt),
          label: const Text('Give me one mission'),
        ),
      ],
    ),
  );

  Widget _buildMission(BuildContext context, ActivationPlan plan) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Your first mission',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(plan.supportLine),
      const SizedBox(height: 20),
      Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plan.minutes} minutes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                plan.firstAction,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, plan),
        icon: const Icon(Icons.play_arrow),
        label: Text('Start ${plan.minutes}-minute mission'),
      ),
      TextButton(
        onPressed: () => setState(() => _plan = null),
        child: const Text('Adjust my check-in'),
      ),
    ],
  );
}
