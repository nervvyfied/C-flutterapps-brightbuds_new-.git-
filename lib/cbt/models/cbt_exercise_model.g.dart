// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cbt_exercise_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CBTExerciseAdapter extends TypeAdapter<CBTExercise> {
  @override
  final int typeId = 50;

  @override
  CBTExercise read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CBTExercise(
      id: fields[0] as String,
      title: fields[1] as String,
      mood: fields[2] as String,
      mode: fields[3] as String,
      recurrence: fields[4] as String,
      description: fields[5] as String,
      duration: fields[6] as String,
      assets: (fields[7] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, CBTExercise obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.mood)
      ..writeByte(3)
      ..write(obj.mode)
      ..writeByte(4)
      ..write(obj.recurrence)
      ..writeByte(5)
      ..write(obj.description)
      ..writeByte(6)
      ..write(obj.duration)
      ..writeByte(7)
      ..write(obj.assets);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CBTExerciseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
