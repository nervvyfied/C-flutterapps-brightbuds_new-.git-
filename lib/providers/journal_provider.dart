import 'package:flutter/foundation.dart';
import '/data/models/journal_model.dart';
import '/data/repositories/journal_repository.dart';

class JournalProvider with ChangeNotifier {
  final JournalRepository _journalRepo = JournalRepository();
  final Map<String, List<JournalEntry>> _entries = {};

  // Get entries for a specific child
  List<JournalEntry> getEntries(String childId) {
    return _entries[childId] ?? [];
  }

  // Fetch entries from remote and update local state
  Future<void> fetchEntries(String parentId, String childId) async {
    try {
      final remoteEntries = await _journalRepo.getAllEntriesRemote(parentId, childId);
      _entries[childId] = remoteEntries;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("Error fetching journal entries: $e");
    }
  }

  // Add a new entry
  Future<void> addEntry(String parentId, String childId, JournalEntry entry) async {
    await _journalRepo.saveEntry(parentId, childId, entry);

    _entries.putIfAbsent(childId, () => []);
    _entries[childId]!.insert(0, entry);
    notifyListeners();
  }

  // Delete an entry
  Future<void> deleteEntry(String parentId, String childId, String jid) async {
    await _journalRepo.deleteEntry(parentId, childId, jid);
    _entries[childId]?.removeWhere((e) => e.jid == jid);
    notifyListeners();
  }
}
