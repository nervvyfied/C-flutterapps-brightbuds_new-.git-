// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assigned_cbt_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssignedCBTAdapter extends TypeAdapter<AssignedCBT> {
  @override
  final int typeId = 51;

  @override
  AssignedCBT read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssignedCBT(
      id: fields[0] as String,
      exerciseId: fields[1] as String,
      childId: fields[2] as String,
      assignedDate: fields[3] as DateTime,
      recurrence: fields[4] as String,
      weekOfYear: fields[7] as int,
      assignedBy: fields[8] as String,
      source: fields[9] as String,
      completed: fields[5] as bool,
      lastCompleted: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, AssignedCBT obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.exerciseId)
      ..writeByte(2)
      ..write(obj.childId)
      ..writeByte(3)
      ..write(obj.assignedDate)
      ..writeByte(4)
      ..write(obj.recurrence)
      ..writeByte(5)
      ..write(obj.completed)
      ..writeByte(6)
      ..write(obj.lastCompleted)
      ..writeByte(7)
      ..write(obj.weekOfYear)
      ..writeByte(8)
      ..write(obj.assignedBy)
      ..writeByte(9)
      ..write(obj.source);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignedCBTAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
