import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'assigned_cbt_model.g.dart';

@HiveType(typeId: 51)
class AssignedCBT {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String exerciseId;
  @HiveField(2)
  final String childId;
  @HiveField(3)
  final DateTime assignedDate;
  @HiveField(4)
  final String recurrence; // daily or weekly
  @HiveField(5)
  bool completed;
  @HiveField(6)
  DateTime? lastCompleted;

  AssignedCBT({
    required this.id,
    required this.exerciseId,
    required this.childId,
    required this.assignedDate,
    required this.recurrence,
    this.completed = false,
    this.lastCompleted,
  });

  factory AssignedCBT.fromMap(Map<String, dynamic> map) {
    DateTime? toDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return AssignedCBT(
      id: map['id'],
      exerciseId: map['exerciseId'],
      childId: map['childId'],
      assignedDate: (map['assignedDate']).toDate(),
      recurrence: map['recurrence'],
      completed: map['completed'] ?? false,
      lastCompleted: toDate(map['lastCompletedDate']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'exerciseId': exerciseId,
        'childId': childId,
        'assignedDate': assignedDate,
        'recurrence': recurrence,
        'completed': completed,
        'lastCompleted': lastCompleted,
      };
}
