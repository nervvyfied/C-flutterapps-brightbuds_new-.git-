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
      balance: fields[2] as int,
      streak: fields[3] as int,
      parentUid: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ChildUser obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.cid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.balance)
      ..writeByte(3)
      ..write(obj.streak)
      ..writeByte(4)
      ..write(obj.parentUid);
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
