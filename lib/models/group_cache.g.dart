// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GroupCacheAdapter extends TypeAdapter<GroupCache> {
  @override
  final int typeId = 1;

  @override
  GroupCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GroupCache(
      id: fields[0] as String?,
      name: fields[1] as String?,
      type: fields[2] as String?,
      memberCount: fields[3] as int?,
      profileImageUrl: fields[4] as String?,
      category: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, GroupCache obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.memberCount)
      ..writeByte(4)
      ..write(obj.profileImageUrl)
      ..writeByte(5)
      ..write(obj.category);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
