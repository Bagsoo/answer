import 'package:hive/hive.dart';

part 'group_cache.g.dart';

@HiveType(typeId: 1)
class GroupCache extends HiveObject {
  @HiveField(0)
  String? id;

  @HiveField(1)
  String? name;

  @HiveField(2)
  String? type;

  @HiveField(3)
  int? memberCount;

  @HiveField(4)
  String? profileImageUrl;

  @HiveField(5)
  String? category;

  GroupCache({
    this.id,
    this.name,
    this.type,
    this.memberCount,
    this.profileImageUrl,
    this.category,
  });

  factory GroupCache.fromJson(Map<String, dynamic> json) {
    return GroupCache(
      id: json['id'] as String?,
      name: json['name'] as String?,
      type: json['type'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt(),
      profileImageUrl: json['group_profile_image'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'member_count': memberCount,
      'group_profile_image': profileImageUrl,
      'category': category,
    };
  }
}
