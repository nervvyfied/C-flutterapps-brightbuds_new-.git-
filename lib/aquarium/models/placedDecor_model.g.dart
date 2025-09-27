// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placedDecor_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlacedDecorAdapter extends TypeAdapter<PlacedDecor> {
  @override
  final int typeId = 6;

  @override
  PlacedDecor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlacedDecor(
      id: fields[0] as String,
      decorId: fields[1] as String,
      x: fields[2] as double,
      y: fields[3] as double,
      isPlaced: fields[4] as bool,
      isSelected: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PlacedDecor obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.decorId)
      ..writeByte(2)
      ..write(obj.x)
      ..writeByte(3)
      ..write(obj.y)
      ..writeByte(4)
      ..write(obj.isPlaced)
      ..writeByte(5)
      ..write(obj.isSelected);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacedDecorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
