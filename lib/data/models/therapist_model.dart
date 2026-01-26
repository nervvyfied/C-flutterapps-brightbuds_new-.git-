import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'therapist_model.g.dart';

@HiveType(typeId: 3)
class TherapistUser {
  @HiveField(0)
  final String uid;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String email;

  @HiveField(3)
  final bool isVerified;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final String? childId;

  @HiveField(6)
  final Map<String, dynamic>? childrenAccessCodes;

  TherapistUser({
    required this.uid,
    required this.name,
    required this.email,
    this.isVerified = false,
    required this.createdAt,
    this.childId,
    this.childrenAccessCodes,
  });

  factory TherapistUser.fromMap(Map<String, dynamic> data, String uid) {
    // Convert Firestore Timestamp to DateTime
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    // Sanitize nested childrenAccessCodes timestamps
    Map<String, dynamic>? sanitizeChildren(Map<String, dynamic>? input) {
      if (input == null) return null;
      return input.map((key, value) {
        final mapVal = Map<String, dynamic>.from(value);
        if (mapVal['linkedAt'] is Timestamp) {
          mapVal['linkedAt'] = (mapVal['linkedAt'] as Timestamp).toDate();
        }
        return MapEntry(key, mapVal);
      });
    }

    return TherapistUser(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      isVerified: data['isVerified'] ?? false,
      createdAt: parseDate(data['createdAt']),
      childId: data['childId'],
      childrenAccessCodes: sanitizeChildren(
        data['childrenAccessCodes'] != null
            ? Map<String, dynamic>.from(data['childrenAccessCodes'])
            : null,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "email": email,
      "isVerified": isVerified,
      "childId": childId,
      "childrenAccessCodes": childrenAccessCodes ?? {},
      'createdAt': createdAt.toIso8601String(), // Hive-safe
    };
  }
}
