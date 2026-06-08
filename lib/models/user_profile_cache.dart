import 'package:hive/hive.dart';

part 'user_profile_cache.g.dart';

@HiveType(typeId: 0)
class UserProfileCache extends HiveObject {
  @HiveField(0)
  String? uid;

  @HiveField(1)
  String? name;

  @HiveField(2)
  String? photoUrl;

  @HiveField(3)
  String? phone;

  @HiveField(4)
  String? locationName;

  @HiveField(5)
  double? locationLat;

  @HiveField(6)
  double? locationLng;

  @HiveField(7)
  List<String>? interests;

  UserProfileCache({
    this.uid,
    this.name,
    this.photoUrl,
    this.phone,
    this.locationName,
    this.locationLat,
    this.locationLng,
    this.interests,
  });
}
