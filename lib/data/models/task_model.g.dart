// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskModelAdapter extends TypeAdapter<TaskModel> {
  @override
  final int typeId = 2;

  @override
  TaskModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskModel(
      id: fields[0] as String,
      name: fields[1] as String,
      difficulty: fields[2] as String,
      reward: fields[3] as int,
      routine: fields[4] as String,
      alarm: fields[5] as DateTime?,
      note: fields[6] as String?,
      isDone: fields[7] as bool,
      doneAt: fields[8] as DateTime?,
      activeStreak: fields[9] as int,
      longestStreak: fields[10] as int,
      totalDaysCompleted: fields[11] as int,
      lastCompletedDate: fields[12] as DateTime?,
      therapistId: fields[13] as String,
      childId: fields[14] as String,
      parentId: fields[18] as String,
      lastUpdated: fields[15] as DateTime?,
      verified: fields[16] as bool,
      createdAt: fields[17] as DateTime,
      creatorId: fields[19] as String,
      creatorType: fields[20] as String,
      rejectionReason: fields[21] as String?,
      reminderMessage: fields[22] as String?,
      isAccepted: fields[23] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, TaskModel obj) {
    writer
      ..writeByte(24)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.difficulty)
      ..writeByte(3)
      ..write(obj.reward)
      ..writeByte(4)
      ..write(obj.routine)
      ..writeByte(5)
      ..write(obj.alarm)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.isDone)
      ..writeByte(8)
      ..write(obj.doneAt)
      ..writeByte(9)
      ..write(obj.activeStreak)
      ..writeByte(10)
      ..write(obj.longestStreak)
      ..writeByte(11)
      ..write(obj.totalDaysCompleted)
      ..writeByte(12)
      ..write(obj.lastCompletedDate)
      ..writeByte(13)
      ..write(obj.therapistId)
      ..writeByte(14)
      ..write(obj.childId)
      ..writeByte(15)
      ..write(obj.lastUpdated)
      ..writeByte(16)
      ..write(obj.verified)
      ..writeByte(17)
      ..write(obj.createdAt)
      ..writeByte(18)
      ..write(obj.parentId)
      ..writeByte(19)
      ..write(obj.creatorId)
      ..writeByte(20)
      ..write(obj.creatorType)
      ..writeByte(21)
      ..write(obj.rejectionReason)
      ..writeByte(22)
      ..write(obj.reminderMessage)
      ..writeByte(23)
      ..write(obj.isAccepted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
