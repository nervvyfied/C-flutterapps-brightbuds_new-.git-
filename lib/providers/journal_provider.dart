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

  // ---------- 📊 Dashboard Helpers ----------

  // Mood stats (total counts)
  Map<String, int> getMoodStats(String childId) {
    final moods = getEntries(childId).map((e) => e.mood).toList();
    final Map<String, int> counts = {};
    for (var mood in moods) {
      counts[mood] = (counts[mood] ?? 0) + 1;
    }
    return counts;
  }

  // Top mood overall
  String getTopMood(String childId) {
    final stats = getMoodStats(childId);
    if (stats.isEmpty) return "—";
    return stats.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ---------- 📅 Weekly Mood Trends ----------

  /// Returns weekly mood stats for a child
  /// Example: { "2025-09-15": {"Happy": 2, "Sad": 1}, "2025-09-08": {"Angry": 3} }
  Map<String, Map<String, int>> getWeeklyMoodTrends(String childId) {
    final entries = getEntries(childId);

    final Map<String, Map<String, int>> weeklyTrends = {};

    for (var entry in entries) {
      final entryDate = entry.entryDate; // Make sure `date` in JournalEntry is DateTime
      final weekStart = _getWeekStart(entryDate);

      final weekKey =
          "${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}";

      weeklyTrends.putIfAbsent(weekKey, () => {});
      weeklyTrends[weekKey]![entry.mood] =
          (weeklyTrends[weekKey]![entry.mood] ?? 0) + 1;
    }

    return weeklyTrends;
  }

  /// Helper: get the Monday of the week for a given date
  DateTime _getWeekStart(DateTime entryDate) {
    return entryDate.subtract(Duration(days: entryDate.weekday - 1));
  }
}
