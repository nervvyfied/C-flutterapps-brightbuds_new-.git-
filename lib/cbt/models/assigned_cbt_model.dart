import 'package:com.brightbuds/cbt/models/cbt_exercise_model.dart';
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

  @HiveField(7)
  final int weekOfYear;

  @HiveField(8)
  final String assignedBy; // parentId

  @HiveField(9)
  final String source; // "auto" or "manual"

  @HiveField(10)
  bool? isApproved;

  @HiveField(11)
  bool? isRequested;

  @HiveField(12)
  bool? isConfirmed;

  AssignedCBT({
    required this.id,
    required this.exerciseId,
    required this.childId,
    required this.assignedDate,
    required this.recurrence,
    required this.weekOfYear,
    required this.assignedBy,
    this.source = "auto",
    this.completed = false,
    this.lastCompleted,
    this.isApproved,
    this.isRequested,
    this.isConfirmed,
  });

  // Factory from Firestore map
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
      assignedDate: toDate(map['assignedDate'])!,
      recurrence: map['recurrence'] ?? 'daily',
      completed: map['completed'] ?? false,
      lastCompleted: toDate(map['lastCompleted']),
      weekOfYear: map['weekOfYear'] ?? 0,
      assignedBy: map['assignedBy'] ?? 'unknown',
      source: map['source'] ?? 'manual',
      isApproved: map['isApproved'], // can be null
      isRequested: map['isRequested'], // can be null
      isConfirmed: map['isConfirmed'], // can be null
    );
  }

  factory AssignedCBT.fromExercise({
    required String id,
    required CBTExercise exercise,
    required String childId,
    required DateTime assignedDate,
    required int weekOfYear,
    required String assignedBy,
    String? recurrence, // use exercise.recurrence by default
    String source = "auto",
    bool? isApproved,
    bool? isRequested,
    bool? isConfirmed,
  }) {
    return AssignedCBT(
      id: id,
      exerciseId: exercise.id,
      childId: childId,
      assignedDate: assignedDate,
      recurrence: recurrence ?? exercise.recurrence,
      weekOfYear: weekOfYear,
      assignedBy: assignedBy,
      source: source,
      completed: false,
      lastCompleted: null,
      isApproved: isApproved,
      isRequested: isRequested,
      isConfirmed: isConfirmed,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'exerciseId': exerciseId,
    'childId': childId,
    'assignedDate': Timestamp.fromDate(assignedDate),
    'recurrence': recurrence,
    'completed': completed,
    'lastCompleted': lastCompleted != null
        ? Timestamp.fromDate(lastCompleted!)
        : null,
    'weekOfYear': weekOfYear,
    'assignedBy': assignedBy,
    'source': source,
    'isApproved': isApproved,
    'isRequested': isRequested,
    'isConfirmed': isConfirmed,
  };
}
