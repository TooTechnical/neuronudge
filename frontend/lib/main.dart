// frontend/lib/main.dart
import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

// Firebase Auth (Google sign-in)
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';

// Local storage
import 'package:hive_flutter/hive_flutter.dart';
import 'data/local_repo.dart';

// AI + scheduling
import 'services/ai_service.dart';
import 'services/scheduler_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter(); // local boxes will be opened per-user after login
  runApp(const NeuroNudgeApp());
}

class NeuroNudgeApp extends StatelessWidget {
  const NeuroNudgeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroNudge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData) {
          return SignInScreen(
            providers: [
              GoogleProvider(
                clientId: '759312443189-dh2ps8prek5h0al56sd2b9nn2rqod00g.apps.googleusercontent.com',
              ),
            ],
          );
        }

        final user = snap.data!;
        return FutureBuilder<LocalRepo>(
          future: LocalRepo.open(user.uid), // open per-user local boxes
          builder: (context, repoSnap) {
            if (!repoSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final repo = repoSnap.data!;
            final profile = repo.getProfile();
            final onboarded = profile['onboarded'] == true;

            return onboarded
                ? Shell(repo: repo)
                : OnboardingScreen(repo: repo, user: user);
          },
        );
      },
    );
  }
}

/// Bottom-tab shell (Tasks / Focus / Profile / Settings)
class Shell extends StatefulWidget {
  final LocalRepo repo;
  const Shell({super.key, required this.repo});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      TasksPage(repo: widget.repo),
      FocusPage(repo: widget.repo),
      ProfilePage(repo: widget.repo),
      SettingsPage(repo: widget.repo),
    ];
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.timelapse), label: 'Focus'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// ===== ONBOARDING (local) =====
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.repo, required this.user});
  final LocalRepo repo;
  final User user;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _saving = false;

  final nameCtrl = TextEditingController();
  String pronouns = 'He/Him';
  final customPronounsCtrl = TextEditingController();
  final ageCtrl = TextEditingController();

  String neuroType = 'ADHD - Combined';
  final bioCtrl = TextEditingController();

  final strengths = <String>{};
  final weaknesses = <String>{};

  final strengthsOptions = const [
    'Creative', 'Focus bursts', 'Problem solving', 'Detail oriented', 'Disciplined', 'Fast learner'
  ];
  final weaknessesOptions = const [
    'Starting', 'Finishing', 'Distractions', 'Time estimation', 'Overthinking', 'Perfectionism'
  ];

  // Schedule
  TimeOfDay? workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? workEnd = const TimeOfDay(hour: 17, minute: 0);
  final dailyTargetCtrl = TextEditingController(text: '3');

  // Workdays selection
  final days = <int>{1, 2, 3, 4, 5}; // Mon–Fri
  final dayLabels = const {1:'Mon',2:'Tue',3:'Wed',4:'Thu',5:'Fri',6:'Sat',7:'Sun'};

  // Nudge windows
  bool allowBefore = true;
  bool allowDuring = true;
  bool allowAfter = true;

  // Goals & nudges
  final goalCtrl = TextEditingController();
  String blocker = 'Starting feels hard';
  String nudgeStyle = 'Coach';
  String role = 'Employee';
  bool allowSounds = true;

  @override
  void initState() {
    super.initState();
    nameCtrl.text = widget.user.displayName ?? '';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    customPronounsCtrl.dispose();
    ageCtrl.dispose();
    bioCtrl.dispose();
    dailyTargetCtrl.dispose();
    goalCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay? t) =>
      t == null ? '' : '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  Future<void> _pick(bool start) async {
    final initial = start ? (workStart ?? const TimeOfDay(hour: 9, minute: 0))
                          : (workEnd ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) setState(() => start ? workStart = picked : workEnd = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;

    final chosenPronouns = (pronouns == 'Custom')
        ? (customPronounsCtrl.text.trim().isEmpty ? 'They/Them' : customPronounsCtrl.text.trim())
        : pronouns;

    final profile = {
      'onboarded': true,
      'name': (nameCtrl.text.trim().isEmpty ? (widget.user.displayName ?? 'User') : nameCtrl.text.trim()),
      'pronouns': chosenPronouns,
      'age': int.tryParse(ageCtrl.text.trim()),
      'role': role,
      'neuroType': neuroType,
      'bio': bioCtrl.text.trim(),
      'strengths': strengths.toList(),
      'weaknesses': weaknesses.toList(),
      'workStart': _fmt(workStart),
      'workEnd': _fmt(workEnd),
      'workDays': (days.toList()..sort()),
      'allowWindows': {
        'before': allowBefore, 'during': allowDuring, 'after': allowAfter,
      },
      'dailyTaskTarget': int.tryParse(dailyTargetCtrl.text.trim()) ?? 3,
      'goals': goalCtrl.text.trim(),
      'biggestBlocker': blocker,
      'preferredNudgeStyle': nudgeStyle,
      'allowSounds': allowSounds,
      'currentStreak': 0,
      'longestStreak': 0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'email': widget.user.email,
      'uid': widget.user.uid,
    };

    setState(() => _saving = true);
    try {
      await widget.repo.saveProfile(profile);
      // notify planner (non-blocking)
      AIService.submitProfile(profile);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved! Loading your dashboard…')),
      );
      // Go to shell
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => Shell(repo: widget.repo),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Step> _steps() => [
    Step(
      title: const Text('About you'),
      isActive: _step >= 0,
      content: Column(
        children: [
          TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: pronouns,
            decoration: const InputDecoration(labelText: 'Pronouns'),
            items: const [
              DropdownMenuItem(value: 'He/Him', child: Text('He/Him')),
              DropdownMenuItem(value: 'She/Her', child: Text('She/Her')),
              DropdownMenuItem(value: 'They/Them', child: Text('They/Them')),
              DropdownMenuItem(value: 'Custom', child: Text('Custom')),
            ],
            onChanged: (v) => setState(() => pronouns = v ?? 'They/Them'),
          ),
          if (pronouns == 'Custom') ...[
            const SizedBox(height: 8),
            TextFormField(controller: customPronounsCtrl, decoration: const InputDecoration(labelText: 'Enter pronouns')),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: ageCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age (optional)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(labelText: 'Primary role'),
            items: const [
              DropdownMenuItem(value: 'Student', child: Text('Student')),
              DropdownMenuItem(value: 'Employee', child: Text('Employee')),
              DropdownMenuItem(value: 'Freelancer', child: Text('Freelancer')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => role = v ?? 'Other'),
          ),
        ],
      ),
    ),
    Step(
      title: const Text('Mind & style'),
      isActive: _step >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: neuroType,
            decoration: const InputDecoration(labelText: 'ADHD / Intellectual disability'),
            items: const [
              DropdownMenuItem(value: 'ADHD - Inattentive', child: Text('ADHD - Inattentive')),
              DropdownMenuItem(value: 'ADHD - Hyperactive', child: Text('ADHD - Hyperactive')),
              DropdownMenuItem(value: 'ADHD - Combined', child: Text('ADHD - Combined')),
              DropdownMenuItem(value: 'Intellectual Disability', child: Text('Intellectual Disability')),
              DropdownMenuItem(value: 'None / Prefer not to say', child: Text('None / Prefer not to say')),
            ],
            onChanged: (v) => setState(() => neuroType = v ?? 'ADHD - Combined'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: bioCtrl,
            maxLength: 500,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Tell NeuroNudge about you (up to 500 chars)',
              hintText: 'What motivates you? What trips you up?',
            ),
          ),
          const SizedBox(height: 8),
          const Text('Strengths'),
          Wrap(
            spacing: 8,
            children: strengthsOptions.map((s) {
              final sel = strengths.contains(s);
              return ChoiceChip(
                label: Text(s),
                selected: sel,
                onSelected: (_) => setState(() { sel ? strengths.remove(s) : strengths.add(s); }),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text('Weaknesses'),
          Wrap(
            spacing: 8,
            children: weaknessesOptions.map((s) {
              final sel = weaknesses.contains(s);
              return ChoiceChip(
                label: Text(s),
                selected: sel,
                onSelected: (_) => setState(() { sel ? weaknesses.remove(s) : weaknesses.add(s); }),
              );
            }).toList(),
          ),
        ],
      ),
    ),
    Step(
      title: const Text('Work schedule'),
      isActive: _step >= 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(labelText: 'Work start', hintText: _fmt(workStart)),
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(labelText: 'Work end', hintText: _fmt(workEnd)),
                  onTap: () => _pick(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Work days'),
          Wrap(
            spacing: 8,
            children: [1,2,3,4,5,6,7].map((d) {
              final sel = days.contains(d);
              return ChoiceChip(
                label: Text(dayLabels[d]!),
                selected: sel,
                onSelected: (_) => setState(() { sel ? days.remove(d) : days.add(d); }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text('When can we nudge you?'),
          SwitchListTile(title: const Text('Before work'), value: allowBefore, onChanged: (v) => setState(() => allowBefore = v)),
          SwitchListTile(title: const Text('During work'), value: allowDuring, onChanged: (v) => setState(() => allowDuring = v)),
          SwitchListTile(title: const Text('After work'), value: allowAfter, onChanged: (v) => setState(() => allowAfter = v)),
          const SizedBox(height: 12),
          TextFormField(
            controller: dailyTargetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Daily task target'),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1) return 'Enter 1 or more';
              return null;
            },
          ),
        ],
      ),
    ),
    Step(
      title: const Text('Goals & nudges'),
      isActive: _step >= 3,
      content: Column(
        children: [
          TextFormField(
            controller: goalCtrl,
            decoration: const InputDecoration(labelText: 'Main goal', hintText: 'e.g., Finish Project 4'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: blocker,
            decoration: const InputDecoration(labelText: 'Biggest blocker'),
            items: const [
              DropdownMenuItem(value: 'Starting feels hard', child: Text('Starting feels hard')),
              DropdownMenuItem(value: 'Easily distracted', child: Text('Easily distracted')),
              DropdownMenuItem(value: 'Overwhelmed by size', child: Text('Overwhelmed by size')),
              DropdownMenuItem(value: 'Perfectionism', child: Text('Perfectionism')),
              DropdownMenuItem(value: 'Low energy/motivation', child: Text('Low energy/motivation')),
            ],
            onChanged: (v) => setState(() => blocker = v ?? 'Starting feels hard'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: nudgeStyle,
            decoration: const InputDecoration(labelText: 'Nudge style'),
            items: const [
              DropdownMenuItem(value: 'Gentle', child: Text('Gentle')),
              DropdownMenuItem(value: 'Coach', child: Text('Coach')),
              DropdownMenuItem(value: 'DrillSergeant', child: Text('Drill Sergeant')),
              DropdownMenuItem(value: 'Comedian', child: Text('Comedian')),
            ],
            onChanged: (v) => setState(() => nudgeStyle = v ?? 'Coach'),
          ),
          SwitchListTile(
            title: const Text('Play sounds on complete'),
            value: allowSounds,
            onChanged: (v) => setState(() => allowSounds = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Finish & Save'),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Let’s set you up'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepCancel: () => setState(() => _step = (_step > 0) ? _step - 1 : 0),
          onStepContinue: () {
            if (_step < _steps().length - 1) {
              setState(() => _step += 1);
            } else {
              _save();
            }
          },
          steps: _steps(),
        ),
      ),
    );
  }
}

/// ===== TASKS (local) =====
class TasksPage extends StatefulWidget {
  final LocalRepo repo;
  const TasksPage({super.key, required this.repo});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Timer? _nudgeTimer;
  bool _nudgeOpen = false;

  @override
  void initState() {
    super.initState();
    _nudgeTimer = Timer.periodic(const Duration(seconds: 45), (_) => _checkNudges());
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNudges() async {
    if (_nudgeOpen) return;
    final tasks = widget.repo.allTasks();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    tasks.sort((a, b) => (a['nextNudgeAt'] ?? 1<<62).compareTo(b['nextNudgeAt'] ?? 1<<62));
    if (tasks.isEmpty) return;

    final due = tasks.firstWhere(
      (t) => (t['completed'] != true) && (t['nextNudgeAt'] != null) && (t['nextNudgeAt'] <= nowMs),
      orElse: () => {},
    );
    if (due.isEmpty) return;

    _nudgeOpen = true;
    final id = due['id'] as String;
    final title = (due['title'] as String?) ?? 'Task';
    final style = (widget.repo.getProfile()['preferredNudgeStyle'] as String?) ?? 'Coach';
    final line = _oneLiner(style);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Nudge: $title'),
        content: Text(line),
        actions: [
          TextButton(
            child: const Text('Snooze 20m'),
            onPressed: () async {
              await widget.repo.updateTask(id, {
                'nextNudgeAt': DateTime.now().add(const Duration(minutes: 20)).millisecondsSinceEpoch
              });
              if (mounted) Navigator.pop(context);
            },
          ),
          TextButton(
            child: const Text('Start 10m'),
            onPressed: () {
              Navigator.pop(context);
              _openSprint(
                title: title,
                taskId: id,
                // Use task's minutes if set, otherwise 10 for this quick start
                minutes: max(5, (due['timeboxMinutes'] as int? ?? 10)),
                steps: (due['steps'] as List?)?.cast<String>() ?? const [],
              );
            },
          ),
          TextButton(
            child: const Text('Dismiss'),
            onPressed: () async {
              await widget.repo.updateTask(id, {
                'nextNudgeAt': DateTime.now().add(const Duration(minutes: 90)).millisecondsSinceEpoch
              });
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );

    _nudgeOpen = false;
  }

  String _oneLiner(String style) {
    final bank = {
      'Gentle': [
        "Two minutes. That’s all.",
        "Tiny wins → big momentum.",
        "Start where it’s easiest."
      ],
      'Coach': [
        "You don’t need motivation — you need motion.",
        "Touch the task. Start the loop.",
        "Action kills anxiety."
      ],
      'DrillSergeant': [
        "No thinking. Start now.",
        "Discipline beats doubt.",
        "120 seconds. Go."
      ],
      'Comedian': [
        "We ball in tiny steps today.",
        "Do it badly first.",
        "Just poke the task."
      ],
    }[style] ?? const ["Start with 2 minutes. Move now."];
    return bank[Random().nextInt(bank.length)];
  }

  Future<int?> _pickSprintMinutes(BuildContext context, {required int initial}) async {
    int temp = initial.clamp(5, 60);
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choose sprint length'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$temp minutes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Slider(
                min: 5, max: 60, divisions: 11,
                value: temp.toDouble(),
                label: '$temp',
                onChanged: (v) => setState(() => temp = v.round()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [5,10,15,20,25,30,45,60].map((m)=>ActionChip(
                  label: Text('${m}m'),
                  onPressed: () => setState(()=> temp = m),
                )).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, temp), child: const Text('Start')),
        ],
      ),
    );
  }

  void _openSprint({
    required String title,
    required String taskId,
    required int minutes,
    required List<String> steps,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FocusSprintSheet(
        repo: widget.repo,
        taskId: taskId,
        taskTitle: title,
        minutes: minutes,
        firstStep: steps.isNotEmpty ? steps.first : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroNudge'),
        actions: [
          IconButton(
            tooltip: 'Quick nudge',
            icon: const Icon(Icons.bolt),
            onPressed: () => _showNudgeNow(context, repo),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              await repo.close();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _GreetingCard(repo: repo),
          const SizedBox(height: 12),
          _StreakRow(repo: repo),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'Add Task',
                icon: const Icon(Icons.add_circle),
                onPressed: () => _showAddOrEditTaskDialog(context, repo),
              ),
            ],
          ),

          ValueListenableBuilder(
            valueListenable: repo.watchTasks(),
            builder: (context, _, __) {
              final tasks = repo.allTasks()
                ..sort((a, b) => (a['createdAt'] ?? 0).compareTo(b['createdAt'] ?? 0));

              if (tasks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text("No tasks yet — tap + to add one.")),
                );
              }

              return Column(
                children: tasks.map((d) {
                  final id = d['id'] as String;
                  final completed = (d['completed'] ?? false) as bool;
                  final title = (d['title'] ?? 'Untitled Task') as String;
                  final steps = (d['steps'] as List?)?.cast<String>() ?? const <String>[];
                  final tb = (d['timeboxMinutes'] ?? 0) as int;
                  final tone = (d['aiTone'] ?? 'Coach') as String;
                  final cat = (d['category'] ?? 'Both') as String;
                  final win = (d['preferredWindow'] ?? 'any') as String;
                  final int? nextMs = d['nextNudgeAt'] as int?;
                  final nextStr = (nextMs == null)
                      ? '—'
                      : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(nextMs)).format(context);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: completed,
                          title: Text(title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (steps.isNotEmpty) Text(steps.join(" • ")),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (tb > 0) _chip(Icons.timer, '$tb min'),
                                  _chip(Icons.campaign, tone == 'DrillSergeant' ? 'Drill Sergeant' : tone),
                                  _chip(Icons.category, cat),
                                  _chip(Icons.access_time, 'Window: ${win[0].toUpperCase()}${win.substring(1)}'),
                                  _chip(Icons.schedule, 'Next: $nextStr'),
                                ],
                              ),
                            ],
                          ),
                          onChanged: (v) => repo.updateTask(id, {'completed': v}),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start'),
                                onPressed: () async {
                                  final chosen = await _pickSprintMinutes(
                                    context,
                                    initial: tb > 0 ? tb : 25,
                                  );
                                  if (chosen == null) return;
                                  _openSprint(
                                    title: title,
                                    taskId: id,
                                    minutes: chosen,
                                    steps: steps,
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                icon: const Icon(Icons.snooze),
                                label: const Text('Snooze 20m'),
                                onPressed: () => repo.updateTask(
                                  id,
                                  {'nextNudgeAt': DateTime.now().add(const Duration(minutes: 20)).millisecondsSinceEpoch},
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                                onPressed: () => _showAddOrEditTaskDialog(context, repo, taskId: id, existing: d),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => repo.deleteTask(id),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.deepPurple.withOpacity(.08),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.deepPurple.withOpacity(.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: Colors.deepPurple),
      const SizedBox(width: 6),
      Text(text),
    ]),
  );
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.repo});
  final LocalRepo repo;

  @override
  Widget build(BuildContext context) {
    final profile = repo.getProfile();
    final name = (profile['name'] as String?) ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Friend';
    final style = (profile['preferredNudgeStyle'] as String?) ?? 'Coach';
    final nudgesByStyle = {
      'Gentle': const [
        "Tiny steps beat big intentions.",
        "Action creates motivation.",
        "Two minutes now. That’s all.",
      ],
      'Coach': const [
        "You don’t need motivation, you need momentum.",
        "Touch the task. Start the loop.",
        "Future you is cheering — give them 2 minutes.",
      ],
      'DrillSergeant': const [
        "No overthinking. Start. Now.",
        "Discipline beats doubt. Move.",
        "You’ve got 120 seconds — go.",
      ],
      'Comedian': const [
        "We ball in tiny steps today.",
        "Do it badly first. Then do it better.",
        "You vs. task: round one. Ding ding.",
      ],
    };
    final list = nudgesByStyle[style] ?? nudgesByStyle['Coach']!;
    final nudge = list[Random().nextInt(list.length)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700]),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome back, $name 👋", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(nudge, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.repo});
  final LocalRepo repo;

  @override
  Widget build(BuildContext context) {
    final d = repo.getProfile();
    final current = (d['currentStreak'] ?? 0).toString();
    final longest = (d['longestStreak'] ?? 0).toString();
    return Row(
      children: [
        _pill(Icons.local_fire_department, 'Current', current),
        const SizedBox(width: 8),
        _pill(Icons.emoji_events, 'Longest', longest),
      ],
    );
  }

  Widget _pill(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.deepPurple.withOpacity(.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.deepPurple.withOpacity(.2)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.deepPurple),
        const SizedBox(width: 6),
        Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
    ),
  );
}

/// Add/Edit Task dialog (local) with AI planner and robust defaults
Future<void> _showAddOrEditTaskDialog(
  BuildContext context,
  LocalRepo repo, {
  String? taskId,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = taskId != null && existing != null;
  final titleCtrl = TextEditingController(text: isEdit ? (existing['title'] ?? '') : '');
  final descCtrl = TextEditingController(text: isEdit ? (existing['description'] ?? '') : '');

  String category = isEdit ? (existing['category'] ?? 'Both') : 'Both';
  String preferredWindow = isEdit ? (existing['preferredWindow'] ?? 'any') : 'any';
  String priority = isEdit ? (existing['priority'] ?? 'Medium') : 'Medium';
  int priorityScore = {'Low': 1, 'Medium': 2, 'High': 3}[priority]!;
  final timeboxCtrl = TextEditingController(
    text: (isEdit
            ? (existing['timeboxMinutes'] as int? ?? 25)
            : 25)
        .toString(),
  );

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isEdit ? 'Edit Task' : 'New Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Describe it (optional)',
                hintText: 'e.g. Clean bedroom / Finish module / Read chapter 3',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'Work', child: Text('Work')),
                DropdownMenuItem(value: 'Home', child: Text('Home')),
                DropdownMenuItem(value: 'Both', child: Text('Both')),
              ],
              onChanged: (v) => category = v ?? 'Both',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: preferredWindow,
              decoration: const InputDecoration(labelText: 'Preferred time window'),
              items: const [
                DropdownMenuItem(value: 'any', child: Text('Any')),
                DropdownMenuItem(value: 'before', child: Text('Before work')),
                DropdownMenuItem(value: 'during', child: Text('During work')),
                DropdownMenuItem(value: 'after', child: Text('After work')),
              ],
              onChanged: (v) => preferredWindow = v ?? 'any',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'High', child: Text('High')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Low', child: Text('Low')),
              ],
              onChanged: (v) {
                priority = v ?? 'Medium';
                priorityScore = {'Low': 1, 'Medium': 2, 'High': 3}[priority]!;
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: timeboxCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sprint minutes (5–60)',
                helperText: 'Used when you tap Start; you can still pick a different length each time.',
              ),
            ),
            const SizedBox(height: 8),
            if (!isEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Auto-plan with AI'),
                  onPressed: () async {
                    final title = titleCtrl.text.trim().isEmpty ? 'New Task' : titleCtrl.text.trim();
                    final description = descCtrl.text.trim();
                    try {
                      final plan = await AIService.planTask(
                        title: title,
                        description: description,
                        profile: repo.getProfile()..removeWhere((k, v) => v == null),
                      );
                      // fill fields from AI
                      if (plan.timeboxMinutes > 0) {
                        timeboxCtrl.text = plan.timeboxMinutes.toString();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AI plan drafted — you can edit before saving.')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('AI unavailable: $e')),
                        );
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () async {
              await repo.deleteTask(taskId!);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted')));
              }
            },
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final title = titleCtrl.text.trim().isEmpty ? 'New Task' : titleCtrl.text.trim();
            final description = descCtrl.text.trim();
            final tbParsed = int.tryParse(timeboxCtrl.text.trim());
            int timeboxMinutes = (tbParsed == null || tbParsed < 5 || tbParsed > 60) ? 25 : tbParsed;
            List<String> steps = isEdit
                ? ((existing?['steps'] as List?)?.cast<String>() ?? const <String>[])
                : const <String>[];
            String tone = isEdit ? (existing?['aiTone'] as String? ?? 'Coach') : 'Coach';

            try {
              if (isEdit) {
                await repo.updateTask(taskId!, {
                  'title': title,
                  'description': description,
                  'category': category,
                  'preferredWindow': preferredWindow,
                  'priority': priority,
                  'priorityScore': priorityScore,
                  'timeboxMinutes': timeboxMinutes,
                  'updatedAt': DateTime.now().millisecondsSinceEpoch,
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task updated')));
                }
                return;
              }

              // CREATE: plan via AI (with fallback)
              try {
                final plan = await AIService.planTask(
                  title: title,
                  description: description,
                  profile: repo.getProfile()..removeWhere((k, v) => v == null),
                );
                steps = plan.steps;
                // If user provided a custom number, keep it; else use AI suggestion
                if (tbParsed == null) timeboxMinutes = plan.timeboxMinutes;
                tone = plan.tone;
              } catch (_) {
                steps = (description.isNotEmpty)
                    ? ['Plan it', 'Start', 'Do next tiny piece']
                    : ['Start for 5 minutes', 'Do second 5 minutes', 'Write a note'];
                // keep user-entered or default 25
                tone = 'Coach';
              }

              final next = SchedulerService.suggestNextNudge(
                now: DateTime.now(),
                profile: repo.getProfile(),
                task: {'preferredWindow': preferredWindow},
              );

              await repo.addTask({
                'title': title,
                'description': description,
                'category': category,
                'preferredWindow': preferredWindow,
                'priority': priority,
                'priorityScore': priorityScore,
                'steps': steps,
                'timeboxMinutes': timeboxMinutes,
                'aiTone': tone,
                'aiPlanned': true,
                'completed': false,
                'createdAt': DateTime.now().millisecondsSinceEpoch,
                'nextNudgeAt': next.millisecondsSinceEpoch,
              });

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task created')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
              }
            }
          },
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    ),
  );
}

Future<void> _showNudgeNow(BuildContext context, LocalRepo repo) async {
  final style = (repo.getProfile()['preferredNudgeStyle'] as String?) ?? 'Coach';
  final lines = {
    'Gentle': [
      "Two minutes. That’s all.",
      "Tiny wins → big momentum.",
      "Start where it’s easiest."
    ],
    'Coach': [
      "You don’t need motivation — you need motion.",
      "Touch the task. Start the loop.",
      "Action kills anxiety."
    ],
    'DrillSergeant': [
      "No thinking. Start now.",
      "Discipline beats doubt.",
      "120 seconds. Go."
    ],
    'Comedian': [
      "We ball in tiny steps today.",
      "Do it badly first.",
      "Just poke the task."
    ],
  }[style]!;
  final msg = lines[Random().nextInt(lines.length)];

  // ignore: use_build_context_synchronously
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Nudge'),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('I’m on it'))],
    ),
  );
}

/// ===== FOCUS (timer) =====
class FocusPage extends StatelessWidget {
  final LocalRepo repo;
  const FocusPage({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus')),
      body: const Center(
        child: Text(
          "Start sprints from tasks for now.\n(Standalone Focus mode coming soon)",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class FocusSprintSheet extends StatefulWidget {
  final LocalRepo repo;
  final String taskId;
  final String taskTitle;
  final int minutes;
  final String? firstStep;

  const FocusSprintSheet({
    super.key,
    required this.repo,
    required this.taskId,
    required this.taskTitle,
    required this.minutes,
    this.firstStep,
  });

  @override
  State<FocusSprintSheet> createState() => _FocusSprintSheetState();
}

class _FocusSprintSheetState extends State<FocusSprintSheet> {
  late int _remainingSec;
  Timer? _timer;
  bool _running = true;
  late int _startedMs;

  @override
  void initState() {
    super.initState();
    _remainingSec = widget.minutes * 60;
    _startedMs = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_running) return;
      if (_remainingSec <= 0) {
        _complete();
        return;
      }
      setState(() => _remainingSec -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _complete() async {
    _timer?.cancel();

    final durationMin = (widget.minutes - (_remainingSec ~/ 60)).clamp(0, widget.minutes);
    await widget.repo.logSession({
      'taskId': widget.taskId,
      'taskTitle': widget.taskTitle,
      'startedAt': _startedMs,
      'durationMin': durationMin,
      'completed': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    await widget.repo.updateTask(widget.taskId, {
      'lastNudgedAt': DateTime.now().millisecondsSinceEpoch,
      'nextNudgeAt': DateTime.now().add(const Duration(minutes: 90)).millisecondsSinceEpoch,
    });

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nice work — sprint logged!')));
  }

  @override
  Widget build(BuildContext context) {
    final m = (_remainingSec ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSec % 60).toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.taskTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (widget.firstStep != null && widget.firstStep!.isNotEmpty)
            Text('First step: ${widget.firstStep!}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('$m:$s', style: const TextStyle(fontSize: 36, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                label: Text(_running ? 'Pause' : 'Resume'),
                onPressed: () => setState(() => _running = !_running),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.flag),
                label: const Text('Finish'),
                onPressed: _complete,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// ===== PROFILE (local) =====
class ProfilePage extends StatelessWidget {
  final LocalRepo repo;
  const ProfilePage({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditProfileSheet(context, repo),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: repo.watchProfile(),
        builder: (context, _, __) {
          final d = repo.getProfile();
          final name = d['name'] as String? ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User';
          final pronouns = d['pronouns'] as String? ?? '—';
          final age = (d['age'] as int?)?.toString() ?? '—';
          final role = d['role'] as String? ?? '—';
          final neuro = d['neuroType'] as String? ?? '—';
          final bio = d['bio'] as String? ?? '—';
          final goal = d['goals'] as String? ?? '—';
          final nudge = d['preferredNudgeStyle'] as String? ?? '—';
          final email = FirebaseAuth.instance.currentUser?.email ?? '—';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: Text(email),
              ),
              const SizedBox(height: 12),
              _info('Pronouns', pronouns, Icons.wc),
              _info('Age', age, Icons.cake_outlined),
              _info('Role', role, Icons.badge_outlined),
              _info('Neurotype', neuro, Icons.psychology),
              _info('Bio', bio, Icons.description_outlined),
              _info('Main Goal', goal, Icons.flag),
              _info('Nudge Style', nudge, Icons.campaign),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  await repo.close();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _info(String title, String value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    ),
  );
}

Future<void> _showEditProfileSheet(BuildContext context, LocalRepo repo) async {
  final d = repo.getProfile();

  final nameCtrl = TextEditingController(text: d['name'] ?? '');
  final bioCtrl = TextEditingController(text: d['bio'] ?? '');
  String pronouns = (d['pronouns'] ?? 'They/Them') as String;
  String neuroType = (d['neuroType'] ?? 'ADHD - Combined') as String;
  String nudgeStyle = (d['preferredNudgeStyle'] ?? 'Coach') as String;
  String role = (d['role'] ?? 'Other') as String;
  final ageCtrl = TextEditingController(text: (d['age']?.toString() ?? ''));

  // ignore: use_build_context_synchronously
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16, right: 16, top: 16,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: pronouns,
              decoration: const InputDecoration(labelText: 'Pronouns'),
              items: const [
                DropdownMenuItem(value: 'He/Him', child: Text('He/Him')),
                DropdownMenuItem(value: 'She/Her', child: Text('She/Her')),
                DropdownMenuItem(value: 'They/Them', child: Text('They/Them')),
              ],
              onChanged: (v) => pronouns = v ?? 'They/Them',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Age (optional)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Primary role'),
              items: const [
                DropdownMenuItem(value: 'Student', child: Text('Student')),
                DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                DropdownMenuItem(value: 'Freelancer', child: Text('Freelancer')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) => role = v ?? 'Other',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: neuroType,
              decoration: const InputDecoration(labelText: 'Neurotype'),
              items: const [
                DropdownMenuItem(value: 'ADHD - Inattentive', child: Text('ADHD - Inattentive')),
                DropdownMenuItem(value: 'ADHD - Hyperactive', child: Text('ADHD - Hyperactive')),
                DropdownMenuItem(value: 'ADHD - Combined', child: Text('ADHD - Combined')),
                DropdownMenuItem(value: 'Intellectual Disability', child: Text('Intellectual Disability')),
                DropdownMenuItem(value: 'None / Prefer not to say', child: Text('None / Prefer not to say')),
              ],
              onChanged: (v) => neuroType = v ?? 'ADHD - Combined',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: nudgeStyle,
              decoration: const InputDecoration(labelText: 'Nudge style'),
              items: const [
                DropdownMenuItem(value: 'Gentle', child: Text('Gentle')),
                DropdownMenuItem(value: 'Coach', child: Text('Coach')),
                DropdownMenuItem(value: 'DrillSergeant', child: Text('Drill Sergeant')),
                DropdownMenuItem(value: 'Comedian', child: Text('Comedian')),
              ],
              onChanged: (v) => nudgeStyle = v ?? 'Coach',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bioCtrl,
              maxLength: 500, maxLines: 4,
              decoration: const InputDecoration(labelText: 'About you (500 chars)'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await repo.saveProfile({
                  ...repo.getProfile(),
                  'name': nameCtrl.text.trim().isEmpty ? 'User' : nameCtrl.text.trim(),
                  'pronouns': pronouns,
                  'age': int.tryParse(ageCtrl.text.trim()),
                  'role': role,
                  'neuroType': neuroType,
                  'preferredNudgeStyle': nudgeStyle,
                  'bio': bioCtrl.text.trim(),
                  'updatedAt': DateTime.now().millisecondsSinceEpoch,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save changes'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// ===== SETTINGS (local) =====
class SettingsPage extends StatefulWidget {
  final LocalRepo repo;
  const SettingsPage({super.key, required this.repo});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;

  TimeOfDay? workStart;
  TimeOfDay? workEnd;
  final days = <int>{};
  bool allowBefore = true;
  bool allowDuring = true;
  bool allowAfter = true;
  final dailyTargetCtrl = TextEditingController(text: '3');
  bool allowSounds = true;

  final dayLabels = const {1:'Mon',2:'Tue',3:'Wed',4:'Thu',5:'Fri',6:'Sat',7:'Sun'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.repo.getProfile();
    String? ws = d['workStart'] as String?;
    String? we = d['workEnd'] as String?;

    setState(() {
      workStart = _parse(ws) ?? const TimeOfDay(hour: 9, minute: 0);
      workEnd = _parse(we) ?? const TimeOfDay(hour: 17, minute: 0);
      days
        ..clear()
        ..addAll(((d['workDays'] as List?) ?? [1,2,3,4,5]).map((e) => (e as num).toInt()));
      final allow = (d['allowWindows'] as Map?) ?? {'before':true,'during':true,'after':true};
      allowBefore = allow['before'] == true;
      allowDuring = allow['during'] == true;
      allowAfter = allow['after'] == true;
      dailyTargetCtrl.text = ((d['dailyTaskTarget'] ?? 3)).toString();
      allowSounds = d['allowSounds'] == true;
      _loading = false;
    });
  }

  TimeOfDay? _parse(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
  }

  String _fmt(TimeOfDay? t) =>
      t == null ? '' : '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  Future<void> _pick(bool start) async {
    final initial = start ? (workStart ?? const TimeOfDay(hour: 9, minute: 0))
                          : (workEnd ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) setState(() => start ? workStart = picked : workEnd = picked);
  }

  @override
  void dispose() {
    dailyTargetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Work schedule', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(labelText: 'Work start', hintText: _fmt(workStart)),
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  readOnly: true,
                  decoration: InputDecoration(labelText: 'Work end', hintText: _fmt(workEnd)),
                  onTap: () => _pick(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Work days'),
          Wrap(
            spacing: 8,
            children: [1,2,3,4,5,6,7].map((d) {
              final sel = days.contains(d);
              return ChoiceChip(
                label: Text(dayLabels[d]!),
                selected: sel,
                onSelected: (_) => setState(() { sel ? days.remove(d) : days.add(d); }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text('When can we nudge you?'),
          SwitchListTile(title: const Text('Before work'), value: allowBefore, onChanged: (v) => setState(() => allowBefore = v)),
          SwitchListTile(title: const Text('During work'), value: allowDuring, onChanged: (v) => setState(() => allowDuring = v)),
          SwitchListTile(title: const Text('After work'), value: allowAfter, onChanged: (v) => setState(() => allowAfter = v)),
          const Divider(height: 24),
          TextFormField(
            controller: dailyTargetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Daily task target'),
          ),
          SwitchListTile(
            title: const Text('Play sounds on complete'),
            value: allowSounds,
            onChanged: (v) => setState(() => allowSounds = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
            onPressed: () async {
              await widget.repo.saveProfile({
                ...widget.repo.getProfile(),
                'workStart': _fmt(workStart),
                'workEnd': _fmt(workEnd),
                'workDays': days.toList()..sort(),
                'allowWindows': {
                  'before': allowBefore,
                  'during': allowDuring,
                  'after': allowAfter,
                },
                'dailyTaskTarget': int.tryParse(dailyTargetCtrl.text.trim()) ?? 3,
                'allowSounds': allowSounds,
                'updatedAt': DateTime.now().millisecondsSinceEpoch,
              });

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
              }
            },
          ),
        ],
      ),
    );
  }
}
