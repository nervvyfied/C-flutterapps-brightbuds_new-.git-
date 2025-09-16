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
      mood: fields[5] as String,
      thankfulFor: fields[6] as String,
      todayILearned: fields[7] as String,
      todayITried: fields[8] as String,
      bestPartOfDay: fields[9] as String,
      createdAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, JournalEntry obj) {
    writer
      ..writeByte(11)
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
      ..write(obj.mood)
      ..writeByte(6)
      ..write(obj.thankfulFor)
      ..writeByte(7)
      ..write(obj.todayILearned)
      ..writeByte(8)
      ..write(obj.todayITried)
      ..writeByte(9)
      ..write(obj.bestPartOfDay)
      ..writeByte(10)
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
