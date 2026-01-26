import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'task_model.g.dart';

@HiveType(typeId: 2)
class TaskModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String difficulty; // "easy" | "medium" | "hard"

  @HiveField(3)
  final int reward; // tokens/coins count

  @HiveField(4)
  final String routine; // "morning" | "afternoon" | "night" | "anytime"

  @HiveField(5)
  final DateTime? alarm;

  @HiveField(6)
  final String? note; // optional child note

  @HiveField(7)
  final bool isDone;

  @HiveField(8)
  final DateTime? doneAt;

  @HiveField(9)
  final int activeStreak;

  @HiveField(10)
  final int longestStreak;

  @HiveField(11)
  final int totalDaysCompleted;

  @HiveField(12)
  final DateTime? lastCompletedDate;

  @HiveField(13)
  final String therapistId;

  @HiveField(14)
  final String childId;

  @HiveField(15)
  final DateTime? lastUpdated;

  @HiveField(16)
  final bool verified;

  @HiveField(17)
  final DateTime createdAt;

  @HiveField(18)
  final String parentId;

  @HiveField(19)
  final String creatorId; // who created it

  @HiveField(20)
  final String creatorType; // "parent" | "therapist"

  TaskModel({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.reward,
    required this.routine,
    this.alarm,
    this.note,
    this.isDone = false,
    this.doneAt,
    this.activeStreak = 0,
    this.longestStreak = 0,
    this.totalDaysCompleted = 0,
    this.lastCompletedDate,
    required this.therapistId,
    required this.childId,
    required this.parentId,
    this.lastUpdated,
    this.verified = false,
    required this.createdAt,
    required this.creatorId,
    required this.creatorType,
  });

  // ---------------- FIRESTORE -> MODEL ----------------
  factory TaskModel.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return TaskModel(
      id: id,
      name: data['name'] as String? ?? '',
      difficulty: data['difficulty'] as String? ?? 'easy',
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      routine: data['routine'] as String? ?? 'anytime',
      alarm: parseDate(data['alarm']),
      note: data['note'] as String?,
      isDone: data['isDone'] as bool? ?? false,
      doneAt: parseDate(data['doneAt']),
      activeStreak: (data['activeStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (data['longestStreak'] as num?)?.toInt() ?? 0,
      totalDaysCompleted: (data['totalDaysCompleted'] as num?)?.toInt() ?? 0,
      lastCompletedDate: parseDate(data['lastCompletedDate']),
      therapistId: data['therapistId'] as String? ?? '',
      childId: data['childId'] as String? ?? '',
      parentId: data['parentId'] as String? ?? '',
      lastUpdated: parseDate(data['lastUpdated']),
      verified: data['verified'] as bool? ?? false,
      createdAt: parseDate(data['createdAt']) ?? DateTime.now(),
      creatorId: data['creatorId'] as String? ?? data['parentId'] ?? '',
      creatorType: data['creatorType'] as String? ?? 'parent',
    );
  }

  // ---------------- MODEL -> FIRESTORE ----------------
  dynamic toTimestamp(DateTime? date) {
    if (date == null || date.isBefore(DateTime(1900)))
      return Timestamp.fromDate(DateTime.now());
    return Timestamp.fromDate(date);
  }

  Map<String, dynamic> toFirestore() {
    Timestamp? ts(DateTime? dt) => dt != null ? Timestamp.fromDate(dt) : null;

    return {
      'id': id,
      'name': name,
      'difficulty': difficulty,
      'reward': reward,
      'routine': routine,
      'alarm': ts(alarm),
      'note': note,
      'isDone': isDone,
      'doneAt': ts(doneAt),
      'activeStreak': activeStreak,
      'longestStreak': longestStreak,
      'totalDaysCompleted': totalDaysCompleted,
      'lastCompletedDate': ts(lastCompletedDate),
      'therapistId': therapistId,
      'childId': childId,
      'parentId': parentId,
      'lastUpdated': ts(lastUpdated ?? DateTime.now()),
      'verified': verified,
      'createdAt': ts(createdAt),
      'creatorId': creatorId,
      'creatorType': creatorType,
    };
  }

  Map<String, dynamic> toMap() => toFirestore();

  // ---------------- COPYWITH ----------------
  TaskModel copyWith({
    String? id,
    String? name,
    String? difficulty,
    int? reward,
    String? routine,
    DateTime? alarm,
    String? note,
    bool? isDone,
    DateTime? doneAt,
    int? activeStreak,
    int? longestStreak,
    int? totalDaysCompleted,
    DateTime? lastCompletedDate,
    String? therapistId,
    String? childId,
    DateTime? lastUpdated,
    bool? verified,
    DateTime? createdAt,
    String? parentId,
    String? creatorId,
    String? creatorType,
  }) {
    return TaskModel(
      id: id ?? this.id,
      name: name ?? this.name,
      difficulty: difficulty ?? this.difficulty,
      reward: reward ?? this.reward,
      routine: routine ?? this.routine,
      alarm: alarm ?? this.alarm,
      note: note ?? this.note,
      isDone: isDone ?? this.isDone,
      doneAt: doneAt ?? this.doneAt,
      activeStreak: activeStreak ?? this.activeStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalDaysCompleted: totalDaysCompleted ?? this.totalDaysCompleted,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
      therapistId: therapistId ?? this.therapistId,
      childId: childId ?? this.childId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      verified: verified ?? this.verified,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      creatorId: creatorId ?? this.creatorId,
      creatorType: creatorType ?? this.creatorType,
    );
  }

  // ---------------- MAP -> MODEL (for Hive/offline) ----------------
  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel.fromFirestore(map, map['id'] ?? '');
  }
}
