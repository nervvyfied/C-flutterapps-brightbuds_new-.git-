// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journal_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class JournalEntryAdapter extends TypeAdapter<JournalEntry> {
  @override
  final int typeId = 4;

  @override
  JournalEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return JournalEntry(
      jid: fields[0] as String,
      cid: fields[1] as String,
      entryDate: fields[2] as DateTime,
      stars: fields[3] as int,
      affirmation: fields[4] as String,
      becauseIm: fields[5] as String,
      mood: fields[6] as String,
      thankfulFor: fields[7] as String,
      todayILearned: fields[8] as String,
      todayITried: fields[9] as String,
      bestPartOfDay: fields[10] as String,
      createdAt: fields[11] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, JournalEntry obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.jid)
      ..writeByte(1)
      ..write(obj.cid)
      ..writeByte(2)
      ..write(obj.entryDate)
      ..writeByte(3)
      ..write(obj.stars)
      ..writeByte(4)
      ..write(obj.affirmation)
      ..writeByte(5)
      ..write(obj.becauseIm)
      ..writeByte(6)
      ..write(obj.mood)
      ..writeByte(7)
      ..write(obj.thankfulFor)
      ..writeByte(8)
      ..write(obj.todayILearned)
      ..writeByte(9)
      ..write(obj.todayITried)
      ..writeByte(10)
      ..write(obj.bestPartOfDay)
      ..writeByte(11)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
