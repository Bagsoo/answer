import 'package:cloud_firestore/cloud_firestore.dart';

enum AppNoticeType {
  update,
  event,
  maintenance,
  announcement,
}

const String kDefaultAndroidNoticeUrl =
    'https://play.google.com/store/apps/details?id=com.answer.app&pli=1';
// ios url 임시
const String kDefaultIOSNoticeUrl =
    'https://daum.net';
const String kDefaultNoticeUrl = 'https://naver.com';

class AppNotice {
  final String id;
  final String title;
  final String content;
  final AppNoticeType noticeType;
  final int? minAppVersion;
  final String? androidUrl;
  final String? iosUrl;
  final String? defaultUrl;
  final bool isActive;
  final int priority;
  final DateTime? expiredAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const AppNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.noticeType,
    this.minAppVersion,
    this.androidUrl,
    this.iosUrl,
    this.defaultUrl,
    required this.isActive,
    required this.priority,
    this.expiredAt,
    this.updatedAt,
    this.createdAt,
  });

  factory AppNotice.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AppNotice(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      noticeType: _parseNoticeType(data['notice_type'] as String?),
      minAppVersion: (data['min_app_version'] as num?)?.toInt(),
      androidUrl: data['android_url'] as String?,
      iosUrl: data['ios_url'] as String?,
      defaultUrl: data['default_url'] as String?,
      isActive: data['is_active'] as bool? ?? false,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      expiredAt: (data['expired_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'notice_type': noticeType.name,
      'min_app_version': minAppVersion,
      'android_url': androidUrl,
      'ios_url': iosUrl,
      'default_url': defaultUrl,
      'is_active': isActive,
      'priority': priority,
      'expired_at': expiredAt,
      'updated_at': updatedAt,
      'created_at': createdAt,
    };
  }

  static String readPreferenceKey(String noticeId, DateTime? updatedAt) {
    final updatedAtValue = updatedAt?.millisecondsSinceEpoch ?? 0;
    return 'pref.app_notice_read.$noticeId.$updatedAtValue';
  }

  static AppNoticeType _parseNoticeType(String? value) {
    return AppNoticeType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AppNoticeType.announcement,
    );
  }

  bool get isExpired =>
      expiredAt != null && expiredAt!.isBefore(DateTime.now());

  String? get normalizedAndroidUrl =>
      (androidUrl == null || androidUrl!.trim().isEmpty) ? null : androidUrl!.trim();

  String? get normalizedIosUrl =>
      (iosUrl == null || iosUrl!.trim().isEmpty) ? null : iosUrl!.trim();

  String? get normalizedDefaultUrl =>
      (defaultUrl == null || defaultUrl!.trim().isEmpty) ? null : defaultUrl!.trim();

  String? resolveUrl({
    required bool isAndroid,
    required bool isIOS,
  }) {
    if (isAndroid) {
      return normalizedAndroidUrl ??
          normalizedDefaultUrl ??
          kDefaultAndroidNoticeUrl;
    }
    if (isIOS) {
      return normalizedIosUrl ?? normalizedDefaultUrl ?? kDefaultIOSNoticeUrl;
    }
    return normalizedDefaultUrl ?? kDefaultNoticeUrl;
  }

  AppNotice copyWith({
    String? title,
    String? content,
    AppNoticeType? noticeType,
    int? minAppVersion,
    String? androidUrl,
    String? iosUrl,
    String? defaultUrl,
    bool? isActive,
    int? priority,
    DateTime? expiredAt,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return AppNotice(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      noticeType: noticeType ?? this.noticeType,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      androidUrl: androidUrl ?? this.androidUrl,
      iosUrl: iosUrl ?? this.iosUrl,
      defaultUrl: defaultUrl ?? this.defaultUrl,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      expiredAt: expiredAt ?? this.expiredAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
