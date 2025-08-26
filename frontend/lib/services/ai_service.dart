// lib/services/ai_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Set your own backend base URL at build time:
/// flutter run -d chrome --dart-define=AI_BASE_URL=http://127.0.0.1:8000
const String _defaultBase =
    String.fromEnvironment('AI_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

class AIPlan {
  final List<String> steps;
  final int timeboxMinutes;
  final String tone; // e.g., 'DrillSergeant', 'Coach', 'Gentle', 'Comedian'

  AIPlan({required this.steps, required this.timeboxMinutes, required this.tone});

  Map<String, dynamic> toJson() => {
        'steps': steps,
        'timeboxMinutes': timeboxMinutes,
        'tone': tone,
      };

  factory AIPlan.fromJson(Map<String, dynamic> j) => AIPlan(
        steps: (j['steps'] as List).cast<String>(),
        timeboxMinutes: (j['timeboxMinutes'] as num).toInt(),
        tone: (j['tone'] as String),
      );
}

class AIService {
  static String get baseUrl => _defaultBase;

  /// Call your backend to save/update the profile.
  /// Expected backend: POST /api/profile  (JSON body)
  static Future<void> submitProfile(Map<String, dynamic> profile) async {
    final uri = Uri.parse('$baseUrl/api/profile');
    try {
      final res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(profile))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      // Non-2xx: silently ignore (frontend keeps working)
    } catch (_) {
      // No backend yet? Ignore; app runs with local logic.
    }
  }

  /// Ask your backend to plan a task. If unavailable, fall back to a local heuristic.
  /// Expected backend: POST /api/plan  (body: { title, description, profile })
  static Future<AIPlan> planTask({
    required String title,
    String? description,
    required Map<String, dynamic> profile,
  }) async {
    final uri = Uri.parse('$baseUrl/api/plan');
    final body = {
      'title': title,
      'description': description ?? '',
      'profile': profile,
    };

    try {
      final res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return AIPlan.fromJson(j);
      }
    } catch (_) {
      // fall through to heuristic
    }

    // ===== Local Heuristic (no backend yet) =====
    return _heuristicPlan(title: title, description: description, profile: profile);
  }

  static AIPlan _heuristicPlan({
    required String title,
    String? description,
    required Map<String, dynamic> profile,
  }) {
    final text = ('$title ${description ?? ''}').toLowerCase();
    final neuro = (profile['neuroType'] ?? '').toString().toLowerCase();
    final preferred = (profile['preferredNudgeStyle'] ?? '').toString();

    // Tone: default by ADHD type or preferred style
    String tone = 'Coach';
    if (preferred.isNotEmpty) {
      tone = preferred.replaceAll(' ', '');
    } else if (neuro.contains('hyper')) {
      tone = 'DrillSergeant';
    } else if (neuro.contains('high') && neuro.contains('adhd')) {
      tone = 'DrillSergeant';
    }

    // Category guess
    bool isClean = RegExp(r'\b(clean|tidy|room|space|desk|kitchen|bed(room)?|organize)\b')
        .hasMatch(text);
    bool isProject = RegExp(r'\b(project|code|build|write|essay|report|website|deploy|homework)\b')
        .hasMatch(text);
    bool isReading =
        RegExp(r'\b(read|book|chapter|study|revision|revise)\b').hasMatch(text);

    int minutes = 20;
    List<String> steps = [];

    if (isClean) {
      minutes = text.contains('personal space') ? 30 : 10;
      steps = [
        'Set a timer for $minutes minutes',
        'Pick ONE zone (desk, floor, or surface)',
        'Trash & laundry out first',
        'Group items: keep, bin, move',
        'Reset the zone and stop when timer ends',
      ];
    } else if (isProject) {
      minutes = 60;
      steps = [
        'Open the project and the exact file/doc you need',
        'Write a 3-line plan for this session',
        'Do the first subtask for 25 minutes',
        'Short break (5 minutes), then continue',
        'Save/commit and write a 1-line summary',
      ];
    } else if (isReading) {
      minutes = 30;
      steps = [
        'Choose a chapter/section (~$minutes minutes)',
        'Read with a pen; underline 3 key ideas',
        'Write 3 bullet points of takeaways',
        'Stop when timer ends and log your progress',
      ];
    } else {
      minutes = 15;
      steps = [
        'Define the smallest meaningful first step',
        'Do it for $minutes minutes (no perfection)',
        'Stop, review, and set the next tiny step',
      ];
    }

    return AIPlan(steps: steps, timeboxMinutes: minutes, tone: tone);
  }
}
