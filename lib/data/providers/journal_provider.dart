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
import '../models/child_model.dart';
import '../models/parent_model.dart';
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
      // Get initial merged data (local + remote)
      final mergedEntries = await _journalRepo.getMergedEntries(
        parentId,
        childId,
      );
      _entries[childId] = mergedEntries;
      notifyListeners();

      // Cancel old listener if any
      await _journalSubscription?.cancel();

      // Attach Firestore listener for real-time updates
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

            _entries[childId] = remoteEntries;
            notifyListeners();

            // Sync with Hive for offline persistence
            for (var entry in remoteEntries) {
              await _journalRepo.saveEntryLocal(entry);
            }

            debugPrint(
              "📡 Realtime update: ${remoteEntries.length} journal entries synced.",
            );
          });
    } catch (e) {
      debugPrint("❌ Error loading entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------- LEGACY MERGED FETCH (NON-REALTIME) ----------------
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
      debugPrint("Error fetching merged journal entries: $e");
      return [];
    }
  }

  // ---------------- CRUD ----------------
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

    // Save locally
    await _journalRepo.saveEntryLocal(newEntry);

    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, newEntry);
    notifyListeners();

    // Save remotely
    if (await NetworkHelper.isOnline()) {
      try {
        await _journalRepo.saveEntryRemote(parentId, childId, newEntry);
      } catch (e) {
        debugPrint("⚠️ Firestore add failed: $e");
      }
    }
  }

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
      } catch (e) {
        debugPrint("⚠️ Firestore update failed: $e");
      }
    }
  }

  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    await _journalRepo.deleteEntryLocal(jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      try {
        await _journalRepo.deleteEntryRemote(parentId, childId, jid);
      } catch (e) {
        debugPrint("⚠️ Firestore delete failed: $e");
      }
    }
  }

  // ---------------- UTILITIES ----------------
  List<JournalEntry> getEntries(String childId) => _entries[childId] ?? [];

  Future<void> pushPendingChanges(String parentId, String childId) async {
    await _journalRepo.pushPendingLocalChanges(parentId, childId);
    notifyListeners();
  }

  @override
  void dispose() {
    _journalSubscription?.cancel();
    super.dispose();
  }
}
