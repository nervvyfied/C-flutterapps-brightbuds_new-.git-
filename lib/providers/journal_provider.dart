import 'package:flutter/foundation.dart';
import '/data/models/journal_model.dart';
import '/data/repositories/journal_repository.dart';

class JournalProvider with ChangeNotifier {
  final JournalRepository _journalRepo = JournalRepository();
  final Map<String, List<JournalEntry>> _entries = {};

  List<JournalEntry> getEntries(String childId, String parentId) {
    return _entries[childId] ?? [];
  }

  Future<void> fetchEntries(String parentId, String childId) async {
    final remoteEntries = await _journalRepo.getAllEntriesRemote(parentId, childId);
    _entries[childId] = remoteEntries;
    notifyListeners();
  }

  Future<void> addEntry(String parentId, String childId, JournalEntry entry) async {
    // Save remotely & locally
    await _journalRepo.saveEntry(parentId, childId, entry);

    // Update local state
    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, entry);
    notifyListeners();
  }

  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    await _journalRepo.deleteEntry(parentId, childId, jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();
  }
}
