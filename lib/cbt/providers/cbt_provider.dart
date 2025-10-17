import 'package:brightbuds_new/cbt/models/cbt_exercise_model.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/assigned_cbt_model.dart';
import '../repositories/cbt_repository.dart';

class CBTProvider with ChangeNotifier {
  final CBTRepository _repository = CBTRepository();
  List<AssignedCBT> _assigned = [];

  List<AssignedCBT> get assigned => _assigned;

  // ===== Utility Helpers =====
  int getCurrentWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSince = date.difference(firstDayOfYear).inDays;
    return ((daysSince + firstDayOfYear.weekday) / 7).ceil();
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  // ====== EXECUTION LOGIC ======
  bool canExecute(AssignedCBT a) {
    final now = DateTime.now();
    if (a.lastCompleted == null) return true;

    if (a.recurrence == 'daily') {
      // can re-execute if lastCompleted was before today
      return _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now));
    } else if (a.recurrence == 'weekly') {
      // can re-execute if lastCompleted was before current week
      final currentWeek = getCurrentWeekNumber(now);
      final lastWeek = getCurrentWeekNumber(a.lastCompleted!);
      return currentWeek != lastWeek;
    }
    // default: daily behaviour
    return _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now));
  }

  // ====== RESET & CLEANUP ======
  Future<void> normalizeAssignedStatusesAndCleanup(String parentId, String childId) async {
    final now = DateTime.now();
    final currentWeek = getCurrentWeekNumber(now);
    final List<String> toUnassign = [];

    for (var a in _assigned) {
      // --- DAILY ---
      if (a.recurrence == 'daily') {
        if (a.lastCompleted != null &&
            _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false; // reset daily
        }
      }

      // --- WEEKLY ---
      else if (a.recurrence == 'weekly') {
        // expired weekly CBT → auto-unassign
        if (a.weekOfYear < currentWeek) {
          toUnassign.add(a.id);
          continue;
        }

        // still current week → check if done this week
        if (a.lastCompleted != null &&
            getCurrentWeekNumber(a.lastCompleted!) == currentWeek) {
          a.completed = true;
        } else {
          a.completed = false;
        }
      }

      // --- fallback daily-like ---
      else {
        if (a.lastCompleted != null &&
            _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false;
        }
      }
    }

    // remove expired weekly CBTs
    for (final id in toUnassign) {
      try {
        await _repository.removeAssignedCBT(parentId, childId, id);
        _assigned.removeWhere((a) => a.id == id);
      } catch (e) {
        debugPrint("Error auto-unassigning expired CBT: $e");
      }
    }

    notifyListeners();
  }

  // ====== ASSIGNMENT ======
  Future<void> assignManualCBT(
      String parentId, String childId, CBTExercise exercise) async {
    final weekOfYear = getCurrentWeekNumber(DateTime.now());
    await loadAssignedCBTs(parentId, childId);

    // prevent duplicates in current week
    final alreadyAssigned = _assigned.any((a) =>
        a.weekOfYear == weekOfYear &&
        a.exerciseId == exercise.id &&
        a.childId == childId);
    if (alreadyAssigned) return;

    final assigned = AssignedCBT.fromExercise(
      id: UniqueKey().toString(),
      exercise: exercise,
      childId: childId,
      assignedDate: DateTime.now(),
      weekOfYear: weekOfYear,
      assignedBy: parentId,
      recurrence: exercise.recurrence,
      source: "manual",
    );

    await _repository.addAssignedCBT(parentId, assigned);
    _assigned.add(assigned);
    notifyListeners();
  }

  Future<void> unassignCBT(
      String parentId, String childId, String assignedId) async {
    try {
      await _repository.removeAssignedCBT(parentId, childId, assignedId);
      _assigned.removeWhere((a) => a.id == assignedId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error unassigning CBT: $e');
    }
  }

  // ====== LOADERS ======
  Future<void> loadAssignedCBTs(String parentId, String childId) async {
    final weekOfYear = getCurrentWeekNumber(DateTime.now());
    final list =
        await _repository.getAssignedCBTsForWeek(parentId, childId, weekOfYear);
    _assigned = list;
    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();
  }

  Future<void> loadCBT(String parentId, String childId) async {
    await _repository.syncFromFirestore(parentId, childId);
    _assigned = _repository.getLocalCBTs(childId);
    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();
  }

  // ====== COMPLETION ======
  Future<bool> markAsCompleted(
      String parentId, String childId, String cbtAssignedId) async {
    final assigned = _assigned.firstWhere(
      (a) => a.id == cbtAssignedId,
      orElse: () => throw Exception('Assigned CBT not found'),
    );

    if (!canExecute(assigned)) {
      return false; // cannot complete again yet
    }

    assigned.completed = true;
    assigned.lastCompleted = DateTime.now();

    await _repository.updateCompletion(parentId, childId, assigned.id);
    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();

    return true;
  }
  

  // ====== GETTERS ======
  List<AssignedCBT> getCurrentWeekAssignments() {
    final week = getCurrentWeekNumber(DateTime.now());
    return _assigned.where((a) => a.weekOfYear == week).toList();
  }

  bool isCompleted(String childId, String exerciseId) {
    final assigned = _assigned
        .where((a) => a.childId == childId && a.exerciseId == exerciseId)
        .toList();
    return assigned.isNotEmpty ? assigned.first.completed : false;
  }

  AssignedCBT? getCBTById(String id) {
    try {
      return _assigned.firstWhere((cbt) => cbt.id == id);
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _assigned = [];
    notifyListeners();
  }
}
