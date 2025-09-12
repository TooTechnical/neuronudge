// frontend/lib/services/ai_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Plan {
  final List<String> steps;
  final int timeboxMinutes;
  final String tone;
  Plan({required this.steps, required this.timeboxMinutes, required this.tone});
}

class AIService {
  static String get baseUrl {
    // Set by: flutter run ... --dart-define=AI_BASE_URL=http://127.0.0.1:8000
    const fromDefine = String.fromEnvironment('AI_BASE_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    // Fallback for dev if you forget the define
    return 'http://127.0.0.1:8000';
  }

  static Future<void> submitProfile(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/profile');
    if (kDebugMode) {
      final short = jsonEncode(payload);
      print('[AI] POST $uri payload=${short.substring(0, short.length.clamp(0, 200))}…');
    }
    try {
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      if (kDebugMode) print('[AI] /profile error: $e');
    }
  }

  static Future<Plan> planTask({
    required String title,
    required String description,
    required Map<String, dynamic> profile,
  }) async {
    final uri = Uri.parse('$baseUrl/plan');
    final bodyMap = {'title': title, 'description': description, 'profile': profile};
    final body = jsonEncode(bodyMap);

    if (kDebugMode) {
      print('[AI] POST $uri body=${body.substring(0, body.length.clamp(0, 200))}…');
    }

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (kDebugMode) print('[AI] /plan status=${resp.statusCode} resp=${resp.body}');

    if (resp.statusCode != 200) {
      throw Exception('AI plan failed ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final steps = (data['steps'] as List?)?.cast<String>() ?? const <String>[];
    final tb = (data['timeboxMinutes'] as num?)?.toInt() ?? 25;
    final tone = (data['tone'] as String?) ?? 'Coach';
    return Plan(steps: steps, timeboxMinutes: tb, tone: tone);
  }
}
