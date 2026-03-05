import 'package:cloud_firestore/cloud_firestore.dart';
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
      throw Exception(
        "Hive box '$hiveBoxName' is not open. Open it before using JournalRepository.",
      );
    }
    _journalBox = Hive.box<JournalEntry>(hiveBoxName);
  }

  // ---------------- HIVE (LOCAL) ----------------
  Future<void> saveEntryLocal(JournalEntry entry) async {
    try {
      await _journalBox.put(entry.jid, entry);
    
    } catch (e) {
    
      rethrow;
    }
  }

  JournalEntry? getEntryLocal(String jid) => _journalBox.get(jid);

  List<JournalEntry> getAllEntriesLocal(String childId) {
    final entries = _journalBox.values.where((e) => e.cid == childId).toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));

   
    return entries;
  }

  Future<void> deleteEntryLocal(String jid) async {
    await _journalBox.delete(jid);
  
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

  Future<void> saveEntryRemote(
    String parentId,
    String childId,
    JournalEntry entry,
  ) async {
    await _childJournalRef(
      parentId,
      childId,
    ).doc(entry.jid).set(entry.toMap(), SetOptions(merge: true));
  
  }

  Future<List<JournalEntry>> getAllEntriesRemote(
    String parentId,
    String childId,
  ) async {
    try {
      final snapshot = await _childJournalRef(parentId, childId).get();
      final remoteEntries = snapshot.docs
          .map(
            (doc) => JournalEntry.fromMap(doc.data() as Map<String, dynamic>),
          )
          .toList();

  
      return remoteEntries;
    } catch (e) {
     
      return [];
    }
  }

  Future<void> deleteEntryRemote(
    String parentId,
    String childId,
    String jid,
  ) async {
    await _childJournalRef(parentId, childId).doc(jid).delete();
 
  }

  // ---------------- OFFLINE-FIRST SYNC ----------------
  Future<bool> _hasConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------------- MERGE LOCAL + REMOTE ----------------
  Future<List<JournalEntry>> getMergedEntries(
    String parentId,
    String childId,
  ) async {
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

     
        return mergedList;
      } catch (e) {
     
        return localEntries;
      }
    }

  
    return localEntries;
  }

  Future<void> pushPendingLocalChanges(String parentId, String childId) async {
    // Get all local entries for this child
    final localEntries = _journalBox.values
        .where((e) => e.cid == childId)
        .toList();

    for (final entry in localEntries) {
      try {
        // Reference to Firestore doc
        final docRef = _childJournalRef(parentId, childId).doc(entry.jid);
        final remoteSnapshot = await docRef.get();

        if (!remoteSnapshot.exists) {
          // Remote doesn't exist → push local
          await saveEntryRemote(parentId, childId, entry);
      
        } else {
          final remoteData = remoteSnapshot.data() as Map<String, dynamic>;
          final remoteEntry = JournalEntry.fromMap(remoteData);

          // Compare timestamps to see which is newer
          final localTime =
              entry.createdAt;
          final remoteTime =
              remoteEntry.createdAt;

          if (localTime.isAfter(remoteTime)) {
            await saveEntryRemote(parentId, childId, entry);
          
          }
        }
      } catch (e) {
       
      }
    }

  }
}
