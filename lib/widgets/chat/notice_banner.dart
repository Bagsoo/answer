import 'package:flutter/material.dart';

class NoticeBanner extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const NoticeBanner({
    super.key,
    required this.text,
    required this.onDismiss,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withOpacity(0.6),
          border: Border(
            bottom: BorderSide(
                color: colorScheme.primary.withOpacity(0.15), width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined,
                size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }
}
