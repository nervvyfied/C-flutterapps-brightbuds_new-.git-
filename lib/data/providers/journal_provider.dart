import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/streak_repository.dart';
import '../services/sync_service.dart';
import '../models/child_model.dart';
import '../models/parent_model.dart';

class JournalProvider extends ChangeNotifier {
  final JournalRepository _journalRepo = JournalRepository();
  final UserRepository _userRepo = UserRepository();
  // create repos required by SyncService
  final TaskRepository _taskRepo = TaskRepository();
  final StreakRepository _streakRepo = StreakRepository();

  late final SyncService _syncService;

  final Map<String, List<JournalEntry>> _entries = {};
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  JournalProvider() {
    // SyncService requires (UserRepository, TaskRepository, StreakRepository)
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
  }

  // ---------------- LOAD JOURNALS ----------------
  /// Loads journal entries.
  /// If isParent == true: loads entries for all children of the parentId.
  /// If isParent == false: loads entries for the specified childId.
  Future<void> loadEntries({
    String? parentId,
    String? childId,
    bool isParent = false,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (isParent) {
        // parent view: require parentId
        if (parentId == null || parentId.isEmpty) {
          debugPrint("⚠️ loadEntries skipped for parent: parentId is empty");
          _entries.clear();
          return;
        }

        // Get children and for each child: pull and load local entries
        final children = await _userRepo.fetchChildrenAndCache(parentId);
        if (children.isEmpty) {
          _entries.clear();
          return;
        }

        for (final child in children) {
          try {
            // Pull remote entries for this child and cache locally
            await _journalRepo.pullChildEntries(parentId, child.cid);
          } catch (e) {
            // If remote pull fails for a child, continue — we still show local data
            debugPrint("Failed to pull journals for child ${child.cid}: $e");
          }

          // Load local entries for this child
          final allLocal = _journalRepo.getAllEntriesLocal(child.cid);
          _entries[child.cid] = allLocal;
        }
      } else {
        // child view: require parentId & childId
        if (parentId == null ||
            parentId.isEmpty ||
            childId == null ||
            childId.isEmpty) {
          debugPrint(
              "⚠️ loadEntries skipped for child: parentId or childId is empty");
          _entries.clear();
          return;
        }

        // Load local first (instant)
        _entries[childId] = _journalRepo.getAllEntriesLocal(childId);

        // Try to pull remote and then refresh local cache
        try {
          await _journalRepo.pullChildEntries(parentId, childId);
        } catch (e) {
          debugPrint("Failed to pull remote journals for $childId: $e");
        }

        _entries[childId] = _journalRepo.getAllEntriesLocal(childId);
      }
    } catch (e) {
      debugPrint("Error loading journal entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------- CRUD OPERATIONS ----------------
  Future<void> addEntry(
    String parentId,
    String childId,
    JournalEntry entry,
  ) async {
    final newEntry = entry.copyWith(
      jid: entry.jid.isNotEmpty ? entry.jid : const Uuid().v4(),
      cid: childId,
      createdAt: DateTime.now(),
    );

    // Save locally & remotely (saveEntry handles both in your repository)
    await _journalRepo.saveEntry(parentId, childId, newEntry);

    // Try to push pending local changes for this child
    try {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    } catch (e) {
      // if offline, it's fine — changes will remain local
      debugPrint("Push pending journals failed (will retry later): $e");
    }

    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, newEntry);
    notifyListeners();
  }

  Future<void> updateEntry(
    String parentId,
    String childId,
    JournalEntry updatedEntry,
  ) async {
    await _journalRepo.saveEntry(parentId, childId, updatedEntry);

    try {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    } catch (e) {
      debugPrint("Push pending journals failed (will retry later): $e");
    }

    final list = _entries[childId];
    if (list != null) {
      final index = list.indexWhere((e) => e.jid == updatedEntry.jid);
      if (index != -1) list[index] = updatedEntry;
    } else {
      // If not present, ensure it's added to local list
      _entries.putIfAbsent(childId, () => [updatedEntry]);
    }

    notifyListeners();
  }

  Future<void> deleteEntry(
    String parentId,
    String childId,
    String jid,
  ) async {
    await _journalRepo.deleteEntry(parentId, childId, jid);

    try {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    } catch (e) {
      debugPrint("Push pending journals failed after delete: $e");
    }

    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();
  }

  List<JournalEntry> getEntries(String childId) => _entries[childId] ?? [];

  // ---------------- SYNC ----------------
  Future<void> syncOnLogin({
    String? uid,
    String? accessCode,
    required bool isParent,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _syncService.syncOnLogin(uid: uid, accessCode: accessCode, isParent: isParent);

      if (isParent && uid != null) {
        // After syncing, load entries for every child
        final children = await _userRepo.fetchChildrenAndCache(uid);
        for (var child in children) {
          await loadEntries(parentId: uid, childId: child.cid, isParent: false);
        }
      } else if (!isParent && accessCode != null) {
        final result = await _userRepo.fetchParentAndChildByAccessCode(accessCode);
        if (result != null) {
          final parent = result['parent'] as ParentUser?;
          final child = result['child'] as ChildUser?;
          if (parent != null && child != null) {
            await loadEntries(parentId: parent.uid, childId: child.cid, isParent: false);
          }
        }
      }
    } catch (e) {
      debugPrint("Error syncing journal on login: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Manually push pending local changes for a child to Firestore
  Future<void> pushPendingChanges(String parentId, String childId) async {
    try {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    } catch (e) {
      debugPrint("Failed to push pending journal changes: $e");
      rethrow;
    }
    notifyListeners();
  }

  // ---------------- DASHBOARD HELPERS ----------------
  Map<String, int> getMoodStats(String childId) {
    final moods = getEntries(childId).map((e) => e.mood).toList();
    final Map<String, int> counts = {};
    for (var mood in moods) {
      counts[mood] = (counts[mood] ?? 0) + 1;
    }
    return counts;
  }

  String getTopMood(String childId) {
    final stats = getMoodStats(childId);
    if (stats.isEmpty) return "—";
    return stats.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ---------------- WEEKLY MOOD TRENDS ----------------
  Map<String, Map<String, int>> getWeeklyMoodTrends(String childId) {
    final entries = getEntries(childId);
    final Map<String, Map<String, int>> weeklyTrends = {};

    for (var entry in entries) {
      final entryDate = entry.entryDate;
      final weekStart = _getWeekStart(entryDate);

      final weekKey =
          "${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}";

      weeklyTrends.putIfAbsent(weekKey, () => {});
      weeklyTrends[weekKey]![entry.mood] =
          (weeklyTrends[weekKey]![entry.mood] ?? 0) + 1;
    }

    return weeklyTrends;
  }

  DateTime _getWeekStart(DateTime entryDate) {
    return entryDate.subtract(Duration(days: entryDate.weekday - 1));
  }
}

// ---------------- EXTENSION: QUICK STATS ----------------
extension JournalStats on JournalProvider {
  int get totalEntries => _entries.values.expand((list) => list).length;

  int moodCount(String childId, String mood) =>
      getEntries(childId).where((e) => e.mood == mood).length;
}
