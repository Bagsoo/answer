import 'package:hive/hive.dart';

part 'notification_settings_cache.g.dart';

@HiveType(typeId: 3)
class NotificationSettingsCache extends HiveObject {
  @HiveField(0)
  bool chatMessage;

  @HiveField(1)
  bool joinRequest;

  @HiveField(2)
  bool newSchedule;

  @HiveField(3)
  bool marketing;

  @HiveField(4)
  DateTime updatedAt;

  NotificationSettingsCache({
    required this.chatMessage,
    required this.joinRequest,
    required this.newSchedule,
    required this.marketing,
    required this.updatedAt,
  });
}
