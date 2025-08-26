import 'dart:math'; // for random nudge
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/ai_service.dart';
import 'services/scheduler_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userDoc.snapshots(),
          builder: (context, profSnap) {
            if (profSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final data = profSnap.data?.data();
            if (data == null || (data['onboarded'] != true)) {
              return OnboardingScreen(userDoc: userDoc, user: user);
            }
            return const Shell();
          },
        );
      },
    );
  }
}

/// Bottom-tab shell (Tasks / Focus / Profile / Settings)
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const TasksPage(),
      const FocusPage(),
      const ProfilePage(),
      const SettingsPage(),
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

/// ===== ONBOARDING =====
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.userDoc, required this.user});
  final DocumentReference<Map<String, dynamic>> userDoc;
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
  final days = <int>{1, 2, 3, 4, 5}; // default Mon–Fri
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
      'workDays': days.toList()..sort(),
      'allowWindows': {
        'before': allowBefore,
        'during': allowDuring,
        'after': allowAfter,
      },
      'dailyTaskTarget': int.tryParse(dailyTargetCtrl.text.trim()) ?? 3,
      'goals': goalCtrl.text.trim(),
      'biggestBlocker': blocker,
      'preferredNudgeStyle': nudgeStyle,
      'allowSounds': allowSounds,
      'currentStreak': 0,
      'longestStreak': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    setState(() => _saving = true);
    try {
      await widget.userDoc.set(profile, SetOptions(merge: true));
      AIService.submitProfile({'uid': widget.user.uid, 'email': widget.user.email, ...profile});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved! Loading your dashboard…')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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

/// ===== TASKS TAB =====
class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    // Simpler query (avoid composite index for now)
    final tasksQuery = userDoc.collection('tasks').orderBy('createdAt', descending: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroNudge'),
        actions: [
          IconButton(
            tooltip: 'Debug: add simple task',
            icon: const Icon(Icons.build_outlined),
            onPressed: () => _debugAddSimpleTask(context, userDoc),
          ),
          IconButton(
            tooltip: 'Nudge me',
            icon: const Icon(Icons.campaign_outlined),
            onPressed: () => _showNudgeNow(context, userDoc),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _GreetingCard(userDoc: userDoc),
          const SizedBox(height: 12),
          _StreakRow(userDoc: userDoc),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'Add Task',
                icon: const Icon(Icons.add_circle),
                onPressed: () => _showAddOrEditTaskDialog(context, userDoc),
              ),
            ],
          ),

          // Typed StreamBuilder + error shown
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: tasksQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading tasks: ${snap.error}\nIf it mentions an index, open the link to create it.',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("No tasks yet — tap  +  to add one.",
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                );
              }

              final tasks = snap.data!.docs;
              return Column(
                children: tasks.map((doc) {
                  final d = doc.data();
                  final completed = (d['completed'] ?? false) as bool;
                  final title = (d['title'] ?? 'Untitled Task') as String;
                  final steps = (d['steps'] as List?)?.cast<String>() ?? const <String>[];
                  final tb = (d['timeboxMinutes'] ?? 0) as int;
                  final tone = (d['aiTone'] ?? 'Coach') as String;
                  final cat = (d['category'] ?? 'Both') as String;
                  final win = (d['preferredWindow'] ?? 'any') as String;
                  final priorLabel = (d['priority'] ?? 'Medium') as String;
                  final Timestamp? nextTs = d['nextNudgeAt'] as Timestamp?;
                  final nextStr = nextTs == null ? '—' : TimeOfDay.fromDateTime(nextTs.toDate()).format(context);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: CheckboxListTile(
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
                              _chip(Icons.flag, 'Priority: $priorLabel'),
                              _chip(Icons.access_time, 'Window: ${win[0].toUpperCase()}${win.substring(1)}'),
                              _chip(Icons.schedule, 'Next: $nextStr'),
                            ],
                          ),
                        ],
                      ),
                      onChanged: (v) => doc.reference.update({'completed': v}),
                      secondary: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showAddOrEditTaskDialog(
                              context,
                              userDoc,
                              docRef: doc.reference, // typed right
                              existing: d,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => doc.reference.delete(),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
      floatingActionButton: null,
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
  const _GreetingCard({required this.userDoc});
  final DocumentReference<Map<String, dynamic>> userDoc;

  @override
  Widget build(BuildContext context) {
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = (data['name'] as String?) ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Friend';
        final style = (data['preferredNudgeStyle'] as String?) ?? 'Coach';
        final all = nudgesByStyle[style] ?? nudgesByStyle['Coach']!;
        final nudge = all[Random().nextInt(all.length)]; // random pick (no shuffle)

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
      },
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.userDoc});
  final DocumentReference<Map<String, dynamic>> userDoc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final current = (data['currentStreak'] ?? 0) as int;
        final longest = (data['longestStreak'] ?? 0) as int;
        return Row(
          children: [
            _pill(Icons.local_fire_department, 'Current', '$current'),
            const SizedBox(width: 8),
            _pill(Icons.emoji_events, 'Longest', '$longest'),
          ],
        );
      },
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

/// Add/Edit Task dialog (CRUD) with AI fallback + robust errors
Future<void> _showAddOrEditTaskDialog(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> userDoc, {
  DocumentReference<Map<String, dynamic>>? docRef,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = docRef != null && existing != null;
  final titleCtrl = TextEditingController(text: isEdit ? (existing['title'] ?? '') : '');
  final descCtrl = TextEditingController(text: isEdit ? (existing['description'] ?? '') : '');

  String category = isEdit ? (existing['category'] ?? 'Both') : 'Both';
  String preferredWindow = isEdit ? (existing['preferredWindow'] ?? 'any') : 'any';
  String priority = isEdit ? (existing['priority'] ?? 'Medium') : 'Medium';
  int priorityScore = {'Low': 1, 'Medium': 2, 'High': 3}[priority]!;

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isEdit ? 'Edit Task' : 'New Task'),
      content: Column(
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
        ],
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () async {
              try {
                await docRef!.delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final title = titleCtrl.text.trim().isEmpty ? 'New Task' : titleCtrl.text.trim();
            final description = descCtrl.text.trim();

            try {
              if (isEdit) {
                await docRef!.update({
                  'title': title,
                  'description': description,
                  'category': category,
                  'preferredWindow': preferredWindow,
                  'priority': priority,
                  'priorityScore': priorityScore,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task updated')));
                }
                return;
              }

              // CREATE: plan via AI, with fallback if AI is offline
              final profSnap = await userDoc.get();
              final profile = (profSnap.data() ?? {})..removeWhere((k, v) => v == null);

              List<String> steps = const <String>[];
              int timeboxMinutes = 25;
              String tone = 'Coach';

              try {
                final plan = await AIService.planTask(
                  title: title,
                  description: description,
                  profile: profile,
                );
                steps = plan.steps;
                timeboxMinutes = plan.timeboxMinutes;
                tone = plan.tone;
              } catch (_) {
                steps = (description.isNotEmpty)
                    ? ['Plan it', 'Start', 'Do next tiny piece']
                    : ['Start for 5 minutes', 'Do second 5 minutes', 'Write a note'];
                timeboxMinutes = 25;
                tone = 'Coach';
              }

              final next = SchedulerService.suggestNextNudge(
                now: DateTime.now(),
                profile: profile,
                task: {'preferredWindow': preferredWindow},
              );

              await userDoc.collection('tasks').add({
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
                'createdAt': FieldValue.serverTimestamp(),
                'nextNudgeAt': Timestamp.fromDate(next),
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

/// Simple “Nudge me now” prompt based on style
Future<void> _showNudgeNow(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> userDoc,
) async {
  final snap = await userDoc.get();
  final style = (snap.data()?['preferredNudgeStyle'] as String?) ?? 'Coach';
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

/// Debug: add a simple task without AI to prove writes work
Future<void> _debugAddSimpleTask(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> userDoc,
) async {
  try {
    await userDoc.collection('tasks').add({
      'title': 'Debug task',
      'description': 'Created without AI',
      'category': 'Both',
      'preferredWindow': 'any',
      'priority': 'Medium',
      'priorityScore': 2,
      'steps': ['Open app', 'Tap a thing', 'Done'],
      'timeboxMinutes': 10,
      'aiTone': 'Coach',
      'aiPlanned': false,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'nextNudgeAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debug task saved')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Debug save failed: $e')));
    }
  }
}

/// ===== FOCUS TAB (placeholder) =====
class FocusPage extends StatelessWidget {
  const FocusPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus')),
      body: const Center(
        child: Text(
          "Focus mode coming soon:\n• Timers\n• One task highlighted\n• Auto-schedule next nudge",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// ===== PROFILE TAB (with Edit) =====
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditProfileSheet(context, userDoc),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc.snapshots(),
        builder: (context, snap) {
          final d = snap.data?.data() ?? {};
          final name = d['name'] as String? ?? user.displayName ?? 'User';
          final pronouns = d['pronouns'] as String? ?? '—';
          final age = (d['age'] as int?)?.toString() ?? '—';
          final role = d['role'] as String? ?? '—';
          final neuro = d['neuroType'] as String? ?? '—';
          final bio = d['bio'] as String? ?? '—';
          final goal = d['goals'] as String? ?? '—';
          final nudge = d['preferredNudgeStyle'] as String? ?? '—';
          final email = user.email ?? '—';

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
                onPressed: () => FirebaseAuth.instance.signOut(),
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

/// Edit Profile (CRUD: Update)
Future<void> _showEditProfileSheet(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> userDoc,
) async {
  final snap = await userDoc.get();
  final d = snap.data() ?? {};

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
                await userDoc.set({
                  'name': nameCtrl.text.trim().isEmpty ? 'User' : nameCtrl.text.trim(),
                  'pronouns': pronouns,
                  'age': int.tryParse(ageCtrl.text.trim()),
                  'role': role,
                  'neuroType': neuroType,
                  'preferredNudgeStyle': nudgeStyle,
                  'bio': bioCtrl.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
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

/// ===== SETTINGS TAB =====
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
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
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final d = doc.data() ?? {};

    String? _s(String k) => d[k] as String?;
    String? ws = _s('workStart');
    String? we = _s('workEnd');

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
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

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
              await userDoc.set({
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
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

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
