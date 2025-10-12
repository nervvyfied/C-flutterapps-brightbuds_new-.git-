import 'package:brightbuds_new/cbt/models/cbt_exercise_model.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/assigned_cbt_model.dart';
import '../repositories/cbt_repository.dart';

class CBTProvider with ChangeNotifier {
  final CBTRepository _repository = CBTRepository();
  List<AssignedCBT> _assigned = [];

  List<AssignedCBT> get assigned => _assigned;

  int getCurrentWeekNumber(DateTime date) {
  final firstDayOfYear = DateTime(date.year, 1, 1);
  final daysSince = date.difference(firstDayOfYear).inDays;
  return ((daysSince + firstDayOfYear.weekday) / 7).ceil();
}


  /// Assign a single CBT manually
  Future<void> assignManualCBT(
      String parentId, String childId, CBTExercise exercise) async {
    final weekOfYear = getCurrentWeekNumber(DateTime.now());

    await loadAssignedCBTs(parentId, childId);

    if (_assigned.any((a) =>
        a.weekOfYear == weekOfYear && a.exerciseId == exercise.id)) return;

    final assigned = AssignedCBT.fromExercise(
      id: UniqueKey().toString(),
      exercise: exercise,
      childId: childId,
      assignedDate: DateTime.now(),
      weekOfYear: weekOfYear,
      assignedBy: parentId,
      source: "manual",
    );

    await _repository.addAssignedCBT(parentId, assigned);
    _assigned.add(assigned);
    notifyListeners();
  }

  /// Load CBT assignments for the child
  Future<void> loadAssignedCBTs(String parentId, String childId) async {
    final weekOfYear = getCurrentWeekNumber(DateTime.now());
    final list =
        await _repository.getAssignedCBTsForWeek(parentId, childId, weekOfYear);
    _assigned = list;
    notifyListeners();
  }

  /// Get current week assignments
  List<AssignedCBT> getCurrentWeekAssignments() {
  final week = getCurrentWeekNumber(DateTime.now());
  return _assigned.where((a) => a.weekOfYear == week).toList();
}

  /// Sync Firestore → local → state
  Future<void> loadCBT(String parentId, String childId) async {
    await _repository.syncFromFirestore(parentId, childId);
    _assigned = _repository.getLocalCBTs(childId);
    notifyListeners();
  }

  /// Mark CBT as completed
  Future<void> markAsCompleted(
      String parentId, String childId, String cbtId) async {
    await _repository.updateCompletion(parentId, childId, cbtId);
    await loadCBT(parentId, childId);
  }

  /// Check if CBT is completed
  bool isCompleted(String childId, String exerciseId) {
    final assigned = _assigned
        .where((a) => a.childId == childId && a.exerciseId == exerciseId)
        .toList();
    return assigned.isNotEmpty ? assigned.first.completed : false;
  }

  /// Get assigned CBT by ID
  AssignedCBT? getCBTById(String id) {
    try {
      return _assigned.firstWhere((cbt) => cbt.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Clear provider state
  void clear() {
    _assigned = [];
    notifyListeners();
  }
}
