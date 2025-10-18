import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/journal_model.dart';
import 'dart:io';

class JournalRepository {
  static const String hiveBoxName = 'journalBox';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final Box<JournalEntry> _journalBox;

  JournalRepository() {
    // Ensure Hive box is already opened before using this repository
    if (!Hive.isBoxOpen(hiveBoxName)) {
      throw Exception("Hive box '$hiveBoxName' is not open. Open it before using JournalRepository.");
    }
    _journalBox = Hive.box<JournalEntry>(hiveBoxName);
  }

  // ---------------- HIVE (LOCAL) ----------------
  Future<void> saveEntryLocal(JournalEntry entry) async {
    try {
      await _journalBox.put(entry.jid, entry);
      debugPrint("Journal ${entry.jid} saved locally.");
    } catch (e) {
      debugPrint("Error saving journal locally: $e");
      rethrow;
    }
  }

  JournalEntry? getEntryLocal(String jid) => _journalBox.get(jid);

  List<JournalEntry> getAllEntriesLocal(String childId) {
    final entries = _journalBox.values.where((e) => e.cid == childId).toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));

    debugPrint("Fetched ${entries.length} local entries for child $childId");
    return entries;
  }

  Future<void> deleteEntryLocal(String jid) async {
    await _journalBox.delete(jid);
    debugPrint("Journal $jid deleted locally.");
  }

  // ---------------- FIRESTORE (REMOTE) ----------------
  CollectionReference _childJournalRef(String parentId, String childId) {
    if (parentId.isEmpty || childId.isEmpty) {
      throw ArgumentError("parentId and childId must not be empty");
    }
    return _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('journals');
  }

  Future<void> saveEntryRemote(String parentId, String childId, JournalEntry entry) async {
    await _childJournalRef(parentId, childId)
        .doc(entry.jid)
        .set(entry.toMap(), SetOptions(merge: true));
    debugPrint("Journal ${entry.jid} saved remotely under child $childId.");
  }

  Future<List<JournalEntry>> getAllEntriesRemote(String parentId, String childId) async {
    try {
      final snapshot = await _childJournalRef(parentId, childId).get();
      final remoteEntries = snapshot.docs
          .map((doc) => JournalEntry.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      debugPrint("Fetched ${remoteEntries.length} remote entries for child $childId");
      return remoteEntries;
    } catch (e) {
      debugPrint("Error fetching remote entries: $e");
      return [];
    }
  }

  Future<void> deleteEntryRemote(String parentId, String childId, String jid) async {
    await _childJournalRef(parentId, childId).doc(jid).delete();
    debugPrint("Journal $jid deleted remotely.");
  }

  // ---------------- OFFLINE-FIRST SYNC ----------------
  Future<bool> _hasConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------------- MERGE LOCAL + REMOTE ----------------
  Future<List<JournalEntry>> getMergedEntries(String parentId, String childId) async {
    final localEntries = getAllEntriesLocal(childId);

    bool online = await _hasConnection();
    List<JournalEntry> remoteEntries = [];

    if (online) {
      try {
        remoteEntries = await getAllEntriesRemote(parentId, childId);

        // Merge: remote overwrites local if same jid
        final Map<String, JournalEntry> mergedMap = {};
        for (var e in [...localEntries, ...remoteEntries]) {
          mergedMap[e.jid] = e;
        }

        final mergedList = mergedMap.values.toList()
          ..sort((a, b) => b.entryDate.compareTo(a.entryDate));

        // Persist merged entries to Hive
        for (var e in mergedList) {
          await _journalBox.put(e.jid, e);
        }

        debugPrint(
            "✅ Merged ${mergedList.length} entries for child $childId (Local: ${localEntries.length}, Remote: ${remoteEntries.length}, Online: $online)");
        return mergedList;
      } catch (e) {
        debugPrint("Error merging remote entries: $e");
        return localEntries;
      }
    }

    debugPrint(
        "Offline: returning local entries (${localEntries.length}) for child $childId");
    return localEntries;
  }

  Future<void> pushPendingLocalChanges(String parentId, String childId) async {
    if (!await _hasConnection()) {
      debugPrint("Offline: skipping push of local changes.");
      return;
    }

    final localEntries = getAllEntriesLocal(childId);
    for (final entry in localEntries) {
      await saveEntryRemote(parentId, childId, entry);
    }
    debugPrint(
        "Pushed ${localEntries.length} local journals to Firestore for child $childId.");
  }
}
