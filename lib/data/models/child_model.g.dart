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
      therapistUid: fields[8] as String?,
      cid: fields[0] as String,
      name: fields[1] as String,
      balance: fields[2] as int,
      streak: fields[3] as int,
      parentUid: fields[4] as String,
      placedDecors: (fields[5] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
      ownedFish: (fields[6] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
      firstVisitUnlocked: fields[7] as bool,
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
      ..writeByte(2)
      ..write(obj.balance)
      ..writeByte(3)
      ..write(obj.streak)
      ..writeByte(4)
      ..write(obj.parentUid)
      ..writeByte(5)
      ..write(obj.placedDecors)
      ..writeByte(6)
      ..write(obj.ownedFish)
      ..writeByte(7)
      ..write(obj.firstVisitUnlocked)
      ..writeByte(8)
      ..write(obj.therapistUid);
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
