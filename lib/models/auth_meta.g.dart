// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_meta.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AuthMetaAdapter extends TypeAdapter<AuthMeta> {
  @override
  final int typeId = 2;

  @override
  AuthMeta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AuthMeta(
      isRegistered: fields[0] as bool?,
      lastUsedProvider: fields[1] as String?,
      registeredUid: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AuthMeta obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.isRegistered)
      ..writeByte(1)
      ..write(obj.lastUsedProvider)
      ..writeByte(2)
      ..write(obj.registeredUid);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthMetaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
