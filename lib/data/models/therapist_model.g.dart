// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'therapist_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TherapistUserAdapter extends TypeAdapter<TherapistUser> {
  @override
  final int typeId = 3;

  @override
  TherapistUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TherapistUser(
      uid: fields[0] as String,
      name: fields[1] as String,
      email: fields[2] as String,
      isVerified: fields[3] as bool,
      createdAt: fields[4] as DateTime,
      childId: fields[5] as String?,
      childrenAccessCodes: (fields[6] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, TherapistUser obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.email)
      ..writeByte(3)
      ..write(obj.isVerified)
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
      other is TherapistUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
