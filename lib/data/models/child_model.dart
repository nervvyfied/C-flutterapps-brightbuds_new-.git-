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

  @HiveField(3)
  final int streak;

  @HiveField(4)
  final String parentUid;

  // Removed: placedDecors and ownedFish
  // HiveField(5) and HiveField(6) removed

  @HiveField(7)
  bool firstVisitUnlocked;

  ChildUser({
    required this.therapistUid,
    required this.cid,
    required this.name,
    this.streak = 0,
    required this.parentUid,
    this.firstVisitUnlocked = false,
  })  : placedDecors = placedDecors ?? <Map<String, dynamic>>[],
        ownedFish = ownedFish ?? <Map<String, dynamic>>[];
    

  factory ChildUser.fromMap(Map<String, dynamic> data, String id) {
    return ChildUser(
      cid: id,
      name: data['name'] ?? '',
      streak: data['streak'] ?? 0,
      parentUid: data['parentUid'] ?? '',
      firstVisitUnlocked: data['firstVisitUnlocked'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "cid": cid,
      "name": name,
      "streak": streak,
      "parentUid": parentUid,
      "firstVisitUnlocked": firstVisitUnlocked,
    };
  }

  ChildUser copyWith({
    String? cid,
    String? name,
    int? streak,
    String? parentUid,
    bool? firstVisitUnlocked,
  }) {
    return ChildUser(
      cid: cid ?? this.cid,
      name: name ?? this.name,
      streak: streak ?? this.streak,
      parentUid: parentUid ?? this.parentUid,
      firstVisitUnlocked: firstVisitUnlocked ?? this.firstVisitUnlocked,
    );
  }
}
