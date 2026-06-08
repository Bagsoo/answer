// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_settings_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NotificationSettingsCacheAdapter
    extends TypeAdapter<NotificationSettingsCache> {
  @override
  final int typeId = 3;

  @override
  NotificationSettingsCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NotificationSettingsCache(
      chatMessage: fields[0] as bool,
      joinRequest: fields[1] as bool,
      newSchedule: fields[2] as bool,
      marketing: fields[3] as bool,
      updatedAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, NotificationSettingsCache obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.chatMessage)
      ..writeByte(1)
      ..write(obj.joinRequest)
      ..writeByte(2)
      ..write(obj.newSchedule)
      ..writeByte(3)
      ..write(obj.marketing)
      ..writeByte(4)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettingsCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
