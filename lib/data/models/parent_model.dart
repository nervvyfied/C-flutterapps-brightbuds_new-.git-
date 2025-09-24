import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'parent_model.g.dart';

@HiveType(typeId: 0)
class ParentUser {
  @HiveField(0)
  final String uid;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String email;

  @HiveField(3)
  final String? accessCode;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final String? childId;

  @HiveField(6)
  final Map<String, String>? childrenAccessCodes;

  ParentUser({
    required this.uid,
    required this.name,
    required this.email,
    this.accessCode,
    required this.createdAt,
    this.childId,
    this.childrenAccessCodes,
  });

  factory ParentUser.fromMap(Map<String, dynamic> data, String uid) {
    return ParentUser(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      accessCode: data['activeAccessCode'],
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      childId: data['childId'],
      childrenAccessCodes: data['childrenAccessCodes'] != null
          ? Map<String, String>.from(data['childrenAccessCodes'])
          : {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "email": email,
      "activeAccessCode": accessCode,
      "childId": childId,
      "childrenAccessCodes": childrenAccessCodes ?? {},
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
