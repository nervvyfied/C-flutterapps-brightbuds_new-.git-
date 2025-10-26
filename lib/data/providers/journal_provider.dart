import 'dart:async';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/streak_repository.dart';
import '../services/sync_service.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

class JournalProvider extends ChangeNotifier {
  final JournalRepository _journalRepo = JournalRepository();
  final UserRepository _userRepo = UserRepository();
  final TaskRepository _taskRepo = TaskRepository();
  final StreakRepository _streakRepo = StreakRepository();
  late final SyncService _syncService;

  final Map<String, List<JournalEntry>> _entries = {};
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  StreamSubscription<QuerySnapshot>? _journalSubscription;

  JournalProvider() {
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
  }

  // ---------------- LOAD ENTRIES (REAL-TIME) ----------------
  Future<void> loadEntries({
    required String parentId,
    required String childId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Merge offline + online on first load
      final mergedEntries = await _journalRepo.getMergedEntries(
        parentId,
        childId,
      );
      _entries[childId] = mergedEntries;
      notifyListeners();

      // Cancel any old listeners
      await _journalSubscription?.cancel();

      // Attach Firestore listener for real-time changes
      _journalSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('journals')
          .orderBy('entryDate', descending: true)
          .snapshots()
          .listen((snapshot) async {
            final remoteEntries = snapshot.docs
                .map(
                  (doc) =>
                      JournalEntry.fromMap(doc.data() as Map<String, dynamic>),
                )
                .toList();

            // Only update if different
            if (!listEquals(_entries[childId], remoteEntries)) {
              _entries[childId] = remoteEntries;

              // Persist to Hive for offline sync
              for (var entry in remoteEntries) {
                await _journalRepo.saveEntryLocal(entry);
              }

              debugPrint(
                "📡 Realtime sync: ${remoteEntries.length} journal entries",
              );
              notifyListeners();
            }
          });
    } catch (e) {
      debugPrint("❌ Error loading entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------- MANUAL FETCH (LEGACY FALLBACK) ----------------
  Future<List<JournalEntry>> getMergedEntries({
    required String parentId,
    required String childId,
  }) async {
    try {
      final merged = await _journalRepo.getMergedEntries(parentId, childId);
      _entries[childId] = merged;
      notifyListeners();
      return merged;
    } catch (e) {
      debugPrint("⚠️ Error fetching merged journal entries: $e");
      return [];
    }
  }

  // ---------------- ADD ENTRY ----------------
  Future<void> addEntry(
    String parentId,
    String childId,
    JournalEntry entry,
  ) async {
    final newEntry = entry.copyWith(
      jid: entry.jid.isNotEmpty ? entry.jid : const Uuid().v4(),
      cid: childId,
      entryDate: entry.entryDate,
      createdAt: DateTime.now(),
    );

    // Save locally first
    await _journalRepo.saveEntryLocal(newEntry);

    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, newEntry);
    notifyListeners();

    // Save remotely if online
    if (await NetworkHelper.isOnline()) {
      try {
        await _journalRepo.saveEntryRemote(parentId, childId, newEntry);
        // Use your sync service’s global sync
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
      } catch (e) {
        debugPrint("⚠️ Firestore add failed: $e");
      }
    }
  }

  // ---------------- UPDATE ENTRY ----------------
  Future<void> updateEntry(
    String parentId,
    String childId,
    JournalEntry updated,
  ) async {
    final updatedEntry = updated.copyWith(createdAt: DateTime.now());
    await _journalRepo.saveEntryLocal(updatedEntry);

    _entries.putIfAbsent(childId, () => []);
    final list = _entries[childId]!;
    final idx = list.indexWhere((e) => e.jid == updatedEntry.jid);
    if (idx != -1) {
      list[idx] = updatedEntry;
    } else {
      list.insert(0, updatedEntry);
    }
    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      try {
        await _journalRepo.saveEntryRemote(parentId, childId, updatedEntry);
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
      } catch (e) {
        debugPrint("⚠️ Firestore update failed: $e");
      }
    }
  }

  // ---------------- DELETE ENTRY ----------------
  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    await _journalRepo.deleteEntryLocal(jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      try {
        await _journalRepo.deleteEntryRemote(parentId, childId, jid);
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
      } catch (e) {
        debugPrint("⚠️ Firestore delete failed: $e");
      }
    }
  }

  // ---------------- UTILITIES ----------------
  List<JournalEntry> getEntries(String childId) => _entries[childId] ?? [];

  Future<void> pushPendingChanges(String parentId, String childId) async {
    await _journalRepo.pushPendingLocalChanges(parentId, childId);
    await _syncService.syncAllPendingChanges(
      parentId: parentId,
      childId: childId,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _journalSubscription?.cancel();
    super.dispose();
  }
}
