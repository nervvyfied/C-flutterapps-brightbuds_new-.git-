import 'package:hive/hive.dart';

part 'placedDecor_model.g.dart';

@HiveType(typeId: 6)
class PlacedDecor {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String decorId;

  @HiveField(2)
  double x;

  @HiveField(3)
  double y;

  @HiveField(4)
  bool isPlaced;

  @HiveField(5)
  bool isSelected;

  PlacedDecor({
    required this.id,
    required this.decorId,
    required this.x,
    required this.y,
    this.isPlaced = false,
    this.isSelected = false,
  });

  factory PlacedDecor.fromMap(Map<String, dynamic> map) {
    return PlacedDecor(
      id: map['id'] ?? '',
      decorId: map['decorId'] ?? '',
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
      isPlaced: map['isPlaced'] ?? false,
      isSelected: map['isSelected'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'decorId': decorId,
      'x': x,
      'y': y,
      'isPlaced': isPlaced,
      'isSelected': isSelected,
    };
  }

  PlacedDecor copyWith({
    String? id,
    String? decorId,
    double? x,
    double? y,
    bool? isPlaced,
    bool? isSelected,
  }) {
    return PlacedDecor(
      id: id ?? this.id,
      decorId: decorId ?? this.decorId,
      x: x ?? this.x,
      y: y ?? this.y,
      isPlaced: isPlaced ?? this.isPlaced,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
