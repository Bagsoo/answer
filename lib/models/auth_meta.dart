import 'package:hive/hive.dart';

part 'auth_meta.g.dart';

@HiveType(typeId: 2)
class AuthMeta extends HiveObject {
  @HiveField(0)
  bool? isRegistered;

  @HiveField(1)
  String? lastUsedProvider;

  @HiveField(2)
  String? registeredUid;

  AuthMeta({
    this.isRegistered,
    this.lastUsedProvider,
    this.registeredUid,
  });
}
