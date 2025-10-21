import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class StreakRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Updates the active streak and longest streak for a specific task
  Future<void> updateStreak(String childId, String parentId, String taskId) async {
    final taskRef = _firestore
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('tasks')
        .doc(taskId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(taskRef);

      if (!snapshot.exists) {
        debugPrint("Task $taskId does not exist for child $childId.");
        return;
      }

      int activeStreak = snapshot['activeStreak'] ?? 0;
      int longestStreak = snapshot['longestStreak'] ?? 0;
      DateTime? lastUpdated;

      final ts = snapshot['lastUpdated'];
      if (ts != null && ts is Timestamp) lastUpdated = ts.toDate();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      DateTime? normalize(DateTime? dt) =>
          dt != null ? DateTime(dt.year, dt.month, dt.day) : null;

      final lastDate = normalize(lastUpdated);

      // Calculate new active streak
      if (lastDate != null && lastDate == today) {
        // Already updated today → do nothing
        return;
      } else if (lastDate != null && lastDate.add(const Duration(days: 1)) == today) {
        activeStreak += 1; // Consecutive day → increment
      } else {
        activeStreak = 1; // Streak broken or first update → reset
      }

      if (activeStreak > longestStreak) longestStreak = activeStreak;

      // Only update streak fields to avoid overwriting other fields
      transaction.update(taskRef, {
        'activeStreak': activeStreak,
        'longestStreak': longestStreak,
        'lastUpdated': Timestamp.fromDate(today),
      });
    }).catchError((e) {
      debugPrint("Failed to update streak for task $taskId: $e");
    });
  }
}
