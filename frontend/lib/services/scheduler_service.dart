// lib/services/scheduler_service.dart
import 'package:flutter/material.dart';

class SchedulerService {
  /// profile: {
  ///   'workStart': 'HH:MM',
  ///   'workEnd': 'HH:MM',
  ///   'workDays': [1..7], // 1=Mon ... 7=Sun
  ///   'allowWindows': { 'before': true, 'during': true, 'after': true }
  /// }
  ///
  /// task: {
  ///   'preferredWindow': 'before'|'during'|'after'|'any'
  /// }
  ///
  /// Returns the next DateTime to nudge.
  static DateTime suggestNextNudge({
    required DateTime now,
    required Map<String, dynamic> profile,
    required Map<String, dynamic> task,
  }) {
    final workStartStr = (profile['workStart'] as String?) ?? '09:00';
    final workEndStr = (profile['workEnd'] as String?) ?? '17:00';
    final startMin = _minutesFromHHMM(workStartStr) ?? 9 * 60;
    final endMin = _minutesFromHHMM(workEndStr) ?? 17 * 60;

    // Days: default Mon–Fri
    final List<dynamic> wdRaw = (profile['workDays'] as List?) ?? [1, 2, 3, 4, 5];
    final workDays = wdRaw.map((e) => (e as num).toInt()).toSet();

    final allow = (profile['allowWindows'] as Map?) ?? {
      'before': true,
      'during': true,
      'after': true,
    };

    // Which window does this task prefer?
    final pref = (task['preferredWindow'] as String?)?.toLowerCase() ?? 'any';
    final windowsInPriority = _windowPriority(pref, allow);

    // Try up to 14 days ahead to find the next valid nudge slot
    DateTime candidate = now;
    for (int i = 0; i < 14; i++) {
      final date = now.add(Duration(days: i));
      if (!workDays.contains(date.weekday)) continue;

      // minutes from midnight for 'now' on 'date'
      final isToday = _sameDay(date, now);
      final nowMin = isToday ? (now.hour * 60 + now.minute) : -1; // -1 => not today

      for (final w in windowsInPriority) {
        if (w == 'before' && (allow['before'] == true)) {
          // pick date at (workStart - 10min) if future; if today & before start, try now+2min
          if (isToday && nowMin >= 0 && nowMin < startMin - 2) {
            return now.add(const Duration(minutes: 2));
          } else {
            final tMin = (startMin - 10).clamp(0, 24 * 60 - 1);
            final dt = _atMinutes(date, tMin);
            if (dt.isAfter(now)) return dt;
          }
        } else if (w == 'during' && (allow['during'] == true)) {
          if (isToday && nowMin >= startMin && nowMin <= endMin - 2) {
            return now.add(const Duration(minutes: 2));
          } else {
            final dt = _atMinutes(date, startMin + 5);
            if (dt.isAfter(now)) return dt;
          }
        } else if (w == 'after' && (allow['after'] == true)) {
          if (isToday && nowMin > endMin) {
            return now.add(const Duration(minutes: 2));
          } else {
            final dt = _atMinutes(date, (endMin + 5).clamp(0, 24 * 60 - 1));
            if (dt.isAfter(now)) return dt;
          }
        }
      }
    }

    // Fallback: nudge in 10 minutes.
    return now.add(const Duration(minutes: 10));
  }

  static List<String> _windowPriority(String pref, Map allow) {
    // Honor preference; if 'any', prefer: during > after > before (sensible default).
    final base = ['during', 'after', 'before'];
    if (pref == 'any') {
      return base.where((w) => allow[w] == true).toList();
    }
    final p = pref.toLowerCase();
    final list = [p, ...base.where((w) => w != p)];
    return list.where((w) => allow[w] == true).toList();
  }

  static int? _minutesFromHHMM(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _atMinutes(DateTime day, int minutesFromMidnight) =>
      DateTime(day.year, day.month, day.day, minutesFromMidnight ~/ 60, minutesFromMidnight % 60);
}
