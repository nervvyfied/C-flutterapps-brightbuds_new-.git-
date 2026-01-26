import 'package:hive/hive.dart';

part 'child_model.g.dart';

@HiveType(typeId: 1)
class ChildUser {
  @HiveField(0)
  final String cid;

  @HiveField(1)
  final String name;

  // Removed: balance
  // HiveField(2) is removed but not reused

  @HiveField(2)
  final int streak;

  @HiveField(3)
  final String parentUid;

  // Removed: placedDecors and ownedFish
  @HiveField(4) 
  final String? therapistUid;

  @HiveField(5)
  bool firstVisitUnlocked;
  // --- NEW FIELDS ---
  @HiveField(6)
  final int xp;           // total XP accumulated

  @HiveField(7)
  final int level;        // derived from XP

  @HiveField(8)
  final int currentWorld; // derived from level

  @HiveField(9)
  List<String> unlockedAchievements;

  ChildUser({
    required this.cid,
    required this.name,
    this.streak = 0,
    required this.parentUid,
    required this.therapistUid,
    this.firstVisitUnlocked = false,
    this.xp = 0,
    this.level = 1,
    this.currentWorld = 1,
    this.unlockedAchievements = const [],
  });

  factory ChildUser.fromMap(Map<String, dynamic> data, String id) {
    return ChildUser(
      cid: id,
      name: data['name'] ?? '',
      streak: data['streak'] ?? 0,
      parentUid: data['parentUid'] ?? '',
      therapistUid: data['therapistUid'] ?? '',
      firstVisitUnlocked: data['firstVisitUnlocked'] ?? false,
      xp: data['xp'] ?? 0,
      level: data['level'] ?? 1,
      currentWorld: data['currentWorld'] ?? 1,
      unlockedAchievements: List<String>.from(data['unlockedAchievements'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "cid": cid,
      "name": name,
      "streak": streak,
      "parentUid": parentUid,
      "therapistUid": therapistUid,
      "firstVisitUnlocked": firstVisitUnlocked,
      "xp": xp,
      "level": level,
      "currentWorld": currentWorld,
      "unlockedAchievements": unlockedAchievements,
    };
  }

  ChildUser copyWith({
    String? cid,
    String? name,
    int? streak,
    String? parentUid,
    String? therapistUid,
    bool? firstVisitUnlocked,
    int? xp,
    int? level,
    int? currentWorld,
    List<String>? unlockedAchievements,
  }) {
    return ChildUser(
      cid: cid ?? this.cid,
      name: name ?? this.name,
      streak: streak ?? this.streak,
      parentUid: parentUid ?? this.parentUid,
      therapistUid: therapistUid ?? therapistUid,
      firstVisitUnlocked: firstVisitUnlocked ?? this.firstVisitUnlocked,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      currentWorld: currentWorld ?? this.currentWorld,
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
    );
  }
}
