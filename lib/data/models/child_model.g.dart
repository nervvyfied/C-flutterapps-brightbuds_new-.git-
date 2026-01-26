// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'child_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChildUserAdapter extends TypeAdapter<ChildUser> {
  @override
  final int typeId = 1;

  @override
  ChildUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChildUser(
      cid: fields[0] as String,
      name: fields[1] as String,
      streak: fields[2] as int,
      parentUid: fields[3] as String,
      therapistUid: fields[4] as String?,
      firstVisitUnlocked: fields[5] as bool,
      xp: fields[6] as int,
      level: fields[7] as int,
      currentWorld: fields[8] as int,
      unlockedAchievements: (fields[9] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ChildUser obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.cid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.streak)
      ..writeByte(3)
      ..write(obj.parentUid)
      ..writeByte(4)
      ..write(obj.therapistUid)
      ..writeByte(5)
      ..write(obj.firstVisitUnlocked)
      ..writeByte(6)
      ..write(obj.xp)
      ..writeByte(7)
      ..write(obj.level)
      ..writeByte(8)
      ..write(obj.currentWorld)
      ..writeByte(9)
      ..write(obj.unlockedAchievements);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
