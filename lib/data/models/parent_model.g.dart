// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parent_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ParentUserAdapter extends TypeAdapter<ParentUser> {
  @override
  final int typeId = 0;

  @override
  ParentUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ParentUser(
      uid: fields[0] as String,
      name: fields[1] as String,
      email: fields[2] as String,
      accessCode: fields[3] as String?,
      createdAt: fields[4] as DateTime,
      childId: fields[5] as String?,
      childrenAccessCodes: (fields[6] as Map?)?.cast<String, String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ParentUser obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.email)
      ..writeByte(3)
      ..write(obj.accessCode)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.childId)
      ..writeByte(6)
      ..write(obj.childrenAccessCodes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParentUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
