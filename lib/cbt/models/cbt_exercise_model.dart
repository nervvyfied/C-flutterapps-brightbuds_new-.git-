import 'package:hive/hive.dart';

part 'cbt_exercise_model.g.dart';

@HiveType(typeId: 50)
class CBTExercise {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String mood;
  @HiveField(3)
  final String mode; // Audio, Visual, Interactive
  @HiveField(4)
  final String recurrence; // daily or weekly
  @HiveField(5)
  final String description;
  @HiveField(6)
  final String duration;
  @HiveField(7)
  final List<String> assets;

  const CBTExercise({
    required this.id,
    required this.title,
    required this.mood,
    required this.mode,
    required this.recurrence,
    required this.description,
    required this.duration,
    required this.assets,
  });

  factory CBTExercise.fromMap(Map<String, dynamic> map) {
    return CBTExercise(
      id: map['id'],
      title: map['title'],
      mood: map['mood'],
      mode: map['mode'],
      recurrence: map['recurrence'],
      description: map['description'],
      duration: map['duration'],
      assets: List<String>.from(map['assets'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'mood': mood,
        'mode': mode,
        'recurrence': recurrence,
        'description': description,
        'duration': duration,
        'assets': assets,
      };
}
