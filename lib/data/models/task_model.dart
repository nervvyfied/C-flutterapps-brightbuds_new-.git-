import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'task_model.g.dart';

@HiveType(typeId: 2)
class TaskModel {
  @HiveField(0)
  final String id; // Firestore docId (uuid if offline)

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String difficulty; // "easy" | "medium" | "hard"

  @HiveField(3)
  final int reward; // tokens/coins count

  @HiveField(4)
  final String routine; // "morning" | "afternoon" | "night" | "anytime"

  @HiveField(5)
  final DateTime? alarm; // nullable if no alarm

  @HiveField(6)
  final String? note; // optional note (child’s note after completion)

  @HiveField(7)
  final bool isDone;

  @HiveField(8)
  final DateTime? doneAt; // when child marked as done

  @HiveField(9)
  final int activeStreak;

  @HiveField(10)
  final int longestStreak;

  @HiveField(11)
  final int totalDaysCompleted;

  @HiveField(12)
  final DateTime? lastCompletedDate;

  @HiveField(13)
  final String parentId; // who assigned it

  @HiveField(14)
  final String childId; // who does it

  @HiveField(15)
  final DateTime? lastUpdated; // 🔑 sync timestamp

  @HiveField(16)
  final bool verified; // parent verification

  @HiveField(17)
  final DateTime createdAt;

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
    required this.parentId,
    required this.childId,
    this.lastUpdated,
    this.verified = false,
    required this.createdAt,
  });

  // ---------------- FIRESTORE -> MODEL ----------------
  factory TaskModel.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime? toDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return TaskModel(
      id: id,
      name: data['name'] as String? ?? '',
      difficulty: data['difficulty'] as String? ?? 'Easy',
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      routine: data['routine'] as String? ?? 'Anytime',
      alarm: toDate(data['alarm']),
      note: data['note'] as String?,
      isDone: data['isDone'] as bool? ?? false,
      doneAt: toDate(data['doneAt']),
      activeStreak: (data['activeStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (data['longestStreak'] as num?)?.toInt() ?? 0,
      totalDaysCompleted: (data['totalDaysCompleted'] as num?)?.toInt() ?? 0,
      lastCompletedDate: toDate(data['lastCompletedDate']),
      parentId: data['parentId'] as String? ?? '',
      childId: data['childId'] as String? ?? '',
      lastUpdated: toDate(data['lastUpdated']),
      verified: data['verified'] as bool? ?? false,
      createdAt: toDate(data['createdAt']) ?? DateTime.now(),
    );
  }

  // ---------------- MODEL -> FIRESTORE ----------------
  dynamic toTimestamp(DateTime? date) {
    if (date == null || date.isBefore(DateTime(1900))) {
      return Timestamp.fromDate(DateTime.now());
    }
    return Timestamp.fromDate(date);
  }

 Map<String, dynamic> toFirestore({bool forUpdate = false}) {
  if (forUpdate) {
    return {
      'name': name,
      'difficulty': difficulty,
      'reward': reward,
      'routine': routine,
      'alarm': toTimestamp(alarm),
      'note': note,
      'lastUpdated': toTimestamp(lastUpdated ?? DateTime.now()),
    };
  } else {
    return {
      'name': name,
      'difficulty': difficulty,
      'reward': reward,
      'routine': routine,
      'alarm': toTimestamp(alarm),
      'note': note,
      'isDone': isDone,
      'doneAt': toTimestamp(doneAt),
      'activeStreak': activeStreak,
      'longestStreak': longestStreak,
      'totalDaysCompleted': totalDaysCompleted,
      'lastCompletedDate': toTimestamp(lastCompletedDate),
      'parentId': parentId,
      'childId': childId,
      'lastUpdated': toTimestamp(lastUpdated ?? DateTime.now()),
      'verified': verified,
      'createdAt': toTimestamp(createdAt),
    };
  }
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
    String? parentId,
    String? childId,
    DateTime? lastUpdated,
    bool? verified,
    DateTime? createdAt,
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
      parentId: parentId ?? this.parentId,
      childId: childId ?? this.childId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      verified: verified ?? this.verified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
  
}
