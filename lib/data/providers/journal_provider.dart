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

  JournalProvider() {
    _syncService = SyncService(_userRepo, _taskRepo, _streakRepo);
  }

  // ---------------- LOAD ENTRIES ----------------
  Future<void> loadEntries({String? parentId, String? childId}) async {
    if (parentId == null || childId == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final merged = await _journalRepo.getMergedEntries(parentId, childId);
      _entries[childId] = merged;
    } catch (e) {
      debugPrint("Error loading entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<JournalEntry>> getMergedEntries({
    required String parentId,
    required String childId,
  }) async {
    final merged = await _journalRepo.getMergedEntries(parentId, childId);
    _entries[childId] = merged;
    notifyListeners();
    return merged;
  }

  // ---------------- CRUD ----------------
Future<void> addEntry(String parentId, String childId, JournalEntry entry) async {
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

  try {
    // Fetch parent FCM token
    final parentSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .get();
    final parentToken = parentSnapshot.data()?['fcmToken'];

    // Fetch child name via childId
    final childSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .get();
    final childName = childSnapshot.data()?['name'] ?? 'Your child';
    final mood = newEntry.mood ?? 'unknown';

    if (parentToken != null) {
      await FCMService.sendNotification(
        title: '📔 New Journal Entry',
        body: '$childName just added a new journal entry. Mood: $mood',
        token: parentToken,
        data: {
          'type': 'journal_added',
          'childName': childName,
          'mood': mood,
        },
      );
    }
  } catch (e) {
    debugPrint('⚠️ Failed to send journal notification: $e');
  }

  notifyListeners();

  // Save remotely if online
  if (await NetworkHelper.isOnline()) {
    try {
      await _journalRepo.saveEntryRemote(parentId, childId, newEntry);
    } catch (e) {
      debugPrint("⚠️ Firestore add failed: $e");
    }
  }
}


  Future<void> updateEntry(String parentId, String childId, JournalEntry updated) async {
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
        debugPrint("Firestore update failed: $e");
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
        debugPrint("Firestore delete failed: $e");
      }
    }
  }

  List<JournalEntry> getEntries(String childId) => _entries[childId] ?? [];

  Future<void> pushPendingChanges(String parentId, String childId) async {
    await _journalRepo.pushPendingLocalChanges(parentId, childId);
    notifyListeners();
  }
}
