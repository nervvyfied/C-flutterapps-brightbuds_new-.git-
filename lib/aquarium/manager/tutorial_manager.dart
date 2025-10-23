import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AquariumTutorial {
  static const _tutorialKeyPrefix = 'aquarium_tutorial_shown_';

  // Check if tutorial was shown before
  static Future<bool> hasSeenTutorial({
    required String parentId,
    required String childId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final localKey = '$_tutorialKeyPrefix$childId';
    bool localSeen = prefs.getBool(localKey) ?? false;
    if (localSeen) return true;

    // Firestore check in 'aquarium' subcollection
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('aquarium')
        .doc('tutorial')
        .get();

    final firestoreSeen = doc.data()?['hasSeenTutorial'] ?? false;
    return firestoreSeen;
  }

  // Mark tutorial as seen
  static Future<void> markTutorialSeen({
    required String parentId,
    required String childId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_tutorialKeyPrefix$childId', true);

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('aquarium')
        .doc('tutorial');

    await docRef.set({'hasSeenTutorial': true}, SetOptions(merge: true));
  }

  // Reset for debugging or retest
  static Future<void> resetTutorial({
    required String parentId,
    required String childId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_tutorialKeyPrefix$childId');

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('aquarium')
        .doc('tutorial');

    await docRef.set({'hasSeenTutorial': false}, SetOptions(merge: true));
  }
}
