import 'dart:async';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:brightbuds_new/cbt/models/cbt_exercise_model.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import '../models/assigned_cbt_model.dart';
import '../repositories/cbt_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CBTProvider with ChangeNotifier {
  final CBTRepository _repository = CBTRepository();

  List<AssignedCBT> _assigned = [];
  List<AssignedCBT> get assigned => _assigned;

  List<String> _pendingSync = [];
  Box<AssignedCBT>? _cbtBox;
  Box<List<String>>? _syncBox;
  StreamSubscription<QuerySnapshot>? _assignedCBTListener;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  String? _lastParentId;
  String? _lastChildId;

  // ===== Hive Initialization =====
  Future<void> initHive() async {
    if (_cbtBox == null || !_cbtBox!.isOpen) {
      _cbtBox = Hive.isBoxOpen('cbtBox')
          ? Hive.box<AssignedCBT>('cbtBox')
          : await Hive.openBox<AssignedCBT>('cbtBox');
    }
    if (_syncBox == null || !_syncBox!.isOpen) {
      _syncBox = Hive.isBoxOpen('cbtSyncBox')
          ? Hive.box<List<String>>('cbtSyncBox')
          : await Hive.openBox<List<String>>('cbtSyncBox');
    }
    _pendingSync =
        _syncBox?.get('pendingSync', defaultValue: [])?.cast<String>() ?? [];
  }

  Future<void> init({String? parentId, String? childId}) async {
    _lastParentId = parentId ?? _lastParentId;
    _lastChildId = childId ?? _lastChildId;
    await initHive();
    _startConnectivityListenerIfNeeded();
    if (_lastChildId != null) {
      await loadLocalCBT(_lastChildId!);
    }
  }

  // ===== Helper to find parent ID for a child =====
  Future<String?> _findParentIdForChild(String childId) async {
    try {
      // Try to find which parent owns this child
      // First check in the children collection
      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(childId)
          .get();

      if (childDoc.exists && childDoc.data()?['parentId'] != null) {
        return childDoc.data()!['parentId'] as String;
      }

      // If not found, try collectionGroup query
      final querySnapshot = await FirebaseFirestore.instance
          .collectionGroup('children')
          .where('id', isEqualTo: childId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final path = querySnapshot.docs.first.reference.path;
        final parts = path.split('/');
        if (parts.length >= 2 && parts[0] == 'users') {
          return parts[1];
        }
      }
    } catch (e) {
      debugPrint('Error finding parent for child $childId: $e');
    }
    return null;
  }

  // ===== Realtime Listener =====
  void startRealtimeCBTUpdates(String parentId, String childId) {
    _lastParentId = parentId;
    _lastChildId = childId;
    _assignedCBTListener?.cancel();

    _assignedCBTListener = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('CBT')
        .snapshots()
        .listen(
          (snapshot) async {
            await initHive();
            bool hasChanges = false;

            for (final docChange in snapshot.docChanges) {
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
                  final idx = _assigned.indexWhere((a) => a.id == assigned.id);
                  if (idx != -1) {
                    _assigned[idx] = assigned;
                    await _cbtBox?.put(assigned.id, assigned);
                    hasChanges = true;
                  } else {
                    _assigned.add(assigned);
                    await _cbtBox?.put(assigned.id, assigned);
                    hasChanges = true;
                  }
                  break;
                case DocumentChangeType.removed:
                  final existed = _assigned.any((a) => a.id == assigned.id);
                  _assigned.removeWhere((a) => a.id == assigned.id);
                  if (existed) {
                    await _cbtBox?.delete(assigned.id);
                    hasChanges = true;
                  }
                  break;
              }
            }

            if (hasChanges) {
              final localCBTs = _cbtBox!.values
                  .where(
                    (a) =>
                        a.childId == childId &&
                        !_assigned.any((e) => e.id == a.id),
                  )
                  .toList();
              if (localCBTs.isNotEmpty) {
                _assigned.addAll(localCBTs);
              }
              await normalizeAssignedStatusesAndCleanup();
              notifyListeners();
            }
          },
          onError: (e) {
            debugPrint('CBTProvider: realtime listener error: $e');
          },
        );
  }

  // ===== Merge local Hive CBTs =====
  Future<void> _mergeLocalCBTs(String childId) async {
    if (_cbtBox == null) return;
    final localCBTs = _cbtBox!.values
        .where((a) => a.childId == childId)
        .toList();
    final Map<String, AssignedCBT> merged = {for (var a in _assigned) a.id: a};
    for (var a in localCBTs) {
      merged[a.id] = a;
    }
    _assigned = merged.values.toList();
  }

  // ===== Load Local CBT =====
  Future<void> loadLocalCBT(String childId) async {
    await initHive();
    await _mergeLocalCBTs(childId);
    await normalizeAssignedStatusesAndCleanup();
    notifyListeners();
  }

  // ===== Load Remote CBT =====
  Future<void> loadRemoteCBT(String parentId, String childId) async {
    _lastParentId = parentId;
    _lastChildId = childId;
    await initHive();
    await _repository.syncFromFirestore(parentId, childId);
    final remote = _repository.getLocalCBTs(childId);

    final Map<String, AssignedCBT> merged = {for (var a in _assigned) a.id: a};
    for (var r in remote) {
      if (merged.containsKey(r.id)) {
        final local = merged[r.id]!;
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
    for (var a in _assigned) {
      await _cbtBox?.put(a.id, a);
    }

    await normalizeAssignedStatusesAndCleanup();
    notifyListeners();
  }

  // In CBTProvider class, add this helper method:
  Future<String> _findRealParentId(String childId) async {
    try {
      debugPrint('🔍 Looking for REAL parent of child: $childId');

      // METHOD 1: Search through ALL users to find which parent has this child
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      for (final userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final userRole = userData['role'] as String?;

        // Only check users who are parents
        if (userRole == 'parent') {
          final childRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .collection('children')
              .doc(childId);

          final childSnap = await childRef.get();
          if (childSnap.exists) {
            debugPrint(
              '✅ Found REAL parent: ${userDoc.id} for child: $childId',
            );
            return userDoc.id; // This is the ACTUAL parent ID
          }
        }
      }

      // METHOD 2: If the above doesn't work, check if there's a direct reference somewhere
      debugPrint(
        '⚠️ Could not find parent in users collection, trying alternative...',
      );

      // Check if child has a parentId reference in some other collection
      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(childId)
          .get();

      if (childDoc.exists && childDoc.data()?['parentId'] != null) {
        final parentId = childDoc.data()!['parentId'] as String;
        debugPrint('✅ Found parentId in children collection: $parentId');
        return parentId;
      }

      debugPrint('❌ Could not find any parent for child: $childId');
      return ''; // Couldn't find parent
    } catch (e) {
      debugPrint('Error finding REAL parent for child $childId: $e');
      return '';
    }
  }

  Future<void> assignManualCBT(
    String therapistId,
    String childId,
    CBTExercise exercise, {
    String? overrideParentId,
  }) async {
    await initHive();

    String parentId;

    // Use overrideParentId if provided
    if (overrideParentId != null && overrideParentId.isNotEmpty) {
      parentId = overrideParentId;
      print('✅ Using provided parentId: $parentId');
    } else {
      // Try to find it (fallback)
      parentId = await _findRealParentId(childId);
      if (parentId.isEmpty) {
        throw Exception('No parent found for child');
      }
    }

    // CRITICAL CHECK
    if (parentId == therapistId) {
      throw Exception('❌ FATAL: Parent ID equals Therapist ID!');
    }

    print('🎯 FINAL: Using parentId: $parentId');
    print('🎯 TherapistId: $therapistId (should be different!)');

    final weekOfYear = getCurrentWeekNumber(DateTime.now());
    if (_assigned.any(
      (a) =>
          a.exerciseId == exercise.id &&
          a.childId == childId &&
          a.weekOfYear == weekOfYear,
    )) {
      return;
    }

    final assigned = AssignedCBT.fromExercise(
      id: UniqueKey().toString(),
      exercise: exercise,
      childId: childId,
      assignedDate: DateTime.now(),
      weekOfYear: weekOfYear,
      assignedBy: therapistId,
      source: "therapist_assigned",
    );

    _assigned.add(assigned);
    await _cbtBox?.put(assigned.id, assigned);

    try {
      // 🔥 THIS IS THE KEY LINE - USE parentId, NOT therapistId
      await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId) // <-- PARENT ID HERE
          .collection('children')
          .doc(childId)
          .collection('CBT')
          .doc(assigned.id)
          .set(assigned.toMap());

      print('✅ CBT stored in parent $parentId collection');
    } catch (e) {
      print('❌ Firestore error: $e');
      // Check the actual error
      if (e.toString().contains('permission-denied')) {
        print(
          '🚨 PERMISSION ERROR: Cannot write to parent $parentId collection',
        );
      }
      rethrow;
    }

    await loadLocalCBT(childId);
    notifyListeners();
  }

  Future<void> unassignCBT(
    String therapistId,
    String childId,
    String assignedId, {
    String? overrideParentId,
  }) async {
    try {
      String parentId;

      // Use overrideParentId if provided
      if (overrideParentId != null && overrideParentId.isNotEmpty) {
        parentId = overrideParentId;
        print('✅ Using provided parentId for unassign: $parentId');
      } else {
        // Use the EXACT SAME method as assignManualCBT
        parentId = await _findRealParentId(childId);
        if (parentId.isEmpty) {
          throw Exception('Cannot find parent for this child');
        }
      }

      // DEBUG: Show what IDs we have
      print('🔍 Unassign CBT Debug:');
      print('   Therapist ID: $therapistId');
      print('   Parent ID to use: $parentId');
      print('   Child ID: $childId');
      print('   Assigned ID: $assignedId');

      // Check if parentId equals therapistId (shouldn't happen if _findRealParentId works)
      if (parentId == therapistId) {
        print('🚨 ERROR: parentId ($parentId) equals therapistId!');
        print('🚨 This means _findRealParentId returned therapist ID');
        throw Exception('❌ Cannot unassign: parentId equals therapistId');
      }

      print(
        '🗑️ Removing CBT from path: users/$parentId/children/$childId/CBT/$assignedId',
      );

      // Remove from PARENT'S collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('CBT')
          .doc(assignedId)
          .delete();

      // Also remove locally
      _assigned.removeWhere((a) => a.id == assignedId);
      await _cbtBox?.delete(assignedId);
      notifyListeners();

      print('✅ Successfully removed from parent $parentId');
    } catch (e) {
      debugPrint('Error unassigning CBT: $e');
      rethrow;
    }
  }

  // ===== Load CBT for therapist view =====
  Future<void> loadCBTForTherapistView(String childId) async {
    await initHive();

    // Find the parent ID for this child
    final parentId = await _findParentIdForChild(childId);

    if (parentId == null) {
      debugPrint('⚠️ Could not find parent for child $childId');
      return;
    }

    // Load from parent's collection using existing method
    await loadRemoteCBT(parentId, childId);
  }

  // ===== Completion =====
  Future<bool> markAsCompleted(
    String parentId,
    String childId,
    String cbtAssignedId,
  ) async {
    await initHive();
    AssignedCBT? assigned;
    try {
      assigned = _assigned.firstWhere((c) => c.id == cbtAssignedId);
    } catch (_) {
      assigned = null;
    }

    if (assigned == null || !canExecute(assigned)) return false;

    assigned.completed = true;
    assigned.lastCompleted = DateTime.now();
    await _cbtBox?.put(assigned.id, assigned);

    if (!_pendingSync.contains(assigned.id)) {
      _pendingSync.add(assigned.id);
      await _syncBox?.put('pendingSync', _pendingSync);
    }

    notifyListeners();

    await syncPendingCompletions(parentId, childId);
    return true;
  }

  Future<void> syncPendingCompletions(String parentId, String childId) async {
    if (_pendingSync.isEmpty) {
      debugPrint('🟢 No pending CBTs to sync.');
      return;
    }

    if (!await NetworkHelper.isOnline()) {
      debugPrint('⛔ Offline - skipping sync.');
      return;
    }

    _syncBox ??= await Hive.openBox('cbtSync');
    await loadLocalCBT(childId);

    debugPrint('🔁 Syncing ${_pendingSync.length} pending CBT completions...');

    for (final id in List<String>.from(_pendingSync)) {
      AssignedCBT? assigned =
          _assigned.firstWhereOrNull((c) => c.id == id) ?? _cbtBox?.get(id);

      if (assigned == null) {
        debugPrint('⚠️ CBT $id not found locally. Removing from pending list.');
        _pendingSync.remove(id);
        await _syncBox!.put('pendingSync', _pendingSync.toList());
        continue;
      }

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('CBT')
          .doc(id);

      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        debugPrint('🆕 Creating missing CBT ${assigned.id} before update...');
        await docRef.set(assigned.toMap());
      }

      await _repository.updateCompletion(parentId, childId, assigned.id);

      _pendingSync.remove(id);
      await _syncBox!.put('pendingSync', _pendingSync.toList());
      debugPrint('✅ Synced CBT ${assigned.id}');
    }
  }

  // ===== Helper Methods =====
  void _startConnectivityListenerIfNeeded() {
    if (_connectivitySub != null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      if (result != ConnectivityResult.none) {
        if (_lastParentId != null && _lastChildId != null) {
          debugPrint('CBTProvider: connectivity regained → sync pending.');
          await syncPendingCompletions(_lastParentId!, _lastChildId!);
        }
      }
    });
  }

  Future<void> normalizeAssignedStatusesAndCleanup() async {
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
        a.completed =
            (a.lastCompleted != null &&
            getCurrentWeekNumber(a.lastCompleted!) == currentWeek);
      } else {
        if (a.lastCompleted != null &&
            _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now))) {
          a.completed = false;
        }
      }
    }

    for (final id in toUnassign) {
      _assigned.removeWhere((a) => a.id == id);
      await _cbtBox?.delete(id);
    }
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
      return getCurrentWeekNumber(a.lastCompleted!) !=
          getCurrentWeekNumber(now);
    }
    return _startOfDay(a.lastCompleted!).isBefore(_startOfDay(now));
  }

  bool isCompleted(String childId, String exerciseId) {
    final found = _assigned
        .where((a) => a.childId == childId && a.exerciseId == exerciseId)
        .toList();
    return found.isNotEmpty ? found.first.completed : false;
  }

  List<AssignedCBT> getCurrentWeekAssignments({String? childId}) {
    final week = getCurrentWeekNumber(DateTime.now());
    var weekAssignments = _assigned.where((a) => a.weekOfYear == week);
    if (childId != null) {
      weekAssignments = weekAssignments.where((a) => a.childId == childId);
    }
    final Map<String, AssignedCBT> deduped = {};
    for (var a in weekAssignments) {
      final key = '${a.exerciseId}_${a.childId}_${a.weekOfYear}';
      if (!deduped.containsKey(key)) deduped[key] = a;
    }
    return deduped.values.toList();
  }

  // ===== Clear =====
  Future<void> clear() async {
    _assigned.clear();
    _pendingSync.clear();
    await _cbtBox?.clear();
    await _syncBox?.put('pendingSync', _pendingSync);
    notifyListeners();
  }

  @override
  void dispose() {
    _assignedCBTListener?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
