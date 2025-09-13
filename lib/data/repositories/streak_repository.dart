import 'package:cloud_firestore/cloud_firestore.dart';

class StreakRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> updateStreak(String uid) async {
    final streakRef = _firestore.collection('streaks').doc(uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(streakRef);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int currentStreak = 0;
      int longestStreak = 0;
      DateTime? lastUpdated;

      if (snapshot.exists) {
        currentStreak = snapshot['currentStreak'] ?? 0;
        longestStreak = snapshot['longestStreak'] ?? 0;
        final ts = snapshot['lastUpdated'];
        if (ts != null) {
          lastUpdated = (ts as Timestamp).toDate();
        }
      }

      // Normalize lastUpdated to "date only"
      DateTime? lastDate = lastUpdated != null
          ? DateTime(lastUpdated.year, lastUpdated.month, lastUpdated.day)
          : null;

      if (lastDate == null) {
        // First streak entry
        currentStreak = 1;
      } else if (lastDate == today) {
        // Already updated today → do nothing
        return;
      } else if (lastDate.add(const Duration(days: 1)) == today) {
        // Consecutive day → increment streak
        currentStreak += 1;
      } else {
        // Break in streak → reset to 1
        currentStreak = 1;
      }

      // Update longest streak if needed
      if (currentStreak > longestStreak) {
        longestStreak = currentStreak;
      }

      // Write back
      transaction.set(streakRef, {
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastUpdated': Timestamp.fromDate(today),
      }, SetOptions(merge: true));
    });
  }
}

