import 'package:flutter/material.dart';

class SystemMessage extends StatelessWidget {
  final String text;
  final ColorScheme colorScheme;

  const SystemMessage({super.key, required this.text, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 12, color: colorScheme.onSurface.withOpacity(0.55)),
        ),
      ),
    );
  }
}
