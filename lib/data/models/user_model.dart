import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel {
  @HiveField(0)
  final String uid;

  @HiveField(1)
  final String role; // parent | child

  @HiveField(2)
  final String? email;

  @HiveField(3)
  final String? name;

  @HiveField(4)
  String? accessCode;

  @HiveField(5)
  final String? linkedParentId;

  @HiveField(6)
  final DateTime? createdAt;

  @HiveField(7)
  bool accessCodeUsed;

  @HiveField(8)
  int balance; // 👈 new field (defaults to 0 for child, null ignored for parent)

  UserModel({
    required this.uid,
    required this.role,
    this.email,
    this.name,
    this.accessCode,
    this.linkedParentId,
    this.createdAt,
    this.accessCodeUsed = false,
    this.balance = 0,
  });

  // Firestore -> Model
  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    DateTime? created;
    final rawCreated = data['createdAt'];
    if (rawCreated != null) {
      if (rawCreated is Timestamp) {
        created = rawCreated.toDate();
      } else if (rawCreated is DateTime) {
        created = rawCreated;
      } else if (rawCreated is String) {
        created = DateTime.tryParse(rawCreated);
      }
    }

    return UserModel(
      uid: uid,
      role: data['role'] ?? '',
      email: data['email'],
      name: data['name'],
      accessCode: data['accessCode'],
      linkedParentId: data['linkedParentId'],
      createdAt: created,
      accessCodeUsed: data['accessCodeUsed'] ?? false,
      balance: data['balance'] ?? 0,
    );
  }

  // Model -> Firestore
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      "role": role,
      "email": email,
      "name": name,
      "accessCode": accessCode,
      "linkedParentId": linkedParentId,
      "accessCodeUsed": accessCodeUsed,
      "balance": balance,
    };

    if (createdAt != null) {
      map['createdAt'] = Timestamp.fromDate(createdAt!);
    }

    return map;
  }
}

