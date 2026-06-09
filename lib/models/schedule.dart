import 'package:cloud_firestore/cloud_firestore.dart';

enum ScheduleType { group, personal }

class Schedule {
  final String id;
  final String title;
  final String description;
  final String cost;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, dynamic>? location;
  final ScheduleType type;
  final String? groupId;
  final String? groupName;
  final String createdBy;
  final DateTime createdAt;

  Schedule({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
    required this.startTime,
    required this.endTime,
    this.location,
    required this.type,
    this.groupId,
    this.groupName,
    required this.createdBy,
    required this.createdAt,
  });

  factory Schedule.fromFirestore(DocumentSnapshot doc, {String? groupName}) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String?;
    final isPersonal = typeStr != null 
        ? typeStr == 'personal'
        : doc.reference.path.contains('personal_schedules');
    
    return Schedule(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      cost: data['cost'] ?? '',
      startTime: (data['start_time'] as Timestamp).toDate(),
      endTime: (data['end_time'] as Timestamp).toDate(),
      location: data['location'] != null ? Map<String, dynamic>.from(data['location']) : null,
      type: isPersonal ? ScheduleType.personal : ScheduleType.group,
      groupId: data['group_id'] ?? (!isPersonal ? doc.reference.parent.parent?.id : null),
      groupName: data['group_name'] ?? groupName,
      createdBy: data['created_by'] ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'cost': cost,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'location': location,
      'type': type.name,
      'group_id': groupId,
      'group_name': groupName,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      cost: json['cost'] as String? ?? '',
      startTime: DateTime.parse(json['start_time'] as String? ?? DateTime.now().toIso8601String()),
      endTime: DateTime.parse(json['end_time'] as String? ?? DateTime.now().toIso8601String()),
      location: json['location'] as Map<String, dynamic>?,
      type: ScheduleType.values.byName(json['type'] as String? ?? 'personal'),
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}
