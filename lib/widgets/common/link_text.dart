import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkText extends StatelessWidget {
  static const LinkifyOptions _options = LinkifyOptions(
    looseUrl: true,
    defaultToHttps: true,
    humanize: false,
  );

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const LinkText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveStyle = style ??
        TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          height: 1.5,
        );
    final effectiveLinkStyle = linkStyle ??
        effectiveStyle.copyWith(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        );

    return Linkify(
      text: text,
      options: _options,
      style: effectiveStyle,
      linkStyle: effectiveLinkStyle,
      maxLines: maxLines,
      overflow: overflow,
      onOpen: _handleLinkOpen,
    );
  }

  Future<void> _handleLinkOpen(LinkableElement link) async {
    final uri = _normalizeUri(link.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Uri? _normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final direct = Uri.tryParse(trimmed);
    if (direct != null && direct.hasScheme) {
      return direct;
    }

    return Uri.tryParse('https://$trimmed');
  }
}
