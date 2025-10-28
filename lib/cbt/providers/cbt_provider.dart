import 'dart:async';

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
  StreamSubscription<QuerySnapshot>? _assignedCBTListener;

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

  // ===== Real-time updates =====
  void startRealtimeCBTUpdates(String parentId, String childId) {
    // Cancel previous listener if exists
    _assignedCBTListener?.cancel();

    _assignedCBTListener = FirebaseFirestore.instance
        .collection('parents')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('CBT')
        .snapshots()
        .listen((snapshot) async {
          bool hasChanges = false;

          for (var docChange in snapshot.docChanges) {
            final data = docChange.doc.data();
            if (data == null) continue;

            final assigned = AssignedCBT.fromMap(data);
            switch (docChange.type) {
              case DocumentChangeType.added:
                if (!_assigned.any((a) => a.id == assigned.id)) {
                  _assigned.add(assigned);
                  await _cbtBox?.put(assigned.id, assigned);
                  hasChanges = true;
                }
                break;
              case DocumentChangeType.modified:
                final index = _assigned.indexWhere((a) => a.id == assigned.id);
                if (index != -1) {
                  final local = _assigned[index];
                  // Preserve local completion if newer
                  if (local.lastCompleted != null &&
                      (assigned.lastCompleted == null ||
                          local.lastCompleted!.isAfter(
                            assigned.lastCompleted!,
                          ))) {
                    assigned.completed = local.completed;
                    assigned.lastCompleted = local.lastCompleted;
                  }
                  _assigned[index] = assigned;
                  await _cbtBox?.put(assigned.id, assigned);
                  hasChanges = true;
                }
                break;
              case DocumentChangeType.removed:
                _assigned.removeWhere((a) => a.id == assigned.id);
                await _cbtBox?.delete(assigned.id);
                hasChanges = true;
                break;
            }
          }

          if (hasChanges) {
            notifyListeners();
          }
        });
  }

  Future<void> listenToAssignedCBTForChild(
    String parentId,
    String childId,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('cbt_exercises')
        .where('parentId', isEqualTo: parentId)
        .where('childId', isEqualTo: childId);

    _assignedCBTListener?.cancel(); // cancel previous listener

    _assignedCBTListener = ref.snapshots().listen((snapshot) {
      _assigned = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return AssignedCBT.fromMap(data);
      }).toList();

      notifyListeners();
    });
  }

  // ===== Update listener for active child =====
  void updateRealtimeListenerForChild(String parentId, String childId) {
    if (childId.isEmpty) return;
    startRealtimeCBTUpdates(parentId, childId);
    loadLocalCBT(parentId, childId); // merge local CBTs immediately
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
    final localCBTs = _cbtBox!.values
        .where((a) => a.childId == childId)
        .toList();

    // Merge instead of replace
    final existingMap = {for (var a in _assigned) a.id: a};
    for (var a in localCBTs) {
      existingMap[a.id] = a;
    }
    _assigned = existingMap.values.toList();

    // Deduplicate by exerciseId + childId + weekOfYear
    final Map<String, AssignedCBT> dedupedMap = {};
    for (var a in _assigned) {
      final key = '${a.exerciseId}_${a.childId}_${a.weekOfYear}';
      if (!dedupedMap.containsKey(key)) {
        dedupedMap[key] = a;
      }
    }
    _assigned = dedupedMap.values.toList();

    await normalizeAssignedStatusesAndCleanup(parentId, childId);
    notifyListeners();
  }

  // ===== Load Remote CBT =====
  Future<void> loadRemoteCBT(String parentId, String childId) async {
    await _repository.syncFromFirestore(parentId, childId);
    final remote = _repository.getLocalCBTs(childId);

    // Merge with existing assignments instead of replacing
    final Map<String, AssignedCBT> merged = {for (var a in _assigned) a.id: a};
    for (var r in remote) {
      if (merged.containsKey(r.id)) {
        final local = merged[r.id]!;
        // Preserve local completion if newer
        if (local.lastCompleted != null &&
            (r.lastCompleted == null ||
                local.lastCompleted!.isAfter(r.lastCompleted!))) {
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
  Future<void> normalizeAssignedStatusesAndCleanup(
    String parentId,
    String childId,
  ) async {
    final now = DateTime.now();
    final currentWeek = getCurrentWeekNumber(now);
    final List<String> toUnassign = [];

    for (var a in _assigned) {
      if (a.recurrence == 'daily') {
        if (a.lastCompleted != null &&
            _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false;
        }
      } else if (a.recurrence == 'weekly') {
        if (a.weekOfYear < currentWeek) {
          toUnassign.add(a.id);
          continue;
        }
        if (a.lastCompleted != null &&
            getCurrentWeekNumber(a.lastCompleted!) == currentWeek) {
          a.completed = true;
        } else {
          a.completed = false;
        }
      } else {
        if (a.lastCompleted != null &&
            _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
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
  Future<bool> markAsCompleted(
    String parentId,
    String childId,
    String cbtAssignedId,
  ) async {
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
          await _repository.updateCompletion(
            parentId,
            assigned.childId,
            assigned.id,
          );
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
  Future<void> assignManualCBT(
    String parentId,
    String childId,
    CBTExercise exercise,
  ) async {
    final weekOfYear = getCurrentWeekNumber(DateTime.now());

    // Prevent duplicates by stable key
    final alreadyAssigned = _assigned.any(
      (a) =>
          a.exerciseId == exercise.id &&
          a.childId == childId &&
          a.weekOfYear == weekOfYear,
    );

    if (alreadyAssigned) return; // <-- now truly prevents duplicates

    // Use a stable ID or Hive key
    final assigned = AssignedCBT.fromExercise(
      id: UniqueKey().toString(), // stable unique ID
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

  Future<void> unassignCBT(
    String parentId,
    String childId,
    String assignedId,
  ) async {
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
  List<AssignedCBT> getCurrentWeekAssignments({String? childId}) {
    final week = getCurrentWeekNumber(DateTime.now());
    var weekAssignments = _assigned.where((a) => a.weekOfYear == week);

    if (childId != null) {
      weekAssignments = weekAssignments.where((a) => a.childId == childId);
    }

    final Map<String, AssignedCBT> dedupedMap = {};
    for (var a in weekAssignments) {
      final key = '${a.exerciseId}_${a.childId}_${a.weekOfYear}';
      if (!dedupedMap.containsKey(key)) dedupedMap[key] = a;
    }
    return dedupedMap.values.toList();
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
    _assigned.clear();
    _pendingSync.clear();
    _syncBox?.put('pendingSync', _pendingSync);
    notifyListeners();
  }
}
