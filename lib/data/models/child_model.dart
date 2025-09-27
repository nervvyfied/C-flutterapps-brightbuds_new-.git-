import 'package:hive/hive.dart';

part 'child_model.g.dart';

@HiveType(typeId: 1)
class ChildUser {
  @HiveField(0)
  final String cid;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int balance;

  @HiveField(3)
  final int streak;

  @HiveField(4)
  final String parentUid;

  @HiveField(5)
  List<Map<String, dynamic>> placedDecors;

  @HiveField(6)
  List<Map<String, dynamic>> ownedFish;

  ChildUser({
    required this.cid,
    required this.name,
    this.balance = 0,
    this.streak = 0,
    required this.parentUid,
    List<Map<String, dynamic>>? placedDecors,
    List<Map<String, dynamic>>? ownedFish,
  })  : placedDecors = placedDecors ?? <Map<String, dynamic>>[],
        ownedFish = ownedFish ?? <Map<String, dynamic>>[];

  factory ChildUser.fromMap(Map<String, dynamic> data, String id) {
    return ChildUser(
      cid: id,
      name: data['name'] ?? '',
      balance: data['balance'] ?? 0,
      streak: data['streak'] ?? 0,
      parentUid: data['parentUid'] ?? '',
      placedDecors: data['placedDecors'] != null
          ? List<Map<String, dynamic>>.from(data['placedDecors'])
          : <Map<String, dynamic>>[],
      ownedFish: data['ownedFish'] != null
          ? List<Map<String, dynamic>>.from(data['ownedFish'])
          : <Map<String, dynamic>>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "cid": cid,
      "name": name,
      "balance": balance,
      "streak": streak,
      "parentUid": parentUid,
      "placedDecors": placedDecors,
      "ownedFish": ownedFish,
    };
  }

  ChildUser copyWith({
    String? cid,
    String? name,
    int? balance,
    int? streak,
    String? parentUid,
    List<Map<String, dynamic>>? placedDecors,
    List<Map<String, dynamic>>? ownedFish,
  }) {
    return ChildUser(
      cid: cid ?? this.cid,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      streak: streak ?? this.streak,
      parentUid: parentUid ?? this.parentUid,
      placedDecors: placedDecors ?? this.placedDecors,
      ownedFish: ownedFish ?? this.ownedFish,
    );
  }
}
