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
      streak: fields[3] as int,
      parentUid: fields[4] as String,
      firstVisitUnlocked: fields[7] as bool,
      xp: fields[8] as int,
      level: fields[9] as int,
      currentWorld: fields[10] as int,
      unlockedAchievements: (fields[11] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ChildUser obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.cid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.streak)
      ..writeByte(4)
      ..write(obj.parentUid)
      ..writeByte(7)
      ..write(obj.firstVisitUnlocked)
      ..writeByte(8)
      ..write(obj.xp)
      ..writeByte(9)
      ..write(obj.level)
      ..writeByte(10)
      ..write(obj.currentWorld)
      ..writeByte(11)
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
