// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: file_names

part of 'ownedFish_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OwnedFishAdapter extends TypeAdapter<OwnedFish> {
  @override
  final int typeId = 7;

  @override
  OwnedFish read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OwnedFish(
      id: fields[0] as String,
      fishId: fields[1] as String,
      isUnlocked: fields[2] as bool,
      isPurchased: fields[3] as bool,
      isActive: fields[4] as bool,
      isNeglected: fields[5] as bool,
      isSelected: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, OwnedFish obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fishId)
      ..writeByte(2)
      ..write(obj.isUnlocked)
      ..writeByte(3)
      ..write(obj.isPurchased)
      ..writeByte(4)
      ..write(obj.isActive)
      ..writeByte(5)
      ..write(obj.isNeglected)
      ..writeByte(6)
      ..write(obj.isSelected);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OwnedFishAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
