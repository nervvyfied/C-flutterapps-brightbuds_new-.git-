import 'package:hive/hive.dart';

part 'journal_model.g.dart';

@HiveType(typeId: 4)
class JournalEntry {
  @HiveField(0)
  final String jid;

  @HiveField(1)
  final String cid;

  @HiveField(2)
  final DateTime entryDate;

  @HiveField(3)
  final int stars;

  @HiveField(4)
  final String affirmation;

  @HiveField(5)
  final String becauseIm;

  @HiveField(6)
  final String mood;

  @HiveField(7)
  final String thankfulFor;

  @HiveField(8)
  final String todayILearned;

  @HiveField(9)
  final String todayITried;

  @HiveField(10)
  final String bestPartOfDay;

  @HiveField(11)
  final DateTime createdAt;

  JournalEntry({
    required this.jid,
    required this.cid,
    required this.entryDate,
    required this.stars,
    required this.affirmation,
    required this.becauseIm,
    required this.mood,
    required this.thankfulFor,
    required this.todayILearned,
    required this.todayITried,
    required this.bestPartOfDay,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'jid': jid,
      'cid': cid,
      'entryDate': entryDate.toIso8601String(),
      'stars': stars,
      'affirmation': affirmation,
      'becauseIm': becauseIm,
      'mood': mood,
      'thankfulFor': thankfulFor,
      'todayILearned': todayILearned,
      'todayITried': todayITried,
      'bestPartOfDay': bestPartOfDay,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      jid: map['jid'] as String,
      cid: map['cid'] as String,
      entryDate: DateTime.parse(map['entryDate'] as String),
      stars: map['stars'] ?? 0,
      affirmation: map['affirmation'] ?? "I am amazing",
      becauseIm: map['becauseIm'] ?? "",
      mood: map['mood'] ?? "",
      thankfulFor: map['thankfulFor'] ?? "",
      todayILearned: map['todayILearned'] ?? "",
      todayITried: map['todayITried'] ?? "",
      bestPartOfDay: map['bestPartOfDay'] ?? "",
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  JournalEntry copyWith({
    String? jid,
    String? cid,
    DateTime? entryDate,
    int? stars,
    String? affirmation,
    String? becauseIm,
    String? mood,
    String? thankfulFor,
    String? todayILearned,
    String? todayITried,
    String? bestPartOfDay,
    DateTime? createdAt,
  }) {
    return JournalEntry(
      jid: jid ?? this.jid,
      cid: cid ?? this.cid,
      entryDate: entryDate ?? this.entryDate,
      stars: stars ?? this.stars,
      affirmation: affirmation ?? this.affirmation,
      becauseIm: becauseIm ?? this.becauseIm,
      mood: mood ?? this.mood,
      thankfulFor: thankfulFor ?? this.thankfulFor,
      todayILearned: todayILearned ?? this.todayILearned,
      todayITried: todayITried ?? this.todayITried,
      bestPartOfDay: bestPartOfDay ?? this.bestPartOfDay,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
