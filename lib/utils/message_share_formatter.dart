import 'package:linkify/linkify.dart';

import '../l10n/app_localizations.dart';

class MessageShareFormatter {
  static const LinkifyOptions _linkifyOptions = LinkifyOptions(
    looseUrl: true,
    defaultToHttps: true,
    humanize: false,
  );

  static String format(Map<String, dynamic> data, AppLocalizations l) {
    final type = data['type'] as String? ?? 'text';

    switch (type) {
      case 'image':
        return _formatImage(data, l);
      case 'video':
        return _formatVideo(data, l);
      case 'file':
        return _formatFile(data, l);
      case 'audio':
        return _formatAudio(data, l);
      case 'location':
        return _formatLocation(data, l);
      case 'contact':
        return _formatContact(data, l);
      default:
        return _formatText(data, l);
    }
  }

  static String _formatText(Map<String, dynamic> data, AppLocalizations l) {
    final text = (data['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      return l.shareMessage;
    }

    final urls = _extractUrls(text);
    if (urls.isEmpty) {
      return text;
    }

    return _joinLines([
      text,
      '',
      ...urls,
    ]);
  }

  static String _formatImage(Map<String, dynamic> data, AppLocalizations l) {
    final imageUrls = List<String>.from(data['image_urls'] as List? ?? []);
    final text = (data['text'] as String? ?? '').trim();
    final label = imageUrls.length > 1 ? '${l.attachPhoto} ${imageUrls.length}' : l.attachPhoto;

    return _joinLines([
      label,
      if (text.isNotEmpty) text,
      ...imageUrls.where((url) => url.trim().isNotEmpty),
    ]);
  }

  static String _formatVideo(Map<String, dynamic> data, AppLocalizations l) {
    final videoUrl = (data['video_url'] as String? ?? '').trim();
    final text = (data['text'] as String? ?? '').trim();

    return _joinLines([
      l.attachVideo,
      if (text.isNotEmpty) text,
      if (videoUrl.isNotEmpty) videoUrl,
    ]);
  }

  static String _formatFile(Map<String, dynamic> data, AppLocalizations l) {
    final fileName = (data['file_name'] as String? ?? '').trim();
    final fileUrl = (data['file_url'] as String? ?? '').trim();
    final fileSize = (data['file_size'] as num?)?.toInt() ?? 0;

    return _joinLines([
      l.attachFile,
      if (fileName.isNotEmpty) fileName,
      if (fileSize > 0) _formatFileSize(fileSize),
      if (fileUrl.isNotEmpty) fileUrl,
    ]);
  }

  static String _formatAudio(Map<String, dynamic> data, AppLocalizations l) {
    final fileName = (data['file_name'] as String? ?? '').trim();
    final audioUrl = (data['audio_url'] as String? ?? '').trim();
    final durationMs = (data['audio_duration_ms'] as num?)?.toInt() ?? 0;

    return _joinLines([
      l.attachAudio,
      if (fileName.isNotEmpty) fileName,
      if (durationMs > 0) _formatDuration(durationMs),
      if (audioUrl.isNotEmpty) audioUrl,
    ]);
  }

  static String _formatLocation(Map<String, dynamic> data, AppLocalizations l) {
    final lat = (data['location_lat'] as num?)?.toDouble();
    final lng = (data['location_lng'] as num?)?.toDouble();
    final type = (data['location_type'] as String? ?? 'current').trim();
    final label = type == 'destination' ? l.locationDestination : l.locationCurrent;

    if (lat == null || lng == null) {
      return l.attachLocation;
    }

    final mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    return _joinLines([
      label,
      '$lat, $lng',
      mapUrl,
    ]);
  }

  static String _formatContact(Map<String, dynamic> data, AppLocalizations l) {
    final name = (data['shared_user_name'] as String? ?? '').trim();
    return _joinLines([
      l.attachContact,
      if (name.isNotEmpty) name else l.unknown,
    ]);
  }

  static List<String> _extractUrls(String text) {
    final elements = linkify(text, options: _linkifyOptions);
    final urls = <String>[];

    for (final element in elements) {
      if (element is! UrlElement) continue;
      final normalized = _normalizeUrl(element.url);
      if (normalized == null || urls.contains(normalized)) continue;
      urls.add(normalized);
    }

    return urls;
  }

  static String? _normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final direct = Uri.tryParse(trimmed);
    if (direct != null && direct.hasScheme) {
      return direct.toString();
    }

    return Uri.tryParse('https://$trimmed')?.toString();
  }

  static String _joinLines(List<String> parts) {
    return parts.where((part) => part.trim().isNotEmpty).join('\n');
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  static String _formatDuration(int durationMs) {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
