import 'package:brightbuds_new/cbt/models/cbt_exercise_model.dart';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/assigned_cbt_model.dart';
import '../repositories/cbt_repository.dart';

class CBTProvider with ChangeNotifier {
  final CBTRepository _repository = CBTRepository();

  List<AssignedCBT> _assigned = [];
  List<AssignedCBT> get assigned => _assigned;

  List<String> _pendingSync = []; // Pending CBT IDs to sync
  Box<AssignedCBT>? _cbtBox;
  Box<List<String>>? _syncBox;

  // ===== Hive Initialization =====
  Future<void> initHive() async {
    if (!Hive.isBoxOpen('cbtBox')) {
      _cbtBox = await Hive.openBox<AssignedCBT>('cbtBox');
    } else {
      _cbtBox = Hive.box<AssignedCBT>('cbtBox');
    }

    if (!Hive.isBoxOpen('cbtSyncBox')) {
      _syncBox = await Hive.openBox<List<String>>('cbtSyncBox');
    } else {
      _syncBox = Hive.box<List<String>>('cbtSyncBox');
    }

    // Load persisted pending sync
    _pendingSync = _syncBox?.get('pendingSync', defaultValue: []) ?? [];
  }

  // ===== Utility =====
  int getCurrentWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSince = date.difference(firstDayOfYear).inDays;
    return ((daysSince + firstDayOfYear.weekday) / 7).ceil();
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool canExecute(AssignedCBT a) {
    final now = DateTime.now();
    if (a.lastCompleted == null) return true;

    if (a.recurrence == 'daily') {
      return _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now));
    } else if (a.recurrence == 'weekly') {
      final currentWeek = getCurrentWeekNumber(now);
      final lastWeek = getCurrentWeekNumber(a.lastCompleted!);
      return currentWeek != lastWeek;
    }
    return _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now));
  }

  // ===== Load Local CBT =====
  Future<void> loadLocalCBT(String parentId, String childId) async {
    await initHive();
    _assigned = _cbtBox!.values.where((a) => a.childId == childId).toList();
    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();
  }

  // ===== Load Remote CBT =====
  Future<void> loadRemoteCBT(String parentId, String childId) async {
    await _repository.syncFromFirestore(parentId, childId);
    final remote = _repository.getLocalCBTs(childId);

    // Merge remote + local intelligently
    final Map<String, AssignedCBT> merged = {for (var a in _assigned) a.id: a};
    for (var r in remote) {
      if (merged.containsKey(r.id)) {
        final local = merged[r.id]!;

        // Preserve local completion if newer
        if (local.lastCompleted != null &&
            (r.lastCompleted == null || local.lastCompleted!.isAfter(r.lastCompleted!))) {
          r.completed = local.completed;
          r.lastCompleted = local.lastCompleted;
        }
      }
      merged[r.id] = r;
    }

    _assigned = merged.values.toList();

    // Save merged to Hive
    for (var a in _assigned) {
      await _cbtBox?.put(a.id, a);
    }

    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();
  }

  // ===== Normalize & Cleanup =====
  Future<void> normalizeAssignedStatusesAndCleanup(String parentId, String childId) async {
    final now = DateTime.now();
    final currentWeek = getCurrentWeekNumber(now);
    final List<String> toUnassign = [];

    for (var a in _assigned) {
      if (a.recurrence == 'daily') {
        if (a.lastCompleted != null && _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false;
        }
      } else if (a.recurrence == 'weekly') {
        if (a.weekOfYear < currentWeek) {
          toUnassign.add(a.id);
          continue;
        }
        if (a.lastCompleted != null && getCurrentWeekNumber(a.lastCompleted!) == currentWeek) {
          a.completed = true;
        } else {
          a.completed = false;
        }
      } else {
        if (a.lastCompleted != null && _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false;
        }
      }
    }

    // Remove expired weekly CBTs
    for (final id in toUnassign) {
      try {
        await _repository.removeAssignedCBT(parentId, childId, id);
        _assigned.removeWhere((a) => a.id == id);
        await _cbtBox?.delete(id);
      } catch (e) {
        debugPrint("Error auto-unassigning expired CBT: $e");
      }
    }

    notifyListeners();
  }

  // ===== Completion (Offline First) =====
  Future<bool> markAsCompleted(String parentId, String childId, String cbtAssignedId) async {
    AssignedCBT? assigned;
    try {
      assigned = _assigned.firstWhere((a) => a.id == cbtAssignedId);
    } catch (_) {
      assigned = null;
    }

    if (assigned == null || !canExecute(assigned)) return false;

    assigned.completed = true;
    assigned.lastCompleted = DateTime.now();

    // Save locally
    await _cbtBox?.put(assigned.id, assigned);

    // Add to pending sync
    if (!_pendingSync.contains(assigned.id)) {
      _pendingSync.add(assigned.id);
      await _syncBox?.put('pendingSync', _pendingSync);
    }

    notifyListeners();

    // Attempt immediate sync if online
    await syncPendingCompletions(parentId);

    return true;
  }

  Future<void> syncPendingCompletions(String parentId) async {
    if (_pendingSync.isEmpty) return;
    final online = await NetworkHelper.isOnline();
    if (!online) return;

    for (var id in List.from(_pendingSync)) {
      AssignedCBT? assigned;
      try {
        assigned = _assigned.firstWhere((a) => a.id == id);
      } catch (_) {
        assigned = null;
      }

      if (assigned != null) {
        try {
          await _repository.updateCompletion(parentId, assigned.childId, assigned.id);
          _pendingSync.remove(id);
          await _syncBox?.put('pendingSync', _pendingSync);
        } catch (e) {
          debugPrint('Failed syncing CBT $id: $e');
        }
      } else {
        _pendingSync.remove(id);
        await _syncBox?.put('pendingSync', _pendingSync);
      }
    }
  }

  // ===== Assignment =====
Future<void> assignManualCBT(String parentId, String childId, CBTExercise exercise) async {
  final weekOfYear = getCurrentWeekNumber(DateTime.now());
  await loadLocalCBT(parentId, childId);

  final alreadyAssigned = _assigned.any((a) =>
      a.weekOfYear == weekOfYear && a.exerciseId == exercise.id && a.childId == childId);
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

  _assigned.add(assigned);
  await _cbtBox?.put(assigned.id, assigned);
  await _repository.addAssignedCBT(parentId, assigned);

  notifyListeners();
}

  Future<void> unassignCBT(String parentId, String childId, String assignedId) async {
    try {
      await _repository.removeAssignedCBT(parentId, childId, assignedId);
      _assigned.removeWhere((a) => a.id == assignedId);
      await _cbtBox?.delete(assignedId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error unassigning CBT: $e');
    }
  }

  // ===== Getters =====
  List<AssignedCBT> getCurrentWeekAssignments() {
    final week = getCurrentWeekNumber(DateTime.now());
    return _assigned.where((a) => a.weekOfYear == week).toList();
  }

  bool isCompleted(String childId, String exerciseId) {
    final assigned = _assigned.where((a) => a.childId == childId && a.exerciseId == exerciseId).toList();
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
    _assigned.clear();
    _pendingSync.clear();
    _syncBox?.put('pendingSync', _pendingSync);
    notifyListeners();
  }
}
