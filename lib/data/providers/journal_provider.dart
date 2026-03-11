// ignore_for_file: unnecessary_cast

import 'package:com.brightbuds/aquarium/manager/achievement_manager.dart';
import 'package:com.brightbuds/aquarium/notifiers/achievement_notifier.dart';
import 'package:com.brightbuds/data/models/child_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/streak_repository.dart';
import '../services/sync_service.dart';
import 'package:com.brightbuds/utils/network_helper.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class JournalProvider extends ChangeNotifier {
  final JournalRepository _journalRepo = JournalRepository();
  final UserRepository _userRepo = UserRepository();
  final TaskRepository _taskRepo = TaskRepository();
  final StreakRepository _streakRepo = StreakRepository();
  final AchievementNotifier achievementNotifier;
  late final SyncService _syncService;

  /// childId -> list of entries shown in UI
  final Map<String, List<JournalEntry>> _entries = {};

  /// childId -> parentId mapping
  final Map<String, String> _parentForChild = {};

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  StreamSubscription<QuerySnapshot>? _journalSubscription;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  JournalProvider(this.achievementNotifier) {
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
    _startConnectivityListener();
  }

  // ---------------- CONNECTIVITY ----------------
  void _startConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      if (result != ConnectivityResult.none) {
        for (final childId in _entries.keys) {
          final parentId = _parentForChild[childId];
          if (parentId == null || parentId.isEmpty) continue;

          try {
            // Push all local entries for this child
            await _journalRepo.pushPendingLocalChanges(parentId, childId);
            await _syncService.syncAllPendingChanges(childId: childId);
          } catch (e) {}
        }

        notifyListeners();
      }
    });
  }

  // ---------------- LOAD ENTRIES ----------------
  Future<void> loadEntries({
    required String parentId,
    required String childId,
  }) async {
    _isLoading = true;
    _parentForChild[childId] = parentId;
    notifyListeners();

    try {
      // Load merged entries (Hive + Firestore)
      final mergedEntries = await _journalRepo.getMergedEntries(
        parentId,
        childId,
      );
      _entries[childId] = mergedEntries;
      notifyListeners();

      // Cancel previous subscription if any
      await _journalSubscription?.cancel();

      // Start realtime Firestore listener
      _journalSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('journals')
          .orderBy('entryDate', descending: true)
          .snapshots()
          .listen((snapshot) async {
            final List<JournalEntry> remoteEntries = [];
            for (var doc in snapshot.docs) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final entry = JournalEntry.fromMap(data).copyWith(jid: doc.id);
                remoteEntries.add(entry);
                // Always save to Hive locally
                await _journalRepo.saveEntryLocal(entry);
              } catch (e) {}
            }

            _entries[childId] = remoteEntries;

            notifyListeners();
          }, onError: (e) {});
    } catch (e) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------- CRUD ----------------
  Future<void> addEntry(
    String parentId,
    String childId,
    JournalEntry entry,
  ) async {
    // Create a new entry with unique ID and correct childId
    final newEntry = entry.copyWith(
      jid: entry.jid.isNotEmpty ? entry.jid : const Uuid().v4(),
      cid: childId,
      createdAt: DateTime.now(),
    );

    // Track parent for child
    _parentForChild[childId] = parentId;

    // Save locally
    await _journalRepo.saveEntryLocal(newEntry);

    // Update in-memory map
    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, newEntry);

    // ✅ Check achievements by childId (no casting needed)
    await _checkAchievementsById(childId);

    // Notify listeners
    notifyListeners();

    // Push pending changes if online
    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges(parentId, childId);
    }
  }

  // ---------------- ACHIEVEMENTS (childId version) ----------------
  Future<void> _checkAchievementsById(String childId) async {
    ChildUser? child = await _userRepo.fetchChildAndCacheById(childId);
    if (child == null) return;

    final achievementManager = AchievementManager(
      achievementNotifier: achievementNotifier, // ✅ shared instance
      child: child,
    );

    achievementManager.checkAchievements();
  }

  Future<void> updateEntry(
    String parentId,
    String childId,
    JournalEntry updated,
  ) async {
    final updatedEntry = updated.copyWith(createdAt: DateTime.now());
    _parentForChild[childId] = parentId;

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
      await pushPendingChanges(parentId, childId);
    }
  }

  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    _parentForChild[childId] = parentId;

    await _journalRepo.deleteEntryLocal(jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();

    if (await NetworkHelper.isOnline()) {
      await pushPendingChanges(parentId, childId);
    }
  }

  void clearEntries() {
    _entries.clear();
    _parentForChild.clear();
    _journalSubscription?.cancel();
    _journalSubscription = null;
    _isLoading = false;
    notifyListeners();
  }

  List<JournalEntry> getEntries(String childId) => _entries[childId] ?? [];

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
      return [];
    }
  }

  // ---------------- PUSH PENDING ----------------
  Future<void> pushPendingChanges(String parentId, String childId) async {
    try {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
      await _syncService.syncAllPendingChanges(childId: childId);
      notifyListeners();
    } catch (e) {}
  }

  @override
  void dispose() {
    _journalSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
