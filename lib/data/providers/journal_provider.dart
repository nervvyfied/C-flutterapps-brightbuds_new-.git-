import 'dart:async';
import 'package:brightbuds_new/notifications/fcm_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
      // Merge offline + online entries on first load
      final mergedEntries = await _journalRepo.getMergedEntries(
        parentId,
        childId,
      );
      _entries[childId] = mergedEntries;
      notifyListeners();

      // Cancel any old listeners
      await _journalSubscription?.cancel();

      // Firestore listener for real-time updates
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

            if (!listEquals(_entries[childId], remoteEntries)) {
              _entries[childId] = remoteEntries;

              // Persist to Hive
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

  // ---------------- MANUAL FETCH ----------------
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

    // ✅ Always save locally first (offline-first)
    await _journalRepo.saveEntryLocal(newEntry);

    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, newEntry);
    notifyListeners();

    // ✅ Check if online using connectivity_plus
    final isOnline = await NetworkHelper.isOnline();

    if (isOnline) {
      try {
        await _journalRepo.saveEntryRemote(parentId, childId, newEntry);
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
        debugPrint("✅ Synced new journal entry ${newEntry.jid} to Firestore.");
      } catch (e) {
        debugPrint("⚠️ Firestore add failed, will retry when back online: $e");
      }
    } else {
      debugPrint("📴 Offline: journal saved locally (${newEntry.jid}).");

      // ✅ Watch for reconnection and push pending entries
      final connectivity = Connectivity();
      StreamSubscription<ConnectivityResult>? subscription; // declare first

      subscription = connectivity.onConnectivityChanged.listen((result) async {
        if (result != ConnectivityResult.none) {
          debugPrint("🌐 Reconnected — pushing pending journals...");
          await _journalRepo.pushPendingLocalChanges(parentId, childId);
          await _syncService.syncAllPendingChanges(
            parentId: parentId,
            childId: childId,
          );
          await subscription?.cancel(); // stop listening after sync
        }
      });
    }
  }

  // ---------------- UPDATE ENTRY ----------------
  Future<void> updateEntry(
    String parentId,
    String childId,
    JournalEntry updated,
  ) async {
    final updatedEntry = updated.copyWith(createdAt: DateTime.now());

    // ✅ Always save locally first
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

    // ✅ Check connectivity
    final isOnline = await NetworkHelper.isOnline();

    if (isOnline) {
      try {
        await _journalRepo.saveEntryRemote(parentId, childId, updatedEntry);
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
        debugPrint(
          "✅ Journal update synced to Firestore (${updatedEntry.jid})",
        );
      } catch (e) {
        debugPrint("⚠️ Firestore update failed, queued for later sync: $e");
      }
    } else {
      debugPrint(
        "📴 Offline: journal update saved locally (${updatedEntry.jid})",
      );

      // ✅ Listen for reconnection and sync pending updates
      final connectivity = Connectivity();
      StreamSubscription<ConnectivityResult>? subscription;

      subscription = connectivity.onConnectivityChanged.listen((result) async {
        if (result != ConnectivityResult.none) {
          debugPrint("🌐 Reconnected — syncing updated journals...");
          await _journalRepo.pushPendingLocalChanges(parentId, childId);
          await _syncService.syncAllPendingChanges(
            parentId: parentId,
            childId: childId,
          );
          await subscription?.cancel();
        }
      });
    }
  }

  // ---------------- DELETE ENTRY ----------------
  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    // ✅ Mark for local deletion first
    await _journalRepo.deleteEntryLocal(jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();

    // ✅ Check connectivity
    final isOnline = await NetworkHelper.isOnline();

    if (isOnline) {
      try {
        await _journalRepo.deleteEntryRemote(parentId, childId, jid);
        await _syncService.syncAllPendingChanges(
          parentId: parentId,
          childId: childId,
        );
        debugPrint("✅ Journal deleted remotely ($jid)");
      } catch (e) {
        debugPrint("⚠️ Firestore delete failed, will retry later: $e");
      }
    } else {
      debugPrint("📴 Offline: journal marked deleted locally ($jid)");

      // ✅ Watch for reconnection and push pending deletions
      final connectivity = Connectivity();
      StreamSubscription<ConnectivityResult>? subscription;

      subscription = connectivity.onConnectivityChanged.listen((result) async {
        if (result != ConnectivityResult.none) {
          debugPrint("🌐 Reconnected — pushing pending deletions...");
          await _journalRepo.pushPendingLocalChanges(parentId, childId);
          await _syncService.syncAllPendingChanges(
            parentId: parentId,
            childId: childId,
          );
          await subscription?.cancel();
        }
      });
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
