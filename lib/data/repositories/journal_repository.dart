import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/journal_model.dart';

class JournalRepository {
  static const String hiveBoxName = 'journalBox';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final Box<JournalEntry> _journalBox;

  JournalRepository() {
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
    return _journalBox.values.where((e) => e.cid == childId).toList();
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
    // Path: users/{parentId}/children/{childId}/journals
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

  Future<JournalEntry?> getEntryRemote(String parentId, String childId, String jid) async {
    final doc = await _childJournalRef(parentId, childId).doc(jid).get();
    if (doc.exists && doc.data() != null) {
      return JournalEntry.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  Future<List<JournalEntry>> getAllEntriesRemote(String parentId, String childId) async {
    final snapshot = await _childJournalRef(parentId, childId).get();
    return snapshot.docs
        .map((doc) => JournalEntry.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteEntryRemote(String parentId, String childId, String jid) async {
    await _childJournalRef(parentId, childId).doc(jid).delete();
    debugPrint("Journal $jid deleted remotely.");
  }

  // ---------------- SYNC HELPERS ----------------
  Future<void> saveEntry(String parentId, String childId, JournalEntry entry) async {
    if (parentId.isEmpty || childId.isEmpty) {
      throw Exception("Cannot save journal: parentId or childId is empty.");
    }

    final updatedEntry = entry.copyWith(
      jid: entry.jid.isNotEmpty ? entry.jid : const Uuid().v4(),
      cid: childId,
      createdAt: entry.createdAt,
    );

    // Save locally and remotely
    await saveEntryLocal(updatedEntry);
    await saveEntryRemote(parentId, childId, updatedEntry);

    debugPrint("Journal ${updatedEntry.jid} saved locally and remotely under child $childId.");
  }

  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    await deleteEntryLocal(jid);
    await deleteEntryRemote(parentId, childId, jid);
    debugPrint("Journal $jid deleted locally and remotely.");
  }

  Future<void> pullChildEntries(String parentId, String childId) async {
    final remoteEntries = await getAllEntriesRemote(parentId, childId);

    // Clear local entries first
    final existing = getAllEntriesLocal(childId).map((e) => e.jid).toList();
    for (final jid in existing) {
      await deleteEntryLocal(jid);
    }

    // Save remote entries locally
    for (final remote in remoteEntries) {
      await saveEntryLocal(remote);
    }

    debugPrint("Pulled ${remoteEntries.length} journals for child $childId.");
  }

  Future<void> pushPendingLocalChanges(String parentId, String childId) async {
    final localEntries = getAllEntriesLocal(childId);

    for (final entry in localEntries) {
      await saveEntryRemote(parentId, childId, entry);
    }

    debugPrint("Pushed ${localEntries.length} local journals to Firestore under child $childId.");
  }
}
