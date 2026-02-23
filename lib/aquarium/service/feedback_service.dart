import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> submitFeedback({
    required String parentUid,
    required String childId,
    required int level,
    required int rating,
    String? emoji,
    String? selectedIssue,
    String? notes,
  }) async {
    final docRef = _db
        .collection('users')
        .doc(parentUid)
        .collection('children')
        .doc(childId)
        .collection('feedback')
        .doc(level.toString());

    await docRef.set({
      "level": level,
      "rating": rating,
      "emoji": emoji ?? '',
      "issue": selectedIssue ?? '',
      "notes": notes ?? '',
      "timestamp": FieldValue.serverTimestamp(),
    });
  }
}