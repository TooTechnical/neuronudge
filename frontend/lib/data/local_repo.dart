// frontend/lib/data/local_repo.dart
import 'package:flutter/foundation.dart'; // <- for ValueListenable
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class LocalRepo {
  final String uid;
  final Box _profileBox;
  final Box _tasksBox;
  final Box _sessionsBox;
  final _uuid = const Uuid();

  LocalRepo._(this.uid, this._profileBox, this._tasksBox, this._sessionsBox);

  static Future<LocalRepo> open(String uid) async {
    final profile = await Hive.openBox('profile_$uid');
    final tasks = await Hive.openBox('tasks_$uid');
    final sessions = await Hive.openBox('sessions_$uid');
    return LocalRepo._(uid, profile, tasks, sessions);
  }

  // ---------- Profile ----------
  Map<String, dynamic> getProfile() {
    final raw = _profileBox.get('data');
    if (raw is Map) return Map<String, dynamic>.from(raw as Map);
    return <String, dynamic>{};
  }

  Future<void> saveProfile(Map<String, dynamic> p) async {
    await _profileBox.put('data', p);
  }

  ValueListenable<Box> watchProfile() => _profileBox.listenable();

  // ---------- Tasks ----------
  ValueListenable<Box> watchTasks() => _tasksBox.listenable();

  List<Map<String, dynamic>> allTasks() {
    return _tasksBox.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<String> addTask(Map<String, dynamic> t) async {
    final id = _uuid.v4();
    await _tasksBox.put(id, {'id': id, ...t});
    return id;
  }

  Future<void> updateTask(String id, Map<String, dynamic> patch) async {
    final existing = _tasksBox.get(id);
    final base = (existing is Map)
        ? Map<String, dynamic>.from(existing as Map)
        : <String, dynamic>{'id': id};
    await _tasksBox.put(id, {...base, ...patch});
  }

  Future<void> deleteTask(String id) async => _tasksBox.delete(id);

  // ---------- Sessions ----------
  Future<void> logSession(Map<String, dynamic> s) async => _sessionsBox.add(s);

  Future<void> close() async {
    await _profileBox.close();
    await _tasksBox.close();
    await _sessionsBox.close();
  }
}
