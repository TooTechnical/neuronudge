import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Plan {
  final List<String> steps;
  final int timeboxMinutes;
  final String tone;

  const Plan({
    required this.steps,
    required this.timeboxMinutes,
    required this.tone,
  });
}

class AIService {
  static const Duration _timeout = Duration(seconds: 20);

  static String get baseUrl {
    const configured = String.fromEnvironment('AI_BASE_URL');
    if (configured.isNotEmpty) {
      final uri = Uri.parse(configured);
      if (kReleaseMode && uri.scheme != 'https') {
        throw StateError('AI_BASE_URL must use HTTPS in release builds.');
      }
      return configured.replaceAll(RegExp(r'/+$'), '');
    }

    if (kReleaseMode) {
      throw StateError('AI_BASE_URL is required for release builds.');
    }
    return 'http://127.0.0.1:8000';
  }

  static Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use NeuroNudge planning.');
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Unable to authenticate this request.');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<void> submitProfile(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/profile');
    try {
      final response = await http
          .post(uri, headers: await _headers(), body: jsonEncode(payload))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(response.statusCode, response.body);
      }
    } on TimeoutException {
      throw const HttpException(408, 'The NeuroNudge service timed out.');
    }
  }

  static Future<Plan> planTask({
    required String title,
    required String description,
    required Map<String, dynamic> profile,
  }) async {
    final uri = Uri.parse('$baseUrl/plan');
    final body = jsonEncode({
      'title': title,
      'description': description,
      'profile': profile,
    });

    late http.Response response;
    try {
      response = await http
          .post(uri, headers: await _headers(), body: body)
          .timeout(_timeout);
    } on TimeoutException {
      throw const HttpException(408, 'The NeuroNudge service timed out.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid response from NeuroNudge service.');
    }

    final rawSteps = decoded['steps'];
    final steps = rawSteps is List
        ? rawSteps.whereType<String>().where((step) => step.trim().isNotEmpty).toList()
        : <String>[];

    if (steps.isEmpty) {
      throw const FormatException('The plan did not contain any steps.');
    }

    return Plan(
      steps: steps,
      timeboxMinutes: (decoded['timeboxMinutes'] as num?)?.toInt() ?? 25,
      tone: decoded['tone'] as String? ?? 'Coach',
    );
  }
}

class HttpException implements Exception {
  final int statusCode;
  final String message;

  const HttpException(this.statusCode, this.message);

  @override
  String toString() => 'NeuroNudge request failed ($statusCode): $message';
}
